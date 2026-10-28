import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/apple_button.dart';
import 'dashboard_client.dart';
import 'dashboard_widgets.dart';
import 'news_article.dart';

// Guard per Navigator, rather than per row: fast taps on different headlines
// must not stack duplicate routes. The retained list owns its scroll position.
final _reading = Expando<bool>();
Future<void> openNewsDetail(
  BuildContext context, {
  required DashboardClient client,
  required Map story,
  DashboardData? snapshot,
}) async {
  final navigator = Navigator.of(context);
  if (_reading[navigator] == true) return;
  _reading[navigator] = true;
  try {
    await navigator.push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/news/article'),
        builder: (_) => NewsDetailScreen(
          client: client,
          article: NewsArticle.fromJson(story),
          stale: snapshot?.stale ?? false,
          warning: snapshot?.warning,
        ),
      ),
    );
  } finally {
    _reading[navigator] = false;
  }
}

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({
    super.key,
    required this.client,
    required this.article,
    this.stale = false,
    this.warning,
  });
  final DashboardClient client;
  final NewsArticle article;
  final bool stale;
  final String? warning;

  void _open(BuildContext context, String url) {
    if (safeNewsUrl(url).isEmpty) return;
    try {
      client.openUrl(url);
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('原文暂时无法打开，请稍后重试。')));
    }
  }

  String get _date {
    final date = article.publishedAt;
    if (date == null) return '发布时间未知';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)} · 本地时间';
  }

  String get _explanation => switch (article.reason) {
    'too_large' => '正文超出应用内阅读长度限制，请前往来源网站阅读全文。',
    'invalid_content' => '正文格式暂不支持安全展示，请前往来源网站阅读全文。',
    'not_provided' => '当前快照未提供可阅读正文，请前往来源网站阅读全文。',
    _ => '尚未确认该来源允许在本应用转载正文或摘要。请点击上方「阅读原文」，在来源网站阅读全文。',
  };

  @override
  Widget build(BuildContext context) => Theme(
    data: dashboardTheme(Theme.of(context)),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const ValueKey('news-detail-page'),
          appBar: AppBar(
            title: const Text('资讯详情'),
            leading: const BackButton(),
          ),
          body: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              key: const PageStorageKey('news-detail-scroll'),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            article.title,
                            key: const ValueKey('news-detail-title'),
                            style: const TextStyle(
                              fontSize: 25,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppleButton.filledIcon(
                            key: const ValueKey('news-original-link'),
                            onPressed: article.url.isEmpty
                                ? null
                                : () => _open(context, article.url),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 17,
                            ),
                            label: const Text('阅读原文'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        if (article.url.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('原文链接不可用，可返回列表刷新后重试。'),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          '来源：${article.source.isEmpty ? '未知' : article.source}',
                          key: const ValueKey('news-detail-source'),
                          style: const TextStyle(
                            color: dashboardMuted,
                            height: 1.6,
                          ),
                        ),
                        Text(
                          _date,
                          style: const TextStyle(
                            color: dashboardMuted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        if (article.url.isNotEmpty)
                          Text(
                            Uri.parse(article.url).host,
                            style: const TextStyle(
                              color: dashboardMuted,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        if (stale || warning != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              [
                                if (stale) '当前为上次保存的资讯，可能已过时。',
                                ?warning,
                              ].join(' '),
                              style: const TextStyle(
                                color: dashboardMuted,
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(height: 1),
                        ),
                        Text(
                          article.kind == 'full'
                              ? '全文 · 已获转载许可'
                              : article.kind == 'excerpt'
                              ? '来源摘要 · 非全文'
                              : '请前往原文阅读',
                          key: const ValueKey('news-content-label'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: dashboardAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          article.body.isEmpty ? _explanation : article.body,
                          key: const ValueKey('news-detail-body'),
                          style: const TextStyle(fontSize: 17, height: 1.85),
                        ),
                        if (article.kind == 'excerpt')
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              '以上为来源摘要，不代表完整文章。阅读全文请使用标题下的原文入口。',
                              style: TextStyle(
                                color: dashboardMuted,
                                height: 1.6,
                              ),
                            ),
                          ),
                        if (article.licenseUrl.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AppleButton.text(
                              onPressed: () =>
                                  _open(context, article.licenseUrl),
                              child: const Text('转载许可说明 ↗'),
                            ),
                          ),
                        if (article.discussion.isNotEmpty &&
                            article.discussion != article.url)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AppleButton.textIcon(
                              onPressed: () =>
                                  _open(context, article.discussion),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                              ),
                              label: const Text('查看 HN 讨论'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
