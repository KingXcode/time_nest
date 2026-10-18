import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/weather_panel.dart';

final _now = DateTime.utc(2026, 10, 18, 0, 30);
const _beijing = {
  'name': '北京',
  'latitude': 39.9,
  'longitude': 116.4,
  'country': '中国',
  'admin1': '北京市',
};
const _shanghai = {
  'name': '上海',
  'latitude': 31.2,
  'longitude': 121.5,
  'country': '中国',
  'admin1': '上海市',
};

class _Client implements DashboardClient {
  final searches = <String, Completer<DashboardData>>{};
  final weatherCalls = <Map<String, dynamic>>[];
  final openedUrls = <String>[];
  final refreshRequests = <bool>[];
  bool cached = false;
  bool stale = false;
  List<Map<String, dynamic>>? forecastHours;
  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) => openedUrls.add(url);
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module == 'searchCities') {
      final result = Completer<DashboardData>();
      searches[args['query'] as String] = result;
      return result.future;
    }
    if (module == 'weather') {
      weatherCalls.add(args);
      refreshRequests.add(refresh);
      return DashboardData(
        data: {
          'timezone': 'Asia/Shanghai',
          'utcOffsetSeconds': 28800,
          'hours':
              forecastHours ??
              [
                for (var hour = 0; hour < 24; hour++)
                  {
                    'time': '2026-10-18T${hour.toString().padLeft(2, '0')}:00',
                    'feels': hour + 10,
                    'rain': 5,
                    'wind': 12,
                    'code': 0,
                  },
              ],
        },
        fetchedAt: _now,
        cached: cached,
        stale: stale,
      );
    }
    throw StateError('Unexpected module: $module');
  }

  void complete(String query, Map<String, dynamic> city) =>
      searches[query]!.complete(
        DashboardData(
          data: {
            'cities': [city],
          },
          fetchedAt: _now,
        ),
      );
}

Widget _frame(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 1000),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);

class _WeatherHarness extends StatefulWidget {
  const _WeatherHarness(this.client, {this.initialCity});
  final _Client client;
  final Map<String, dynamic>? initialCity;
  @override
  State<_WeatherHarness> createState() => _WeatherHarnessState();
}

class _WeatherHarnessState extends State<_WeatherHarness> {
  late Map<String, dynamic>? city = widget.initialCity;
  @override
  Widget build(BuildContext context) => WeatherPanel(
    client: widget.client,
    city: city,
    now: () => _now,
    onCityChanged: (value) => setState(() => city = value),
  );
}

void main() {
  testWidgets('ordinary forecast shows temperature, feels-like and no advice', (
    tester,
  ) async {
    final client = _Client()
      ..forecastHours = [
        for (var hour = 7; hour < 20; hour++)
          {
            'time': '2026-10-18T${hour.toString().padLeft(2, '0')}:00',
            'temperature': hour + 14,
            'feels': hour + 10,
            'rain': 5,
            'wind': 12,
            'code': 0,
          },
      ];
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing)),
    );
    await tester.pumpAndSettle();
    expect(find.text('北京'), findsOneWidget);
    expect(find.text('当前小时预报 · 气温'), findsOneWidget);
    expect(find.text('22°'), findsNWidgets(2));
    expect(find.text('体感 18°'), findsNWidgets(2));
    expect(find.text('降雨概率 5% · 风速 12 km/h'), findsOneWidget);
    expect(find.text('晴'), findsWidgets);
    expect(find.text('逐小时预报'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('07:00'), findsNothing);
    expect(find.text('16:00'), findsNothing);
    expect(find.textContaining('出门'), findsNothing);
    expect(find.textContaining('筛选规则'), findsNothing);
    expect(find.textContaining('连休'), findsNothing);
    expect(find.textContaining('实时'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing or invalid temperature is labeled as feels-like', (
    tester,
  ) async {
    final client = _Client()
      ..forecastHours = [
        {
          'time': '2026-10-18T08:00',
          'temperature': double.nan,
          'feels': 18,
          'rain': 5,
          'wind': 12,
          'code': 3,
        },
        {
          'time': '2026-10-18T09:00',
          'feels': 19,
          'rain': 7,
          'wind': 10,
          'code': 3,
        },
      ];
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing)),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前小时预报 · 体感温度'), findsOneWidget);
    expect(find.text('18°'), findsNWidgets(2));
    expect(find.text('体感温度'), findsNWidgets(2));
    expect(find.text('多云'), findsWidgets);
    expect(find.textContaining('气温'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('future hourly forecast keeps local dates across midnight', (
    tester,
  ) async {
    final client = _Client()
      ..forecastHours = [
        for (final time in [
          '2026-10-18T20:00',
          '2026-10-18T22:00',
          '2026-10-18T23:00',
          '2026-10-19T00:00',
          '2026-10-19T01:00',
        ])
          {'time': time, 'feels': 20, 'rain': 5, 'wind': 12, 'code': 0},
      ];
    await tester.pumpWidget(
      _frame(
        WeatherPanel(
          client: client,
          city: _beijing,
          now: () => DateTime.utc(2026, 10, 18, 13, 30),
          onCityChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10/18 22:00 预报 · 体感温度'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('10/19 00:00'), findsOneWidget);
    expect(find.text('20:00'), findsNothing);
    expect(find.textContaining('当前小时'), findsNothing);
    expect(find.textContaining('出门'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expired forecasts do not appear as current weather', (
    tester,
  ) async {
    final client = _Client()
      ..forecastHours = [
        {
          'time': '2026-10-17T20:00',
          'feels': 18,
          'rain': 5,
          'wind': 12,
          'code': 0,
        },
      ];
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing)),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无可用的后续小时预报，请刷新或稍后重试。'), findsOneWidget);
    expect(find.text('18°'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'city stays manual and older search cannot replace newer results',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(_frame(_WeatherHarness(client)));
      expect(client.weatherCalls, isEmpty);
      expect(find.text('手动选择城市，不自动获取你的位置。'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '北京');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '上海');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      client.complete('上海', _shanghai);
      await tester.pumpAndSettle();
      client.complete('北京', _beijing);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, '上海'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '北京'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, '上海'));
      await tester.pumpAndSettle();
      expect(client.weatherCalls.last['latitude'], 31.2);
      expect(find.text('18°'), findsNWidgets(2));
      expect(find.text('当前小时预报 · 体感温度'), findsOneWidget);
      expect(find.textContaining('出门'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancel invalidates pending city search and can reopen cleanly', (
    tester,
  ) async {
    final client = _Client();
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('换城市'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '上海');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    client.complete('上海', _shanghai);
    await tester.pumpAndSettle();
    await tester.tap(find.text('换城市'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '上海'), findsNothing);
    expect(client.weatherCalls.length, 1);
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('city search handles short queries, errors and empty results', (
    tester,
  ) async {
    final client = _Client();
    await tester.pumpWidget(_frame(_WeatherHarness(client)));
    await tester.enterText(find.byType(TextField), '北');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    expect(find.textContaining('请输入至少 2 个字'), findsOneWidget);
    expect(client.searches, isEmpty);
    await tester.enterText(find.byType(TextField), '北京');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    client.searches['北京']!.completeError(Exception('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('城市搜索暂不可用，请稍后重试。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    client.searches['北京']!.complete(
      DashboardData(data: const {'cities': []}, fetchedAt: _now),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有找到城市，试试完整名称或英文名。'), findsOneWidget);
    expect(client.weatherCalls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('weather and city search fit 320 px at double text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _Client()
      ..forecastHours = [
        {
          'time': '2026-10-18T08:00',
          'temperature': 22,
          'feels': 18,
          'rain': 100,
          'wind': 120,
          'code': 95,
        },
      ];
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing), scale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('换城市'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '上海');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pump();
    client.complete('上海', _shanghai);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, '上海'));
    await tester.pumpAndSettle();
    expect(client.weatherCalls.last['latitude'], 31.2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('weather keeps source, cache status and explicit refresh', (
    tester,
  ) async {
    final client = _Client()..cached = true;
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing)),
    );
    await tester.pumpAndSettle();
    final source = find.text('Open-Meteo · 非商用免费接口 ↗');
    expect(source, findsOneWidget);
    expect(find.textContaining('缓存 '), findsOneWidget);
    await tester.ensureVisible(source);
    await tester.tap(source);
    expect(client.openedUrls, ['https://open-meteo.com/']);
    client.stale = true;
    await tester.ensureVisible(find.text('刷新'));
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(client.refreshRequests, [false, true]);
    expect(find.textContaining('当前为上次保存的数据，可能已过时。'), findsOneWidget);
    expect(find.textContaining('旧数据 '), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
