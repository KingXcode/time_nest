import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
import 'dashboard_widgets.dart';
import '../ui/apple_button.dart';

const _newsAccent = Color(0xFF67D8C2);

class NewsPanel extends StatefulWidget {
  const NewsPanel({
    super.key,
    required this.client,
    required this.feed,
    required this.onFeedChanged,
  });

  final DashboardClient client;
  final String feed;
  final ValueChanged<String> onFeedChanged;

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends State<NewsPanel> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant NewsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed != widget.feed) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final feed = dashboardFeeds.contains(widget.feed) ? widget.feed : 'sspai';
    final chinese = feed == 'sspai';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final option in const [
              ('sspai', '中文 · 少数派'),
              ('top', 'HN 热门'),
              ('new', 'HN 最新'),
              ('show', 'Show HN'),
            ])
              ChoiceChip(
                label: Text(option.$2),
                selected: feed == option.$1,
                selectedColor: const Color(0xFF21443E),
                labelStyle: TextStyle(
                  color: feed == option.$1 ? _newsAccent : null,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => widget.onFeedChanged(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          chinese
              ? '少数派官方 RSS · 科技、数码与效率生活，标题为中文原文。'
              : 'Hacker News 英文原文，保留文章与讨论链接。',
          style: const TextStyle(
            color: Color(0xFFA8B5BB),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ApiSection(
          client: widget.client,
          module: 'news',
          args: {'feed': feed},
          sourceLabel: chinese ? '少数派 · 官方 RSS' : 'Hacker News · 官方 API',
          sourceUrl: chinese
              ? 'https://sspai.com/feed'
              : 'https://github.com/HackerNews/API',
          builder: (context, result) {
            final raw = result.data['stories'];
            final stories = raw is List
                ? raw.whereType<Map>().take(10).toList()
                : <Map>[];
            if (stories.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('当前列表暂无可显示的文章，请稍后刷新。'),
              );
            }
            final count = _expanded
                ? stories.length
                : stories.length.clamp(0, 6);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DashboardColumns(
                  children: [
                    for (var i = 0; i < count; i++)
                      _NewsStory(
                        client: widget.client,
                        story: stories[i],
                        rank: i + 1,
                        chinese: chinese,
                      ),
                  ],
                ),
                if (stories.length > 6)
                  AppleButton.textIcon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _expanded ? '收起列表' : '展开全部 ${stories.length} 条',
                    ),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _NewsStory extends StatelessWidget {
  const _NewsStory({
    required this.client,
    required this.story,
    required this.rank,
    required this.chinese,
  });
  final DashboardClient client;
  final Map story;
  final int rank;
  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final title = story['title'] is String ? story['title'] as String : '未命名文章';
    final id = story['id'];
    final discussion =
        story['discussion'] is String &&
            (story['discussion'] as String).isNotEmpty
        ? story['discussion'] as String
        : chinese
        ? ''
        : 'https://news.ycombinator.com/item?id=$id';
    final url = story['url'] is String && (story['url'] as String).isNotEmpty
        ? story['url'] as String
        : discussion;
    final domain =
        Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';
    final score = story['score'] is num ? (story['score'] as num).toInt() : 0;
    final comments = story['comments'] is num
        ? (story['comments'] as num).toInt()
        : 0;
    final by = story['by'] is String ? story['by'] as String : '';
    final time = _storyTime(story['time']);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              rank.toString().padLeft(2, '0'),
              style: const TextStyle(color: Color(0xFF7E9299), fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppleButton.text(
                onPressed: () => client.openUrl(url),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE5EDEE),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  minimumSize: const Size(0, 32),
                  alignment: Alignment.centerLeft,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 9,
                runSpacing: 4,
                children: [
                  if (!chinese)
                    Text(
                      '$score 分',
                      style: const TextStyle(color: _newsAccent, fontSize: 12),
                    ),
                  if (domain.isNotEmpty)
                    Text(
                      domain,
                      style: const TextStyle(
                        color: Color(0xFFA8B5BB),
                        fontSize: 12,
                      ),
                    ),
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: const TextStyle(
                        color: Color(0xFFA8B5BB),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              if (!chinese)
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppleButton.textIcon(
                      onPressed: () => client.openUrl(discussion),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                      ),
                      label: Text(
                        '$comments 条评论 · HN',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (by.isNotEmpty)
                      Text(
                        'by $by',
                        style: const TextStyle(
                          color: Color(0xFF8FA0A6),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _storyTime(Object? time) {
  DateTime? date;
  if (time is num && time.isFinite && time >= 0 && time < 8640000000000) {
    date = DateTime.fromMillisecondsSinceEpoch((time * 1000).toInt());
  } else if (time is String) {
    date = DateTime.tryParse(time);
  }
  if (date == null) return '';
  final difference = DateTime.now().difference(date);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  return '${difference.inDays} 天前';
}
