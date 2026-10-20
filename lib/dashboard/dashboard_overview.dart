import 'package:flutter/material.dart';

import 'crypto_market.dart';
import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
import 'dashboard_widgets.dart';

/// Bounded, on-demand snapshots. The full charts and streams belong to detail
/// routes; the overview never starts background polling or a trading widget.
class DashboardOverview extends StatelessWidget {
  const DashboardOverview({
    super.key,
    required this.client,
    required this.preferences,
    required this.modules,
    required this.onOpen,
    this.now,
  });
  final DashboardClient client;
  final DashboardPreferences preferences;
  final List<String> modules;
  final ValueChanged<String> onOpen;
  final DateTime Function()? now;

  Widget _frame(
    String id,
    String title,
    IconData icon,
    String caption,
    Widget child,
  ) => Container(
    key: ValueKey('dashboard-summary-$id'),
    decoration: BoxDecoration(
      color: dashboardSurface,
      border: Border.all(color: dashboardBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: dashboardAccent),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: () => onOpen(id), child: const Text('展开')),
          ],
        ),
        Text(
          caption,
          style: const TextStyle(fontSize: 11, color: dashboardMuted),
        ),
        const SizedBox(height: 8),
        Flexible(fit: FlexFit.loose, child: child),
      ],
    ),
  );

  Widget _quotes() => _frame(
    'crypto',
    '数字货币',
    Icons.currency_bitcoin_rounded,
    '币安现货快照 / USDT / 滚动 24h',
    ApiSection(
      client: client,
      module: 'cryptoQuotes',
      args: const {},
      compact: true,
      sourceLabel: '币安',
      sourceUrl: 'https://www.binance.com/en/markets',
      builder: (context, result) {
        final quotes = (result.data['quotes'] as List? ?? [])
            .whereType<Map>()
            .map(CryptoQuote.fromJson)
            .toList();
        if (quotes.isEmpty) return const Text('暂无报价，可刷新重试。');
        return LayoutBuilder(
          builder: (context, box) {
            final scaledWidth =
                box.maxWidth / MediaQuery.textScalerOf(context).scale(1);
            final columns = scaledWidth >= 660
                ? 6
                : scaledWidth >= 330
                ? 3
                : 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final quote in quotes)
                  SizedBox(
                    width: (box.maxWidth - (columns - 1) * 8) / columns,
                    child: Semantics(
                      label:
                          '${cryptoAssets[quote.symbol]!.$1} 最新 ${cryptoPrice(quote.price)} USDT',
                      child: InkWell(
                        onTap: () => onOpen('crypto'),
                        borderRadius: BorderRadius.circular(5),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cryptoAssets[quote.symbol]!.$1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: dashboardMuted,
                                ),
                              ),
                              Text(
                                cryptoPrice(quote.price),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              Text(
                                '${quote.changePercent >= 0 ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: quote.changePercent >= 0
                                      ? const Color(0xFF67D8AB)
                                      : const Color(0xFFFF8A92),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );

  Widget _weather() {
    final city = preferences.city;
    return _frame(
      'weather',
      city == null ? '天气' : '${city['name']}天气',
      Icons.wb_sunny_outlined,
      '所选城市逐小时预报',
      city == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择城市后显示气温、降雨和风速。'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => onOpen('weather'),
                    icon: const Icon(Icons.add_location_alt_outlined, size: 15),
                    label: const Text('选择城市'),
                  ),
                ],
              ),
            )
          : ApiSection(
              client: client,
              module: 'weather',
              args: {
                'latitude': city['latitude'],
                'longitude': city['longitude'],
              },
              compact: true,
              sourceLabel: 'Open-Meteo',
              sourceUrl: 'https://open-meteo.com/',
              builder: (context, result) {
                final data = result.data;
                final local = (now ?? DateTime.now)().toUtc().add(
                  Duration(
                    seconds: (data['utcOffsetSeconds'] as num? ?? 0).toInt(),
                  ),
                );
                final currentHour = DateTime.utc(
                  local.year,
                  local.month,
                  local.day,
                  local.hour,
                );
                final hours =
                    (data['hours'] as List? ?? []).whereType<Map>().where((
                      row,
                    ) {
                      final time = DateTime.tryParse('${row['time']}Z');
                      return time != null && !time.isBefore(currentHour);
                    }).toList()..sort(
                      (a, b) => '${a['time']}'.compareTo('${b['time']}'),
                    );
                if (hours.isEmpty) return const Text('暂无后续预报，请刷新。');
                final hour = hours.first;
                final temperature =
                    hour['temperature'] as num? ?? hour['feels'] as num?;
                String value(Object? n, String unit) =>
                    n is num ? '${n.round()}$unit' : '—';
                return Wrap(
                  spacing: 18,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      value(temperature, '°'),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${hour['time'].toString().substring(11, 16)} ${hour['temperature'] == null ? '体感预报' : '气温预报'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: dashboardMuted,
                          ),
                        ),
                        Text(
                          '降雨 ${value(hour['rain'], '%')} / 风速 ${value(hour['wind'], ' km/h')}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _news() => _frame(
    'news',
    '科技资讯',
    Icons.article_outlined,
    preferences.feed == 'sspai' ? '少数派 / 中文原文' : 'Hacker News / 英文原文',
    ApiSection(
      client: client,
      module: 'news',
      args: {'feed': preferences.feed},
      compact: true,
      sourceLabel: preferences.feed == 'sspai' ? '少数派 RSS' : 'Hacker News',
      sourceUrl: preferences.feed == 'sspai'
          ? 'https://sspai.com/feed'
          : 'https://news.ycombinator.com/',
      builder: (context, result) {
        final stories = (result.data['stories'] as List? ?? [])
            .whereType<Map>()
            .take(10)
            .toList();
        if (stories.isEmpty) return const Text('暂无文章，可刷新重试。');
        return Column(
          children: [
            for (final story in stories)
              InkWell(
                onTap: () => client.openUrl('${story['url']}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: dashboardBorder)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5, right: 8),
                        child: Icon(
                          Icons.circle,
                          size: 4,
                          color: dashboardAccent,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${story['title']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 6, top: 2),
                        child: Icon(
                          Icons.north_east,
                          size: 12,
                          color: dashboardMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _releases() => _frame(
    'releases',
    '项目更新',
    Icons.code_rounded,
    '已关注 ${preferences.repos.length} 个 / 首页显示前 4 个',
    preferences.repos.isEmpty
        ? TextButton(
            onPressed: () => onOpen('releases'),
            child: const Text('添加关注项目'),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final repo in preferences.repos.take(4))
                Padding(
                  key: ValueKey(repo),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ApiSection(
                    client: client,
                    module: 'releases',
                    args: {'repo': repo},
                    compact: true,
                    builder: (context, result) {
                      final releases = (result.data['releases'] as List? ?? [])
                          .whereType<Map>();
                      final release = releases.firstOrNull;
                      final date = DateTime.tryParse(
                        '${release?['publishedAt']}',
                      );
                      return InkWell(
                        onTap: () => client.openUrl(
                          release?['url'] as String? ??
                              'https://github.com/$repo/releases',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      repo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      date == null
                                          ? '暂无发布记录'
                                          : '${date.month}/${date.day} 发布',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: dashboardMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  release?['tag'] as String? ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: dashboardAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide =
          box.maxWidth / MediaQuery.textScalerOf(context).scale(1) >= 760;
      Widget pair(
        String left,
        Widget first,
        String right,
        Widget second, {
        int firstFlex = 4,
        int secondFlex = 6,
      }) {
        final a = modules.contains(left), b = modules.contains(right);
        if (!a && !b) return const SizedBox();
        if (a && b && wide) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StatefulBuilder(
              builder: (context, update) =>
                  NotificationListener<ApiSectionChanged>(
                    onNotification: (_) {
                      // Loaded text can outgrow the row's previous tight height.
                      // Remeasure both cells together after each snapshot settles.
                      update(() {});
                      return true;
                    },
                    child: Table(
                      columnWidths: {
                        0: FlexColumnWidth(firstFlex.toDouble()),
                        1: const FixedColumnWidth(12),
                        2: FlexColumnWidth(secondFlex.toDouble()),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.intrinsicHeight,
                      children: [
                        TableRow(
                          children: [first, const SizedBox(width: 12), second],
                        ),
                      ],
                    ),
                  ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (a)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: first),
            if (b)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: second,
              ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pair(
            'weather',
            _weather(),
            'crypto',
            _quotes(),
            firstFlex: 3,
            secondFlex: 7,
          ),
          pair(
            'news',
            _news(),
            'releases',
            _releases(),
            firstFlex: 6,
            secondFlex: 4,
          ),
        ],
      );
    },
  );
}
