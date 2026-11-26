// 天气：免费 Open-Meteo 接口（免 Key），只在用户点“获取天气”时调用。
// 拿不到定位 / 没网 / 接口失败，一律返回默认 20°C，绝不阻塞推荐。

import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherInfo {
  final double tempC;
  final String desc; // 如 晴 22°C
  final bool fromNetwork; // true=实时天气，false=默认/离线
  final String note; // 给用户看的说明

  const WeatherInfo({
    required this.tempC,
    required this.desc,
    required this.fromNetwork,
    required this.note,
  });

  static const fallback = WeatherInfo(
    tempC: 20,
    desc: '默认 20°C',
    fromNetwork: false,
    note: '未获取到天气，已按 20°C 推荐（点刷新可重试）',
  );
}

/// WMO 天气代码 -> 中文
String weatherCodeDesc(int code) {
  switch (code) {
    case 0:
      return '晴';
    case 1:
      return '大部晴';
    case 2:
      return '多云';
    case 3:
      return '阴';
    case 45:
    case 48:
      return '雾';
    case 51:
    case 53:
    case 55:
      return '毛毛雨';
    case 56:
    case 57:
      return '冻毛毛雨';
    case 61:
      return '小雨';
    case 63:
      return '中雨';
    case 65:
      return '大雨';
    case 66:
    case 67:
      return '冻雨';
    case 71:
      return '小雪';
    case 73:
      return '中雪';
    case 75:
      return '大雪';
    case 77:
      return '雪粒';
    case 80:
    case 81:
    case 82:
      return '阵雨';
    case 85:
    case 86:
      return '阵雪';
    case 95:
      return '雷阵雨';
    case 96:
    case 99:
      return '雷阵雨伴冰雹';
    default:
      return '多云';
  }
}

class WeatherService {
  /// 获取当前天气。任何一步失败都返回 fallback，不抛异常。
  static Future<WeatherInfo> fetchCurrent() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const WeatherInfo(
          tempC: 20,
          desc: '默认 20°C',
          fromNetwork: false,
          note: '未给定位权限，已按 20°C 推荐',
        );
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10),
        ),
      );
      final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${pos.latitude}&longitude=${pos.longitude}&current=temperature_2m,weather_code&timezone=auto');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return WeatherInfo.fallback;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>;
      final temp = (current['temperature_2m'] as num).toDouble();
      final code = (current['weather_code'] as num).toInt();
      final desc = weatherCodeDesc(code);
      return WeatherInfo(
        tempC: temp,
        desc: '$desc ${temp.toStringAsFixed(0)}°C',
        fromNetwork: true,
        note: '实时天气：$desc ${temp.toStringAsFixed(0)}°C',
      );
    } catch (_) {
      return WeatherInfo.fallback;
    }
  }
}
