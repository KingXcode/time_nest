import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'crypto_chart_gestures.dart';
import 'crypto_chart_controls.dart';
import 'crypto_view_settings.dart';

import 'crypto_indicators.dart';
import 'crypto_market.dart';
import 'dashboard_widgets.dart';
import 'dashboard_preferences.dart';
import '../ui/apple_button.dart';

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
const _cryptoMainSurface = Color(0xFF242426);
const _cryptoPaneSurface = Color(0xFF141416);
const _cryptoPaneHeader = Color(0xFF2C2C2E);
const _cryptoTimelineSurface = Color(0xFF1C1C1E);
const _cryptoResizeSurface = Color(0xFF2C2C2E);

class CryptoChart extends StatefulWidget {
  const CryptoChart({
    super.key,
    required this.candles,
    required this.asset,
    this.quoteAsset = 'USDT',
    required this.fetchedAt,
    this.overlays = defaultCryptoOverlays,
    this.panes = defaultCryptoPanes,
    this.infoRight = false,
    this.paneHeights = const {},
    this.onPaneHeightsChanged,
    this.onSettingsChanged,
    this.afterCharts,
    this.chartLayout,
    this.canAdvise = false,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.hasMoreHistory = false,
    this.historyError,
    this.viewSettings = const CryptoViewSettings(),
    this.onViewSettings,
    this.interval,
    this.quote,
    this.onIntervalChanged,
    this.compact = false,
  });
  final List<CryptoCandle> candles;
  final String asset, quoteAsset;
  final DateTime fetchedAt;
  final List<String> overlays, panes;
  final bool infoRight, canAdvise;
  final Widget? afterCharts;
  // Keep chart state stable while its frame and side panels adapt to width.
  final Widget Function(Widget plots)? chartLayout;
  final Map<String, double> paneHeights;
  final ValueChanged<Map<String, double>>? onPaneHeightsChanged;
  final void Function(List<String>, List<String>, bool)? onSettingsChanged;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder, hasMoreHistory;
  final String? historyError;
  final CryptoViewSettings viewSettings;
  final VoidCallback? onViewSettings;
  final String? interval;
  final CryptoQuote? quote;
  final ValueChanged<String>? onIntervalChanged;

  /// Read-only home snapshot using the same price scale and candle painter.
  /// Omits controls, gestures, indicators, and advice without changing the
  /// interactive dashboard layout.
  final bool compact;

  @override
  State<CryptoChart> createState() => _CryptoChartState();
}

class _CryptoChartState extends State<CryptoChart> {
  int? _selectedTime;
  // Null follows the latest bars. Otherwise pin the left edge by time so that
  // prepending history and receiving live bars never shift a historical view.
  int? _viewportStartTime;
  double _dragRemainder = 0;
  bool _dragging = false, _crosshair = false, _boxTool = false;
  final _chartFocus = FocusNode();
  final _zoomBack = <({int? time, int count})>[];
  Offset? _boxFrom, _boxTo;
  Offset _dragPoint = Offset.zero;
  String? _boxPane, _selectionHint;
  int _boxStart = 0, _boxCount = 0;
  bool _touchInput = false;
  int _visibleCount = 200, _scaleCount = 200, _scaleStart = 0;
  double _scaleAnchor = .5, _pointerY = .5;
  String? _pointerPane, _hoveredResize, _resizingPane;
  late Map<String, double> _paneHeights = cleanCryptoPaneHeights(
    widget.paneHeights,
  );

  void _range(int start, int count) {
    final rows = widget.candles;
    if (rows.isEmpty) return;
    count = count.clamp(math.min(10, rows.length), rows.length);
    start = start.clamp(0, math.max(0, rows.length - count));
    setState(() {
      _visibleCount = count;
      _viewportStartTime = start + count == rows.length
          ? null
          : rows[start].time;
    });
  }

  void _rememberView() {
    final view = (time: _viewportStartTime, count: _visibleCount);
    if (_zoomBack.isEmpty || _zoomBack.last != view) _zoomBack.add(view);
    if (_zoomBack.length > 10) _zoomBack.removeAt(0);
  }

  void _closeCrosshair() => setState(() {
    _crosshair = false;
    _selectedTime = null;
  });

  @override
  void dispose() {
    _chartFocus.dispose();
    super.dispose();
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
    if (!mapEquals(old.paneHeights, widget.paneHeights)) {
      _paneHeights = cleanCryptoPaneHeights(widget.paneHeights);
    }
    if (old.candles != widget.candles || old.fetchedAt != widget.fetchedAt) {
      _studies = calculateCryptoIndicators(widget.candles);
      _assessment = assessCrypto(
        widget.candles.skip(math.max(0, widget.candles.length - 500)).toList(),
        widget.fetchedAt.millisecondsSinceEpoch,
      );
    }
  }

  String _studyName(String id) {
    final name = cryptoIndicators[id]!.name;
    if (id == 'vol') return '$name (${widget.asset})';
    if (id == 'amount') return '$name (${widget.quoteAsset})';
    return name;
  }

  String _studyFormula(String id) {
    final formula = cryptoIndicators[id]!.formula;
    if (id == 'vol') return '$formula，单位 ${widget.asset}';
    if (id == 'amount') return '$formula（${widget.quoteAsset}）';
    return formula;
  }

  String _value(double? v) => v == null
      ? '—'
      : v.abs() >= 10000
      ? cryptoVolume(v)
      : v.toStringAsFixed(
          v != 0 && v.abs() < .0001
              ? 8
              : v.abs() < 1
              ? 4
              : 2,
        );

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
                            message: _studyFormula(e.key),
                            child: FilterChip(
                              key: ValueKey('indicator-${e.key}'),
                              label: Text(_studyName(e.key)),
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
            AppleButton.text(
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
    final offset = widget.compact ? math.max(0, all.length - 64) : _startIndex;
    final rows = all.sublist(
      offset,
      widget.compact
          ? all.length
          : math.min(all.length, offset + _visibleCount),
    );
    var index = _selectedTime == null
        ? rows.length - 1
        : rows.indexWhere((r) => r.time == _selectedTime);
    if (index < 0) index = rows.length - 1;
    final selected = rows[index], absolute = index + offset;
    final forming =
        selected.closeTime >= widget.fetchedAt.millisecondsSinceEpoch;
    final overlays = [
      if (!widget.compact)
        for (final id in widget.overlays) ?_studies[id],
    ];
    final scales = <String, _ChartScale>{
      'price': _ChartScale(rows, offset, overlays, price: true),
      for (final id in widget.compact ? <String>[] : widget.panes)
        if (_studies[id] case final study?)
          id: _ChartScale(rows, offset, [study], price: false),
    };
    // One measured gutter keeps candle timestamps aligned across every pane.
    final axisWidth = scales.values
        .map((scale) => scale.axisWidth)
        .reduce(math.max);
    final priceScale = scales['price']!;
    if (widget.compact) {
      final latest = rows.last;
      return Semantics(
        label:
            '${widget.asset} K 线只读快照，最近 ${rows.length} 根，'
            '最新收盘价 ${cryptoPrice(latest.close)} ${widget.quoteAsset}，'
            '绿色上涨、红色下跌',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${cryptoPrice(latest.close)} ${widget.quoteAsset}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: latest.close >= latest.open ? cryptoUp : cryptoDown,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              key: const Key('crypto-compact-price-plot'),
              height: 180,
              child: CustomPaint(
                painter: _MarketPainter(
                  rows,
                  rows.length - 1,
                  offset,
                  const [],
                  price: true,
                  crosshair: false,
                  pointerY: 0,
                  axisWidth: axisWidth,
                  scale: priceScale,
                  horizontalCrosshair: false,
                ),
              ),
            ),
            SizedBox(
              height: 22,
              child: CustomPaint(painter: _TimeAxisPainter(rows, axisWidth)),
            ),
          ],
        ),
      );
    }
    final cursorValue =
        priceScale.high -
        ((_pointerY * cryptoPriceHeight - 10) / (cryptoPriceHeight - 20)).clamp(
              0.0,
              1.0,
            ) *
            (priceScale.high - priceScale.low);
    Widget legend(List<IndicatorStudy> studies, {bool right = false}) {
      if (!widget.viewSettings.indicatorValues) return const SizedBox.shrink();
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

    Widget paneHeader(IndicatorStudy study) => LayoutBuilder(
      builder: (context, box) {
        final title = Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '副图',
              style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2)),
            ),
            Text(
              _studyName(study.id),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        );
        if (box.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(12) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 2),
              legend([study]),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(width: 10),
            Expanded(child: legend([study])),
          ],
        );
      },
    );

    Widget plot({IndicatorStudy? study}) => LayoutBuilder(
      builder: (context, box) {
        final width = math.max(1.0, box.maxWidth - axisWidth - 4);
        final infoOnRight = (index + .5) / rows.length < .5;
        // Keep either floating corner within half of the drawable plot, so a
        // narrow phone does not put the window over a central candle.
        final infoWidth = math.min(164.0, math.max(1.0, width / 2 - 12));
        final height = study == null
            ? cryptoPriceHeight
            : (_paneHeights[study.id] ?? cryptoPaneHeight);
        double x(Offset pos) => ((pos.dx - 4) / width).clamp(0.0, 1.0);
        void point(Offset pos) {
          final start = _startIndex;
          final count = math.min(_visibleCount, all.length - start);
          final i = (x(pos) * count).floor().clamp(0, count - 1);
          setState(() {
            _selectedTime = all[start + i].time;
            _pointerPane = study?.id;
            _pointerY = (pos.dy / height).clamp(0.0, 1.0);
          });
        }

        void finishBox(bool cancelled) {
          if (_boxFrom == null) return;
          final first = (math.min(x(_boxFrom!), x(_boxTo!)) * _boxCount)
              .floor()
              .clamp(0, _boxCount - 1);
          final last = (math.max(x(_boxFrom!), x(_boxTo!)) * _boxCount)
              .floor()
              .clamp(0, _boxCount - 1);
          final count = last - first + 1;
          if (!cancelled && count >= 10) {
            _rememberView();
            _range(_boxStart + first, count);
          }
          setState(() {
            _selectionHint = !cancelled && count < 10 ? '至少选择 10 根 K 线' : null;
            _boxFrom = _boxTo = null;
            _boxTool = false;
          });
        }

        final navigation = RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            CryptoChartGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  CryptoChartGestureRecognizer
                >(() => CryptoChartGestureRecognizer(), (gesture) {
                  gesture.tracking = () => _crosshair;
                  gesture.selecting = (kind) =>
                      !_crosshair &&
                      (_boxTool ||
                          kind == PointerDeviceKind.mouse &&
                              HardwareKeyboard.instance.isShiftPressed);
                  gesture.onInput = (kind) {
                    _chartFocus.requestFocus();
                    setState(
                      () => _touchInput =
                          kind == PointerDeviceKind.touch ||
                          kind == PointerDeviceKind.stylus ||
                          kind == PointerDeviceKind.invertedStylus,
                    );
                  };
                  gesture.onDoubleClick = (pos) {
                    if (_crosshair) {
                      _closeCrosshair();
                    } else {
                      point(pos);
                      setState(() {
                        _crosshair = true;
                        _boxTool = false;
                        _selectionHint = null;
                      });
                    }
                  };
                  gesture.onTrack = (pos) {
                    point(pos);
                    setState(() {
                      _crosshair = true;
                      _boxTool = false;
                      _selectionHint = null;
                    });
                  };
                  gesture.onPanStart = (pos) {
                    _dragPoint = pos;
                    _dragRemainder = 0;
                    setState(() {
                      _dragging = true;
                      _selectionHint = null;
                    });
                  };
                  gesture.onPanUpdate = (delta) {
                    _dragPoint += delta;
                    _dragRemainder -=
                        delta.dx / width * math.min(_visibleCount, all.length);
                    final bars = _dragRemainder.truncate();
                    if (bars != 0) {
                      _dragRemainder -= bars;
                      _pan(bars);
                    }
                    if (_crosshair) point(_dragPoint);
                  };
                  gesture.onPinchStart = (pos) {
                    _rememberView();
                    _scaleCount = math.min(_visibleCount, all.length);
                    _scaleStart = _startIndex;
                    _scaleAnchor = x(pos);
                    setState(() => _dragging = true);
                  };
                  gesture.onPinchUpdate = (scale) {
                    final count = (_scaleCount / math.max(.01, scale))
                        .round()
                        .clamp(math.min(10, all.length), all.length);
                    _range(
                      (_scaleStart + (_scaleCount - count) * _scaleAnchor)
                          .round(),
                      count.toInt(),
                    );
                  };
                  gesture.onBoxStart = (pos) {
                    setState(() {
                      _boxFrom = _boxTo = pos;
                      _boxPane = study?.id;
                      _boxStart = _startIndex;
                      _boxCount = math.min(_visibleCount, all.length);
                      _selectionHint = null;
                      _dragging = true;
                    });
                  };
                  gesture.onBoxUpdate = (pos) {
                    if (_boxFrom != null) {
                      setState(() => _boxTo = pos);
                    }
                  };
                  gesture.onBoxEnd = finishBox;
                  gesture.onEnd = () {
                    if (mounted) {
                      setState(() => _dragging = false);
                    }
                  };
                }),
          },
          child: CustomPaint(
            painter: _MarketPainter(
              rows,
              index,
              offset,
              study == null ? overlays : [study],
              price: study == null,
              crosshair: _crosshair,
              pointerY: _pointerY,
              axisWidth: axisWidth,
              scale: scales[study?.id ?? 'price']!,
              horizontalCrosshair: _pointerPane == study?.id,
            ),
          ),
        );

        return MouseRegion(
          cursor:
              _boxTool ||
                  HardwareKeyboard.instance.isShiftPressed && !_crosshair
              ? SystemMouseCursors.precise
              : _dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          onHover: (event) {
            if (_crosshair && !_dragging) point(event.localPosition);
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent ||
                  !_crosshair ||
                  event.scrollDelta.dy == 0) {
                return;
              }
              GestureBinding.instance.pointerSignalResolver.register(event, (
                _,
              ) {
                _rememberView();
                final anchor = x(event.localPosition);
                final count =
                    (rows.length *
                            math.exp(
                              event.scrollDelta.dy.clamp(-600.0, 600.0) * .0015,
                            ))
                        .round()
                        .clamp(math.min(10, all.length), all.length);
                _range(
                  (offset + (rows.length - count) * anchor).round(),
                  count.toInt(),
                );
                point(event.localPosition);
              });
            },
            child: Semantics(
              label: study == null
                  ? 'K 线主图，价格单位 ${widget.quoteAsset}，绿色上涨、红色下跌，左键拖动平移，双击或长按查看，Shift 拖动框选，双指缩放'
                  : '${_studyName(study.id)} 副图，与主图时间联动',
              child: SizedBox(
                key: study == null
                    ? const Key('crypto-price-plot')
                    : ValueKey('crypto-pane-${study.id}'),
                height: height,
                child: ColoredBox(
                  color: study == null
                      ? _cryptoMainSurface
                      : _cryptoPaneSurface,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      navigation,
                      if (_boxFrom != null && _boxPane == study?.id)
                        Positioned(
                          left: 4 + math.min(x(_boxFrom!), x(_boxTo!)) * width,
                          width: math.max(
                            1,
                            (x(_boxTo!) - x(_boxFrom!)).abs() * width,
                          ),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              key: const Key('crypto-selection-box'),
                              decoration: BoxDecoration(
                                color: const Color(0xFF77BCFF)
                                    .withValues(alpha: .16),
                                border: Border.all(
                                  color: const Color(0xFF77BCFF),
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  '${((x(_boxTo!) * _boxCount).floor().clamp(0, _boxCount - 1) - (x(_boxFrom!) * _boxCount).floor().clamp(0, _boxCount - 1)).abs() + 1} 根',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_crosshair && study == null)
                        Positioned(
                          top: 8,
                          left: infoOnRight ? null : 8,
                          right: infoOnRight ? axisWidth + 6 : null,
                          child: Semantics(
                            label: 'K 线信息窗口，价格单位 ${widget.quoteAsset}',
                            container: true,
                            explicitChildNodes: true,
                            child: Stack(
                              children: [
                                IgnorePointer(
                                  child: Container(
                                    key: const Key('crypto-info-window'),
                                    width: infoWidth,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: dashboardSurface.withValues(
                                        alpha: .94,
                                      ),
                                      border: Border.all(
                                        color: dashboardBorder,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: DefaultTextStyle(
                                      style: TextStyle(
                                        fontSize: infoWidth < 144 ? 10 : 11,
                                        color: Colors.white,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 22,
                                            ),
                                            child: Text(
                                              '${cryptoTime(selected.time)}\nUTC+8${forming ? ' · 未收盘' : ''}',
                                              key: const Key(
                                                'crypto-candle-time',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: dashboardMuted,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          for (final entry in <String, String>{
                                            '数值': cryptoPrice(
                                              _pointerPane == null
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
                                                '${cryptoVolume(selected.quoteVolume)} ${widget.quoteAsset}',
                                            '涨幅':
                                                '${((selected.close / selected.open - 1) * 100).toStringAsFixed(2)}%',
                                            '振幅':
                                                '${((selected.high - selected.low) / selected.open * 100).toStringAsFixed(2)}%',
                                          }.entries)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 1,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    flex: 2,
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: Text(
                                                        entry.key,
                                                        maxLines: 1,
                                                        style: const TextStyle(
                                                          color: dashboardMuted,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    flex: 3,
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        entry.value,
                                                        textAlign:
                                                            TextAlign.right,
                                                        maxLines: 1,
                                                      ),
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
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    key: const Key('crypto-close-crosshair'),
                                    tooltip: '关闭十字线',
                                    onPressed: _closeCrosshair,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 40,
                                      height: 40,
                                    ),
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(
                                      Icons.close,
                                      size: 13,
                                      color: dashboardMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_crosshair && study == null)
                        Positioned(
                          bottom: 0,
                          left: 4,
                          child: IgnorePointer(
                            child: Text(
                              _touchInput
                                  ? '十字线已锁定 · 滑动查看 · × 关闭'
                                  : '十字线已锁定 · 双击 / Esc 关闭',
                              key: const Key('crypto-crosshair'),
                              style: const TextStyle(
                                fontSize: 10,
                                color: dashboardMuted,
                              ),
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
    final navigation = IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(28, 28),
          maximumSize: const Size(28, 28),
          padding: EdgeInsets.zero,
          iconSize: 17,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('crypto-pan-older'),
            onPressed: offset > 0 ? () => _pan(-_visibleCount) : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '更早',
          ),
          IconButton(
            key: const Key('crypto-pan-newer'),
            onPressed: offset + rows.length < all.length
                ? () => _pan(_visibleCount)
                : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: '较新',
          ),
          IconButton(
            key: const Key('crypto-latest'),
            tooltip: '回到最新',
            onPressed: _viewportStartTime == null
                ? null
                : () => setState(() {
                    _viewportStartTime = null;
                    _selectedTime = null;
                  }),
            icon: const Icon(Icons.last_page, size: 16),
          ),
          IconButton(
            key: const Key('crypto-box-select'),
            tooltip: _crosshair ? '关闭十字线后框选' : '框选放大（至少 10 根，Shift + 拖动）',
            isSelected: _boxTool,
            onPressed: _crosshair
                ? null
                : () => setState(() {
                    _boxTool = !_boxTool;
                    _selectionHint = null;
                    _chartFocus.requestFocus();
                  }),
            icon: const Icon(Icons.select_all, size: 16),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          IconButton(
            key: const Key('crypto-undo-zoom'),
            tooltip: '恢复上次视图',
            onPressed: _zoomBack.isEmpty
                ? null
                : () => setState(() {
                    final view = _zoomBack.removeLast();
                    _viewportStartTime = view.time;
                    _visibleCount = view.count;
                    _selectedTime = null;
                  }),
            icon: const Icon(Icons.undo, size: 16),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
    final surface = Semantics(
      label: 'K 线图表区域',
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        key: const Key('crypto-chart-surface'),
        decoration: BoxDecoration(
          color: _cryptoMainSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dashboardBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CryptoChartHeader(
                asset: widget.asset,
                quoteAsset: widget.quoteAsset,
                interval: widget.interval,
                quote: widget.quote,
                loaded: all.length,
                navigation: navigation,
                onIntervalChanged: widget.onIntervalChanged,
                onSettings: widget.onViewSettings,
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 26),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                color: _cryptoPaneHeader,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '主图 · 价格',
                        style: TextStyle(
                          color: Color(0xFFC9E3FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: legend(overlays, right: widget.infoRight)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: plot(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ColoredBox(
                  color: _cryptoTimelineSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 22,
                        child: CustomPaint(
                          painter: _TimeAxisPainter(rows, axisWidth),
                        ),
                      ),
                      if (widget.viewSettings.timeline) ...[
                        Row(
                          children: [
                            IconButton(
                              key: const Key('crypto-load-older'),
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: widget.loadingOlder
                                  ? '正在加载历史…'
                                  : widget.historyError != null
                                  ? '重试加载历史'
                                  : widget.hasMoreHistory
                                  ? '加载更多历史'
                                  : '已到最早数据',
                              onPressed:
                                  widget.loadingOlder ||
                                      !widget.hasMoreHistory ||
                                      widget.onLoadOlder == null
                                  ? null
                                  : _loadOlder,
                              icon: Icon(
                                widget.loadingOlder
                                    ? Icons.hourglass_top
                                    : widget.historyError != null
                                    ? Icons.refresh
                                    : Icons.history,
                                size: 18,
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
                      ],
                    ],
                  ),
                ),
              ),
              for (final id in widget.panes)
                if (_studies[id] case final study?) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: _cryptoPaneHeader,
                      border: Border(
                        top: BorderSide(color: Color(0xFF48484A)),
                        bottom: BorderSide(color: Color(0xFF38383A)),
                      ),
                    ),
                    child: paneHeader(study),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: plot(study: study),
                  ),
                  _resizeHandle(id),
                ],
              CryptoIndicatorBar(
                overlays: widget.overlays,
                panes: widget.panes,
                onSettings: _showSettings,
                onChanged: widget.onSettingsChanged == null
                    ? null
                    : (overlays, panes) => widget.onSettingsChanged!(
                        overlays,
                        panes,
                        widget.infoRight,
                      ),
              ),
              if (widget.historyError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    widget.historyError!,
                    key: const Key('crypto-history-error'),
                    style: const TextStyle(
                      color: Color(0xFFFFCF70),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Focus(
      includeSemantics: false,
      focusNode: _chartFocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        if (_boxFrom != null || _boxTool) {
          setState(() {
            _boxFrom = _boxTo = null;
            _boxTool = false;
          });
        } else if (_crosshair) {
          _closeCrosshair();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.chartLayout?.call(surface) ?? surface,
          const SizedBox(height: 8),
          Text(
            _selectionHint ??
                (_boxTool
                    ? '拖动框选至少 10 根 K 线 · Esc 取消'
                    : '左键平移 · 双击查看 / 滚轮缩放 · Shift 拖动框选 · 手机长按查看，× 关闭后拖动 · 双指缩放。UTC+8。'),
            key: const Key('crypto-selection-hint'),
            style: TextStyle(color: dashboardMuted, fontSize: 11, height: 1.4),
          ),
          ?widget.afterCharts,
          const SizedBox(height: 14),
          if (widget.viewSettings.assessment) _assessmentPanel(),
        ],
      ),
    );
  }

  Widget _resizeHandle(String id) {
    final height = _paneHeights[id] ?? cryptoPaneHeight;
    final active = _hoveredResize == id || _resizingPane == id;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    void finish() {
      setState(() => _resizingPane = null);
      widget.onPaneHeightsChanged?.call(Map.of(_paneHeights));
    }

    void save() => widget.onPaneHeightsChanged?.call(Map.of(_paneHeights));
    void resize(double value, {bool persist = true}) {
      setState(
        () => _paneHeights[id] = value.clamp(
          cryptoMinPaneHeight,
          cryptoMaxPaneHeight,
        ),
      );
      if (persist) save();
    }

    return Semantics(
      label: '调整 ${_studyName(id)} 副图高度',
      excludeSemantics: true,
      value: '${height.round()} 像素',
      increasedValue:
          '${(height + 20).clamp(cryptoMinPaneHeight, cryptoMaxPaneHeight).round()} 像素',
      decreasedValue:
          '${(height - 20).clamp(cryptoMinPaneHeight, cryptoMaxPaneHeight).round()} 像素',
      onIncrease: () => resize(height + 20),
      onDecrease: () => resize(height - 20),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _hoveredResize = id),
        onExit: (_) => setState(() => _hoveredResize = null),
        child: Tooltip(
          message: '拖动调整副图高度',
          child: GestureDetector(
            key: ValueKey('crypto-resize-$id'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => setState(() => _resizingPane = id),
            onVerticalDragUpdate: (e) => resize(
              (_paneHeights[id] ?? cryptoPaneHeight) + e.delta.dy,
              persist: false,
            ),
            onVerticalDragEnd: (_) => finish(),
            onVerticalDragCancel: finish,
            child: Container(
              height: math.max(22, textScale * 14 + 4),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF3A3A3C) : _cryptoResizeSurface,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF48484A)),
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: math.min(
                  MediaQuery.sizeOf(context).width - 32,
                  136 * textScale,
                ),
                height: math.max(18, textScale * 14),
                decoration: BoxDecoration(
                  color: active ? dashboardAccent : const Color(0xFF48484A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFB9D8FF)
                        : const Color(0xFF98989D),
                  ),
                ),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: 'ShikeSans',
                    fontSize: 10,
                    color: active
                        ? dashboardBackground
                        : const Color(0xFFE0EDFA),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.unfold_more,
                        size: 14,
                        color: active
                            ? dashboardBackground
                            : const Color(0xFFE0EDFA),
                      ),
                      const SizedBox(width: 3),
                      const Text('调整高度'),
                      const SizedBox(width: 6),
                      Text('${height.round()}px'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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

class _ChartScale {
  _ChartScale(
    List<CryptoCandle> rows,
    int offset,
    List<IndicatorStudy> studies, {
    required this.price,
  }) {
    final values = <double>[
      if (price)
        for (final row in rows) ...[row.low, row.high],
      for (final study in studies)
        for (final line in study.lines)
          for (final value in line.values.skip(offset).take(rows.length))
            if (value != null && value.isFinite) value,
      if (!price)
        for (final study in studies) ...study.levels,
      if (!price && studies.any((s) => s.lines.any((l) => l.bars))) 0,
    ];
    final min = values.isEmpty ? 0.0 : values.reduce(math.min);
    final max = values.isEmpty ? 1.0 : values.reduce(math.max);
    final pad = math.max(
      (max - min) * .08,
      math.max(math.max(min.abs(), max.abs()), 1e-12) * .001,
    );
    low =
        !price &&
            studies.every(
              (s) =>
                  const ['vol', 'amount', 'atr', 'natr', 'bbw'].contains(s.id),
            )
        ? 0.0
        : min - pad;
    high = max + pad;
  }
  final bool price;
  late final double low, high;
  String format(double value) => price
      ? cryptoPrice(
          double.parse(
            value.toStringAsFixed(
              (high - low).abs() < .001
                  ? 8
                  : value.abs() >= 10
                  ? 2
                  : value.abs() >= 1
                  ? 4
                  : 6,
            ),
          ),
        )
      : value.abs() >= 10000
      ? cryptoVolume(value)
      : value.toStringAsFixed(
          value != 0 && value.abs() < .001
              ? 8
              : value.abs() < 1
              ? 3
              : 2,
        );
  double get axisWidth {
    var width = 0.0;
    for (var i = 0; i <= 4; i++) {
      final text = TextPainter(
        text: TextSpan(
          text: format(low + (high - low) * i / 4),
          style: const TextStyle(fontSize: 10, fontFamily: 'ShikeSans'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      width = math.max(width, text.width);
      text.dispose();
    }
    return width.ceilToDouble() + 10;
  }
}

class _MarketPainter extends CustomPainter {
  _MarketPainter(
    this.rows,
    this.selected,
    this.offset,
    this.studies, {
    required this.price,
    required this.scale,
    required this.axisWidth,
    this.crosshair = false,
    this.pointerY = .5,
    this.horizontalCrosshair = false,
  });
  final List<CryptoCandle> rows;
  final int selected, offset;
  final List<IndicatorStudy> studies;
  final bool price, crosshair, horizontalCrosshair;
  final double pointerY, axisWidth;
  final _ChartScale scale;
  @override
  void paint(Canvas canvas, Size size) {
    final right = size.width - axisWidth,
        width = math.max(1.0, right - 4),
        bottom = size.height - 10;
    final low = scale.low, high = scale.high;
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
      )..layout(maxWidth: math.max(1, axisWidth - 6));
      painter.paint(canvas, point);
    }

    final grid = Paint()
      ..color = dashboardBorder
      ..strokeWidth = .5;
    for (var i = 0; i <= 4; i++) {
      final value = low + (high - low) * i / 4;
      canvas.drawLine(Offset(4, y(value)), Offset(right, y(value)), grid);
      label(scale.format(value), Offset(right + 4, y(value) - 6));
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
      if (!horizontalCrosshair) {
        canvas.restore();
        return;
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
        Rect.fromLTWH(right + 2, py - 8, axisWidth - 2, 17),
        Paint()..color = price ? _cryptoMainSurface : _cryptoPaneSurface,
      );
      label(
        scale.format(high - (py - 10) / (bottom - 10) * (high - low)),
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
        final minimum = math.min(10, n);
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
  _TimeAxisPainter(this.rows, this.axisWidth);
  final double axisWidth;
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
        i / ticks * math.max(1, size.width - axisWidth - 4),
        3,
        size.width,
      );
    }
  }

  @override
  bool shouldRepaint(_TimeAxisPainter old) =>
      old.rows != rows || old.axisWidth != axisWidth;
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
