// 衣服贴合引擎（纯本机计算，不联网、不调任何云端服务）。
//
// 原理：每帧用 ML Kit 姿态关键点算出衣服在画面上的目标四边形，
// 再用单应性（透视变换）把真实衣服抠图贴上去——
// 肩线方向决定旋转，肩宽/躯干长度决定缩放，肩-髋两条线定透视，
// 所以衣服会跟着身体转、跟着身体走，不是固定 P 上去的一张图。
//
// 遮挡：手臂在衣服前面时，用 BlendMode.dstOut 沿肩-肘-腕把衣服
// 对应位置擦掉，露出下面摄像头拍到的真实手臂。
//
// 已知做不到（实话，不会偷偷换云端方案）：
// - 袖子不跟手臂走：整件上衣是按躯干四边形贴的，长袖不会顺着手臂弯；
// - 没有布料褶皱/垂坠物理效果，那需要生成式模型，本机不做、云端不调；
// - 遮挡只处理了手臂，其他东西挡在身前时处理不了。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 解 8 元线性方程组（高斯消元 + 列主元），失败返回 null。
List<double>? _solve8(List<List<double>> a, List<double> b) {
  const n = 8;
  final m = List.generate(n, (i) => [...a[i], b[i]]);
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var row = col + 1; row < n; row++) {
      if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
    }
    if (m[pivot][col].abs() < 1e-9) return null;
    if (pivot != col) {
      final t = m[pivot];
      m[pivot] = m[col];
      m[col] = t;
    }
    for (var row = col + 1; row < n; row++) {
      final f = m[row][col] / m[col][col];
      for (var k = col; k <= n; k++) {
        m[row][k] -= f * m[col][k];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var row = n - 1; row >= 0; row--) {
    var s = m[row][n];
    for (var k = row + 1; k < n; k++) {
      s -= m[row][k] * x[k];
    }
    x[row] = s / m[row][row];
  }
  return x;
}

/// 单应性矩阵：把单位正方形 (0,0)(1,0)(1,1)(0,1) 映射到 [dst] 四边形
/// （顺序：左上、右上、右下、左下，像素坐标）。失败返回 null。
Matrix4? homographyForQuad(List<Offset> dst) {
  if (dst.length != 4) return null;
  const src = [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 1),
    Offset(0, 1),
  ];
  final a = <List<double>>[];
  final b = <double>[];
  for (var i = 0; i < 4; i++) {
    final x = src[i].dx;
    final y = src[i].dy;
    final X = dst[i].dx;
    final Y = dst[i].dy;
    a.add([x, y, 1, 0, 0, 0, -x * X, -y * X]);
    b.add(X);
    a.add([0, 0, 0, x, y, 1, -x * Y, -y * Y]);
    b.add(Y);
  }
  final h = _solve8(a, b);
  if (h == null) return null;
  // 行主序参数：[h00 h01 0 h02 / h10 h11 0 h12 / 0 0 1 0 / h20 h21 0 1]
  return Matrix4(
    h[0], h[1], 0, h[2],
    h[3], h[4], 0, h[5],
    0, 0, 1, 0,
    h[6], h[7], 0, 1,
  );
}

Offset _mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

Offset _unit(Offset v) {
  final len = v.distance;
  if (len < 1e-6) return Offset.zero;
  return v / len;
}

/// 上装目标四边形（像素坐标）：左上、右上、右下、左下。
/// 肩线定上沿方向与旋转，髋线定下沿，肩宽/躯干长定缩放。
List<Offset>? topGarmentQuad(
    Map<PoseLandmarkType, Offset> lm, Size size) {
  final ls = lm[PoseLandmarkType.leftShoulder];
  final rs = lm[PoseLandmarkType.rightShoulder];
  final lh = lm[PoseLandmarkType.leftHip];
  final rh = lm[PoseLandmarkType.rightHip];
  if (ls == null || rs == null || lh == null || rh == null) return null;
  Offset px(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
  final lsP = px(ls);
  final rsP = px(rs);
  final lhP = px(lh);
  final rhP = px(rh);
  final shoulderMid = _mid(lsP, rsP);
  final hipMid = _mid(lhP, rhP);
  final shoulderDir = _unit(rsP - lsP);
  final hipDir = _unit(rhP - lhP);
  final torsoDir = _unit(hipMid - shoulderMid);
  final shoulderW = (rsP - lsP).distance;
  final hipW = (rhP - lhP).distance;
  final torsoLen = (hipMid - shoulderMid).distance;
  if (shoulderW < 10 || torsoLen < 10) return null;
  final topLeft = lsP - shoulderDir * (0.38 * shoulderW) - torsoDir * (0.28 * shoulderW);
  final topRight = rsP + shoulderDir * (0.38 * shoulderW) - torsoDir * (0.28 * shoulderW);
  final bottomRight = rhP + hipDir * (0.38 * hipW) + torsoDir * (0.18 * torsoLen);
  final bottomLeft = lhP - hipDir * (0.38 * hipW) + torsoDir * (0.18 * torsoLen);
  return [topLeft, topRight, bottomRight, bottomLeft];
}

/// 下装目标四边形（像素坐标）：左上、右上、右下、左下。
List<Offset>? bottomGarmentQuad(
    Map<PoseLandmarkType, Offset> lm, Size size) {
  final lh = lm[PoseLandmarkType.leftHip];
  final rh = lm[PoseLandmarkType.rightHip];
  final lk = lm[PoseLandmarkType.leftKnee];
  final rk = lm[PoseLandmarkType.rightKnee];
  if (lh == null || rh == null || lk == null || rk == null) return null;
  Offset px(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
  final lhP = px(lh);
  final rhP = px(rh);
  final lkP = px(lk);
  final rkP = px(rk);
  final hipMid = _mid(lhP, rhP);
  final kneeMid = _mid(lkP, rkP);
  final hipDir = _unit(rhP - lhP);
  final kneeDir = _unit(rkP - lkP);
  final legDir = _unit(kneeMid - hipMid);
  final hipW = (rhP - lhP).distance;
  final kneeW = (rkP - lkP).distance;
  final legLen = (kneeMid - hipMid).distance;
  if (hipW < 8 || legLen < 8) return null;
  final topLeft = lhP - hipDir * (0.32 * hipW);
  final topRight = rhP + hipDir * (0.32 * hipW);
  final bottomRight = rkP + kneeDir * (0.32 * kneeW) + legDir * (0.12 * legLen);
  final bottomLeft = lkP - kneeDir * (0.32 * kneeW) + legDir * (0.12 * legLen);
  return [topLeft, topRight, bottomRight, bottomLeft];
}

/// 把真实衣服抠图按姿态四边形做透视贴合；手臂处擦除衣服、露出真实手臂。
class GarmentWarpPainter extends CustomPainter {
  /// 归一化关键点（0~1 显示坐标，已按传感器方向旋转、按需镜像）。
  final Map<PoseLandmarkType, Offset> landmarks;
  final bool hasPose;
  final ui.Image? topImage;
  final ui.Image? bottomImage;

  GarmentWarpPainter({
    required this.landmarks,
    required this.hasPose,
    this.topImage,
    this.bottomImage,
  });

  void _drawWarped(Canvas canvas, ui.Image? image, List<Offset> quad) {
    if (image == null) return;
    final m = homographyForQuad(quad);
    if (m == null) return;
    canvas.save();
    canvas.transform(m.storage);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint(),
    );
    canvas.restore();
  }

  void _eraseArm(
    Canvas canvas,
    Size size,
    PoseLandmarkType shoulder,
    PoseLandmarkType elbow,
    PoseLandmarkType wrist,
    double armWidth,
  ) {
    final s = landmarks[shoulder];
    final e = landmarks[elbow];
    final w = landmarks[wrist];
    if (s == null || e == null || w == null) return;
    Offset px(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
    final erase = Paint()
      ..blendMode = BlendMode.dstOut
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(px(s), px(e), erase..strokeWidth = armWidth);
    canvas.drawLine(px(e), px(w), erase..strokeWidth = armWidth * 0.9);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!hasPose) return;
    final ls = landmarks[PoseLandmarkType.leftShoulder];
    final rs = landmarks[PoseLandmarkType.rightShoulder];
    final shoulderW = (ls != null && rs != null)
        ? (Offset(ls.dx * size.width, ls.dy * size.height) -
                Offset(rs.dx * size.width, rs.dy * size.height))
            .distance
        : 0.0;

    // 衣服画在一层里，之后在同一层内擦除手臂、最后一次性合成，
    // 这样 dstOut 只擦衣服，不擦下面的摄像头画面。
    canvas.saveLayer(null, Paint());
    final topQuad = topGarmentQuad(landmarks, size);
    if (topQuad != null) _drawWarped(canvas, topImage, topQuad);
    final bottomQuad = bottomGarmentQuad(landmarks, size);
    if (bottomQuad != null) _drawWarped(canvas, bottomImage, bottomQuad);
    if (shoulderW > 10) {
      final armW = math.max(6.0, shoulderW * 0.30);
      _eraseArm(canvas, size, PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, armW);
      _eraseArm(canvas, size, PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, armW);
    }
    canvas.restore();

    // 淡淡的骨架点，方便确认识别是否准。
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final p in landmarks.values) {
      canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GarmentWarpPainter old) =>
      old.landmarks != landmarks ||
      old.hasPose != hasPose ||
      old.topImage != topImage ||
      old.bottomImage != bottomImage;
}
