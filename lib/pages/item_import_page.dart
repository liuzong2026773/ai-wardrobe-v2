// 导入/编辑衣服：给一张图打标签后存进本地衣橱。
// 新衣服默认名按分类生成；编辑时回填已有标签。

import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/clothing_item.dart';

class ItemImportPage extends StatefulWidget {
  final String imagePath;
  final String? cutoutPath;
  final ClothingItem? existing;

  const ItemImportPage({
    super.key,
    required this.imagePath,
    this.cutoutPath,
    this.existing,
  });

  @override
  State<ItemImportPage> createState() => _ItemImportPageState();
}

class _ItemImportPageState extends State<ItemImportPage> {
  late final TextEditingController _nameCtrl;
  String _category = '上衣';
  String _color = '白色';
  String _colorHex = '#FFFFFF';
  final Set<String> _seasons = {'春', '夏', '秋'};
  final Set<String> _moods = {'休闲'};
  RangeValues _temp = const RangeValues(15, 25);
  bool _showCutout = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    if (e != null) {
      _category = e.category;
      _color = e.color;
      _colorHex = e.colorHex;
      _seasons
        ..clear()
        ..addAll(e.seasons);
      _moods
        ..clear()
        ..addAll(e.moods);
      _temp = RangeValues(e.tempMin.toDouble(), e.tempMax.toDouble());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_seasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少选一个季节')),
      );
      return;
    }
    if (_moods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少选一种心情/场合')),
      );
      return;
    }
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim().isEmpty
        ? '我的$_category'
        : _nameCtrl.text.trim();
    final existing = widget.existing;
    try {
      if (existing == null) {
        await AppDatabase.instance.insertClothing(ClothingItem(
          name: name,
          category: _category,
          color: _color,
          colorHex: _colorHex,
          seasons: _seasons.toList(),
          moods: _moods.toList(),
          tempMin: _temp.start.round(),
          tempMax: _temp.end.round(),
          imagePath: widget.imagePath,
          cutoutPath: widget.cutoutPath,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } else {
        await AppDatabase.instance.updateClothing(existing.copyWith(
          name: name,
          category: _category,
          color: _color,
          colorHex: _colorHex,
          seasons: _seasons.toList(),
          moods: _moods.toList(),
          tempMin: _temp.start.round(),
          tempMax: _temp.end.round(),
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存：$name')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final previewPath = (_showCutout && widget.cutoutPath != null)
        ? widget.cutoutPath!
        : widget.imagePath;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑衣服' : '添加到衣橱')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              height: 220,
              width: 220,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(previewPath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image, size: 48),
              ),
            ),
          ),
          if (widget.cutoutPath != null) ...[
            const SizedBox(height: 8),
            Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('抠图效果')),
                  ButtonSegment(value: false, label: Text('原图')),
                ],
                selected: {_showCutout},
                onSelectionChanged: (s) =>
                    setState(() => _showCutout = s.first),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '名字（可不填，默认按分类命名）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('分类', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: kCategories
                .map((c) => ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('颜色', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: kColors
                .map((c) => ChoiceChip(
                      label: Text(c['name']!),
                      selected: _color == c['name'],
                      onSelected: (_) => setState(() {
                        _color = c['name']!;
                        _colorHex = c['hex']!;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('适合季节（可多选）',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: kSeasons
                .map((s) => FilterChip(
                      label: Text(s),
                      selected: _seasons.contains(s),
                      onSelected: (v) => setState(() {
                        v ? _seasons.add(s) : _seasons.remove(s);
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('适合心情/场合（可多选）',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: kMoods
                .map((m) => FilterChip(
                      label: Text(m),
                      selected: _moods.contains(m),
                      onSelected: (v) => setState(() {
                        v ? _moods.add(m) : _moods.remove(m);
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            '适合温度：${_temp.start.round()}–${_temp.end.round()}°C',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          RangeSlider(
            values: _temp,
            min: 0,
            max: 35,
            divisions: 35,
            labels: RangeLabels(
              '${_temp.start.round()}°C',
              '${_temp.end.round()}°C',
            ),
            onChanged: (v) => setState(() => _temp = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : (isEdit ? '保存修改' : '存入衣橱')),
          ),
        ],
      ),
    );
  }
}
