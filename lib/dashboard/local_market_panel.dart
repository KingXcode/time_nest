import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'market_history.dart';
import 'local_market_config.dart';
import 'local_market_source.dart';
import 'market_config.dart';
import 'native_market_history.dart';
import 'dashboard_widgets.dart';

class LocalMarketPanel extends StatefulWidget {
  const LocalMarketPanel({
    super.key,
    required this.client,
    required this.indexId,
    required this.onChanged,
    this.source,
  });
  final DashboardClient client;
  final String indexId;
  final void Function(String, String) onChanged;
  final MarketHistorySource? source;
  @override
  State<LocalMarketPanel> createState() => _LocalMarketPanelState();
}

class _LocalMarketPanelState extends State<LocalMarketPanel> {
  late MarketHistorySource _source =
      widget.source ?? LocalMarketHistorySource();
  @override
  void didUpdateWidget(LocalMarketPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _source = widget.source ?? LocalMarketHistorySource();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('本机个人研究')),
          Chip(label: Text('BaoStock 公共日线')),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        '指数收盘走势',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        '最近 30 个自然日的已收盘记录。点击曲线或拖动日期选择器，查看对应交易日的收盘点位。',
        style: TextStyle(color: dashboardMuted, height: 1.7),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in localMarketCodes.keys)
            ChoiceChip(
              label: Text(marketIndexFor(id).name),
              selected: widget.indexId == id,
              onSelected: (_) => widget.onChanged(id, 'D'),
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (localMarketCodes.containsKey(widget.indexId))
        NativeMarketHistory(
          source: _source,
          indexId: widget.indexId,
          requestTimeout: const Duration(seconds: 100),
          openSource: (url) => widget.client.openUrl(url.toString()),
        )
      else
        const Text('当前选择尚未接入本地数据，请选择上方指数。'),
      const Divider(height: 28),
      const Text(
        '仅供个人研究，不构成投资建议。数据可能延迟或缺失；获取时间不代表交易日期，也不保证数据已经更新至最新交易日。',
        style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.7),
      ),
    ],
  );
}
