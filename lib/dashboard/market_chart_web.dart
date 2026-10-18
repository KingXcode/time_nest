// This compatibility layer is isolated to the JavaScript web target.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';

import 'market_config.dart';

class MarketChart extends StatefulWidget {
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
  State<MarketChart> createState() => _MarketChartState();
}

class _MarketChartState extends State<MarketChart> {
  html.IFrameElement? _frame;

  void _configure() {
    final index = marketIndexFor(widget.indexId);
    final interval = marketIntervals.containsKey(widget.interval)
        ? widget.interval
        : 'D';
    _frame?.src = Uri.base
        .resolve('market_chart.html')
        .replace(
          queryParameters: {
            'index': index.id,
            'interval': interval,
            if (widget.technical) 'kind': 'technical',
          },
          fragment: '',
        )
        .toString();
  }

  @override
  void didUpdateWidget(MarketChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indexId != widget.indexId ||
        oldWidget.interval != widget.interval ||
        oldWidget.technical != widget.technical) {
      _configure();
    }
  }

  @override
  void dispose() {
    // Stop the provider frame when leaving the route or retrying. Never keep
    // hidden widgets alive, and never inspect cross-origin quote/chart data.
    _frame?.src = 'about:blank';
    _frame?.remove();
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as html.IFrameElement;
      _frame = frame;
      frame
        ..title = widget.technical
            ? 'TradingView 所选指数日线技术面'
            : 'TradingView A股历史走势图'
        ..setAttribute(
          'sandbox',
          'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox',
        )
        ..setAttribute('referrerpolicy', 'no-referrer')
        ..setAttribute('loading', 'eager')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = '0';
      // The local wrapper executes only our hash-pinned bootstrap. Provider code
      // runs in its own cross-origin iframe, isolated from application storage.
      // Both frames deny top navigation; popups are user-opened source links.
      _configure();
    },
  );
}
