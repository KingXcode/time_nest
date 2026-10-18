import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_widgets.dart';

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
    final feed = ['top', 'new', 'show'].contains(widget.feed)
        ? widget.feed
        : 'top';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final option in const [
              ('top', '热门'),
              ('new', '最新'),
              ('show', 'Show HN'),
            ])
              ChoiceChip(
                label: Text(option.$2),
                selected: feed == option.$1,
                selectedColor: const Color(0xFF21443E),
                labelStyle: TextStyle(
                  color: feed == option.$1 ? _newsAccent : null,
                ),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => widget.onFeedChanged(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ApiSection(
          client: widget.client,
          module: 'news',
          args: {'feed': feed},
          sourceLabel: 'Hacker News · 官方 API',
          sourceUrl: 'https://github.com/HackerNews/API',
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
                for (var i = 0; i < count; i++) ...[
                  if (i > 0)
                    const Divider(height: 20, color: Color(0xFF30363A)),
                  _NewsStory(
                    client: widget.client,
                    story: stories[i],
                    rank: i + 1,
                  ),
                ],
                if (stories.length > 6)
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _expanded ? '收起列表' : '展开全部 ${stories.length} 条',
                    ),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
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
  });
  final DashboardClient client;
  final Map story;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final title = story['title'] is String
        ? story['title'] as String
        : 'Untitled';
    final id = story['id'];
    final discussion =
        story['discussion'] is String &&
            (story['discussion'] as String).isNotEmpty
        ? story['discussion'] as String
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
            padding: const EdgeInsets.only(top: 12),
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
              TextButton(
                onPressed: () => client.openUrl(url),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE5EDEE),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 48),
                  alignment: Alignment.centerLeft,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 9,
                runSpacing: 4,
                children: [
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
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => client.openUrl(discussion),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      minimumSize: const Size(0, 48),
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
