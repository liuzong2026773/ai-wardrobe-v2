// 静态试穿：选一张全身照，把衣橱里的上衣/下装叠上去，
// 衣服可以拖动、双指缩放，调到贴合为止；满意可保存到穿搭日历。
// 不涉及相机流和姿态检测，纯图片合成预览。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../models/clothing_item.dart';
import '../state/selection.dart';

class StaticTryOnPage extends StatefulWidget {
  const StaticTryOnPage({super.key});

  @override
  State<StaticTryOnPage> createState() => _StaticTryOnPageState();
}

class _StaticTryOnPageState extends State<StaticTryOnPage> {
  String? _bodyPhotoPath;
  List<ClothingItem> _tops = [];
  List<ClothingItem> _bottoms = [];
  ClothingItem? _top;
  ClothingItem? _bottom;
  bool _loading = true;

  // 两件衣服在照片上的位置/大小（相对值，0~1）。
  Offset _topPos = const Offset(0.5, 0.30);
  double _topScale = 1.0;
  Offset _bottomPos = const Offset(0.5, 0.62);
  double _bottomScale = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
    // 如果是从“穿搭”页带过来的推荐，先穿上它。
    final s = selectedOutfit.value;
    if (s != null) {
      _top = s.top;
      _bottom = s.bottom;
    }
  }

  Future<void> _load() async {
    final items = await AppDatabase.instance.allClothes();
    final body = await AppDatabase.instance.defaultBodyPhotoPath();
    if (!mounted) return;
    setState(() {
      _tops = items
          .where((e) => e.category == '上衣' || e.category == '裙装')
          .toList();
      _bottoms = items.where((e) => e.category == '下装').toList();
      _bodyPhotoPath = body;
      _loading = false;
      // 推荐带过来的衣服如果不在列表里（刚被删），清掉。
      if (_top != null && !_tops.any((e) => e.id == _top!.id)) _top = null;
      if (_bottom != null && !_bottoms.any((e) => e.id == _bottom!.id)) {
        _bottom = null;
      }
      _top ??= _tops.isNotEmpty ? _tops.first : null;
      _bottom ??= _bottoms.isNotEmpty ? _bottoms.first : null;
    });
  }

  Future<void> _pickBodyPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 90);
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final bodyDir = Directory(p.join(dir.path, 'wardrobe', 'body'));
      if (!await bodyDir.exists()) await bodyDir.create(recursive: true);
      final saved = File(p.join(bodyDir.path,
          'body_${DateTime.now().millisecondsSinceEpoch}.jpg'));
      await File(picked.path).copy(saved.path);
      await AppDatabase.instance
          .insertBodyPhoto('全身照', saved.path);
      if (!mounted) return;
      setState(() => _bodyPhotoPath = saved.path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全身照已保存，下次直接用这张')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选图失败：$e')),
      );
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('静态试穿'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_camera),
            tooltip: '拍全身照',
            onPressed: () => _pickBodyPhoto(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: '从相册选全身照',
            onPressed: () => _pickBodyPhoto(ImageSource.gallery),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _previewArea()),
                _selectors(),
              ],
            ),
    );
  }

  Widget _previewArea() {
    if (_bodyPhotoPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('先拍一张全身照', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text('站远一点，拍到头到脚，穿睡衣也可以，\n试穿效果会在这张照片上叠加显示。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _pickBodyPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('拍全身照'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pickBodyPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('从相册选'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Container(
          color: Colors.black12,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.file(
                  File(_bodyPhotoPath!),
                  fit: BoxFit.contain,
                ),
              ),
              if (_top != null)
                _draggableGarment(
                  key: const ValueKey('top'),
                  path: _top!.displayPath,
                  baseWidth: w * 0.52,
                  pos: _topPos,
                  scale: _topScale,
                  area: Size(w, h),
                  onMove: (pos, scale) =>
                      setState(() { _topPos = pos; _topScale = scale; }),
                ),
              if (_bottom != null)
                _draggableGarment(
                  key: const ValueKey('bottom'),
                  path: _bottom!.displayPath,
                  baseWidth: w * 0.46,
                  pos: _bottomPos,
                  scale: _bottomScale,
                  area: Size(w, h),
                  onMove: (pos, scale) => setState(
                      () { _bottomPos = pos; _bottomScale = scale; }),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('拖动衣服可移动，双指缩放可调大小',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _draggableGarment({
    required Key key,
    required String path,
    required double baseWidth,
    required Offset pos,
    required double scale,
    required Size area,
    required void Function(Offset pos, double scale) onMove,
  }) {
    final width = baseWidth * scale;
    return Positioned(
      key: key,
      left: pos.dx * area.width - width / 2,
      top: pos.dy * area.height - width / 2,
      child: GestureDetector(
        onPanUpdate: (d) {
          onMove(
            Offset(
              (pos.dx + d.delta.dx / area.width).clamp(0.05, 0.95),
              (pos.dy + d.delta.dy / area.height).clamp(0.05, 0.95),
            ),
            scale,
          );
        },
        onScaleUpdate: (d) {
          onMove(pos, (scale * d.scale).clamp(0.4, 2.5));
        },
        child: Image.file(
          File(path),
          width: width,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image, size: 48),
        ),
      ),
    );
  }

  Widget _selectors() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _itemDropdown('上衣', _tops, _top,
                    (v) => setState(() => _top = v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _itemDropdown('下装', _bottoms, _bottom,
                    (v) => setState(() => _bottom = v)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() {
                  _topPos = const Offset(0.5, 0.30);
                  _topScale = 1.0;
                  _bottomPos = const Offset(0.5, 0.62);
                  _bottomScale = 1.0;
                }),
                child: const Text('位置复位'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saveOutfit,
                icon: const Icon(Icons.calendar_month),
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
              .map((e) =>
                  DropdownMenuItem(value: e, child: Text(e.name)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
