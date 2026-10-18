import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
import 'dashboard_widgets.dart';
import 'fx_panel.dart';
import 'market_panel.dart';
import 'news_panel.dart';
import 'releases_panel.dart';
import 'weather_panel.dart';

const _titles = {
  'weather': '天气',
  'releases': '项目更新',
  'fx': '汇率换算',
  'news': '科技资讯',
  'market': 'A股行情',
};
const _subtitles = {
  'weather': '查看城市天气与逐小时预报',
  'releases': '关注热门开源项目的最新发布',
  'fx': '每日参考汇率与近 30 天变化',
  'news': '中文科技资讯，也可切换 HN 英文',
  'market': '免费收盘参考，查看 A 股指数与历史走势',
};
const _icons = {
  'weather': Icons.wb_sunny_outlined,
  'releases': Icons.code_rounded,
  'fx': Icons.currency_exchange_rounded,
  'news': Icons.auto_awesome_outlined,
  'market': Icons.show_chart_rounded,
};
const _storageWarning = '浏览器存储不可用。当前选择仍可使用，刷新后可能丢失。';

ThemeData _dashboardTheme(ThemeData theme) => theme.copyWith(
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  ),
);

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

  bool _save(VoidCallback change) {
    setState(() {
      change();
      _saved = _client.writePreferences(_preferences.encode());
    });
    return _saved;
  }

  void _toggleFavorite(String id) => _save(() {
    _preferences.favorites = List.of(_preferences.favorites);
    if (_preferences.favorites.contains(id)) {
      _preferences.favorites.remove(id);
    } else {
      _preferences.favorites.add(id);
    }
  });

  void _openModule(String id) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _DashboardModuleScreen(
          id: id,
          client: _client,
          preferences: _preferences,
          onPreferencesChanged: _save,
          saved: _saved,
          now: widget.now,
        ),
      ),
    );
  }

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
                        child: Text('安排功能入口', style: TextStyle(fontSize: 20)),
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
                    itemBuilder: (context, index) => Padding(
                      key: ValueKey(order[index]),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_indicator_rounded),
                            ),
                          ),
                          Expanded(child: Text(_titles[order[index]]!)),
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

  Widget _entry(String id) => Material(
    color: const Color(0xFF151C1D),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFF2A3434)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('dashboard-entry-$id'),
      onTap: () => _openModule(id),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icons[id], size: 26, color: dashboardAccent),
                const Spacer(),
                IconButton(
                  tooltip:
                      '${_preferences.favorites.contains(id) ? '取消收藏' : '收藏'}${_titles[id]}',
                  isSelected: _preferences.favorites.contains(id),
                  onPressed: () => _toggleFavorite(id),
                  icon: const Icon(Icons.star_outline_rounded, size: 21),
                  selectedIcon: const Icon(
                    Icons.star_rounded,
                    color: dashboardAccent,
                    size: 21,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _titles[id]!,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitles[id]!,
              style: const TextStyle(
                fontSize: 13,
                color: dashboardMuted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(
                  child: Text('打开', style: TextStyle(color: dashboardAccent)),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: dashboardAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final today = (widget.now ?? DateTime.now)();
    final modules = _preferences.order
        .where((id) => !_favoritesOnly || _preferences.favorites.contains(id))
        .toList();
    return Theme(
      data: _dashboardTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('此刻 / 每日看板', style: TextStyle(fontSize: 16)),
          backgroundColor: const Color(0xFF0B1112),
          surfaceTintColor: Colors.transparent,
          leading: BackButton(onPressed: () => Navigator.maybePop(context)),
          actions: [
            IconButton(
              tooltip: '调整入口顺序',
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
                constraints: const BoxConstraints(maxWidth: 1100),
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
                      '选择一个功能，打开独立页面。\n你的选择只保存在这台设备的浏览器里。',
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
                          label: const Text('全部功能'),
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
                          _storageWarning,
                          style: TextStyle(color: dashboardMuted),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (modules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text('还没有收藏。在全部功能里点一下星标吧。'),
                      ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns = box.maxWidth >= 700 ? 2 : 1;
                        final width =
                            (box.maxWidth - (columns - 1) * 20) / columns;
                        return Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            for (final id in modules)
                              SizedBox(width: width, child: _entry(id)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      '进入功能后才会加载对应数据。公开数据有缓存和来源；第三方服务可能延迟或暂时不可用。',
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

/// A route owns only its selected panel. Other modules stay unmounted, avoiding
/// their network requests and preserving the dashboard as a lightweight entry.
class _DashboardModuleScreen extends StatefulWidget {
  const _DashboardModuleScreen({
    required this.id,
    required this.client,
    required this.preferences,
    required this.onPreferencesChanged,
    required this.saved,
    this.now,
  });

  final String id;
  final DashboardClient client;
  final DashboardPreferences preferences;
  final bool Function(VoidCallback) onPreferencesChanged;
  final bool saved;
  final DateTime Function()? now;

  @override
  State<_DashboardModuleScreen> createState() => _DashboardModuleScreenState();
}

class _DashboardModuleScreenState extends State<_DashboardModuleScreen> {
  late bool _saved = widget.saved;

  void _save(VoidCallback change) => setState(() {
    _saved = widget.onPreferencesChanged(change);
  });

  Widget _panel() {
    final preferences = widget.preferences;
    return switch (widget.id) {
      'weather' => WeatherPanel(
        client: widget.client,
        city: preferences.city,
        onCityChanged: (city) => _save(() => preferences.city = city),
        now: widget.now,
      ),
      'releases' => ReleasesPanel(
        client: widget.client,
        repos: preferences.repos,
        onReposChanged: (repos) => _save(() => preferences.repos = repos),
      ),
      'fx' => FxPanel(
        client: widget.client,
        base: preferences.base,
        quote: preferences.quote,
        amount: preferences.amount,
        onChanged: (base, quote, amount) => _save(() {
          preferences.base = base;
          preferences.quote = quote;
          preferences.amount = amount;
        }),
      ),
      'market' => MarketPanel(
        client: widget.client,
        indexId: preferences.marketIndex,
        interval: preferences.marketInterval,
        onChanged: (index, interval) => _save(() {
          preferences.marketIndex = index;
          preferences.marketInterval = interval;
        }),
      ),
      _ => NewsPanel(
        client: widget.client,
        feed: preferences.feed,
        onFeedChanged: (feed) => _save(() => preferences.feed = feed),
      ),
    };
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _dashboardTheme(Theme.of(context)),
    child: Scaffold(
      key: ValueKey('dashboard-page-${widget.id}'),
      appBar: AppBar(
        title: Text(_titles[widget.id]!),
        backgroundColor: const Color(0xFF0B1112),
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: PageStorageKey('dashboard-${widget.id}-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _subtitles[widget.id]!,
                    style: const TextStyle(
                      color: dashboardMuted,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151C1D),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF2A3434)),
                    ),
                    child: _panel(),
                  ),
                  if (!_saved)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        _storageWarning,
                        style: TextStyle(color: dashboardMuted),
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
