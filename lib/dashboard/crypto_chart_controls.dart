import 'package:flutter/material.dart';

import 'crypto_indicators.dart';
import 'crypto_market.dart';
import 'dashboard_widgets.dart';

/// The chart owns its controls, so its side panels always share the same top.
class CryptoChartHeader extends StatelessWidget {
  const CryptoChartHeader({
    super.key,
    required this.asset,
    this.quoteAsset = 'USDT',
    this.interval,
    this.quote,
    this.loaded,
    this.navigation = const SizedBox.shrink(),
    this.onIntervalChanged,
    this.onSettings,
  });
  final String asset, quoteAsset;
  final String? interval;
  final CryptoQuote? quote;
  final int? loaded;
  final Widget navigation;
  final ValueChanged<String>? onIntervalChanged;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    Widget metric(String label, String value) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: dashboardMuted),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(
        fontSize: 11,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('crypto-chart-toolbar'),
          color: const Color(0xFF21364D),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey('crypto-chart-toolbar-scroll'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (onIntervalChanged != null) ...[
                        for (final period in cryptoIntervals.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: ChoiceChip(
                              key: ValueKey('crypto-period-${period.key}'),
                              label: Text(period.value),
                              selected: interval == period.key,
                              onSelected: (_) => onIntervalChanged!(period.key),
                              showCheckmark: false,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              labelStyle: const TextStyle(fontSize: 11),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        const SizedBox(
                          height: 16,
                          child: VerticalDivider(width: 12),
                        ),
                      ],
                      navigation,
                    ],
                  ),
                ),
              ),
              if (onSettings != null)
                IconButton(
                  key: const Key('crypto-view-settings'),
                  tooltip: '图表设置',
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
        Container(
          key: const Key('crypto-chart-market-info'),
          decoration: const BoxDecoration(
            color: Color(0xFF152639),
            border: Border(bottom: BorderSide(color: dashboardBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SingleChildScrollView(
            key: const PageStorageKey('crypto-chart-market-scroll'),
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 12,
              children: [
                Text(
                  '$asset / $quoteAsset',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC9E3FF),
                  ),
                ),
                if (q != null) ...[
                  metric('24h 高', cryptoPrice(q.high)),
                  metric('24h 低', cryptoPrice(q.low)),
                  metric('成交量 ($asset)', cryptoVolume(q.volume)),
                  metric('成交额 ($quoteAsset)', cryptoVolume(q.quoteVolume)),
                ],
                if (loaded != null)
                  Text(
                    '已加载 $loaded 根',
                    key: const Key('crypto-history-count'),
                    style: const TextStyle(color: dashboardMuted, fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Common studies can be toggled directly; the full catalogue stays in the dialog.
class CryptoIndicatorBar extends StatelessWidget {
  const CryptoIndicatorBar({
    super.key,
    required this.overlays,
    required this.panes,
    required this.onSettings,
    this.onChanged,
  });
  final List<String> overlays, panes;
  final VoidCallback onSettings;
  final void Function(List<String>, List<String>)? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('crypto-chart-indicators'),
    decoration: const BoxDecoration(
      color: Color(0xFF152639),
      border: Border(top: BorderSide(color: Color(0xFF49617B))),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const PageStorageKey('crypto-indicator-bar-scroll'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final overlay in [true, false]) ...[
                  if (!overlay)
                    const SizedBox(
                      height: 16,
                      child: VerticalDivider(width: 16),
                    ),
                  Text(
                    overlay ? '主图' : '副图',
                    style: const TextStyle(color: dashboardMuted, fontSize: 10),
                  ),
                  const SizedBox(width: 4),
                  for (final id
                      in overlay
                          ? ['ma', 'ema', 'boll', 'bbi']
                          : ['vol', 'macd', 'rsi', 'kdj', 'adx', 'obv'])
                    _tab(id, overlay),
                ],
              ],
            ),
          ),
        ),
        Tooltip(
          message: '全部指标 · 主图 ${overlays.length}/8 · 副图 ${panes.length}/8',
          child: TextButton.icon(
            key: const PageStorageKey('crypto-indicator-settings'),
            onPressed: onChanged == null ? null : onSettings,
            icon: const Icon(Icons.tune, size: 13),
            label: const Text('指标设置'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tab(String id, bool overlay) {
    final list = overlay ? overlays : panes;
    final selected = list.contains(id), spec = cryptoIndicators[id]!;
    return Tooltip(
      message:
          '${spec.name} · ${spec.formula}${!selected && list.length >= 8 ? ' · 最多选择 8 个' : ''}',
      child: FilterChip(
        key: ValueKey('crypto-quick-indicator-$id'),
        label: Text(id == 'adx' ? 'DMI' : id.toUpperCase()),
        selected: selected,
        onSelected: onChanged == null || (!selected && list.length >= 8)
            ? null
            : (value) {
                final next = List<String>.of(list);
                value ? next.add(id) : next.remove(id);
                onChanged!(
                  overlay ? next : List.of(overlays),
                  overlay ? List.of(panes) : next,
                );
              },
        showCheckmark: false,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 7),
        labelStyle: const TextStyle(fontSize: 11),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
