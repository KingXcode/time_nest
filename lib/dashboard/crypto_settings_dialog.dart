import 'package:flutter/material.dart';

import 'crypto_view_settings.dart';
import 'dashboard_widgets.dart';

Future<CryptoViewSettings?> showCryptoViewSettings(
  BuildContext context,
  CryptoViewSettings current,
) => showDialog<CryptoViewSettings>(
  context: context,
  builder: (context) {
    var draft = current;
    return StatefulBuilder(
      builder: (context, update) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('图表设置'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '窗口显示',
                  style: TextStyle(color: dashboardMuted, fontSize: 12),
                ),
                for (final item in [
                  ('orderBook', '订单簿', draft.orderBook),
                  ('trades', '最新成交', draft.trades),
                  ('timeline', '历史时间轴', draft.timeline),
                  ('indicatorValues', '指标数值', draft.indicatorValues),
                  ('assessment', '技术参考', draft.assessment),
                ])
                  SwitchListTile.adaptive(
                    key: ValueKey('crypto-setting-${item.$1}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(item.$2, style: const TextStyle(fontSize: 13)),
                    value: item.$3,
                    onChanged: (value) =>
                        update(() => draft = draft.change(item.$1, value)),
                  ),
                const Divider(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('成交显示条数', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownButton<int>(
                      key: const Key('crypto-setting-tradeRows'),
                      value: draft.tradeRows,
                      items: [
                        for (final n in [20, 50, 100])
                          DropdownMenuItem(value: n, child: Text('$n 条')),
                      ],
                      onChanged: (n) {
                        if (n != null) {
                          update(() => draft = draft.change('tradeRows', n));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '设置保存在本设备。最新成交显示公开市场成交，绿色为主动买入，红色为主动卖出。',
                  style: TextStyle(
                    fontSize: 11,
                    color: dashboardMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('应用'),
          ),
        ],
      ),
    );
  },
);
