// AR 试衣镜：前置摄像头 + ML Kit 姿态关键点，
// 把用户衣橱里那件真实衣服的抠图按姿态做透视贴合。
//
// 硬要求（全部本机实现，不联网、不调任何云端/付费服务）：
// 1. 衣服必须是真实的：只用用户导入/拍照的真实衣服抠图，
//    没有内置样衣、不生成假衣服；衣橱空着就什么都不画。
// 2. 对位要准：每帧按肩/髋/膝关键点重新算目标四边形，
//    单应性透视变换贴合（旋转+缩放+透视一次完成），衣服跟着身体走；
//    边缘做过羽化，手臂处擦除衣服、露出真实手臂。
// 3. 绝不付费：试衣全程只用本机 ML Kit + 本机图像变换，
//    代码里没有任何付费接口、云端试衣/生图调用。
//
// 懒加载原则：相机、姿态检测器只在这里的 initState 里创建，
// 离开页面（dispose）即停止视频流、释放相机、关闭检测器。
// 任何一步失败（无相机权限、检测器加载失败）都只显示错误卡片，
// 绝不会影响 App 启动和其他页面。
//
// 已知做不到（实话）：袖子不跟手臂走、没有布料褶皱/垂坠效果、
// 遮挡只处理了手臂——这些要生成式模型才有，本机不做、云端不调。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../data/database.dart';
import '../models/clothing_item.dart';
import '../services/garment_image.dart';
import '../services/garment_warp.dart';
import '../state/selection.dart';

class LiveTryOnPage extends StatefulWidget {
  const LiveTryOnPage({super.key});

  @override
  State<LiveTryOnPage> createState() => _LiveTryOnPageState();
}

class _LiveTryOnPageState extends State<LiveTryOnPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  PoseDetector? _poseDetector;
  bool _initializing = true;
  String? _error;
  String _status = '正在打开相机…';

  List<ClothingItem> _tops = [];
  List<ClothingItem> _bottoms = [];
  ClothingItem? _top;
  ClothingItem? _bottom;
  ui.Image? _topImage;
  ui.Image? _bottomImage;

  // 最新一帧的姿态关键点（已归一化到显示坐标 0~1）。
  Map<PoseLandmarkType, Offset> _landmarks = {};
  bool _hasPose = false;
  bool _busy = false;
  int _lastProcessMs = 0;
  bool _mirror = true; // 前置摄像头默认镜像，画面才像照镜子
  int _cameraIndex = 0;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    final s = selectedOutfit.value;
    if (s != null) {
      _top = s.top;
      _bottom = s.bottom;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.stopImageStream().catchError((_) {});
    } else if (state == AppLifecycleState.resumed) {
      _startStream().catchError((_) {});
    }
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final items = await AppDatabase.instance.allClothes();
      _tops = items
          .where((e) => e.category == '上衣' || e.category == '裙装')
          .toList();
      _bottoms = items.where((e) => e.category == '下装').toList();
      _top ??= _tops.isNotEmpty ? _tops.first : null;
      _bottom ??= _bottoms.isNotEmpty ? _bottoms.first : null;
      await _loadGarmentImages();

      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('这台手机没有可用摄像头');
      // 优先前置摄像头（自拍试衣）。
      _cameraIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
      if (_cameraIndex < 0) _cameraIndex = 0;

      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.accurate,
          mode: PoseDetectionMode.stream,
        ),
      );
      await _startCamera();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = '请站在镜头前，全身入镜';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'AR 试衣打不开：$e\n\n请检查相机权限，或先用“静态试穿”。';
      });
    }
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    _controller = controller;
    await _startStream();
  }

  Future<void> _startStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.startImageStream(_onFrame);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    await _disposeCamera();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final isFront =
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
    setState(() => _mirror = isFront);
    await _startCamera();
  }

  Future<void> _disposeCamera() async {
    final c = _controller;
    _controller = null;
    try {
      await c?.stopImageStream();
    } catch (_) {}
    try {
      await c?.dispose();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_busy || now - _lastProcessMs < 120) return; // 最高约 8 帧/秒
    _lastProcessMs = now;
    _busy = true;
    _processFrame(image).whenComplete(() => _busy = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final detector = _poseDetector;
      final controller = _controller;
      if (detector == null || controller == null) return;
      final camera = _cameras[_cameraIndex];
      final rotation = InputImageRotationValue.fromRawValue(
              camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final bytes = _concatPlanes(image);
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      final poses = await detector.processImage(inputImage);
      if (!mounted) return;
      if (poses.isEmpty) {
        setState(() {
          _hasPose = false;
          _status = '未检测到人体，请站远一点、全身入镜';
        });
        return;
      }
      final pose = poses.first;
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final mapped = <PoseLandmarkType, Offset>{};
      for (final entry in pose.landmarks.entries) {
        final lm = entry.value;
        // 置信度低的关键点直接丢掉，不拿它算衣服位置（否则衣服会乱飘）。
        if (lm.likelihood < 0.5) continue;
        final nx = lm.x / w;
        final ny = lm.y / h;
        // 按传感器方向把图像坐标转成竖屏显示坐标，再按需镜像。
        final Offset d = _rotateNormalized(nx, ny, camera.sensorOrientation);
        mapped[entry.key] = Offset(_mirror ? 1 - d.dx : d.dx, d.dy);
      }
      setState(() {
        _landmarks = mapped;
        _hasPose = true;
        _status = '已识别姿态，衣服已贴合';
      });
    } catch (_) {
      // 单帧失败直接丢弃，不刷屏、不崩溃。
    }
  }

  /// 图像归一化坐标 (nx, ny) 按传感器旋转角度转成竖屏显示坐标。
  Offset _rotateNormalized(double nx, double ny, int sensorOrientation) {
    switch (sensorOrientation % 360) {
      case 90:
        return Offset(1 - ny, nx);
      case 180:
        return Offset(1 - nx, 1 - ny);
      case 270:
        return Offset(ny, 1 - nx);
      default:
        return Offset(nx, ny);
    }
  }

  Uint8List _concatPlanes(CameraImage image) {
    final buffer = WriteBuffer();
    for (final plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    return buffer.done().buffer.asUint8List();
  }

  Future<void> _loadGarmentImages() async {
    _topImage =
        _top == null ? null : await loadGarmentImage(_top!.displayPath);
    _bottomImage = _bottom == null
        ? null
        : await loadGarmentImage(_bottom!.displayPath);
  }

  Future<void> _saveOutfit() async {
    if (_top == null && _bottom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先选一件上衣或下装')),
      );
      return;
    }
    final today = dateKey(DateTime.now());
    final title = [
      if (_top != null) _top!.name,
      if (_bottom != null) _bottom!.name,
    ].join(' + ');
    await AppDatabase.instance.insertSavedOutfit(SavedOutfit(
      title: title,
      date: today,
      topId: _top?.id,
      bottomId: _bottom?.id,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存到今天（$today）的穿搭')),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _poseDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR试衣'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip),
            tooltip: _mirror ? '取消镜像' : '镜像显示',
            onPressed: () => setState(() => _mirror = !_mirror),
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera),
            tooltip: '切换摄像头',
            onPressed: _cameras.length > 1 ? _switchCamera : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新打开相机',
            onPressed: _init,
          ),
        ],
      ),
      body: _initializing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在打开相机…'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off,
                            size: 56, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _init, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(child: _preview()),
                    _statusBar(),
                    _selectors(),
                  ],
                ),
    );
  }

  Widget _preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('相机未就绪'));
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),
            Positioned.fill(
              child: CustomPaint(
                painter: GarmentWarpPainter(
                  landmarks: _landmarks,
                  hasPose: _hasPose,
                  topImage: _topImage,
                  bottomImage: _bottomImage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _hasPose ? Colors.green.shade50 : Colors.orange.shade50,
      child: Text(
        _status,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _hasPose ? Colors.green.shade900 : Colors.orange.shade900,
        ),
      ),
    );
  }

  Widget _selectors() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _itemDropdown('上衣', _tops, _top, (v) async {
                  setState(() => _top = v);
                  _topImage = v == null
                      ? null
                      : await loadGarmentImage(v.displayPath);
                  setState(() {});
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _itemDropdown('下装', _bottoms, _bottom, (v) async {
                  setState(() => _bottom = v);
                  _bottomImage = v == null
                      ? null
                      : await loadGarmentImage(v.displayPath);
                  setState(() {});
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '衣服按每帧姿态做透视贴合，会跟身体走；手臂挡住衣服时会露出真实手臂。长袖不跟手臂、没有布料褶皱效果。',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
              FilledButton.icon(
                onPressed: _saveOutfit,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('保存到今天'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemDropdown(String label, List<ClothingItem> items,
      ClothingItem? value, void Function(ClothingItem?) onChanged) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ClothingItem>(
          value: value,
          isExpanded: true,
          hint: Text(items.isEmpty ? '衣橱里没有$label' : '请选择'),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
