// 跨页共享的“当前选中的一套穿搭”：
// 在“穿搭”页点“去试穿”后，静态试穿页 / AR 试衣页读取这里，
// 直接把选好的上衣、下装穿上，不用每页重新选。

import 'package:flutter/foundation.dart';

import '../data/recommendation.dart';

/// null = 未选择
final ValueNotifier<OutfitSuggestion?> selectedOutfit =
    ValueNotifier<OutfitSuggestion?>(null);
