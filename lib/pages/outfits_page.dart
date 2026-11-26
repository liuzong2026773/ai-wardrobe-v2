// 穿搭页：今日天气 + 心情选择 + 自动推荐 3 套 + 保存到日历。
// 天气只在用户点“刷新天气”时才联网（Open-Meteo，免 Key）；
// 没网/没定位就按 20°C 推荐，绝不卡住。

import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/recommendation.dart';
import '../data/weather_service.dart';
import '../models/clothing_item.dart';
import '../state/selection.dart';

class OutfitsPage extends StatefulWidget {
  /// 点“去试穿”后由 AppShell 切换 tab：2=静态试穿，3=AR试衣。
  final void Function(int tab) onTryOn;

  const OutfitsPage({super.key, required this.onTryOn});

  @override
  State<OutfitsPage> createState() => _OutfitsPageState();
}

class _OutfitsPageState extends State<OutfitsPage> {
  WeatherInfo _weather = WeatherInfo.fallback;
  bool _weatherLoading = false;
  String _mood = '休闲';
  List<OutfitSuggestion> _suggestions = [];
  bool _recommending = false;
  String? _emptyReason;
  List<ClothingItem> _items = [];
  DateTime _selectedDate = DateTime.now();
  List<SavedOutfit> _savedToday = [];

  @override
  void initState() {
    super.initState();
    _refreshWeather();
    _loadSaved();
  }

  Future<void> _refreshWeather() async {
    setState(() => _weatherLoading = true);
    final w = await WeatherService.fetchCurrent();
    if (!mounted) return;
    setState(() {
      _weather = w;
      _weatherLoading = false;
    });
  }

  Future<void> _loadSaved() async {
    final list =
        await AppDatabase.instance.outfitsOnDate(dateKey(_selectedDate));
    if (!mounted) return;
    setState(() => _savedToday = list);
  }

  Future<void> _recommend() async {
    setState(() {
      _recommending = true;
      _emptyReason = null;
    });
    final items = await AppDatabase.instance.allClothes();
    final suggestions = recommendOutfits(
      items: items,
      tempC: _weather.tempC,
      mood: _mood,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _suggestions = suggestions;
      _recommending = false;
      if (items.isEmpty) {
        _emptyReason = '衣橱还是空的，先去“衣橱”页添加几件衣服吧。';
      } else if (suggestions.isEmpty) {
        _emptyReason = '暂时组不出穿搭，试试换个心情或多加几件衣服。';
      }
    });
  }

  Future<void> _saveOutfit(OutfitSuggestion s) async {
    final date = dateKey(_selectedDate);
    await AppDatabase.instance.insertSavedOutfit(SavedOutfit(
      title: s.title,
      date: date,
      topId: s.top?.id,
      bottomId: s.bottom?.id,
      outerId: s.outer?.id,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (s.top != null) AppDatabase.instance.bumpWearCount(s.top!.id!);
    if (s.bottom != null) AppDatabase.instance.bumpWearCount(s.bottom!.id!);
    if (s.outer != null) AppDatabase.instance.bumpWearCount(s.outer!.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存到 $date 的穿搭')),
    );
    _loadSaved();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() => _selectedDate = d);
    _loadSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日穿搭')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _weatherCard(),
          const SizedBox(height: 16),
          const Text('今天什么心情？',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: kMoods
                .map((m) => ChoiceChip(
                      label: Text(m),
                      selected: _mood == m,
                      onSelected: (_) => setState(() => _mood = m),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _recommending ? null : _recommend,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_recommending ? '推荐中…' : '为我推荐 3 套'),
          ),
          const SizedBox(height: 16),
          if (_emptyReason != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_emptyReason!),
              ),
            ),
          ..._suggestions.map(_suggestionCard),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('穿搭日历',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(dateKey(_selectedDate)),
              ),
            ],
          ),
          if (_savedToday.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('这一天还没保存穿搭，推荐后点“保存到这一天”即可。'),
              ),
            ),
          ..._savedToday.map((s) => Card(
                child: ListTile(
                  title: Text(s.title),
                  subtitle: Text(s.date),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await AppDatabase.instance.deleteSavedOutfit(s.id!);
                      _loadSaved();
                    },
                  ),
                ),
              )),
          const SizedBox(height: 24),
          if (_items.isNotEmpty)
            Text('衣橱里共 ${_items.length} 件衣服',
                style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _weatherCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny, size: 40, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _weather.desc,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _weather.note,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _weatherLoading ? null : _refreshWeather,
              child: Text(_weatherLoading ? '获取中…' : '刷新天气'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionCard(OutfitSuggestion s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('推荐分 ${s.score}',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: s.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: Image.file(
                              File(item.displayPath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 72,
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (s.reasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                s.reasons.take(3).join('；'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    selectedOutfit.value = s;
                    widget.onTryOn(3);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('已选好这套，去 AR 试衣镜看看效果')),
                    );
                  },
                  icon: const Icon(Icons.videocam, size: 18),
                  label: const Text('AR试衣'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    selectedOutfit.value = s;
                    widget.onTryOn(2);
                  },
                  icon: const Icon(Icons.accessibility_new, size: 18),
                  label: const Text('静态试穿'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _saveOutfit(s),
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text('保存到这一天'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
