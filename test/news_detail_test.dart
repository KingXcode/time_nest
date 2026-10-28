import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_overview.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/news_article.dart';
import 'package:time_nest/dashboard/news_detail_screen.dart';
import 'package:time_nest/dashboard/news_panel.dart';

const _story = {
  'title': '测试资讯：这是用于验证阅读界面的原创测试标题',
  'url': 'https://sspai.com/post/100001',
  'source': '少数派',
  'sourceId': 'sspai',
  'time': 1792278000,
};
const _permission = NewsReusePermission(
  licenseUrl: 'https://example.org/license',
  excerpt: true,
  full: true,
);

class _Client implements DashboardClient {
  int loads = 0;
  bool fail = false, throwOnOpen = false;
  Completer<void>? pending;
  final opened = <String>[];
  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) {
    if (throwOnOpen) throw StateError('unavailable');
    opened.add(url);
  }

  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    loads++;
    if (pending != null) await pending!.future;
    if (fail) throw const DashboardException('网络暂不可用');
    return DashboardData(
      fetchedAt: DateTime(2026, 10, 28),
      stale: true,
      warning: '少数派暂不可用，显示缓存',
      data: {
        'stories': [
          for (var i = 0; i < 25; i++)
            {
              ..._story,
              'title': '测试资讯 $i',
              'url': 'https://sspai.com/post/${100001 + i}',
            },
        ],
      },
    );
  }
}

Map _withBody(String kind, String text) => {
  ..._story,
  'sourceId': 'licensed-test-source',
  'content': {
    'kind': kind,
    'format': 'plain_text',
    'text': text,
    'licenseUrl': _permission.licenseUrl,
  },
};
NewsArticle _licensed(Map data) => NewsArticle.fromJson(
  data,
  permissions: const {'licensed-test-source': _permission},
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(bottom: 34, left: 4, right: 4),
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: child,
    ),
  );
  await tester.pump();
}

void main() {
  test('untrusted URLs allow only credential-free HTTP(S)', () {
    for (final value in [
      null,
      3,
      'javascript:alert(1)',
      'data:text/html,x',
      '//example.com',
      'https://user:pass@example.org',
      'https://example.com\n.bad',
      r'https://example.com\@evil.org',
      'file:///etc/passwd',
      '',
    ]) {
      expect(safeNewsUrl(value), '', reason: '$value');
    }
    expect(
      safeNewsUrl('https://example.com/path?a=1#part'),
      'https://example.com/path?a=1#part',
    );
    expect(safeNewsUrl('http://example.com/'), 'http://example.com/');
  });

  test(
    'missing/forged permission and old schema never expose article bodies',
    () {
      expect(newsReusePermissions, isEmpty);
      expect(NewsArticle.fromJson(_story).kind, 'unavailable');
      for (final source in ['sspai', 'ithome', 'solidot', 'unknown']) {
        final article = NewsArticle.fromJson({
          ..._withBody('full', 'forged'),
          'sourceId': source,
        });
        expect(article.body, isEmpty);
        expect(article.reason, 'permission_required');
      }
    },
  );

  test(
    'reviewed source supports clearly labeled bounded plain-text full/excerpt',
    () {
      expect(_licensed(_withBody('full', '原创测试第一段\n\n第二段。')).kind, 'full');
      expect(_licensed(_withBody('excerpt', '原创测试摘要')).kind, 'excerpt');
      expect(_licensed(_withBody('full', '文' * 24001)).reason, 'too_large');
      expect(_licensed(_withBody('excerpt', '文' * 281)).reason, 'too_large');
      expect(
        _licensed(_withBody('excerpt', '😀' * 280)).body.runes.length,
        280,
      );
      final badLicense = _withBody('full', 'text');
      (badLicense['content'] as Map)['licenseUrl'] = 'javascript:alert(1)';
      expect(_licensed(badLicense).body, isEmpty);
      final badFormat = _withBody('full', '<script>danger</script>');
      (badFormat['content'] as Map)['format'] = 'html';
      expect(_licensed(badFormat).body, isEmpty);
      expect(_licensed(_withBody('full', '')).body, isEmpty);
      expect(
        NewsArticle.fromJson({'time': double.infinity}).publishedAt,
        isNull,
      );
      expect(NewsArticle.fromJson({'title': 'x' * 900}).title.length, 500);
    },
  );

  testWidgets(
    'original link directly follows title, with source/date and honest fallback',
    (tester) async {
      final client = _Client();
      await _pump(
        tester,
        NewsDetailScreen(client: client, article: NewsArticle.fromJson(_story)),
      );
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('news-detail-title'));
      final original = find.byKey(const Key('news-original-link'));
      final source = find.byKey(const Key('news-detail-source'));
      expect(
        tester.getBottomLeft(title).dy,
        lessThan(tester.getTopLeft(original).dy),
      );
      expect(
        tester.getBottomLeft(original).dy,
        lessThan(tester.getTopLeft(source).dy),
      );
      expect(find.text('请前往原文阅读'), findsOneWidget);
      expect(find.textContaining('本地时间'), findsOneWidget);
      expect(client.loads, 0);
      await tester.tap(find.text('阅读原文'));
      expect(client.opened, [_story['url']]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list tap opens once without network and back restores exact list position',
    (tester) async {
      final client = _Client();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: NewsPanel(client: client, feed: 'zh', onFeedChanged: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('测试资讯 12'));
      await tester.pumpAndSettle();
      final before = scroll.offset;
      final title = find.text('测试资讯 12');
      final buttonContext = tester.element(title);
      // Simulate overlapping row callbacks before the navigation transition builds.
      unawaited(openNewsDetail(buttonContext, client: client, story: _story));
      unawaited(openNewsDetail(buttonContext, client: client, story: _story));
      await tester.pumpAndSettle();
      expect(find.byType(NewsDetailScreen), findsOneWidget);
      expect(client.loads, 1);
      expect(client.opened, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NewsDetailScreen), findsNothing);
      expect(scroll.offset, before);
      expect(find.text('测试资讯 12'), findsOneWidget);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.textContaining('上次保存的资讯'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(NewsDetailScreen), findsNothing);
      expect(client.loads, 1);
    },
  );

  testWidgets('overview headline also opens detail, not an external page', (
    tester,
  ) async {
    final client = _Client();
    await _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: DashboardOverview(
            client: client,
            preferences: DashboardPreferences.decode(null),
            modules: const ['news'],
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试资讯 0'));
    await tester.pumpAndSettle();
    expect(find.byType(NewsDetailScreen), findsOneWidget);
    expect(client.opened, isEmpty);
    expect(client.loads, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NewsDetailScreen), findsNothing);
  });

  testWidgets(
    'loading/error/retry settles before detail and malformed link stays disabled',
    (tester) async {
      final client = _Client()
        ..pending = Completer<void>()
        ..fail = true;
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: NewsPanel(client: client, feed: 'zh', onFeedChanged: (_) {}),
          ),
        ),
      );
      expect(find.text('正在获取最新数据…'), findsOneWidget);
      client.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('网络暂不可用'), findsOneWidget);
      client.fail = false;
      client.pending = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('测试资讯 0'), findsOneWidget);
      await _pump(
        tester,
        NewsDetailScreen(
          client: client,
          article: NewsArticle.fromJson({
            ..._story,
            'url': 'javascript:alert(1)',
          }),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('阅读原文'));
      expect(client.opened, isEmpty);
      expect(find.textContaining('原文链接不可用'), findsOneWidget);
    },
  );

  testWidgets('external opener failure is recoverable', (tester) async {
    final client = _Client()..throwOnOpen = true;
    await _pump(
      tester,
      NewsDetailScreen(client: client, article: NewsArticle.fromJson(_story)),
    );
    await tester.tap(find.text('阅读原文'));
    await tester.pump();
    expect(find.text('原文暂时无法打开，请稍后重试。'), findsOneWidget);
    client.throwOnOpen = false;
    await tester.tap(find.text('阅读原文'));
    expect(client.opened, [_story['url']]);
  });

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'plain reading remains scrollable at $size and double text scale',
      (tester) async {
        final text = List.filled(80, '这是原创的合成测试段落，不是来源文章内容。').join('\n\n');
        await _pump(
          tester,
          NewsDetailScreen(
            client: _Client(),
            article: _licensed(_withBody('full', text)),
          ),
          size: size,
          scale: 2,
        );
        await tester.pumpAndSettle();
        expect(find.text('全文 · 已获转载许可'), findsOneWidget);
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(find.text('转载许可说明 ↗')).dy,
          lessThanOrEqualTo(size.height - 34),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
