import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_widgets.dart';
import 'market_chart.dart';
import 'market_config.dart';
import 'local_market_config.dart';
import 'local_market_panel.dart';

class MarketPanel extends StatefulWidget {
  const MarketPanel({
    super.key,
    required this.client,
    required this.indexId,
    required this.interval,
    required this.onChanged,
  });
  final DashboardClient client;
  final String indexId;
  final String interval;
  final void Function(String, String) onChanged;
  @override
  State<MarketPanel> createState() => _MarketPanelState();
}

class _MarketPanelState extends State<MarketPanel> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    if (localMarketResearchBuild) {
      return LocalMarketPanel(
        client: widget.client,
        indexId: widget.indexId,
        onChanged: widget.onChanged,
      );
    }
    final selected = marketIndexFor(widget.indexId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('免费行情')),
            Chip(label: Text('日线与历史走势 · 不保证实时')),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '先看大盘，再看不同市场。',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '免费版以收盘趋势观察为主，可查看日线、周线与月线。数据日期、延迟与市场状态以 TradingView 图内标注为准；刷新频率不等于交易所实时行情。',
          style: TextStyle(color: dashboardMuted, height: 1.7),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final index in marketIndices)
              ChoiceChip(
                label: Text(index.name),
                selected: index.id == selected.id,
                onSelected: (_) => widget.onChanged(index.id, widget.interval),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${selected.name} · ${selected.symbol}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          selected.description,
          style: const TextStyle(color: dashboardMuted, height: 1.6),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in marketIntervals.entries)
              ChoiceChip(
                label: Text(period.value),
                selected: widget.interval == period.key,
                onSelected: (_) => widget.onChanged(selected.id, period.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: box.maxWidth < 500 ? 460 : 560,
            child: MarketChart(
              key: ValueKey(
                'market-chart-${selected.id}-${widget.interval}-$_attempt',
              ),
              indexId: selected.id,
              interval: widget.interval,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '若图表空白、报错或提示该品种不可用，可能是网络或数据授权限制。可重试，或打开 TradingView 来源查看。',
          style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.7),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _attempt++),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新加载图表'),
            ),
            TextButton.icon(
              onPressed: () => widget.client.openUrl(selected.sourceUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('打开来源'),
            ),
          ],
        ),
        const Divider(height: 32),
        const Text(
          '所选指数技术面 · 日线',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '下方为 TradingView 对当前所选指数的日线技术评级，与上方图表周期独立。免费数据以收盘观察为主；若组件未标注数据日期，无法确认截至时间，不按“今日市场”解读。',
          style: TextStyle(color: dashboardMuted, height: 1.7),
        ),
        const SizedBox(height: 12),
        if (selected.id == 'star50')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('科创50 技术评级暂缺。提供方目前没有该指数的评级数据，可继续查看上方历史走势。'),
          )
        else
          SizedBox(
            height: 520,
            child: MarketChart(
              key: ValueKey('market-technical-${selected.id}-$_attempt'),
              indexId: selected.id,
              interval: 'D',
              technical: true,
            ),
          ),
        const Text(
          '评级把移动平均线与振荡指标汇总：均线侧重趋势，振荡指标侧重动能与超买/超卖。“买入”“卖出”是技术信号标签，不是操作建议，也不是未来涨跌的保证。',
          style: TextStyle(color: dashboardMuted, height: 1.8),
        ),
        const SizedBox(height: 8),
        const Text(
          '这只解释所选指数的技术状态，不能代表所有股票、市场涨跌家数、资金流向、新闻或基本面。不同指数信号分歧时，更不能用一个评级判断整个市场好坏。',
          style: TextStyle(color: dashboardMuted, height: 1.8),
        ),
        TextButton(
          onPressed: () => widget.client.openUrl(
            'https://www.tradingview.com/support/solutions/43000614331-technical-ratings/',
          ),
          child: const Text('技术评级计算说明'),
        ),
        const Divider(height: 32),
        const Text(
          '怎样看整体走势？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '把日线切换到周线、月线，看上涨或下跌是否持续；再对照上证、深证与沪深300，观察走势是否一致。指数上涨不代表多数股票都上涨，单日涨跌也不足以判断整体“好坏”。',
          style: TextStyle(color: dashboardMuted, height: 1.8),
        ),
        const SizedBox(height: 16),
        const Text(
          '图表由 TradingView 免费官方组件提供。进入本页会连接其服务，并向其提供页面网址、组件类型、所选指数及 IP 地址。TradingView 声明组件不设置 Cookie。本应用不读取、保存或转发图表中的行情。仅供信息参考，不构成投资建议。',
          style: TextStyle(color: dashboardMuted, fontSize: 11, height: 1.7),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => widget.client.openUrl(
                'https://www.tradingview.com/privacy-policy/',
              ),
              child: const Text('TradingView 隐私政策'),
            ),
            TextButton(
              onPressed: () => widget.client.openUrl(
                'https://www.tradingview.com/widget-docs/markets/asia-pacific/',
              ),
              child: const Text('数据覆盖说明'),
            ),
          ],
        ),
      ],
    );
  }
}
