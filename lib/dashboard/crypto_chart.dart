import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_indicators.dart';
import 'crypto_market.dart';
import 'dashboard_widgets.dart';

const cryptoUp = Color(0xFF67D8AB);
const cryptoDown = Color(0xFFFF8A92);
const _colors = [
  Color(0xFFFFCF70),
  Color(0xFF77BCFF),
  Color(0xFFC59BFF),
  Color(0xFF67D8AB),
  Color(0xFFFF91C7),
  Color(0xFFFFA26B),
  Color(0xFF68D7DF),
  Color(0xFFC2D976),
];
const cryptoPriceHeight = 320.0;
const cryptoPaneHeight = 150.0;

class CryptoChart extends StatefulWidget {
  const CryptoChart({
    super.key,
    required this.candles,
    required this.asset,
    required this.fetchedAt,
    this.overlays = defaultCryptoOverlays,
    this.panes = defaultCryptoPanes,
    this.infoRight = false,
    this.onSettingsChanged,
    this.canAdvise = false,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.hasMoreHistory = false,
    this.historyError,
  });
  final List<CryptoCandle> candles;
  final String asset;
  final DateTime fetchedAt;
  final List<String> overlays, panes;
  final bool infoRight, canAdvise;
  final void Function(List<String>, List<String>, bool)? onSettingsChanged;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder, hasMoreHistory;
  final String? historyError;

  @override
  State<CryptoChart> createState() => _CryptoChartState();
}

class _CryptoChartState extends State<CryptoChart> {
  int? _selectedTime;
  // Null follows the latest bars. Otherwise pin the left edge by time so that
  // prepending history and receiving live bars never shift a historical view.
  int? _viewportStartTime;
  double _dragRemainder = 0;
  bool _dragging = false, _requestedDuringDrag = false;
  static const _visibleCount = 120;

  int get _startIndex {
    final rows = widget.candles;
    final max = math.max(0, rows.length - _visibleCount);
    if (_viewportStartTime == null) return max;
    final index = rows.indexWhere((r) => r.time >= _viewportStartTime!);
    return (index < 0 ? max : index).clamp(0, max);
  }

  void _loadOlder() {
    if (widget.loadingOlder ||
        !widget.hasMoreHistory ||
        widget.onLoadOlder == null ||
        widget.candles.isEmpty) {
      return;
    }
    setState(() => _viewportStartTime = widget.candles[_startIndex].time);
    widget.onLoadOlder!();
  }

  void _pan(int bars, {bool fromDrag = false}) {
    final rows = widget.candles;
    final max = math.max(0, rows.length - _visibleCount);
    final start = (_startIndex + bars).clamp(0, max);
    setState(() {
      _viewportStartTime = start == max ? null : rows[start].time;
      _selectedTime = null;
    });
    if (bars < 0 &&
        start <= 20 &&
        widget.historyError == null &&
        (!fromDrag || !_requestedDuringDrag)) {
      _requestedDuringDrag = true;
      _loadOlder();
    }
  }

  void _finishDrag() => setState(() => _dragging = false);

  late Map<String, IndicatorStudy> _studies = calculateCryptoIndicators(
    widget.candles,
  );
  late CryptoAssessment? _assessment = assessCrypto(
    widget.candles.skip(math.max(0, widget.candles.length - 500)).toList(),
    widget.fetchedAt.millisecondsSinceEpoch,
  );
  @override
  void didUpdateWidget(CryptoChart old) {
    super.didUpdateWidget(old);
    if (old.candles != widget.candles || old.fetchedAt != widget.fetchedAt) {
      _studies = calculateCryptoIndicators(widget.candles);
      _assessment = assessCrypto(
        widget.candles.skip(math.max(0, widget.candles.length - 500)).toList(),
        widget.fetchedAt.millisecondsSinceEpoch,
      );
    }
  }

  String _value(double? v) => v == null
      ? '—'
      : v.abs() >= 10000
      ? cryptoVolume(v)
      : v.toStringAsFixed(v.abs() < 1 ? 4 : 2);

  Future<void> _showSettings() async {
    var overlays = List<String>.of(widget.overlays);
    var panes = List<String>.of(widget.panes);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          insetPadding: const EdgeInsets.all(12),
          title: const Text('指标设置'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final overlay in [true, false]) ...[
                    Text(overlay ? '主图叠加（最多 8 个）' : '独立副图（最多 8 个，增加副图不压缩 K 线）'),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final e in cryptoIndicators.entries.where(
                          (e) => e.value.overlay == overlay,
                        ))
                          Tooltip(
                            message: e.value.formula,
                            child: FilterChip(
                              key: ValueKey('indicator-${e.key}'),
                              label: Text(e.value.name),
                              selected: (overlay ? overlays : panes).contains(
                                e.key,
                              ),
                              onSelected:
                                  widget.onSettingsChanged == null ||
                                      (!(overlay ? overlays : panes).contains(
                                            e.key,
                                          ) &&
                                          (overlay ? overlays : panes).length >=
                                              8)
                                  ? null
                                  : (selected) {
                                      final list = List<String>.of(
                                        overlay ? overlays : panes,
                                      );
                                      selected
                                          ? list.add(e.key)
                                          : list.remove(e.key);
                                      update(() {
                                        if (overlay) {
                                          overlays = list;
                                        } else {
                                          panes = list;
                                        }
                                      });
                                      widget.onSettingsChanged!(
                                        overlays,
                                        panes,
                                        widget.infoRight,
                                      );
                                    },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    '参数见指标提示。预热不足显示“—”；每屏显示 120 根，左右拖动浏览历史。',
                    style: TextStyle(color: dashboardMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.candles;
    if (all.isEmpty) return const Text('币安暂未返回该周期的 K 线。');
    final offset = _startIndex;
    final rows = all.sublist(
      offset,
      math.min(all.length, offset + _visibleCount),
    );
    var index = _selectedTime == null
        ? rows.length - 1
        : rows.indexWhere((r) => r.time == _selectedTime);
    if (index < 0) index = rows.length - 1;
    final selected = rows[index], absolute = index + offset;
    final forming =
        selected.closeTime >= widget.fetchedAt.millisecondsSinceEpoch;
    final alignment = widget.infoRight
        ? WrapAlignment.end
        : WrapAlignment.start;
    void select(int i) => setState(
      () => _selectedTime = i == rows.length - 1 ? null : rows[i].time,
    );
    final overlays = [for (final id in widget.overlays) ?_studies[id]];
    Widget legend(List<IndicatorStudy> studies, {bool right = false}) {
      var color = 0;
      return Wrap(
        alignment: right ? WrapAlignment.end : WrapAlignment.start,
        spacing: 12,
        runSpacing: 5,
        children: [
          for (final study in studies)
            for (final line in study.lines)
              Text(
                '${cryptoIndicators[study.id]!.name.split(' ').first} ${line.name} ${_value(line.values[absolute])}',
                style: TextStyle(
                  color: _colors[color++ % _colors.length],
                  fontSize: 11,
                ),
              ),
        ],
      );
    }

    Widget plot({IndicatorStudy? study}) => LayoutBuilder(
      builder: (context, box) {
        void point(Offset pos) => select(
          ((pos.dx - 4) / math.max(1, box.maxWidth - 76) * rows.length)
              .floor()
              .clamp(0, rows.length - 1),
        );
        return MouseRegion(
          cursor: _dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          onHover: (event) {
            if (!_dragging) point(event.localPosition);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (event) => point(event.localPosition),
            onHorizontalDragStart: (_) => setState(() {
              _dragging = true;
              _dragRemainder = 0;
              _requestedDuringDrag = false;
            }),
            onHorizontalDragUpdate: (event) {
              _dragRemainder -=
                  event.delta.dx / math.max(1, box.maxWidth - 76) * rows.length;
              final bars = _dragRemainder.truncate();
              if (bars == 0) return;
              _dragRemainder -= bars;
              _pan(bars, fromDrag: true);
            },
            onHorizontalDragEnd: (_) => _finishDrag(),
            onHorizontalDragCancel: _finishDrag,
            child: Semantics(
              label: study == null
                  ? 'K 线主图，绿色上涨、红色下跌，左右拖动浏览历史，可用下方滑杆选择时间'
                  : '${cryptoIndicators[study.id]!.name} 副图，与主图时间联动',
              child: SizedBox(
                key: study == null
                    ? const Key('crypto-price-plot')
                    : ValueKey('crypto-pane-${study.id}'),
                height: study == null ? cryptoPriceHeight : cryptoPaneHeight,
                child: CustomPaint(
                  painter: _MarketPainter(
                    rows,
                    index,
                    offset,
                    study == null ? overlays : [study],
                    price: study == null,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const PageStorageKey('crypto-indicator-settings'),
              onPressed: widget.onSettingsChanged == null
                  ? null
                  : _showSettings,
              icon: const Icon(Icons.tune, size: 15),
              label: const Text('指标设置'),
            ),
            Text(
              '主图 ${widget.overlays.length}/8 · 副图 ${widget.panes.length}/8',
              style: const TextStyle(color: dashboardMuted, fontSize: 11),
            ),

            TextButton.icon(
              key: const Key('crypto-pan-older'),
              onPressed: offset > 0 || widget.hasMoreHistory
                  ? () => _pan(-_visibleCount)
                  : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('更早'),
            ),
            TextButton.icon(
              key: const Key('crypto-pan-newer'),
              onPressed: offset + rows.length < all.length
                  ? () => _pan(_visibleCount)
                  : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('较新'),
            ),
            TextButton(
              key: const Key('crypto-latest'),
              onPressed: _viewportStartTime == null
                  ? null
                  : () => setState(() {
                      _viewportStartTime = null;
                      _selectedTime = null;
                    }),
              child: const Text('回到最新'),
            ),
            TextButton(
              key: const Key('crypto-load-older'),
              onPressed:
                  widget.loadingOlder ||
                      !widget.hasMoreHistory ||
                      widget.onLoadOlder == null
                  ? null
                  : _loadOlder,
              child: Text(
                widget.loadingOlder
                    ? '正在加载历史…'
                    : widget.historyError != null
                    ? '重试加载历史'
                    : widget.hasMoreHistory
                    ? '加载更多历史'
                    : '已到最早数据',
              ),
            ),
            Text(
              '已加载 ${all.length} 根',
              key: const Key('crypto-history-count'),
              style: const TextStyle(color: dashboardMuted, fontSize: 12),
            ),
            IconButton(
              key: const Key('crypto-info-position'),
              tooltip: widget.infoRight ? '信息靠左' : '信息靠右',
              onPressed: widget.onSettingsChanged == null
                  ? null
                  : () => widget.onSettingsChanged!(
                      widget.overlays,
                      widget.panes,
                      !widget.infoRight,
                    ),
              icon: Icon(
                widget.infoRight
                    ? Icons.format_align_left
                    : Icons.format_align_right,
                size: 15,
              ),
            ),
          ],
        ),
        if (widget.historyError != null)
          Text(
            widget.historyError!,
            key: const Key('crypto-history-error'),
            style: const TextStyle(color: Color(0xFFFFCF70), fontSize: 12),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: dashboardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dashboardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: widget.infoRight
                      ? Alignment.topRight
                      : Alignment.topLeft,
                  child: Text(
                    '${cryptoTime(selected.time)} UTC+8${forming ? ' · 未收盘' : ''}',
                    key: const Key('crypto-candle-time'),
                    style: const TextStyle(color: dashboardMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  key: const Key('crypto-ohlcv'),
                  alignment: alignment,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      '开 ${cryptoPrice(selected.open)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '高 ${cryptoPrice(selected.high)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '低 ${cryptoPrice(selected.low)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '收 ${cryptoPrice(selected.close)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '成交量 ${cryptoVolume(selected.volume)} ${widget.asset}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '成交额 ${cryptoVolume(selected.quoteVolume)} USDT',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                legend(overlays, right: widget.infoRight),
                const SizedBox(height: 6),
                plot(),
              ],
            ),
          ),
        ),
        if (rows.length > 1)
          SizedBox(
            height: 28,
            child: Slider(
              key: const Key('crypto-candle-slider'),
              value: index.toDouble(),
              max: (rows.length - 1).toDouble(),
              divisions: rows.length - 1,
              semanticFormatterCallback: (v) =>
                  cryptoTime(rows[v.round()].time),
              label: cryptoTime(selected.time),
              onChanged: (v) => select(v.round()),
            ),
          ),
        Semantics(
          label:
              '显示区间：${cryptoTime(rows.first.time)} 至 ${cryptoTime(rows.last.time)}',
          excludeSemantics: true,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                cryptoTime(rows.first.time),
                key: const Key('crypto-range-start'),
              ),
              Text(
                cryptoTime(rows.last.time),
                key: const Key('crypto-range-end'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '左右拖动浏览历史，点击图表或拖动滑杆定位。时间为 UTC+8。',
          style: TextStyle(color: dashboardMuted, fontSize: 11, height: 1.4),
        ),
        for (final id in widget.panes)
          if (_studies[id] case final study?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: dashboardBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cryptoIndicators[id]!.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: legend([study])),
                        ],
                      ),
                      const SizedBox(height: 4),
                      plot(study: study),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 14),
        _assessmentPanel(),
      ],
    );
  }

  Widget _assessmentPanel() {
    final assessment = _assessment;
    return Column(
      key: const Key('crypto-assessment'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '技术指标 · 买入参考',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        if (!widget.canAdvise)
          const Text(
            '行情尚未实时同步或推送已暂停，暂不提供买入参考。',
            style: TextStyle(color: Color(0xFFFFCF70)),
          )
        else if (assessment == null)
          const Text('已收盘 K 线不足 60 根，暂不提供买入参考。')
        else ...[
          Text(
            assessment.title,
            style: TextStyle(
              fontSize: 18,
              color: assessment.score >= 3
                  ? cryptoUp
                  : assessment.score <= -3
                  ? cryptoDown
                  : const Color(0xFFFFCF70),
            ),
          ),
          const SizedBox(height: 8),
          Text(assessment.suggestion, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 8),
          Text(
            '依据最新已收盘 K 线：${cryptoTime(assessment.time, seconds: true)} UTC+8；当前未收盘 K 线不参与。',
            style: const TextStyle(
              color: dashboardMuted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '偏多 ${assessment.votes.where((v) => v.direction > 0).length} · 中性 ${assessment.votes.where((v) => v.direction == 0).length} · 偏空 ${assessment.votes.where((v) => v.direction < 0).length}    ATR14 / 收盘 ${assessment.atrPercent.toStringAsFixed(2)}%',
          ),
          const SizedBox(height: 10),
          DashboardColumns(
            children: [
              for (final vote in assessment.votes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(vote.name),
                          Text(vote.value),
                          Text(
                            vote.direction > 0
                                ? '偏多'
                                : vote.direction < 0
                                ? '偏空'
                                : '中性',
                            style: TextStyle(
                              color: vote.direction > 0
                                  ? cryptoUp
                                  : vote.direction < 0
                                  ? cryptoDown
                                  : dashboardMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        vote.reason,
                        style: const TextStyle(
                          color: dashboardMuted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Text(
            '评分规则：六项各计 +1 / 0 / −1；合计≥3为偏多，≤−3为偏空，其余观望。固定使用六项，勾选图形不会改变评分。',
            style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.6),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '这是基于历史价格与成交量的规则参考，未做收益回测，不保证未来表现，也未考虑你的持仓、成本与风险承受能力。',
          style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}

class _MarketPainter extends CustomPainter {
  _MarketPainter(
    this.rows,
    this.selected,
    this.offset,
    this.studies, {
    required this.price,
  });
  final List<CryptoCandle> rows;
  final int selected, offset;
  final List<IndicatorStudy> studies;
  final bool price;
  @override
  void paint(Canvas canvas, Size size) {
    final right = size.width - 72,
        width = math.max(1.0, right - 4),
        bottom = size.height - 10;
    final values = <double>[
      if (price)
        for (final row in rows) ...[row.low, row.high],
      for (final study in studies)
        for (final line in study.lines)
          for (final v in line.values.skip(offset).take(rows.length))
            if (v != null && v.isFinite) v,
      if (!price)
        for (final study in studies) ...study.levels,
      if (!price && studies.any((s) => s.lines.any((l) => l.bars))) 0,
    ];
    if (values.isEmpty) return;
    final min = values.reduce(math.min),
        max = values.reduce(math.max),
        pad = math.max((max - min) * .08, math.max(max.abs(), 1) * .001);
    final positivePane =
        !price &&
        studies.every(
          (s) => const ['vol', 'amount', 'atr', 'natr', 'bbw'].contains(s.id),
        );
    final low = positivePane ? 0.0 : min - pad, high = max + pad;
    double y(double value) =>
        10 + (high - value) / (high - low) * (bottom - 10);
    void label(String text, Offset point, {Color color = dashboardMuted}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: 10, fontFamily: 'ShikeSans'),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 68);
      painter.paint(canvas, point);
    }

    final grid = Paint()
      ..color = dashboardBorder
      ..strokeWidth = .5;
    for (var i = 0; i <= 4; i++) {
      final value = low + (high - low) * i / 4;
      canvas.drawLine(Offset(4, y(value)), Offset(right, y(value)), grid);
      label(
        price
            ? cryptoPrice(value)
            : value.abs() >= 10000
            ? cryptoVolume(value)
            : value.toStringAsFixed(value.abs() < 1 ? 3 : 2),
        Offset(right + 4, y(value) - 6),
      );
    }
    final step = width / rows.length, bodyWidth = (step * .65).clamp(.6, 12.0);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(3, 0, right + 1, size.height));
    if (price) {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i],
            x = 4 + step * (i + .5),
            pen = Paint()
              ..color = row.close >= row.open ? cryptoUp : cryptoDown
              ..strokeWidth = 1;
        canvas.drawLine(Offset(x, y(row.high)), Offset(x, y(row.low)), pen);
        canvas.drawRect(
          Rect.fromLTWH(
            x - bodyWidth / 2,
            math.min(y(row.open), y(row.close)),
            bodyWidth,
            math.max(1, (y(row.open) - y(row.close)).abs()),
          ),
          pen,
        );
      }
    }
    var color = 0;
    for (final study in studies) {
      if (!price) {
        for (final level in study.levels) {
          canvas.drawLine(
            Offset(4, y(level)),
            Offset(right, y(level)),
            Paint()
              ..color = Colors.white30
              ..strokeWidth = 1,
          );
        }
      }
      for (final line in study.lines) {
        final paint = Paint()
          ..color = _colors[color++ % _colors.length]
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        final path = Path();
        var started = false;
        for (var i = 0; i < rows.length; i++) {
          final value = line.values[i + offset], x = 4 + step * (i + .5);
          if (value == null || !value.isFinite) {
            started = false;
            continue;
          }
          if (line.bars) {
            canvas.drawRect(
              Rect.fromLTWH(
                x - bodyWidth / 2,
                math.min(y(value), y(0)),
                bodyWidth,
                math.max(1, (y(value) - y(0)).abs()),
              ),
              Paint()
                ..color =
                    (study.id == 'vol' || study.id == 'amount'
                        ? rows[i].close >= rows[i].open
                        : value >= 0)
                    ? cryptoUp
                    : cryptoDown,
            );
          } else {
            if (started) {
              path.lineTo(x, y(value));
            } else {
              path.moveTo(x, y(value));
              started = true;
            }
          }
        }
        if (!line.bars) canvas.drawPath(path, paint);
      }
    }
    final x = 4 + step * (selected + .5);
    canvas.drawLine(
      Offset(x, 5),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 1,
    );
    if (price) {
      canvas.drawCircle(
        Offset(x, y(rows[selected].close)),
        3,
        Paint()..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarketPainter old) => true;
}
