// 真实衣服图片加载：读用户衣橱里那件真实衣服的抠图，
// 做一次性边缘羽化（本地纯 Dart 计算，不联网），再解成 ui.Image。
// 衣服永远是用户自己导入/拍照的那件——没有内置样衣，不生成假衣服。
// 任何一步失败都返回 null 或回退到原图直解，不抛异常。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// 对 RGBA 字节流的 alpha 通道做半径 2 的可分离盒式模糊，
///
/// 再与原 alpha 取最小值：内部保持完全不透明，只让边缘 2px 渐隐，
///
/// 贴合时衣服边缘不会出现硬锯齿白边。
void _featherAlpha(Uint8List rgba, int w, int h) {
  const r = 2;
  final n = w * h;
  final orig = Uint8List(n);
  var hasTransparent = false;
  for (var i = 0; i < n; i++) {
    final a = rgba[i * 4 + 3];
    orig[i] = a;
    if (a < 255) hasTransparent = true;
  }
  if (!hasTransparent) return; // 全不透明，原图没有透明边，不用羽化
  final tmp = Uint8List(n);
  final div = 2 * r + 1;
  // 横向
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += orig[row + _clampInt(k, 0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum ~/ div;
      sum -= orig[row + _clampInt(x - r, 0, w - 1)];
      sum += orig[row + _clampInt(x + r + 1, 0, w - 1)];
    }
  }
  // 纵向
  final blurred = Uint8List(n);
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[_clampInt(k, 0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      blurred[y * w + x] = sum ~/ div;
      sum -= tmp[_clampInt(y - r, 0, h - 1) * w + x];
      sum += tmp[_clampInt(y + r + 1, 0, h - 1) * w + x];
    }
  }
  for (var i = 0; i < n; i++) {
    final a = orig[i];
    final b = blurred[i];
    rgba[i * 4 + 3] = a < b ? a : b;
  }
}

Future<ui.Image> _decodeUi(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// 读一件衣服的图（抠图优先），做边缘羽化后返回 ui.Image。
/// 失败返回 null（调用方不画这件，不崩溃）。
Future<ui.Image?> loadGarmentImage(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return await _decodeUi(bytes);
    if (decoded.numChannels < 4) return await _decodeUi(bytes); // 无透明通道
    var work = decoded;
    if (work.width > 900 || work.height > 900) {
      work = img.copyResize(
        work,
        width: work.width >= work.height ? 900 : null,
        height: work.width < work.height ? 900 : null,
      );
    }
    final rgba = work.getBytes(order: img.ChannelOrder.rgba);
    _featherAlpha(rgba, work.width, work.height);
    final feathered = img.Image.fromBytes(
      width: work.width,
      height: work.height,
      bytes: rgba.buffer,
      numChannels: 4,
    );
    return await _decodeUi(img.encodePng(feathered));
  } catch (_) {
    try {
      return await _decodeUi(await File(path).readAsBytes());
    } catch (_) {
      return null;
    }
  }
}
