import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
import 'dashboard_overview.dart';
import 'dashboard_widgets.dart';
import 'crypto_panel.dart';
import 'market_panel.dart';
import 'news_panel.dart';
import 'releases_panel.dart';
import 'weather_panel.dart';

const _titles = {
  'weather': '天气',
  'releases': '项目更新',
  'news': '科技资讯',
  'market': 'A股行情',
  'crypto': '数字货币行情',
};
const _subtitles = {
  'weather': '查看城市天气与逐小时预报',
  'releases': '关注热门开源项目的最新发布',
  'news': '中文科技资讯，也可切换 HN 英文',
  'market': '免费收盘参考，查看 A 股指数与历史走势',
  'crypto': 'BTC、ETH 等主流币行情与 K 线',
};
const _icons = {
  'weather': Icons.wb_sunny_outlined,
  'releases': Icons.code_rounded,
  'news': Icons.auto_awesome_outlined,
  'market': Icons.show_chart_rounded,
  'crypto': Icons.currency_bitcoin_rounded,
};
const _storageWarning = '浏览器存储不可用。当前选择仍可使用，刷新后可能丢失。';

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
  bool _detailOpen = false;

  bool _save(VoidCallback change) {
    void apply() {
      change();
      _saved = _client.writePreferences(_preferences.encode());
    }

    if (_detailOpen) {
      apply();
    } else {
      setState(apply);
    }
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

  Future<void> _openModule(String id) async {
    _detailOpen = true;
    await Navigator.of(context).push<void>(
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
    _detailOpen = false;
    if (mounted) setState(() {});
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
    color: dashboardSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
      side: const BorderSide(color: dashboardBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('dashboard-entry-$id'),
      onTap: () => _openModule(id),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 2, top: 2, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[id], size: 16, color: dashboardAccent),
            const SizedBox(width: 7),
            Text(
              _titles[id]!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 5),
            IconButton(
              tooltip:
                  '${_preferences.favorites.contains(id) ? '取消收藏' : '收藏'}${_titles[id]}',
              isSelected: _preferences.favorites.contains(id),
              onPressed: () => _toggleFavorite(id),
              icon: const Icon(Icons.star_outline_rounded, size: 15),
              selectedIcon: const Icon(
                Icons.star_rounded,
                color: dashboardAccent,
                size: 15,
              ),
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
      data: dashboardTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('每日看板'),
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
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '数据总览',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${today.year} 年 ${today.month} 月 ${today.day} 日',
                          style: const TextStyle(
                            fontSize: 11,
                            color: dashboardMuted,
                          ),
                        ),
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
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [for (final id in modules) _entry(id)],
                    ),
                    if (!_saved)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          _storageWarning,
                          style: TextStyle(color: dashboardMuted, fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (modules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('还没有收藏。在全部功能里点一下星标吧。'),
                      ),
                    DashboardOverview(
                      client: _client,
                      preferences: _preferences,
                      modules: modules,
                      onOpen: _openModule,
                      now: widget.now,
                    ),
                    const Text(
                      '首页为按需加载的数据快照，展开可查看完整数据与实时图表。',
                      style: TextStyle(color: dashboardMuted, fontSize: 11),
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

/// Detail routes own their chart subscriptions; overview snapshots have no timers.
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
      'crypto' => CryptoPanel(
        client: widget.client,
        symbol: preferences.cryptoSymbol,
        interval: preferences.cryptoInterval,
        overlays: preferences.cryptoOverlays,
        panes: preferences.cryptoPanes,
        infoRight: preferences.cryptoInfoRight,
        paneHeights: preferences.cryptoPaneHeights,
        onPaneHeightsChanged: (heights) =>
            _save(() => preferences.cryptoPaneHeights = Map.of(heights)),
        onChartChanged: (overlays, panes, right) => _save(() {
          preferences.cryptoOverlays = overlays;
          preferences.cryptoPanes = panes;
          preferences.cryptoInfoRight = right;
        }),
        onChanged: (symbol, interval) => _save(() {
          preferences.cryptoSymbol = symbol;
          preferences.cryptoInterval = interval;
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
    data: dashboardTheme(Theme.of(context)),
    child: Scaffold(
      key: ValueKey('dashboard-page-${widget.id}'),
      appBar: AppBar(
        title: Text(_titles[widget.id]!),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: PageStorageKey('dashboard-${widget.id}-scroll'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.id == 'crypto')
                    _panel()
                  else ...[
                    Text(
                      _subtitles[widget.id]!,
                      style: const TextStyle(
                        color: dashboardMuted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: dashboardSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dashboardBorder),
                      ),
                      child: _panel(),
                    ),
                  ],
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
