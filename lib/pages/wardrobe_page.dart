// 衣橱页：衣服列表 + 筛选 + 导入 + 编辑/删除。
// 数据库第一次在这里被访问（App 启动后），不是启动时。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../models/clothing_item.dart';
import '../services/cutout_service.dart';
import 'item_import_page.dart';

class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  String _categoryFilter = '全部';
  bool _favOnly = false;
  List<ClothingItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppDatabase.instance.allClothes();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '衣橱打不开：$e';
      });
    }
  }

  List<ClothingItem> get _filtered {
    return _items.where((e) {
      if (_favOnly && !e.isFavorite) return false;
      if (_categoryFilter != '全部' && e.category != _categoryFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickAndImport(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: source, maxWidth: 1600, imageQuality: 90);
      if (picked == null) return;
      if (!mounted) return;
      // 先把原图拷进应用目录（相册原图可能随时被删）。
      final dir = await getApplicationDocumentsDirectory();
      final origDir = Directory(p.join(dir.path, 'wardrobe', 'original'));
      if (!await origDir.exists()) await origDir.create(recursive: true);
      final ext = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final saved = File(p.join(origDir.path,
          '${DateTime.now().millisecondsSinceEpoch}$ext'));
      await File(picked.path).copy(saved.path);

      // 抠图（ML Kit，失败就用原图，不阻塞）。
      File? cutout;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在抠图，请稍等…')),
        );
      }
      cutout = await CutoutService.instance.cutout(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (cutout == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没抠出主体，已用原图，可手动重试')),
        );
      }
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ItemImportPage(
            imagePath: saved.path,
            cutoutPath: cutout?.path,
          ),
        ),
      );
      if (added == true) _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('拍照录入现有衣服'),
              onTap: () {
                Navigator.pop(context);
                _pickAndImport(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册导入（购物网站保存的图片）'),
              onTap: () {
                Navigator.pop(context);
                _pickAndImport(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(ClothingItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这件衣服？'),
        content: Text('${item.name} 会从衣橱里删掉，图片文件也会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || item.id == null) return;
    await AppDatabase.instance.deleteClothing(item.id!);
    for (final path in [item.imagePath, item.cutoutPath]) {
      if (path == null) continue;
      try {
        await File(path).delete();
      } catch (_) {}
    }
    _reload();
  }

  void _edit(ClothingItem item) {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => ItemImportPage(
              imagePath: item.imagePath,
              cutoutPath: item.cutoutPath,
              existing: item,
            ),
          ),
        )
        .then((saved) {
      if (saved == true) _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的衣橱'),
        actions: [
          IconButton(
            icon: Icon(
              _favOnly ? Icons.favorite : Icons.favorite_border,
              color: _favOnly ? Colors.pink : null,
            ),
            tooltip: '只看收藏',
            onPressed: () => setState(() => _favOnly = !_favOnly),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _reload, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _filters(),
                    Expanded(
                      child: _filtered.isEmpty
                          ? _emptyState()
                          : RefreshIndicator(
                              onRefresh: _reload,
                              child: GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _card(_filtered[i]),
                              ),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('添加衣服'),
      ),
    );
  }

  Widget _filters() {
    final cats = ['全部', ...kCategories];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: cats
            .map((c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: _categoryFilter == c,
                    onSelected: (_) =>
                        setState(() => _categoryFilter = c),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checkroom, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _items.isEmpty ? '衣橱还是空的' : '这个分类下没有衣服',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '点右下角“添加衣服”，拍照录入现有衣服，\n或从相册导入购物网站保存的图片。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add),
              label: const Text('添加第一件衣服'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ClothingItem item) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.grey.shade200,
                    child: Image.file(
                      File(item.displayPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image,
                          size: 48,
                          color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          await AppDatabase.instance.toggleFavorite(
                              item.id!, !item.isFavorite);
                          _reload();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            item.isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: item.isFavorite
                                ? Colors.pinkAccent
                                : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _tag(item.category),
                      _tag(item.color),
                      _tag(item.tempLabel),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => _delete(item),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: Colors.red),
                          Text('删除',
                              style: TextStyle(
                                  color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}
