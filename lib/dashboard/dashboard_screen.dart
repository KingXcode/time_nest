import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
import 'dashboard_widgets.dart';
import 'fx_panel.dart';
import 'holiday_panel.dart';
import 'news_panel.dart';
import 'releases_panel.dart';
import 'weather_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.client, this.now});
  final DashboardClient? client;
  final DateTime Function()? now;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardClient _client = widget.client ?? createDashboardClient();
  late final DashboardPreferences _preferences = DashboardPreferences.decode(
    _client.readPreferences(),
  );
  bool _favoritesOnly = false;
  bool _saved = true;
  final Map<String, GlobalKey> _keys = {
    for (final id in dashboardModules) id: GlobalKey(),
  };

  void _save(VoidCallback change) {
    setState(() {
      change();
      _saved = _client.writePreferences(_preferences.encode());
    });
  }

  static const _titles = {
    'weather': '什么时候出门',
    'holidays': '下个假期怎么拼',
    'releases': '关注的项目更新了',
    'fx': '这笔花费值多少',
    'news': '科技圈正在聊什么',
  };
  static const _subtitles = {
    'weather': '未来几小时的天气窗口',
    'holidays': '中国大陆节假日与调休',
    'releases': '公开仓库 · 最新 Release',
    'fx': '每日参考汇率与近 30 天变化',
    'news': '中文科技资讯 · 也可切换 HN 英文',
  };
  static const _icons = {
    'weather': Icons.wb_sunny_outlined,
    'holidays': Icons.calendar_month_outlined,
    'releases': Icons.code_rounded,
    'fx': Icons.currency_exchange_rounded,
    'news': Icons.auto_awesome_outlined,
  };

  Future<void> _organize() async {
    final order = List<String>.of(_preferences.order);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('安排你的看板', style: TextStyle(fontSize: 20)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, order),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '拖动调整顺序，也可用上下按钮。',
                    style: TextStyle(color: dashboardMuted),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: order.length,
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) => update(() {
                      order.insert(newIndex, order.removeAt(oldIndex));
                    }),
                    itemBuilder: (context, index) => ListTile(
                      key: ValueKey(order[index]),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator_rounded),
                      ),
                      title: Text(_titles[order[index]]!),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '上移${_titles[order[index]]}',
                            onPressed: index == 0
                                ? null
                                : () => update(() {
                                    order.insert(
                                      index - 1,
                                      order.removeAt(index),
                                    );
                                  }),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: '下移${_titles[order[index]]}',
                            onPressed: index == order.length - 1
                                ? null
                                : () => update(() {
                                    order.insert(
                                      index + 1,
                                      order.removeAt(index),
                                    );
                                  }),
                            icon: const Icon(
                              Icons.arrow_downward_rounded,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) _save(() => _preferences.order = result);
  }

  Widget _panel(String id) => switch (id) {
    'weather' => WeatherPanel(
      client: _client,
      city: _preferences.city,
      onCityChanged: (city) => _save(() => _preferences.city = city),
      now: widget.now,
    ),
    'holidays' => HolidayPanel(
      client: _client,
      leaveDays: _preferences.leaveDays,
      onLeaveDaysChanged: (days) => _save(() => _preferences.leaveDays = days),
      now: widget.now,
    ),
    'releases' => ReleasesPanel(
      client: _client,
      repos: _preferences.repos,
      onReposChanged: (repos) => _save(() => _preferences.repos = repos),
    ),
    'fx' => FxPanel(
      client: _client,
      base: _preferences.base,
      quote: _preferences.quote,
      amount: _preferences.amount,
      onChanged: (base, quote, amount) => _save(() {
        _preferences.base = base;
        _preferences.quote = quote;
        _preferences.amount = amount;
      }),
    ),
    _ => NewsPanel(
      client: _client,
      feed: _preferences.feed,
      onFeedChanged: (feed) => _save(() => _preferences.feed = feed),
    ),
  };

  Widget _card(String id) => Container(
    key: _keys[id],
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF151C1D),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFF2A3434)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(_icons[id], size: 22, color: dashboardAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[id]!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitles[id]!,
                    style: const TextStyle(fontSize: 12, color: dashboardMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip:
                  '${_preferences.favorites.contains(id) ? '取消收藏' : '收藏'}${_titles[id]}',
              isSelected: _preferences.favorites.contains(id),
              onPressed: () => _save(() {
                _preferences.favorites = List.of(_preferences.favorites);
                if (_preferences.favorites.contains(id)) {
                  _preferences.favorites.remove(id);
                } else {
                  _preferences.favorites.add(id);
                }
              }),
              icon: const Icon(Icons.star_outline_rounded, size: 21),
              selectedIcon: const Icon(
                Icons.star_rounded,
                color: dashboardAccent,
                size: 21,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _panel(id),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final today = (widget.now ?? DateTime.now)();
    final modules = _preferences.order
        .where((id) => !_favoritesOnly || _preferences.favorites.contains(id))
        .toList();
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: dashboardAccent,
          onPrimary: const Color(0xFF082F27),
          surface: const Color(0xFF151C1D),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1112),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF101617),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('此刻 / 每日看板', style: TextStyle(fontSize: 16)),
          backgroundColor: const Color(0xFF0B1112),
          surfaceTintColor: Colors.transparent,
          leading: BackButton(onPressed: () => Navigator.maybePop(context)),
          actions: [
            IconButton(
              tooltip: '调整卡片顺序',
              onPressed: _organize,
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            key: const PageStorageKey('dashboard-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1260),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${today.year} 年 ${today.month} 月 ${today.day} 日',
                      style: const TextStyle(
                        color: dashboardAccent,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '今天的事，一眼有数。',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '看天气、安排假期、关注更新。\n你的选择只保存在这台设备的浏览器里。',
                      style: TextStyle(
                        color: dashboardMuted,
                        height: 1.7,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('全部看板'),
                          selected: !_favoritesOnly,
                          onSelected: (_) =>
                              setState(() => _favoritesOnly = false),
                        ),
                        ChoiceChip(
                          label: Text('已收藏 ${_preferences.favorites.length}'),
                          selected: _favoritesOnly,
                          onSelected: (_) =>
                              setState(() => _favoritesOnly = true),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.swap_vert_rounded, size: 16),
                          label: const Text('调整顺序'),
                          onPressed: _organize,
                        ),
                      ],
                    ),
                    if (!_saved)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          '浏览器存储不可用。当前选择仍可使用，刷新后可能丢失。',
                          style: TextStyle(color: dashboardMuted),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (modules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text('还没有收藏。在全部看板里点一下星标吧。'),
                      ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns = box.maxWidth >= 950 ? 2 : 1;
                        final width =
                            (box.maxWidth - (columns - 1) * 20) / columns;
                        return Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            for (final id in modules)
                              SizedBox(
                                width: id == 'news' ? box.maxWidth : width,
                                child: _card(id),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      '公开数据按需更新，有缓存也有来源。断网时尽量显示上次保存的结果；第三方服务可能延迟或暂时不可用。',
                      style: TextStyle(
                        color: dashboardMuted,
                        fontSize: 11,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
