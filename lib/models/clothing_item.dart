// 衣服数据模型（全新编写，与旧工程无关）。
// 一件衣服 = 一张图（原图 + 抠图）+ 分类/颜色/季节/心情/温度范围等标签，
// 推荐引擎只读这些标签打分，不依赖任何云端服务。

class ClothingItem {
  final int? id;
  final String name;
  final String category; // 上衣 / 下装 / 外套 / 裙装 / 鞋 / 配饰
  final String color; // 颜色名，如 白色
  final String colorHex; // 如 #FFFFFF
  final List<String> seasons; // 春 夏 秋 冬
  final List<String> moods; // 休闲 正式 运动 约会 通勤
  final int tempMin; // 适合最低温度（℃）
  final int tempMax; // 适合最高温度（℃）
  final String imagePath; // 原图本地路径
  final String? cutoutPath; // 抠图（透明底）本地路径，失败时为空
  final bool isFavorite;
  final int wearCount;
  final int createdAt; // 毫秒时间戳

  const ClothingItem({
    this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.colorHex,
    required this.seasons,
    required this.moods,
    required this.tempMin,
    required this.tempMax,
    required this.imagePath,
    this.cutoutPath,
    this.isFavorite = false,
    this.wearCount = 0,
    required this.createdAt,
  });

  ClothingItem copyWith({
    int? id,
    String? name,
    String? category,
    String? color,
    String? colorHex,
    List<String>? seasons,
    List<String>? moods,
    int? tempMin,
    int? tempMax,
    String? imagePath,
    String? cutoutPath,
    bool? isFavorite,
    int? wearCount,
    int? createdAt,
  }) {
    return ClothingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      color: color ?? this.color,
      colorHex: colorHex ?? this.colorHex,
      seasons: seasons ?? this.seasons,
      moods: moods ?? this.moods,
      tempMin: tempMin ?? this.tempMin,
      tempMax: tempMax ?? this.tempMax,
      imagePath: imagePath ?? this.imagePath,
      cutoutPath: cutoutPath ?? this.cutoutPath,
      isFavorite: isFavorite ?? this.isFavorite,
      wearCount: wearCount ?? this.wearCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'color': color,
      'colorHex': colorHex,
      'seasons': seasons.join(','),
      'moods': moods.join(','),
      'tempMin': tempMin,
      'tempMax': tempMax,
      'imagePath': imagePath,
      'cutoutPath': cutoutPath,
      'isFavorite': isFavorite ? 1 : 0,
      'wearCount': wearCount,
      'createdAt': createdAt,
    };
  }

  factory ClothingItem.fromMap(Map<String, dynamic> m) {
    List<String> split(String? s) =>
        (s == null || s.isEmpty) ? <String>[] : s.split(',');
    return ClothingItem(
      id: m['id'] as int?,
      name: m['name'] as String,
      category: m['category'] as String,
      color: m['color'] as String,
      colorHex: m['colorHex'] as String,
      seasons: split(m['seasons'] as String?),
      moods: split(m['moods'] as String?),
      tempMin: m['tempMin'] as int,
      tempMax: m['tempMax'] as int,
      imagePath: m['imagePath'] as String,
      cutoutPath: m['cutoutPath'] as String?,
      isFavorite: (m['isFavorite'] as int) == 1,
      wearCount: m['wearCount'] as int,
      createdAt: m['createdAt'] as int,
    );
  }

  /// 显示用图：优先抠图，没有就用原图。
  String get displayPath => cutoutPath ?? imagePath;

  /// 适合的温度区间文字，如 15–25°C
  String get tempLabel => '$tempMin–$tempMax°C';
}

/// 分类常量（UI 下拉 / 筛选共用）
const List<String> kCategories = ['上衣', '下装', '外套', '裙装', '鞋', '配饰'];

/// 上衣类、下装类：推荐时按这个分
bool isTopCategory(String c) => c == '上衣' || c == '外套';
bool isBottomCategory(String c) => c == '下装';
bool isDressCategory(String c) => c == '裙装';

const List<String> kSeasons = ['春', '夏', '秋', '冬'];
const List<String> kMoods = ['休闲', '正式', '运动', '约会', '通勤'];

/// 常用颜色（名字 + 色值），导入时点选即可。
const List<Map<String, String>> kColors = [
  {'name': '白色', 'hex': '#FFFFFF'},
  {'name': '黑色', 'hex': '#222222'},
  {'name': '灰色', 'hex': '#9AA0A6'},
  {'name': '红色', 'hex': '#D93025'},
  {'name': '蓝色', 'hex': '#1A73E8'},
  {'name': '绿色', 'hex': '#188038'},
  {'name': '黄色', 'hex': '#F9AB00'},
  {'name': '粉色', 'hex': '#F8BBD0'},
  {'name': '紫色', 'hex': '#8E24AA'},
  {'name': '棕色', 'hex': '#795548'},
  {'name': '米色', 'hex': '#E8DCC8'},
  {'name': '牛仔蓝', 'hex': '#5B7FA6'},
];

/// 保存到某一天的一套穿搭。
class SavedOutfit {
  final int? id;
  final String title;
  final String date; // yyyy-MM-dd
  final int? topId;
  final int? bottomId;
  final int? outerId;
  final String? note;
  final int createdAt;

  const SavedOutfit({
    this.id,
    required this.title,
    required this.date,
    this.topId,
    this.bottomId,
    this.outerId,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date,
      'topId': topId,
      'bottomId': bottomId,
      'outerId': outerId,
      'note': note,
      'createdAt': createdAt,
    };
  }

  factory SavedOutfit.fromMap(Map<String, dynamic> m) {
    return SavedOutfit(
      id: m['id'] as int?,
      title: m['title'] as String,
      date: m['date'] as String,
      topId: m['topId'] as int?,
      bottomId: m['bottomId'] as int?,
      outerId: m['outerId'] as int?,
      note: m['note'] as String?,
      createdAt: m['createdAt'] as int,
    );
  }
}
