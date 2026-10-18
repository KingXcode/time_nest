import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';
import 'package:time_nest/dashboard/fx_panel.dart';
import 'package:time_nest/dashboard/market_panel.dart';
import 'package:time_nest/dashboard/news_panel.dart';
import 'package:time_nest/dashboard/releases_panel.dart';
import 'package:time_nest/dashboard/weather_panel.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

class FixtureDashboardClient implements DashboardClient {
  String? preferences;
  bool persistent = true;
  bool fail = false;
  Completer<void>? pending;
  final calls = <String>[];
  final requests = <Map<String, dynamic>>[];
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
    requests.add({'module': module, ...args});
    if (pending != null) await pending!.future;
    if (fail) throw Exception('网络暂时不可用，请稍后重试。');
    final data = switch (module) {
      'weather' => {
        'timezone': 'Asia/Shanghai',
        'utcOffsetSeconds': 28800,
        'hours': [
          for (var i = 0; i < 36; i++)
            {
              'time': DateTime.utc(
                2026,
                10,
                18,
                9,
              ).add(Duration(hours: i)).toIso8601String().substring(0, 16),
              'temperature': 23 + i % 3,
              'feels': 21 + i % 3,
              'rain': 12,
              'wind': 9,
              'code': 1,
            },
        ],
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

const titles = {
  'weather': '天气',
  'releases': '项目更新',
  'fx': '汇率换算',
  'news': '科技资讯',
  'market': 'A股行情',
};
final testNow = DateTime.utc(2026, 10, 18, 1);

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> openModule(WidgetTester tester, String id) async {
  final entry = find.byKey(ValueKey('dashboard-entry-$id'));
  final title = find.descendant(of: entry, matching: find.text(titles[id]!));
  await tester.ensureVisible(title);
  await tester.pumpAndSettle();
  await tester.tap(title);
  await tester.pumpAndSettle();
  expect(find.byKey(ValueKey('dashboard-page-$id')), findsOneWidget);
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(736, 320),
    const Size(1280, 900),
  ]) {
    testWidgets('home is an entry-only page with zero requests at $size', (
      tester,
    ) async {
      setSize(tester, size);
      final client = FixtureDashboardClient()
        ..preferences = DashboardPreferences(
          city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
        ).encode();
      await tester.pumpWidget(
        app(DashboardScreen(client: client, now: () => testNow)),
      );
      await tester.pumpAndSettle();
      expect(find.text('今天的事，一眼有数。'), findsOneWidget);
      for (final id in dashboardModules) {
        expect(find.byKey(ValueKey('dashboard-entry-$id')), findsOneWidget);
      }
      expect(find.byType(WeatherPanel), findsNothing);
      expect(find.byType(ReleasesPanel), findsNothing);
      expect(find.byType(FxPanel), findsNothing);
      expect(find.byType(NewsPanel), findsNothing);
      expect(find.textContaining('假期'), findsNothing);
      expect(client.calls, isEmpty);
      await tester.drag(
        find.byKey(const PageStorageKey('dashboard-scroll')),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      expect(client.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final viewport in [
    (const Size(320, 900), 2.0),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets('independent pages load only on entry and fit $viewport', (
      tester,
    ) async {
      setSize(tester, viewport.$1);
      final client = FixtureDashboardClient()
        ..preferences = DashboardPreferences(
          city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
        ).encode();
      await tester.pumpWidget(
        app(
          DashboardScreen(client: client, now: () => testNow),
          scale: viewport.$2,
        ),
      );
      await tester.pumpAndSettle();
      expect(client.calls, isEmpty);
      expect(tester.takeException(), isNull);
      for (final id in dashboardModules) {
        client.calls.clear();
        await openModule(tester, id);
        expect(client.calls.toSet(), id == 'market' ? <String>{} : {id});
        expect(
          client.calls.length,
          id == 'market'
              ? 0
              : id == 'releases'
              ? 4
              : 1,
        );
        expect(
          find.byType(MarketPanel),
          id == 'market' ? findsOneWidget : findsNothing,
        );
        expect(find.text('今天的事，一眼有数。'), findsNothing);
        expect(
          find.byType(WeatherPanel),
          id == 'weather' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(ReleasesPanel),
          id == 'releases' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(FxPanel),
          id == 'fx' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NewsPanel),
          id == 'news' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byKey(PageStorageKey('dashboard-$id-scroll')),
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        client.calls.clear();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('今天的事，一眼有数。'), findsOneWidget);
        expect(client.calls, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('favorites and ordering persist without loading modules', (
    tester,
  ) async {
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消收藏天气'));
    await tester.pumpAndSettle();
    expect(DashboardPreferences.decode(client.preferences).favorites, isEmpty);
    await tester.tap(find.text('已收藏 0'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard-entry-weather')), findsNothing);
    expect(find.text('还没有收藏。在全部功能里点一下星标吧。'), findsOneWidget);
    await tester.tap(find.text('全部功能'));
    await tester.pumpAndSettle();
    final favorite = find.byTooltip('收藏项目更新');
    await tester.ensureVisible(favorite);
    await tester.tap(favorite);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('调整入口顺序'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移项目更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      DashboardPreferences.decode(client.preferences).order.first,
      'releases',
    );
    expect(DashboardPreferences.decode(client.preferences).favorites, [
      'releases',
    ]);
    expect(client.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('已收藏 1'), findsOneWidget);
    expect(find.byTooltip('取消收藏项目更新'), findsOneWidget);
    expect(client.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather waits for city and keeps it after back and reopen', (
    tester,
  ) async {
    final client = FixtureDashboardClient();
    await tester.pumpWidget(
      app(DashboardScreen(client: client, now: () => testNow)),
    );
    await tester.pumpAndSettle();
    await openModule(tester, 'weather');
    expect(client.calls, isEmpty);
    await tester.enterText(find.byType(TextField), '上海');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(client.calls, ['searchCities']);
    await tester.tap(find.widgetWithText(OutlinedButton, '上海'));
    await tester.pumpAndSettle();
    expect(client.calls, ['searchCities', 'weather']);
    expect(DashboardPreferences.decode(client.preferences).city?['name'], '上海');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    client.calls.clear();
    await openModule(tester, 'weather');
    expect(find.text('上海'), findsOneWidget);
    expect(client.calls, ['weather']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('news selections update on page and survive back and restart', (
    tester,
  ) async {
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    await openModule(tester, 'news');
    expect(client.requests.last['feed'], 'sspai');
    await tester.tap(find.text('HN 最新'));
    await tester.pumpAndSettle();
    expect(client.requests.last['feed'], 'new');
    expect(DashboardPreferences.decode(client.preferences).feed, 'new');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openModule(tester, 'news');
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'HN 最新'))
          .selected,
      isTrue,
    );
    expect(client.requests.last['feed'], 'new');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    await openModule(tester, 'news');
    expect(client.requests.last['feed'], 'new');
    expect(client.calls.toSet(), {'news'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository removal survives back and reopening', (tester) async {
    final client = FixtureDashboardClient()
      ..preferences = DashboardPreferences(
        repos: ['flutter/flutter', 'dart-lang/sdk'],
      ).encode();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    await openModule(tester, 'releases');
    await tester.tap(find.byTooltip('移除 flutter/flutter'));
    await tester.pumpAndSettle();
    expect(find.text('flutter/flutter'), findsNothing);
    expect(DashboardPreferences.decode(client.preferences).repos, [
      'dart-lang/sdk',
    ]);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    client.requests.clear();
    await openModule(tester, 'releases');
    expect(client.requests, [
      {'module': 'releases', 'repo': 'dart-lang/sdk'},
    ]);
    expect(find.text('已关注 1 个项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a loading page ignores its late response', (
    tester,
  ) async {
    final gate = Completer<void>();
    final client = FixtureDashboardClient()..pending = gate;
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    final news = find.descendant(
      of: find.byKey(const ValueKey('dashboard-entry-news')),
      matching: find.text('科技资讯'),
    );
    await tester.ensureVisible(news);
    await tester.pumpAndSettle();
    await tester.tap(news);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('正在获取最新数据…'), findsOneWidget);
    expect(client.calls, ['news']);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('今天的事，一眼有数。'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(client.calls, ['news']);
    expect(find.byType(NewsPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await openModule(tester, 'news');
    expect(client.calls, ['news', 'news']);
    expect(find.text('正在获取最新数据…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FX amount edits update the page and survive back', (
    tester,
  ) async {
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    await openModule(tester, 'fx');
    final amount = find.byType(TextField);
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '250');
    await tester.pumpAndSettle();
    expect(DashboardPreferences.decode(client.preferences).amount, 250);
    expect(find.text('1,780.00 CNY'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openModule(tester, 'fx');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '250',
    );
    expect(client.calls.toSet(), {'fx'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected module can retry and reports persistence errors', (
    tester,
  ) async {
    final client = FixtureDashboardClient()
      ..fail = true
      ..persistent = false;
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsNothing);
    expect(client.calls, isEmpty);
    await openModule(tester, 'news');
    expect(find.text('重试'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('HN 最新'));
    await tester.pumpAndSettle();
    expect(find.text('浏览器存储不可用。当前选择仍可使用，刷新后可能丢失。'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('浏览器存储不可用。当前选择仍可使用，刷新后可能丢失。'), findsOneWidget);
    expect(client.calls.toSet(), {'news'});
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
