import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/news_panel.dart';

class _FakeClient implements DashboardClient {
  final opened = <String>[];
  final requests = <Map<String, dynamic>>[];
  bool emptyNews = false;

  @override
  String? readPreferences() => null;

  @override
  bool writePreferences(String raw) => true;

  @override
  void openUrl(String url) => opened.add(url);

  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    requests.add({'module': module, ...args, 'refresh': refresh});
    return DashboardData(
      fetchedAt: DateTime(2026, 10, 18, 9),
      data: switch (module) {
        'news' => {
          'feed': args['feed'],
          'stories': emptyNews
              ? []
              : [
                  for (var i = 1; i <= (args['feed'] == 'zh' ? 45 : 10); i++)
                    {
                      'id': i,
                      'title': args['feed'] == 'zh'
                          ? '中文资讯 $i：科技、数码与效率生活'
                          : 'Story $i: An English headline that wraps on a small screen',
                      'score': 100 + i,
                      'comments': i,
                      'url': 'https://example.com/story/$i',
                      'discussion': 'https://news.ycombinator.com/item?id=$i',
                      'time': 1792278000,
                      'by': 'reader$i',
                    },
                ],
        },
        _ => <String, dynamic>{},
      },
    );
  }
}

Future<void> _pumpPanel(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Chinese feed shows original headlines without fabricated HN metrics',
    (tester) async {
      final client = _FakeClient();
      await _pumpPanel(
        tester,
        NewsPanel(client: client, feed: 'zh', onFeedChanged: (_) {}),
      );
      expect(client.requests.single['feed'], 'zh');
      expect(find.text('中文资讯 1：科技、数码与效率生活'), findsOneWidget);
      expect(find.text('中文资讯 · 官方 RSS 汇总 ↗'), findsOneWidget);
      expect(find.textContaining('条评论 · HN'), findsNothing);
      expect(find.text('101 分'), findsNothing);
      expect(find.text('中文资讯 20：科技、数码与效率生活'), findsOneWidget);
      expect(find.text('中文资讯 21：科技、数码与效率生活'), findsNothing);
      await tester.ensureVisible(find.text('加载更多 · 已显示 20 / 45 条'));
      await tester.tap(find.text('加载更多 · 已显示 20 / 45 条'));
      await tester.pumpAndSettle();
      expect(find.text('中文资讯 40：科技、数码与效率生活'), findsOneWidget);
      expect(find.text('中文资讯 41：科技、数码与效率生活'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('news renders six stories, opens links and switches feeds', (
    tester,
  ) async {
    final client = _FakeClient();
    var feed = 'top';
    await _pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => NewsPanel(
          client: client,
          feed: feed,
          onFeedChanged: (value) => setState(() => feed = value),
        ),
      ),
    );
    expect(find.textContaining('Story 6:'), findsOneWidget);
    expect(find.textContaining('Story 7:'), findsNothing);
    await tester.tap(find.textContaining('Story 1:'));
    expect(client.opened.last, 'https://example.com/story/1');
    await tester.tap(find.text('1 条评论 · HN'));
    expect(client.opened.last, 'https://news.ycombinator.com/item?id=1');
    await tester.ensureVisible(find.text('展开全部 10 条'));
    await tester.tap(find.text('展开全部 10 条'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Story 10:'), findsOneWidget);
    await tester.ensureVisible(find.text('HN 最新'));
    await tester.tap(find.text('HN 最新'));
    await tester.pumpAndSettle();
    expect(feed, 'new');
    expect(client.requests.last['feed'], 'new');
    expect(find.textContaining('Story 7:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty news feed is explicit', (tester) async {
    final client = _FakeClient()..emptyNews = true;
    await _pumpPanel(
      tester,
      NewsPanel(client: client, feed: 'show', onFeedChanged: (_) {}),
    );
    expect(find.text('当前列表暂无可显示的文章，请稍后刷新。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
