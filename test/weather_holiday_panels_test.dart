import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/holiday_panel.dart';
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
  bool known = true;
  bool boundaryKnown = true;
  List<Map<String, dynamic>>? forecastHours;
  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) {}
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module == 'searchCities') {
      return searches
          .putIfAbsent(
            args['query'] as String,
            () => Completer<DashboardData>(),
          )
          .future;
    }
    if (module == 'weather') {
      weatherCalls.add(args);
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
      );
    }
    return DashboardData(
      data: {
        'year': args['year'],
        'known': known,
        'boundaryKnown': boundaryKnown,
        'days': [
          {'date': '2026-10-10', 'name': '国庆节', 'isOffDay': false},
          {'date': '2026-10-09', 'name': '国庆节', 'isOffDay': true},
        ],
        'papers': <String>[],
      },
      fetchedAt: _now,
    );
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
  testWidgets('outing windows reject hours crossing midnight', (tester) async {
    final client = _Client()
      ..forecastHours = [
        for (final time in [
          '2026-10-18T22:00',
          '2026-10-18T23:00',
          '2026-10-19T00:00',
          '2026-10-19T01:00',
          '2026-10-19T07:00',
          '2026-10-19T08:00',
          '2026-10-19T09:00',
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
    expect(find.text('10/19 07:00–10:00'), findsOneWidget);
    expect(find.text('10/18 22:00–01:00'), findsNothing);
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
      expect(find.text('10/18 09:00–12:00'), findsOneWidget);
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

  testWidgets('weather and holiday panels fit 320 px at double text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _Client();
    await tester.pumpWidget(
      _frame(_WeatherHarness(client, initialCity: _beijing), scale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      _frame(
        HolidayPanel(
          client: client,
          leaveDays: 5,
          onLeaveDaysChanged: (_) {},
          now: () => _now,
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('连休'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown official year does not offer a weekend-based plan', (
    tester,
  ) async {
    final client = _Client()..known = false;
    await tester.pumpWidget(
      _frame(
        HolidayPanel(
          client: client,
          leaveDays: 5,
          onLeaveDaysChanged: (_) {},
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('官方调休安排待公布或暂不可用'), findsOneWidget);
    expect(find.text('确认官方安排后，才会计算拼假。'), findsOneWidget);
    expect(find.textContaining('请 5 天，连休'), findsNothing);
  });
}
