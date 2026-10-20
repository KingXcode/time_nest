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
  bool _dragging = false, _crosshair = false, _tapHadCrosshair = false;
  int _visibleCount = 200, _scaleCount = 200, _scaleStart = 0;
  double _scaleAnchor = .5, _pointerY = .5;

  void _range(int start, int count) {
    final rows = widget.candles;
    if (rows.isEmpty) return;
    count = count.clamp(math.min(20, rows.length), rows.length);
    start = start.clamp(0, math.max(0, rows.length - count));
    setState(() {
      _visibleCount = count;
      _viewportStartTime = start + count == rows.length
          ? null
          : rows[start].time;
    });
  }

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

  void _pan(int bars) {
    final rows = widget.candles;
    final max = math.max(0, rows.length - _visibleCount);
    final start = (_startIndex + bars).clamp(0, max);
    setState(() {
      _viewportStartTime = start == max ? null : rows[start].time;
      _selectedTime = null;
    });
  }

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
                    '参数见指标提示。预热不足显示“—”；默认显示 200 根，左右拖动浏览，双指缩放。',
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
    void select(int i) => setState(() => _selectedTime = rows[i].time);
    final overlays = [for (final id in widget.overlays) ?_studies[id]];
    final priceValues = <double>[
      for (final row in rows) ...[row.low, row.high],
      for (final study in overlays)
        for (final line in study.lines)
          for (final value in line.values.skip(offset).take(rows.length))
            if (value != null && value.isFinite) value,
    ];
    final low = priceValues.reduce(math.min),
        high = priceValues.reduce(math.max);
    final padding = math.max(
      (high - low) * .08,
      math.max(high.abs(), 1) * .001,
    );
    final cursorValue =
        high +
        padding -
        ((_pointerY * cryptoPriceHeight - 10) / (cryptoPriceHeight - 20)).clamp(
              0.0,
              1.0,
            ) *
            (high - low + padding * 2);
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
        void point(Offset pos) {
          select(
            ((pos.dx - 4) / math.max(1, box.maxWidth - 76) * rows.length)
                .floor()
                .clamp(0, rows.length - 1),
          );
          if (study == null) {
            _pointerY = (pos.dy / cryptoPriceHeight).clamp(0.0, 1.0);
          }
        }

        return MouseRegion(
          cursor: _dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          onHover: (event) {
            if (_crosshair && !_dragging) point(event.localPosition);
          },
          child: Listener(
            onPointerDown: (event) {
              _tapHadCrosshair = _crosshair;
              point(event.localPosition);
              setState(() => _crosshair = true);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (_) => setState(() => _crosshair = !_tapHadCrosshair),
              onScaleStart: (event) {
                _dragging = true;
                _dragRemainder = 0;
                _scaleCount = rows.length;
                _scaleStart = _startIndex;
                _scaleAnchor =
                    (event.localFocalPoint.dx / math.max(1, box.maxWidth - 76))
                        .clamp(0.0, 1.0);
              },
              onScaleUpdate: (event) {
                if (event.pointerCount > 1) {
                  final count = (_scaleCount / event.scale).round().clamp(
                    math.min(20, all.length),
                    all.length,
                  );
                  _range(
                    (_scaleStart +
                            _scaleCount * _scaleAnchor -
                            count * _scaleAnchor)
                        .round(),
                    count.toInt(),
                  );
                } else {
                  _dragRemainder -=
                      event.focalPointDelta.dx /
                      math.max(1, box.maxWidth - 76) *
                      rows.length;
                  final bars = _dragRemainder.truncate();
                  if (bars != 0) {
                    _dragRemainder -= bars;
                    _pan(bars);
                  }
                }
              },
              onScaleEnd: (_) => setState(() => _dragging = false),
              child: Semantics(
                label: study == null
                    ? 'K 线主图，绿色上涨、红色下跌，左右拖动浏览历史，双指缩放，下方时间轴选择范围'
                    : '${cryptoIndicators[study.id]!.name} 副图，与主图时间联动',
                child: SizedBox(
                  key: study == null
                      ? const Key('crypto-price-plot')
                      : ValueKey('crypto-pane-${study.id}'),
                  height: study == null ? cryptoPriceHeight : cryptoPaneHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _MarketPainter(
                          rows,
                          index,
                          offset,
                          study == null ? overlays : [study],
                          price: study == null,
                          crosshair: _crosshair,
                          pointerY: _pointerY,
                        ),
                      ),
                      if (study == null)
                        Positioned(
                          top: 8,
                          left: widget.infoRight ? null : 8,
                          right: widget.infoRight ? 78 : null,
                          child: IgnorePointer(
                            child: Container(
                              key: const Key('crypto-info-window'),
                              width: math.min(
                                202,
                                math.max(146, box.maxWidth * .4),
                              ),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: dashboardSurface.withValues(alpha: .94),
                                border: Border.all(color: dashboardBorder),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: DefaultTextStyle(
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${cryptoTime(selected.time)}\nUTC+8${forming ? ' · 未收盘' : ''}',
                                      key: const Key('crypto-candle-time'),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: dashboardMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    for (final entry in <String, String>{
                                      '数值': cryptoPrice(
                                        _crosshair
                                            ? cursorValue
                                            : selected.close,
                                      ),
                                      '开盘价': cryptoPrice(selected.open),
                                      '最高价': cryptoPrice(selected.high),
                                      '最低价': cryptoPrice(selected.low),
                                      '收盘价': cryptoPrice(selected.close),
                                      '成交量':
                                          '${cryptoVolume(selected.volume)} ${widget.asset}',
                                      '成交额':
                                          '${cryptoVolume(selected.quoteVolume)} USDT',
                                      '涨幅':
                                          '${((selected.close / selected.open - 1) * 100).toStringAsFixed(2)}%',
                                      '振幅':
                                          '${((selected.high - selected.low) / selected.open * 100).toStringAsFixed(2)}%',
                                    }.entries)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 1,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              entry.key,
                                              style: const TextStyle(
                                                color: dashboardMuted,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                entry.value,
                                                textAlign: TextAlign.right,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_crosshair && study == null)
                        const Positioned(
                          bottom: 0,
                          left: 4,
                          child: Text(
                            '十字线已锁定 · 再次点击关闭',
                            key: Key('crypto-crosshair'),
                            style: TextStyle(
                              fontSize: 10,
                              color: dashboardMuted,
                            ),
                          ),
                        ),
                    ],
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
              onPressed: offset > 0 ? () => _pan(-_visibleCount) : null,
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
                legend(overlays, right: widget.infoRight),
                const SizedBox(height: 6),
                plot(),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 22,
          child: CustomPaint(painter: _TimeAxisPainter(rows)),
        ),
        Row(
          children: [
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
            Expanded(
              child: CryptoTimeline(
                candles: all,
                start: offset,
                count: rows.length,
                onRangeChanged: _range,
              ),
            ),
          ],
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
          '左右拖动 · 双指缩放 · 点击查看十字线，再次点击关闭。时间为 UTC+8。',
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
    this.crosshair = false,
    this.pointerY = .5,
  });
  final List<CryptoCandle> rows;
  final int selected, offset;
  final List<IndicatorStudy> studies;
  final bool price, crosshair;
  final double pointerY;
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
    if (crosshair) {
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
      final py = (size.height * pointerY).clamp(10.0, bottom);
      canvas.drawLine(
        Offset(4, py),
        Offset(right, py),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = .8,
      );
      canvas.restore();
      canvas.drawRect(
        Rect.fromLTWH(right + 2, py - 8, 70, 17),
        Paint()..color = dashboardSurface,
      );
      label(
        cryptoPrice(high - (py - 10) / (bottom - 10) * (high - low)),
        Offset(right + 4, py - 6),
        color: Colors.white,
      );
    } else {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MarketPainter old) => true;
}

/// Full loaded history, with draggable viewport and independently resizable ends.
class CryptoTimeline extends StatefulWidget {
  const CryptoTimeline({
    super.key,
    required this.candles,
    required this.start,
    required this.count,
    required this.onRangeChanged,
  });
  final List<CryptoCandle> candles;
  final int start, count;
  final void Function(int start, int count) onRangeChanged;
  @override
  State<CryptoTimeline> createState() => _CryptoTimelineState();
}

class _CryptoTimelineState extends State<CryptoTimeline> {
  int _edge = 0, _start = 0, _count = 0;
  double _origin = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final n = widget.candles.length;
      void begin(double x) {
        _origin = x;
        _start = widget.start;
        _count = widget.count;
        final left = _start / n * box.maxWidth;
        final right = (_start + _count) / n * box.maxWidth;
        _edge = (x - left).abs() < 12
            ? -1
            : (x - right).abs() < 12
            ? 1
            : 0;
      }

      void move(double x) {
        final delta = ((x - _origin) / box.maxWidth * n).round();
        final minimum = math.min(20, n);
        if (_edge < 0) {
          final start = (_start + delta).clamp(0, _start + _count - minimum);
          widget.onRangeChanged(start, _start + _count - start);
        } else if (_edge > 0) {
          widget.onRangeChanged(
            _start,
            (_count + delta).clamp(minimum, n - _start),
          );
        } else {
          widget.onRangeChanged((_start + delta).clamp(0, n - _count), _count);
        }
      }

      return Semantics(
        label: '历史时间轴',
        value: '显示 ${widget.count} / $n 根',
        increasedValue: '较新范围',
        decreasedValue: '更早范围',
        onIncrease: () => widget.onRangeChanged(
          math.min(
            n - widget.count,
            widget.start + math.max(1, widget.count ~/ 4),
          ),
          widget.count,
        ),
        onDecrease: () => widget.onRangeChanged(
          math.max(0, widget.start - math.max(1, widget.count ~/ 4)),
          widget.count,
        ),
        child: GestureDetector(
          key: const Key('crypto-timeline'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragDown: (e) => begin(e.localPosition.dx),
          onHorizontalDragUpdate: (e) => move(e.localPosition.dx),
          onTapUp: (e) => widget.onRangeChanged(
            (e.localPosition.dx / box.maxWidth * n - widget.count / 2)
                .round()
                .clamp(0, n - widget.count),
            widget.count,
          ),
          child: SizedBox(
            height: 48,
            child: CustomPaint(
              painter: _TimelinePainter(
                widget.candles,
                widget.start,
                widget.count,
              ),
            ),
          ),
        ),
      );
    },
  );
}

void _axisText(Canvas canvas, String text, double x, double y, double width) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 10,
        color: dashboardMuted,
        fontFamily: 'ShikeSans',
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  painter.paint(
    canvas,
    Offset(x.clamp(0.0, math.max(0.0, width - painter.width)), y),
  );
}

class _TimeAxisPainter extends CustomPainter {
  _TimeAxisPainter(this.rows);
  final List<CryptoCandle> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final ticks = size.width < 500 ? 2 : 4;
    for (var i = 0; i <= ticks; i++) {
      final index = ((rows.length - 1) * i / ticks).round();
      final date = cryptoTime(rows[index].time);
      _axisText(
        canvas,
        date.substring(5),
        i / ticks * math.max(1, size.width - 76),
        3,
        size.width,
      );
    }
  }

  @override
  bool shouldRepaint(_TimeAxisPainter old) => old.rows != rows;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.rows, this.start, this.count);
  final List<CryptoCandle> rows;
  final int start, count;
  @override
  void paint(Canvas canvas, Size size) {
    final min = rows.map((r) => r.close).reduce(math.min);
    final max = rows.map((r) => r.close).reduce(math.max);
    final path = Path();
    for (var i = 0; i < rows.length; i++) {
      final x = i / math.max(1, rows.length - 1) * size.width;
      final y = 5 + (max - rows[i].close) / math.max(.000001, max - min) * 25;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = dashboardMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final left = start / rows.length * size.width,
        right = (start + count) / rows.length * size.width;
    canvas.drawRect(
      Rect.fromLTRB(left, 1, right, 33),
      Paint()..color = const Color(0x3377BCFF),
    );
    canvas.drawRect(
      Rect.fromLTRB(left, 1, right, 33),
      Paint()
        ..color = const Color(0xFF77BCFF)
        ..style = PaintingStyle.stroke,
    );
    for (final x in [left, right]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            (x - 3).clamp(0, math.max(0, size.width - 6)),
            9,
            6,
            18,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF77BCFF),
      );
    }
    _axisText(
      canvas,
      cryptoTime(rows.first.time).substring(0, 10),
      0,
      34,
      size.width,
    );
    _axisText(
      canvas,
      cryptoTime(rows.last.time).substring(0, 10),
      size.width,
      34,
      size.width,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.rows != rows || old.start != start || old.count != count;
}
