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
  });
  final List<CryptoCandle> candles;
  final String asset;
  final DateTime fetchedAt;
  final List<String> overlays, panes;
  final bool infoRight, canAdvise;
  final void Function(List<String>, List<String>, bool)? onSettingsChanged;

  @override
  State<CryptoChart> createState() => _CryptoChartState();
}

class _CryptoChartState extends State<CryptoChart> {
  int? _selectedTime;
  late Map<String, IndicatorStudy> _studies = calculateCryptoIndicators(
    widget.candles,
  );
  late CryptoAssessment? _assessment = assessCrypto(
    widget.candles,
    widget.fetchedAt.millisecondsSinceEpoch,
  );
  @override
  void didUpdateWidget(CryptoChart old) {
    super.didUpdateWidget(old);
    if (old.candles != widget.candles || old.fetchedAt != widget.fetchedAt) {
      _studies = calculateCryptoIndicators(widget.candles);
      _assessment = assessCrypto(
        widget.candles,
        widget.fetchedAt.millisecondsSinceEpoch,
      );
    }
  }

  String _value(double? v) => v == null
      ? '—'
      : v.abs() >= 10000
      ? cryptoVolume(v)
      : v.toStringAsFixed(v.abs() < 1 ? 4 : 2);

  Widget _settings() => Material(
    color: Colors.transparent,
    child: ExpansionTile(
      key: const PageStorageKey('crypto-indicator-settings'),
      tilePadding: EdgeInsets.zero,
      title: const Text('指标设置'),
      subtitle: Text(
        '主图 ${widget.overlays.length}/8 · 副图 ${widget.panes.length}/8 · ${cryptoIndicators.length} 种指标',
      ),
      children: [
        for (final overlay in [true, false])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(overlay ? '主图叠加（最多 8 个）' : '独立副图（最多 8 个，增加副图不压缩 K 线）'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final e in cryptoIndicators.entries.where(
                      (e) => e.value.overlay == overlay,
                    ))
                      Tooltip(
                        message: e.value.formula,
                        child: FilterChip(
                          key: ValueKey('indicator-${e.key}'),
                          label: Text(e.value.name),
                          selected: (overlay ? widget.overlays : widget.panes)
                              .contains(e.key),
                          onSelected:
                              widget.onSettingsChanged == null ||
                                  (!(overlay ? widget.overlays : widget.panes)
                                          .contains(e.key) &&
                                      (overlay ? widget.overlays : widget.panes)
                                              .length >=
                                          8)
                              ? null
                              : (selected) {
                                  final list = List<String>.of(
                                    overlay ? widget.overlays : widget.panes,
                                  );
                                  selected
                                      ? list.add(e.key)
                                      : list.remove(e.key);
                                  widget.onSettingsChanged!(
                                    overlay ? list : widget.overlays,
                                    overlay ? widget.panes : list,
                                    widget.infoRight,
                                  );
                                },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        const Text(
          '参数见指标提示。指标预热不足显示“—”；计算使用最多 500 根历史，图上显示最近 120 根。',
          style: TextStyle(color: dashboardMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = widget.candles;
    if (all.isEmpty) return const Text('币安暂未返回该周期的 K 线。');
    final offset = math.max(0, all.length - 120), rows = all.sublist(offset);
    var index = _selectedTime == null
        ? rows.length - 1
        : rows.indexWhere((r) => r.time == _selectedTime);
    if (index < 0) index = 0;
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
          onHover: (event) => point(event.localPosition),
          child: GestureDetector(
            onTapDown: (event) => point(event.localPosition),
            onHorizontalDragUpdate: (event) => point(event.localPosition),
            child: Semantics(
              label: study == null
                  ? 'K 线主图，绿色上涨、红色下跌，可用下方滑杆选择时间'
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
        _settings(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              key: const Key('crypto-info-position'),
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
                size: 16,
              ),
              label: Text(widget.infoRight ? '信息靠左' : '信息靠右'),
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF101718),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF293735)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
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
                const SizedBox(height: 8),
                Wrap(
                  key: const Key('crypto-ohlcv'),
                  alignment: alignment,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Text('开 ${cryptoPrice(selected.open)}'),
                    Text('高 ${cryptoPrice(selected.high)}'),
                    Text('低 ${cryptoPrice(selected.low)}'),
                    Text('收 ${cryptoPrice(selected.close)}'),
                    Text(
                      '成交量 ${cryptoVolume(selected.volume)} ${widget.asset}',
                    ),
                    Text('成交额 ${cryptoVolume(selected.quoteVolume)} USDT'),
                  ],
                ),
                const SizedBox(height: 8),
                legend(overlays, right: widget.infoRight),
                const SizedBox(height: 12),
                plot(),
              ],
            ),
          ),
        ),
        if (rows.length > 1)
          Slider(
            key: const Key('crypto-candle-slider'),
            value: index.toDouble(),
            max: (rows.length - 1).toDouble(),
            divisions: rows.length - 1,
            semanticFormatterCallback: (v) => cryptoTime(rows[v.round()].time),
            label: cryptoTime(selected.time),
            onChanged: (v) => select(v.round()),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(cryptoTime(rows.first.time)),
            Text(cryptoTime(rows.last.time)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '悬停、点击图表或拖动滑杆查看开高低收、成交量与成交额。主副图时间联动；UTC 分周期，时间显示 UTC+8。',
          style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.6),
        ),
        for (final id in widget.panes)
          if (_studies[id] case final study?)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF293735)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        cryptoIndicators[id]!.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      legend([study]),
                      const SizedBox(height: 6),
                      plot(study: study),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 24),
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
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
          for (final vote in assessment.votes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
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
          for (final v in line.values.skip(offset))
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
      ..color = const Color(0xFF293735)
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
