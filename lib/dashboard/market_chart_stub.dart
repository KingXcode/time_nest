import 'package:flutter/material.dart';

class MarketChart extends StatelessWidget {
  const MarketChart({
    super.key,
    required this.indexId,
    required this.interval,
    this.technical = false,
  });
  final String indexId;
  final String interval;
  final bool technical;
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('此平台暂不支持内嵌图表。请使用下方“打开来源”查看行情。'),
    ),
  );
}
