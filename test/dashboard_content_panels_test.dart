import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/news_panel.dart';
import 'package:time_nest/dashboard/releases_panel.dart';

class _FakeClient implements DashboardClient {
  final opened = <String>[];
  final requests = <Map<String, dynamic>>[];
  bool emptyRelease = false;
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
        'releases' => {
          'repo': args['repo'],
          'noReleases': emptyRelease,
          'releases': emptyRelease
              ? []
              : [
                  {
                    'name': 'A long release name that wraps safely in a narrow card',
                    'tag': 'v3.47.5',
                    'publishedAt': '2026-10-17T10:00:00Z',
                    'url': 'https://github.com/flutter/flutter/releases/tag/v3.47.5',
                    'body': '## Highlights\nA useful update with [release details](https://flutter.dev).',
                  },
                ],
        },
        'news' => {
          'feed': args['feed'],
          'stories': emptyNews
              ? []
              : [
                  for (var i = 1; i <= 10; i++)
                    {
                      'id': i,
                      'title': args['feed'] == 'sspai'
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
    'release controls validate, add, remove and open source at 320px',
    (tester) async {
      final client = _FakeClient();
      var repos = <String>[];
      await _pumpPanel(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ReleasesPanel(
            client: client,
            repos: repos,
            onReposChanged: (value) => setState(() => repos = value),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'not a repo');
      await tester.tap(find.byTooltip('添加仓库'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 owner/repo，例如 flutter/flutter。'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://github.com/flutter/flutter.git',
      );
      await tester.tap(find.byTooltip('添加仓库'));
      await tester.pumpAndSettle();
      expect(repos, ['flutter/flutter']);
      expect(find.text('v3.47.5'), findsOneWidget);
      expect(find.textContaining('Highlights A useful update'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('完整发布说明'));
      expect(
        client.opened.last,
        'https://github.com/flutter/flutter/releases/tag/v3.47.5',
      );
      await tester.enterText(find.byType(TextField), 'Flutter/Flutter');
      await tester.ensureVisible(find.byTooltip('添加仓库'));
      await tester.tap(find.byTooltip('添加仓库'));
      await tester.pumpAndSettle();
      expect(find.text('这个仓库已经在列表中。'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('移除 flutter/flutter'));
      await tester.tap(find.byTooltip('移除 flutter/flutter'));
      await tester.pumpAndSettle();
      expect(repos, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('popular repositories paginate without fetching hidden pages', (
    tester,
  ) async {
    final client = _FakeClient();
    var repos = List<String>.of(defaultDashboardRepos);
    await _pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ReleasesPanel(
          client: client,
          repos: repos,
          onReposChanged: (value) => setState(() => repos = value),
        ),
      ),
    );
    expect(client.requests, hasLength(4));
    expect(find.text('已关注 24 个项目'), findsOneWidget);
    expect(find.text('open-webui/open-webui'), findsNothing);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(client.requests, hasLength(8));
    expect(find.text('open-webui/open-webui'), findsOneWidget);
    expect(find.text('flutter/flutter'), findsNothing);
    expect(find.text('正在显示第 5–8 个，共 24 个'), findsOneWidget);
    await tester.tap(find.byTooltip('移除 open-webui/open-webui'));
    await tester.pumpAndSettle();
    expect(repos, hasLength(23));
    expect(repos, isNot(contains('open-webui/open-webui')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing the last repository on a page returns to a valid page',
    (tester) async {
      final client = _FakeClient();
      var repos = List<String>.of(defaultDashboardRepos.take(5));
      await _pumpPanel(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ReleasesPanel(
            client: client,
            repos: repos,
            onReposChanged: (value) => setState(() => repos = value),
          ),
        ),
      );
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('移除 open-webui/open-webui'));
      await tester.pumpAndSettle();
      expect(repos, hasLength(4));
      expect(find.text('flutter/flutter'), findsOneWidget);
      expect(find.text('下一页'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'popular list can be explicitly restored from an empty selection',
    (tester) async {
      final client = _FakeClient();
      var repos = <String>[];
      await _pumpPanel(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ReleasesPanel(
            client: client,
            repos: repos,
            onReposChanged: (value) => setState(() => repos = value),
          ),
        ),
      );
      expect(client.requests, isEmpty);
      await tester.tap(find.text('补齐热门项目'));
      await tester.pumpAndSettle();
      expect(repos, defaultDashboardRepos);
      expect(client.requests, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Chinese feed shows original headlines without fabricated HN metrics',
    (tester) async {
      final client = _FakeClient();
      await _pumpPanel(
        tester,
        NewsPanel(client: client, feed: 'sspai', onFeedChanged: (_) {}),
      );
      expect(client.requests.single['feed'], 'sspai');
      expect(find.textContaining('中文资讯 1'), findsOneWidget);
      expect(find.text('少数派 · 官方 RSS ↗'), findsOneWidget);
      expect(find.textContaining('条评论 · HN'), findsNothing);
      expect(find.text('101 分'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('release with no published items is explicit', (tester) async {
    final client = _FakeClient()..emptyRelease = true;
    await _pumpPanel(
      tester,
      ReleasesPanel(
        client: client,
        repos: const ['owner/repo'],
        onReposChanged: (_) {},
      ),
    );
    expect(find.text('此仓库尚无 Release。'), findsOneWidget);
    expect(find.text('查看仓库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
