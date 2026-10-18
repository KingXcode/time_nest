import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dashboard_widgets.dart';
import 'market_config.dart';
import 'market_history.dart';

/// Not wired into the live market page until a usable licensed source exists.
/// No iframe, external script, or data fixture is used by this renderer.
class NativeMarketHistory extends StatefulWidget {
  const NativeMarketHistory({
    super.key,
    required this.source,
    required this.indexId,
    required this.openSource,
    this.requestTimeout = const Duration(seconds: 15),
  }) : assert(requestTimeout > Duration.zero);

  final MarketHistorySource source;
  final String indexId;
  final ValueChanged<Uri> openSource;
  final Duration requestTimeout;

  @override
  State<NativeMarketHistory> createState() => _NativeMarketHistoryState();
}

class _NativeMarketHistoryState extends State<NativeMarketHistory> {
  MarketHistory? _history;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NativeMarketHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indexId != widget.indexId ||
        oldWidget.source != widget.source) {
      _history = null;
      _error = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_generation;
    _timer?.cancel();
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _timer = Timer(widget.requestTimeout, () {
      if (!mounted || generation != _generation) return;
      _generation++;
      setState(() {
        _loading = false;
        _error = '获取超时，请稍后重试。';
      });
    });
    try {
      final indexId = widget.indexId;
      if (!marketIndices.any((index) => index.id == indexId)) {
        throw const FormatException('Unknown index');
      }
      final result = await widget.source.load(indexId, refresh: refresh);
      if (!mounted || generation != _generation) return;
      if (result.indexId != indexId) {
        throw const FormatException('Mismatched index');
      }
      _timer?.cancel();
      setState(() {
        _history = result;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _timer?.cancel();
      setState(() {
        _loading = false;
        _error = error is FormatException
            ? '数据格式未通过校验，暂不绘图。'
            : '暂时无法获取收盘历史，请稍后重试。';
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('收盘历史 · 非实时', style: TextStyle(color: dashboardMuted)),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('正在获取收盘历史…'),
          ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (history != null) ...[
          if (_loading || _error != null) const Text('保留上次获取结果，可能已过时。'),
          if (history.closes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('来源没有返回可显示的历史数据。'),
            )
          else
            CloseHistoryChart(key: ObjectKey(history), history: history),
          Text('数据截至：${history.asOf?.label ?? '暂无'}（上海交易日）'),
          Text(switch (history.freshness) {
            HistoryFreshness.unverified => '时效未核实，请以来源说明为准。',
            HistoryFreshness.verifiedThroughDate => '来源已确认截至所示交易日。',
            HistoryFreshness.stale => '来源标记为旧数据，可能已过时。',
          }, style: const TextStyle(color: dashboardMuted)),
          Text(history.source.timingNote),
          Text(
            '获取时间：${history.fetchedAt.add(const Duration(hours: 8)).toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC+8',
            style: const TextStyle(color: dashboardMuted, fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.openSource(history.source.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text('来源：${history.source.name}'),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(_loading ? '获取中' : '重新获取'),
          ),
        ),
      ],
    );
  }
}

class CloseHistoryChart extends StatefulWidget {
  const CloseHistoryChart({super.key, required this.history});
  final MarketHistory history;

  @override
  State<CloseHistoryChart> createState() => _CloseHistoryChartState();
}

class _CloseHistoryChartState extends State<CloseHistoryChart> {
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _selected = math.max(0, widget.history.closes.length - 1);
  }

  @override
  void didUpdateWidget(CloseHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history) {
      _selected = math.max(0, widget.history.closes.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closes = widget.history.closes;
    if (closes.isEmpty) return const SizedBox.shrink();
    final selected = closes[_selected];
    final low = closes.map((point) => point.close).reduce(math.min);
    final high = closes.map((point) => point.close).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${marketIndexFor(widget.history.indexId).name} · 每日收盘点位',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        Wrap(
          spacing: 16,
          children: [
            Text('区间高 ${high.toStringAsFixed(2)}'),
            Text('区间低 ${low.toStringAsFixed(2)}'),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            onTapDown: (details) {
              final fraction =
                  ((details.localPosition.dx - 8) /
                          math.max(1, constraints.maxWidth - 16))
                      .clamp(0.0, 1.0);
              setState(
                () => _selected = (fraction * (closes.length - 1)).round(),
              );
            },
            child: Semantics(
              image: true,
              label: '${closes.length} 个交易日的收盘走势，详细值可用下方日期选择器查看。',
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: CustomPaint(
                  painter: CloseHistoryPainter(
                    values: closes.map((point) => point.close).toList(),
                    selectedIndex: _selected,
                  ),
                ),
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(closes.first.date.label),
            Text(closes.last.date.label),
          ],
        ),
        const Text(
          '横轴按交易记录等距排列，纵轴按本区间缩放。',
          style: TextStyle(color: dashboardMuted, fontSize: 12),
        ),
        if (closes.length == 1)
          const Text('仅有一个收盘记录，暂不能形成走势。')
        else
          Slider(
            label: selected.date.label,
            value: _selected.toDouble(),
            min: 0,
            max: (closes.length - 1).toDouble(),
            divisions: closes.length - 1,
            semanticFormatterCallback: (value) {
              final point = closes[value.round()];
              return '${point.date.label}，收盘 ${point.close.toStringAsFixed(2)} 点';
            },
            onChanged: (value) => setState(() => _selected = value.round()),
          ),
        Semantics(
          liveRegion: true,
          child: Text(
            '${selected.date.label} · 收盘 ${selected.close.toStringAsFixed(2)} 点',
            key: const ValueKey('selected-market-close'),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Pure local drawing, without interpolation across unobserved session dates.
class CloseHistoryPainter extends CustomPainter {
  CloseHistoryPainter({
    required List<double> values,
    required this.selectedIndex,
  }) : values = List.unmodifiable(values);
  final List<double> values;
  final int selectedIndex;

  List<Offset> positions(Size size) {
    if (values.isEmpty || size.width <= 16 || size.height <= 16) return [];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    // Normalize before subtraction to remain finite for large finite values.
    final normalizedLow = low / high;
    final range = 1 - normalizedLow;
    return [
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1
              ? size.width / 2
              : 8 + i / (values.length - 1) * (size.width - 16),
          range == 0
              ? size.height / 2
              : 8 + (1 - values[i] / high) / range * (size.height - 16),
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final points = positions(size);
    if (points.isEmpty) return;
    final grid = Paint()
      ..color = dashboardMuted.withValues(alpha: .18)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 8 + i / 2 * (size.height - 16);
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), grid);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = dashboardAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final selected = points[selectedIndex.clamp(0, points.length - 1)];
    canvas.drawLine(
      Offset(selected.dx, 8),
      Offset(selected.dx, size.height - 8),
      grid,
    );
    canvas.drawCircle(selected, 4, Paint()..color = dashboardAccent);
  }

  @override
  bool shouldRepaint(CloseHistoryPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.selectedIndex != selectedIndex;
}
