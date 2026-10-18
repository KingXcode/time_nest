import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

class FixtureDashboardClient implements DashboardClient {
  String? preferences;
  bool persistent = true;
  bool fail = false;
  final calls = <String>[];
  final opened = <String>[];

  @override
  String? readPreferences() => preferences;
  @override
  bool writePreferences(String raw) {
    preferences = raw;
    return persistent;
  }

  @override
  void openUrl(String url) => opened.add(url);
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    calls.add(module);
    if (fail) throw Exception('网络暂时不可用，请稍后重试。');
    final data = switch (module) {
      'weather' => {
        'timezone': 'Asia/Shanghai',
        'utcOffsetSeconds': 28800,
        'hours': [
          for (var i = 0; i < 36; i++)
            {
              'time': DateTime.now()
                  .toUtc()
                  .add(Duration(hours: i + 8))
                  .toIso8601String()
                  .substring(0, 16),
              'feels': 21 + i % 3,
              'rain': 12,
              'wind': 9,
              'code': 1,
            },
        ],
      },
      'holidays' => {
        'year': args['year'],
        'known': true,
        'days': [
          {'date': '${args['year']}-10-01', 'name': '国庆节', 'isOffDay': true},
          {'date': '${args['year']}-10-10', 'name': '国庆节', 'isOffDay': false},
        ],
        'papers': <String>[],
      },
      'releases' => {
        'repo': args['repo'],
        'noReleases': false,
        'releases': [
          {
            'name': 'Stable release',
            'tag': '3.47.5',
            'publishedAt': '2026-10-17T12:00:00Z',
            'url': 'https://github.com/flutter/flutter/releases',
            'body': 'Test release with improvements.',
          },
        ],
      },
      'fx' => {
        'base': args['base'],
        'quote': args['quote'],
        'rate': 7.12,
        'date': '2026-10-16',
        'history': [
          {'date': '2026-09-16', 'rate': 7.05},
          {'date': '2026-10-16', 'rate': 7.12},
        ],
      },
      'news' => {
        'feed': args['feed'],
        'stories': [
          for (var i = 0; i < 6; i++)
            {
              'id': i + 1,
              'title':
                  'An interesting development story with an unusually long English title $i',
              'score': 125,
              'comments': 42,
              'url': 'https://example.com/$i',
              'discussion': 'https://news.ycombinator.com/item?id=${i + 1}',
              'time': 1792281600,
              'by': 'tester',
            },
        ],
      },
      _ => {
        'cities': [
          {
            'name': '上海',
            'latitude': 31.23,
            'longitude': 121.47,
            'country': '中国',
            'admin1': '上海',
            'timezone': 'Asia/Shanghai',
          },
        ],
      },
    };
    return DashboardData(data: data, fetchedAt: DateTime(2026, 10, 18, 9));
  }
}

Widget app(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(736, 320),
    const Size(1280, 900),
  ]) {
    testWidgets('dashboard all live modules render and scroll at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureDashboardClient();
      client.preferences = DashboardPreferences(
        city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
      ).encode();
      await tester.pumpWidget(
        app(DashboardScreen(client: client, now: () => DateTime(2026, 10, 18))),
      );
      await tester.pumpAndSettle();
      expect(find.text('今天的事，一眼有数。'), findsOneWidget);
      expect(
        client.calls.toSet(),
        containsAll(['weather', 'holidays', 'releases', 'fx', 'news']),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const PageStorageKey('dashboard-scroll')),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('all cards remain usable at 320px and double text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client), scale: 2));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const PageStorageKey('dashboard-scroll')),
      const Offset(0, -2400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('favorites, ordering and persistence remain editable', (
    tester,
  ) async {
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消收藏什么时候出门'));
    await tester.pumpAndSettle();
    expect(DashboardPreferences.decode(client.preferences).favorites, [
      'holidays',
    ]);
    await tester.tap(find.text('已收藏 1'));
    await tester.pumpAndSettle();
    expect(find.text('什么时候出门'), findsNothing);
    await tester.tap(find.byTooltip('调整卡片顺序'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移下个假期怎么拼'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      DashboardPreferences.decode(client.preferences).order.first,
      'holidays',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('已收藏 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather never requests network weather before city chosen', (
    tester,
  ) async {
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    expect(client.calls, isNot(contains('weather')));
    expect(client.calls, isNot(contains('searchCities')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('errors have retry and storage failure is visible', (
    tester,
  ) async {
    final client = FixtureDashboardClient()
      ..fail = true
      ..persistent = false;
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsWidgets);
    await tester.tap(find.byTooltip('取消收藏什么时候出门'));
    await tester.pumpAndSettle();
    expect(find.text('浏览器存储不可用。当前选择仍可使用，刷新后可能丢失。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clock dashboard returns without changing settings or timer', (
    tester,
  ) async {
    final browser = MemoryBrowserClient(introSeen: true);
    await tester.pumpWidget(ShikeApp(browser: browser));
    await tester.pump();
    final settings = browser.settings, timer = browser.timer;
    await tester.tap(find.byTooltip('每日看板').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('今天的事，一眼有数。'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(browser.settings, settings);
    expect(browser.timer, timer);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
