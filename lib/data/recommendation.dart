// 穿搭推荐：纯本地打分规则，不联网、不调任何模型。
// 打分：温度合适 +30（越贴合越高）、心情标签 +20、季节 +10、
// 收藏 +5；温度差得越多扣分越多。
// 每次返回 3 套：上衣 + 下装（可选外套，冷时自动加；裙装可单独成套）。

import '../models/clothing_item.dart';

class OutfitSuggestion {
  final ClothingItem? top;
  final ClothingItem? bottom;
  final ClothingItem? outer;
  final int score;
  final List<String> reasons;

  const OutfitSuggestion({
    this.top,
    this.bottom,
    this.outer,
    required this.score,
    required this.reasons,
  });

  String get title {
    final parts = <String>[];
    if (top != null) parts.add(top!.name);
    if (bottom != null) parts.add(bottom!.name);
    if (outer != null) parts.add(outer!.name);
    return parts.isEmpty ? '空穿搭' : parts.join(' + ');
  }

  List<ClothingItem> get items =>
      [top, bottom, outer].whereType<ClothingItem>().toList();
}

int _scoreItem(ClothingItem item, double tempC, String mood,
    List<String> reasons) {
  var score = 0;
  // 温度：落在区间内 +30，区间外每差 1°C 扣 3 分。
  if (tempC >= item.tempMin && tempC <= item.tempMax) {
    score += 30;
    reasons.add('${item.name}适合${item.tempLabel}');
  } else {
    final diff = tempC < item.tempMin
        ? (item.tempMin - tempC).round()
        : (tempC - item.tempMax).round();
    score -= diff * 3;
  }
  // 心情
  if (item.moods.contains(mood)) {
    score += 20;
    reasons.add('${item.name}适合$mood');
  }
  // 季节：按温度推断季节
  final season = tempC >= 26
      ? '夏'
      : tempC >= 18
          ? '春'
          : tempC >= 10
              ? '秋'
              : '冬';
  if (item.seasons.contains(season) || item.seasons.contains('四季')) {
    score += 10;
  }
  // 收藏
  if (item.isFavorite) score += 5;
  return score;
}

List<OutfitSuggestion> recommendOutfits({
  required List<ClothingItem> items,
  required double tempC,
  required String mood,
  int count = 3,
}) {
  if (items.isEmpty) return [];
  final tops = items
      .where((e) => e.category == '上衣' || e.category == '裙装')
      .toList();
  final bottoms = items.where((e) => e.category == '下装').toList();
  final outers = items.where((e) => e.category == '外套').toList();

  final scored = <ClothingItem, int>{};
  final reasonsOf = <ClothingItem, List<String>>{};
  for (final item in items) {
    final reasons = <String>[];
    scored[item] = _scoreItem(item, tempC, mood, reasons);
    reasonsOf[item] = reasons;
  }

  final suggestions = <OutfitSuggestion>[];
  final usedKeys = <String>{};

  void add(ClothingItem? top, ClothingItem? bottom, ClothingItem? outer) {
    if (top == null && bottom == null) return;
    final key = '${top?.id}_${bottom?.id}_${outer?.id}';
    if (usedKeys.contains(key)) return;
    usedKeys.add(key);
    var score = 0;
    final reasons = <String>[];
    for (final it in [top, bottom, outer]) {
      if (it == null) continue;
      score += scored[it] ?? 0;
      reasons.addAll(reasonsOf[it] ?? const []);
    }
    // 颜色搭配小规则：上下装同色系或黑白百搭加分
    if (top != null && bottom != null) {
      if (top.color == bottom.color) {
        score += 5;
        reasons.add('上下同色，顺色搭配');
      } else if (top.colorHex == '#FFFFFF' ||
          top.colorHex == '#222222' ||
          bottom.colorHex == '#FFFFFF' ||
          bottom.colorHex == '#222222') {
        score += 5;
        reasons.add('黑白百搭');
      }
    }
    suggestions.add(OutfitSuggestion(
      top: top,
      bottom: bottom,
      outer: outer,
      score: score,
      reasons: reasons.toSet().toList(),
    ));
  }

  // 按分数排序后组合，保证 3 套尽量不重样。
  tops.sort((a, b) => (scored[b] ?? 0).compareTo(scored[a] ?? 0));
  bottoms.sort((a, b) => (scored[b] ?? 0).compareTo(scored[a] ?? 0));
  outers.sort((a, b) => (scored[b] ?? 0).compareTo(scored[a] ?? 0));

  final needOuter = tempC < 18;
  for (var i = 0; i < tops.length && suggestions.length < count; i++) {
    final top = tops[i];
    if (isDressCategory(top.category)) {
      // 裙装单独成套
      add(top, null, needOuter && outers.isNotEmpty ? outers.first : null);
      continue;
    }
    if (bottoms.isEmpty) {
      add(top, null, needOuter && outers.isNotEmpty ? outers.first : null);
    } else {
      final bottom = bottoms[i % bottoms.length];
      final outer = needOuter && outers.isNotEmpty
          ? outers[i % outers.length]
          : null;
      add(top, bottom, outer);
    }
  }
  // 兜底：如果上衣不够，用剩余下装补一套
  if (suggestions.length < count && bottoms.isNotEmpty && tops.isEmpty) {
    for (final b in bottoms) {
      if (suggestions.length >= count) break;
      add(null, b, null);
    }
  }
  suggestions.sort((a, b) => b.score.compareTo(a.score));
  return suggestions.take(count).toList();
}
