// 本地数据库：sqflite，懒加载。
// 关键设计：启动时不打开数据库。第一次访问 AppDatabase.db 时才 open，
// 所以即使数据库文件出问题，App 也能先打开首页、再报错，而不是秒闪退。
// 表：clothes（衣服）、saved_outfits（按日期保存的穿搭）、body_photos（全身照）。

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/clothing_item.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'ai_wardrobe_v2.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clothes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            color TEXT NOT NULL,
            colorHex TEXT NOT NULL,
            seasons TEXT NOT NULL,
            moods TEXT NOT NULL,
            tempMin INTEGER NOT NULL,
            tempMax INTEGER NOT NULL,
            imagePath TEXT NOT NULL,
            cutoutPath TEXT,
            isFavorite INTEGER NOT NULL DEFAULT 0,
            wearCount INTEGER NOT NULL DEFAULT 0,
            createdAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE saved_outfits(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            date TEXT NOT NULL,
            topId INTEGER,
            bottomId INTEGER,
            outerId INTEGER,
            note TEXT,
            createdAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE body_photos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            imagePath TEXT NOT NULL,
            isDefault INTEGER NOT NULL DEFAULT 0,
            createdAt INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // ---- 衣服 ----
  Future<int> insertClothing(ClothingItem item) async {
    final d = await db;
    return d.insert('clothes', item.toMap());
  }

  Future<List<ClothingItem>> allClothes() async {
    final d = await db;
    final rows = await d.query('clothes', orderBy: 'createdAt DESC');
    return rows.map(ClothingItem.fromMap).toList();
  }

  Future<ClothingItem?> clothingById(int id) async {
    final d = await db;
    final rows = await d.query('clothes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ClothingItem.fromMap(rows.first);
  }

  Future<int> updateClothing(ClothingItem item) async {
    final d = await db;
    return d.update('clothes', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteClothing(int id) async {
    final d = await db;
    return d.delete('clothes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> toggleFavorite(int id, bool fav) async {
    final d = await db;
    return d.update('clothes', {'isFavorite': fav ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> bumpWearCount(int id) async {
    final d = await db;
    return d.rawUpdate(
        'UPDATE clothes SET wearCount = wearCount + 1 WHERE id = ?', [id]);
  }

  // ---- 保存的穿搭（日历） ----
  Future<int> insertSavedOutfit(SavedOutfit o) async {
    final d = await db;
    return d.insert('saved_outfits', o.toMap());
  }

  Future<List<SavedOutfit>> outfitsOnDate(String date) async {
    final d = await db;
    final rows = await d.query('saved_outfits',
        where: 'date = ?', whereArgs: [date], orderBy: 'createdAt DESC');
    return rows.map(SavedOutfit.fromMap).toList();
  }

  Future<List<SavedOutfit>> recentSavedOutfits({int limit = 30}) async {
    final d = await db;
    final rows = await d.query('saved_outfits',
        orderBy: 'date DESC, createdAt DESC', limit: limit);
    return rows.map(SavedOutfit.fromMap).toList();
  }

  Future<int> deleteSavedOutfit(int id) async {
    final d = await db;
    return d.delete('saved_outfits', where: 'id = ?', whereArgs: [id]);
  }

  // ---- 全身照 ----
  Future<int> insertBodyPhoto(String label, String imagePath) async {
    final d = await db;
    // 新照片设为默认，旧的取消默认。
    await d.update('body_photos', {'isDefault': 0});
    return d.insert('body_photos', {
      'label': label,
      'imagePath': imagePath,
      'isDefault': 1,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<String?> defaultBodyPhotoPath() async {
    final d = await db;
    final rows = await d.query('body_photos',
        where: 'isDefault = ?', whereArgs: [1], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['imagePath'] as String;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// yyyy-MM-dd
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
