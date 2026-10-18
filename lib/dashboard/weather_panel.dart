import 'dart:async';

import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_widgets.dart';

const _accent = Color(0xFF67D8C2);
const _secondary = Color(0xFF9BA8AF);

class WeatherPanel extends StatefulWidget {
  const WeatherPanel({
    super.key,
    required this.client,
    required this.city,
    required this.onCityChanged,
    this.now,
  });
  final DashboardClient client;
  final Map<String, dynamic>? city;
  final ValueChanged<Map<String, dynamic>> onCityChanged;
  final DateTime Function()? now;

  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends State<WeatherPanel> {
  final _query = TextEditingController();
  bool _changing = false, _searching = false, _searched = false;
  String? _searchError;
  List<Map<String, dynamic>> _cities = [];
  int _searchVersion = 0;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(() => _searchError = '请输入至少 2 个字或字母，例如北京、上海或 London。');
      return;
    }
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _searchError = null;
      _cities = [];
      _searched = false;
    });
    try {
      final result = await widget.client.load('searchCities', {'query': query});
      if (!mounted || version != _searchVersion) return;
      final cities = (result.data['cities'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where((city) => city['latitude'] is num && city['longitude'] is num)
          .toList();
      setState(() {
        _cities = cities;
        _searched = true;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _searching = false;
        _searchError = '城市搜索暂不可用，请稍后重试。';
      });
    }
  }

  void _choose(Map<String, dynamic> city) {
    _searchVersion++;
    setState(() {
      _changing = false;
      _cities = [];
      _searched = false;
      _searching = false;
      _searchError = null;
    });
    widget.onCityChanged(city);
  }

  void _closeSearch() {
    _searchVersion++;
    setState(() {
      _changing = false;
      _searching = false;
      _cities = [];
      _searched = false;
      _searchError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.city;
    final hasCity =
        city != null && city['latitude'] is num && city['longitude'] is num;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasCity || _changing) ...[
          if (!hasCity) ...[
            const Text(
              '先选一座城市，看看什么时候适合出门。',
              style: TextStyle(fontSize: 17, height: 1.5),
            ),
            const SizedBox(height: 6),
            const Text(
              '手动选择城市，不自动获取你的位置。',
              style: TextStyle(color: _secondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onChanged: (_) {
              _searchVersion++;
              setState(() {
                _cities = [];
                _searching = false;
                _searched = false;
                _searchError = null;
              });
            },
            decoration: const InputDecoration(
              labelText: '搜索城市',
              hintText: '城市名 / English name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(_searching ? '搜索中' : '搜索'),
              ),
              if (hasCity)
                TextButton(onPressed: _closeSearch, child: const Text('取消')),
            ],
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _searchError!,
                style: const TextStyle(color: Color(0xFFFFB4AB), height: 1.5),
              ),
            ),
          if (_searched && _cities.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '没有找到城市，试试完整名称或英文名。',
                style: TextStyle(color: _secondary),
              ),
            ),
          for (final candidate in _cities.take(6))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _choose(candidate),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate['name']?.toString() ?? '未命名城市',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [candidate['admin1'], candidate['country']]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(fontSize: 12, color: _secondary),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (hasCity) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 11, right: 8),
                child: Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: _accent,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    city['name']?.toString() ?? '所选城市',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _changing
                    ? _closeSearch()
                    : setState(() => _changing = true),
                child: Text(_changing ? '收起' : '换城市'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ApiSection(
            client: widget.client,
            module: 'weather',
            args: {
              'latitude': city['latitude'],
              'longitude': city['longitude'],
            },
            sourceLabel: 'Open-Meteo · 非商用免费接口',
            sourceUrl: 'https://open-meteo.com/',
            builder: (context, response) => _forecast(response.data),
          ),
        ],
      ],
    );
  }

  Widget _forecast(Map<String, dynamic> data) {
    // Open-Meteo returns local wall-clock strings without a zone. Represent
    // both these and offset-adjusted "now" as UTC fields, never device-local.
    final localNow = (widget.now ?? DateTime.now)().toUtc().add(
      Duration(seconds: (data['utcOffsetSeconds'] as num? ?? 0).toInt()),
    );
    final currentHour = DateTime.utc(
      localNow.year,
      localNow.month,
      localNow.day,
      localNow.hour,
    );
    final hours =
        (data['hours'] as List? ?? const [])
            .whereType<Map>()
            .map(_ForecastHour.parse)
            .whereType<_ForecastHour>()
            .where((hour) => !hour.time.isBefore(currentHour))
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (hours.isEmpty) {
      return const Text(
        '暂无可用的后续小时预报，请刷新或稍后重试。',
        style: TextStyle(color: _secondary, height: 1.5),
      );
    }
    final current = hours.first;
    List<_ForecastHour>? outing;
    for (var i = 0; i + 2 < hours.length; i++) {
      final candidate = hours.sublist(i, i + 3);
      if (candidate.first.time.isBefore(localNow) ||
          candidate.first.time.isAfter(
            localNow.add(const Duration(hours: 48)),
          )) {
        continue;
      }
      if (!candidate.every(
        (hour) => hour.time.hour >= 7 && hour.time.hour <= 20,
      )) {
        continue;
      }
      if (candidate.every((hour) => hour.rain < 35 && hour.wind < 25) &&
          candidate.last.time.difference(candidate.first.time).inHours == 2 &&
          candidate[1].time.difference(candidate.first.time).inHours == 1) {
        outing = candidate;
        break;
      }
    }
    final currentLabel = current.time == currentHour
        ? '当前小时体感'
        : '${_timeLabel(current.time)} 体感';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentLabel,
                  style: const TextStyle(fontSize: 12, color: _secondary),
                ),
                const SizedBox(height: 3),
                Text(
                  '${current.feels.round()}°',
                  style: const TextStyle(
                    fontSize: 48,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    color: _accent,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_weatherIcon(current.code), color: _accent, size: 28),
                const SizedBox(height: 7),
                Text(
                  _weatherName(current.code),
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  '降雨 ${current.rain.round()}% · 风 ${current.wind.round()} km/h',
                  style: const TextStyle(
                    color: _secondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: .2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '出门时间参考',
                style: TextStyle(color: _secondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                outing == null
                    ? '可用预报中，暂无符合条件的连续 3 小时'
                    : '${_timeLabel(outing.first.time)}–${_hour(outing.last.time.add(const Duration(hours: 1)))}',
                style: const TextStyle(
                  fontSize: 19,
                  color: _accent,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                outing == null
                    ? '可按下方逐小时预报，灵活调整行程。'
                    : '这段时间雨的可能性较低、风较小。${_clothing(outing)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '筛选规则：当地 7–21 时，每小时降雨概率 < 35%、风速 < 25 km/h，连续 3 小时。仅为简易参考，请同时留意当地预警。',
          style: TextStyle(fontSize: 11, height: 1.5, color: _secondary),
        ),
        const SizedBox(height: 18),
        const Text('接下来 8 小时', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final hour in hours.take(8))
                _HourCard(hour: hour, today: localNow),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text(
          '时间均为所选城市当地时间 · ${data['timezone'] ?? '当地时区'}\n降雨为概率，风速单位为 km/h。',
          style: const TextStyle(color: _secondary, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

class _ForecastHour {
  const _ForecastHour(this.time, this.feels, this.rain, this.wind, this.code);
  final DateTime time;
  final double feels, rain, wind;
  final int code;
  static _ForecastHour? parse(Map value) {
    final text = value['time']?.toString() ?? '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})')
        .firstMatch(text);
    if (match == null ||
        value['feels'] is! num ||
        value['rain'] is! num ||
        value['wind'] is! num) {
      return null;
    }
    final feels = (value['feels'] as num).toDouble(),
        rain = (value['rain'] as num).toDouble(),
        wind = (value['wind'] as num).toDouble();
    if (!feels.isFinite || !rain.isFinite || !wind.isFinite) return null;
    final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
    final time = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4]);
    return _ForecastHour(
      time,
      feels,
      rain,
      wind,
      (value['code'] as num? ?? -1).toInt(),
    );
  }
}

class _HourCard extends StatelessWidget {
  const _HourCard({required this.hour, required this.today});
  final _ForecastHour hour;
  final DateTime today;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${_timeLabel(hour.time)}，${_weatherName(hour.code)}，体感 ${hour.feels.round()} 度，降雨概率 ${hour.rain.round()}%，风速 ${hour.wind.round()} 千米每小时',
    excludeSemantics: true,
    child: Container(
      width: 102,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151D22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hour.time.day == today.day && hour.time.month == today.month
                ? _hour(hour.time)
                : '${hour.time.month}/${hour.time.day} ${_hour(hour.time)}',
            style: const TextStyle(fontSize: 11, color: _secondary),
          ),
          const SizedBox(height: 10),
          Icon(_weatherIcon(hour.code), size: 22, color: _accent),
          const SizedBox(height: 8),
          Text('${hour.feels.round()}°', style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 7),
          Text(
            '雨 ${hour.rain.round()}%',
            style: const TextStyle(fontSize: 11, color: _secondary),
          ),
          const SizedBox(height: 4),
          Text(
            '风 ${hour.wind.round()}',
            style: const TextStyle(fontSize: 11, color: _secondary),
          ),
        ],
      ),
    ),
  );
}

String _hour(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:00';
String _timeLabel(DateTime date) => '${date.month}/${date.day} ${_hour(date)}';
String _clothing(List<_ForecastHour> hours) {
  final lowest = hours.map((h) => h.feels).reduce((a, b) => a < b ? a : b);
  final highest = hours.map((h) => h.feels).reduce((a, b) => a > b ? a : b);
  if (lowest < 12) return '体感偏凉，记得带件外套。';
  if (highest >= 29) return '体感偏热，可以选阴凉路线。';
  return '体感 ${lowest.round()}–${highest.round()}°。';
}

String _weatherName(int code) {
  if (code == 0) return '晴';
  if (code <= 3 && code > 0) return '多云';
  if (code == 45 || code == 48) return '有雾';
  if (code >= 51 && code <= 67) return '有雨';
  if (code >= 71 && code <= 77 || code == 85 || code == 86) return '有雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code >= 95) return '雷雨';
  return '天气预报';
}

IconData _weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny_outlined;
  if (code <= 3 && code > 0) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 71 && code <= 77 || code == 85 || code == 86) {
    return Icons.ac_unit;
  }
  if (code >= 95) return Icons.thunderstorm_outlined;
  if (code >= 51) return Icons.umbrella_outlined;
  return Icons.cloud_outlined;
}
