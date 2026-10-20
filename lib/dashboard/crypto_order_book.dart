import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_chart.dart' show cryptoUp, cryptoDown;
import 'crypto_market.dart';
import 'dashboard_widgets.dart';
import 'dashboard_client.dart';

class CryptoBookLevel {
  const CryptoBookLevel(this.price, this.quantity, this.amount);
  factory CryptoBookLevel.fromJson(Map value) {
    final price = value['price'], quantity = value['quantity'];
    if (price is! num ||
        quantity is! num ||
        !price.isFinite ||
        !quantity.isFinite ||
        price <= 0 ||
        quantity <= 0 ||
        !(price * quantity).isFinite) {
      throw const FormatException('Invalid depth level');
    }
    return CryptoBookLevel(
      price.toDouble(),
      quantity.toDouble(),
      (price * quantity).toDouble(),
    );
  }
  final double price, quantity, amount;
}

class CryptoBook {
  CryptoBook.fromJson(
    Map value, {
    required this.symbol,
    required this.receivedAt,
  }) {
    if (!cryptoAssets.containsKey(symbol) ||
        receivedAt <= 0 ||
        receivedAt >= 8640000000000000 ||
        value['lastUpdateId'] is! int ||
        (value['lastUpdateId'] as int) < 0 ||
        value['priceDecimals'] is! int ||
        (value['priceDecimals'] as int) < 0 ||
        (value['priceDecimals'] as int) > 8) {
      throw const FormatException('Invalid depth snapshot');
    }
    updateId = value['lastUpdateId'] as int;
    priceDecimals = value['priceDecimals'] as int;
    List<CryptoBookLevel> side(Object? raw, bool bid) {
      if (raw is! List || raw.length > 10000) {
        throw const FormatException('Invalid depth side');
      }
      final rows = raw.map((r) => CryptoBookLevel.fromJson(r as Map)).toList();
      for (var i = 1; i < rows.length; i++) {
        if (bid
            ? rows[i].price >= rows[i - 1].price
            : rows[i].price <= rows[i - 1].price) {
          throw const FormatException('Unsorted depth');
        }
      }
      return List.unmodifiable(rows);
    }

    bids = side(value['bids'], true);
    asks = side(value['asks'], false);
    double? cutoff(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! num || !raw.isFinite || raw <= 0) {
        throw const FormatException('Invalid depth cutoff');
      }
      return raw.toDouble();
    }

    bidFloor = cutoff('bidFloor');
    askCeiling = cutoff('askCeiling');
    if ((bidFloor != null && bids.any((r) => r.price < bidFloor!)) ||
        (askCeiling != null && asks.any((r) => r.price > askCeiling!))) {
      throw const FormatException('Depth outside trusted range');
    }
    if (bids.isNotEmpty &&
        asks.isNotEmpty &&
        bids.first.price >= asks.first.price) {
      throw const FormatException('Crossed depth');
    }
  }
  final String symbol;
  final int receivedAt;
  late final int updateId, priceDecimals;
  late final List<CryptoBookLevel> bids, asks;
  late final double? bidFloor, askCeiling;
  final _groupCache = <(bool, int, double?), List<CryptoBookLevel>>{};

  List<CryptoBookLevel> grouped({
    required bool bid,
    int multiplier = 1,
    double? step,
  }) {
    final rows = bid ? bids : asks;
    final key = (bid, multiplier, step);
    final cached = _groupCache[key];
    if (cached != null) return cached;
    if (step == null && multiplier == 1) return rows;
    var decimals = priceDecimals;
    if (step != null) {
      if (!step.isFinite || step <= 0) {
        throw const FormatException('Invalid grouping step');
      }
      final fraction = step
          .toStringAsFixed(8)
          .split('.')[1]
          .replaceFirst(RegExp(r'0+$'), '');
      decimals = math.max(decimals, fraction.length);
    }
    final scale = math.pow(10, decimals).toDouble();
    if (step != null) multiplier = (step * scale).round();
    if (multiplier < 1) throw const FormatException('Invalid grouping step');
    final boundary = bid ? bidFloor : askCeiling;
    final cutoff = boundary == null ? null : (boundary * scale).round();
    final groups = <int, CryptoBookLevel>{};
    for (final row in rows) {
      final ticks = (row.price * scale).round();
      final bucket =
          (bid ? ticks ~/ multiplier : (ticks + multiplier - 1) ~/ multiplier) *
          multiplier;
      // A coarse bucket crossing the original 5000-level boundary is only
      // partly known. Omit it instead of presenting a partial sum as complete.
      if (cutoff != null && (bid ? bucket < cutoff : bucket > cutoff)) continue;
      final old = groups[bucket];
      groups[bucket] = CryptoBookLevel(
        bucket / scale,
        row.quantity + (old?.quantity ?? 0),
        row.amount + (old?.amount ?? 0),
      );
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => bid ? b.compareTo(a) : a.compareTo(b));
    return _groupCache[key] = List.unmodifiable([
      for (final key in keys) groups[key]!,
    ]);
  }

  late final double bidQuantity = bids.fold(
    0,
    (sum, row) => sum + row.quantity,
  );
  late final double askQuantity = asks.fold(
    0,
    (sum, row) => sum + row.quantity,
  );
  double get bidShare => bidQuantity + askQuantity == 0
      ? 0
      : bidQuantity / (bidQuantity + askQuantity);
}

/// The chart keeps its full price height; only horizontal space is shared.
class CryptoBookLayout extends StatelessWidget {
  const CryptoBookLayout({
    super.key,
    required this.chart,
    required this.orderBook,
  });
  final Widget Function(Widget? belowChart) chart;
  final Widget orderBook;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = MediaQuery.sizeOf(context);
      final side =
          box.maxWidth >= 900 ||
          (size.width > size.height && box.maxWidth >= 520);
      if (!side) {
        return chart(
          Padding(padding: const EdgeInsets.only(top: 10), child: orderBook),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: chart(null)),
          const SizedBox(width: 8),
          SizedBox(
            width: (box.maxWidth * .30).clamp(220.0, 320.0),
            child: orderBook,
          ),
        ],
      );
    },
  );
}

enum _BookView { both, bids, asks }

class CryptoOrderBook extends StatefulWidget {
  const CryptoOrderBook({
    super.key,
    required this.symbol,
    required this.book,
    required this.status,
    this.lastPrice,
    required this.client,
    this.currency = 'USD',
    this.onCurrencyChanged,
    this.active = true,
    this.levels,
    this.priceStep,
    this.onLevelsChanged,
    this.onPriceStepChanged,
  });
  final String symbol, status, currency;
  final DashboardClient client;
  final ValueChanged<String>? onCurrencyChanged;
  final bool active;
  final int? levels;
  final double? priceStep;
  final ValueChanged<int>? onLevelsChanged;
  final ValueChanged<double>? onPriceStepChanged;
  final CryptoBook? book;
  final double? lastPrice;
  @override
  State<CryptoOrderBook> createState() => _CryptoOrderBookState();
}

class _CryptoOrderBookState extends State<CryptoOrderBook>
    with WidgetsBindingObserver {
  _BookView _view = _BookView.both;
  late int? _visibleLevels = widget.levels;
  late double? _selectedStep = widget.priceStep;
  CryptoPriceRule? _rule;
  DateTime? _ruleFetchedAt;
  StreamSubscription<DashboardData>? _ruleUpdates;
  int _ruleWatchSerial = 0;
  bool _rulesError = false;
  int _priceDirection = 0;
  String? _hoveredLevel;
  late String _currency = widget.currency == 'CNY' ? 'CNY' : 'USD';
  DashboardData? _rates;
  bool _rateError = false, _ratesBusy = false;
  Timer? _rateTimer;
  int _rateSerial = 0;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _watchRules();
    _loadRates();
  }

  void _watchRules() {
    final token = ++_ruleWatchSerial;
    _ruleUpdates?.cancel();
    final client = widget.client;
    _ruleUpdates = client is CryptoRulesUpdates
        ? (client as CryptoRulesUpdates).watchCryptoRules().listen((data) {
            if (mounted && token == _ruleWatchSerial) _applyRules(data);
          }, onError: (Object _) {})
        : null;
  }

  void _applyRules(DashboardData result) {
    try {
      final rows = (result.data['rules'] as List).map(
        (r) => CryptoPriceRule.fromJson(r as Map),
      );
      final rule = rows.firstWhere((r) => r.symbol == widget.symbol);
      if (_ruleFetchedAt != null &&
          result.fetchedAt.isBefore(_ruleFetchedAt!)) {
        return;
      }
      setState(() {
        _rule = rule;
        _ruleFetchedAt = result.fetchedAt;
        _rulesError = result.stale;
      });
    } catch (_) {
      /* An invalid update must not replace usable cached rules. */
    }
  }

  Future<void> _loadRates() async {
    if (!_visible || !widget.active || _ratesBusy) return;
    _rateTimer?.cancel();
    _ratesBusy = true;
    final serial = ++_rateSerial;
    Future<void> conversion() async {
      try {
        final result = await widget.client.load('cryptoConversion', const {});
        if (result.data['base'] != 'USDT' ||
            !const ['USD', 'CNY'].every(
              (key) =>
                  result.data[key] is num &&
                  (result.data[key] as num).isFinite &&
                  (result.data[key] as num) > 0,
            )) {
          throw const FormatException('Invalid conversion rates');
        }
        if (!mounted || serial != _rateSerial) return;
        setState(() {
          _rates = result;
          _rateError = result.stale;
        });
      } catch (_) {
        if (mounted && serial == _rateSerial) setState(() => _rateError = true);
      }
    }

    Future<void> rules() async {
      try {
        final result = await widget.client.load('cryptoBookRules', const {});
        if (!mounted || serial != _rateSerial) return;
        _applyRules(result);
      } catch (_) {
        if (mounted && serial == _rateSerial) {
          setState(() => _rulesError = true);
        }
      }
    }

    await Future.wait([conversion(), rules()]);
    if (mounted && serial == _rateSerial) {
      _ratesBusy = false;
      if (_visible && widget.active) {
        _rateTimer = Timer(
          Duration(minutes: _rateError || _rulesError ? 1 : 5),
          _loadRates,
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_visible == visible) return;
    _visible = visible;
    _rateSerial++;
    _ratesBusy = false;
    _rateTimer?.cancel();
    if (visible) _loadRates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ruleWatchSerial++;
    _ruleUpdates?.cancel();
    _rateSerial++;
    _rateTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CryptoOrderBook old) {
    super.didUpdateWidget(old);
    if (old.book != null && widget.book == null) _hoveredLevel = null;
    if (old.levels != widget.levels) _visibleLevels = widget.levels;
    if (old.priceStep != widget.priceStep) _selectedStep = widget.priceStep;
    if (old.currency != widget.currency) {
      _currency = widget.currency == 'CNY' ? 'CNY' : 'USD';
    }
    if (old.active != widget.active || old.client != widget.client) {
      _rateSerial++;
      _ratesBusy = false;
      _rateTimer?.cancel();
      if (old.client != widget.client) {
        _rates = null;
        _rule = null;
        _ruleFetchedAt = null;
        _watchRules();
      }
      _loadRates();
    }
    if (old.lastPrice != null &&
        widget.lastPrice != null &&
        old.lastPrice != widget.lastPrice) {
      _priceDirection = widget.lastPrice!.compareTo(old.lastPrice!);
    }
  }

  String compact(double value, {int precision = 5}) {
    final abs = value.abs();
    if (abs >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (abs >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
    return value.toStringAsFixed(precision);
  }

  String price(double value, int digits) {
    final parts = value.toStringAsFixed(digits).split('.');
    parts[0] = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return parts.join('.');
  }

  Widget _conversion() {
    final rates = _rates;
    final freshEnough =
        rates != null &&
        DateTime.now().difference(rates.fetchedAt) <= const Duration(days: 1);
    final rate = freshEnough ? (rates.data[_currency] as num).toDouble() : null;
    final amount = rate != null && widget.lastPrice != null
        ? widget.lastPrice! * rate
        : null;
    final stale =
        _rateError ||
        (rates != null &&
            DateTime.now().difference(rates.fetchedAt) >=
                const Duration(minutes: 5));
    final value = amount != null && amount.isFinite
        ? '≈ ${_currency == 'USD' ? r'$' : '¥'}${price(amount, 2)}${stale ? ' · 旧汇率' : ''}'
        : rates == null && !_rateError
        ? '汇率加载中…'
        : '汇率暂不可用';
    final detail = rate == null
        ? '参考折算汇率暂不可用，稍后自动重试'
        : 'Coinbase 参考汇率\n1 USDT ≈ $rate $_currency\n获取：${cryptoTime(rates!.fetchedAt.millisecondsSinceEpoch, seconds: true)} UTC+8${stale ? '\n当前使用旧汇率，稍后自动重试' : ''}';
    return PopupMenuButton<String>(
      key: const Key('crypto-book-currency'),
      tooltip: '切换折算货币',
      initialValue: _currency,
      onSelected: (value) {
        setState(() => _currency = value);
        widget.onCurrencyChanged?.call(value);
      },
      itemBuilder: (_) => [
        for (final entry in const {'USD': '美元 USD', 'CNY': '人民币 CNY'}.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Tooltip(
        message: detail,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$value $_currency',
                  key: const Key('crypto-book-converted-price'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: dashboardMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Icon(Icons.expand_more, size: 14, color: dashboardMuted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final rule = _rule;
    final digits = rule?.decimals ?? book?.priceDecimals ?? 2;
    final quantityDigits = rule?.quantityDecimals ?? 8;
    final amountDigits = rule?.amountDecimals ?? 8;
    final steps = rule?.steps ?? <double>[];
    final step = steps.contains(_selectedStep)
        ? _selectedStep
        : steps.firstOrNull;
    final size = MediaQuery.sizeOf(context);
    final compactLandscape = size.width > size.height && size.height < 600;
    final levels = _visibleLevels ?? (compactLandscape ? 5 : 20);
    final bids =
        book?.grouped(bid: true, step: step).take(levels).toList() ??
        <CryptoBookLevel>[];
    final asks =
        book?.grouped(bid: false, step: step).take(levels).toList() ??
        <CryptoBookLevel>[];
    final bidQuantity = bids.fold<double>(0, (sum, row) => sum + row.quantity);
    final askQuantity = asks.fold<double>(0, (sum, row) => sum + row.quantity);
    final bidShare = bidQuantity + askQuantity == 0
        ? 0.0
        : bidQuantity / (bidQuantity + askQuantity);
    final insufficient = bids.length < levels || asks.length < levels;
    final truncated = book?.bidFloor != null || book?.askCeiling != null;
    final maxBidQty = bids.fold<double>(
      0,
      (max, r) => math.max(max, r.quantity),
    );
    final maxAskQty = asks.fold<double>(
      0,
      (max, r) => math.max(max, r.quantity),
    );
    final live =
        book != null &&
        widget.status == 'live' &&
        DateTime.now().millisecondsSinceEpoch - book.receivedAt <= 15000;
    final status = widget.status == 'paused'
        ? '已暂停'
        : widget.status == 'syncing'
        ? book == null
              ? '正在同步订单簿…'
              : '同步中 · 旧快照'
        : widget.status == 'retrying'
        ? book == null
              ? '同步重试中'
              : '同步重试 · 旧快照'
        : live
        ? '实时 · $levels档'
        : book == null
        ? '等待深度数据'
        : widget.status == 'live'
        ? '等待更新 · 旧快照'
        : '重连中 · 旧快照';
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final rowHeight = math.max(
      compactLandscape ? 17.0 : 19.0,
      textScale * 14 + 3,
    );
    final rowStyle = DefaultTextStyle.of(context).style.merge(
      const TextStyle(
        fontSize: 11,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    double textWidth(String text) => (TextPainter(
      text: TextSpan(text: text, style: rowStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout()).width;
    String number(double value, int precision, bool abbreviate) => abbreviate
        ? compact(value, precision: precision)
        : price(value, precision);
    String tail(String text) {
      final dot = text.indexOf('.');
      return dot >= 0
          ? text.substring(dot)
          : RegExp(r'[KM]$').firstMatch(text)?.group(0) ?? '';
    }

    final quantityTail = textWidth(
      '${quantityDigits > 0 || [...bids, ...asks].any((r) => r.quantity >= 1000) ? '.' : ''}${'0' * math.max(quantityDigits, [...bids, ...asks].any((r) => r.quantity >= 1000) ? 2 : 0)}M',
    );
    final amountTail = textWidth('.${'0' * math.max(amountDigits, 2)}M');
    Widget cell(
      double value,
      int precision, {
      bool abbreviate = false,
      Color? color,
      double? reservedTail,
      String label = '',
    }) {
      final text = number(value, precision, abbreviate);
      final reserve = reservedTail ?? textWidth(tail(text));
      return Semantics(
        label: '$label $text',
        container: true,
        excludeSemantics: true,
        child: Tooltip(
          message: price(value, precision),
          child: Padding(
            padding: EdgeInsets.only(
              right: math.max(0, reserve - textWidth(tail(text))),
            ),
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: rowStyle.copyWith(color: color),
              maxLines: 1,
            ),
          ),
        ),
      );
    }

    double requiredColumnWidth(
      double Function(CryptoBookLevel) value,
      int precision,
      bool abbreviate,
      double? reserve,
    ) {
      return [...bids, ...asks].fold<double>(0, (width, row) {
        final text = number(value(row), precision, abbreviate);
        return math.max(
          width,
          textWidth(text) +
              math.max(
                0,
                (reserve ?? textWidth(tail(text))) - textWidth(tail(text)),
              ),
        );
      });
    }

    final columnWidths = [
      math.max(
        55 * textScale,
        requiredColumnWidth((r) => r.price, digits, false, null),
      ),
      math.max(
        55 * textScale,
        requiredColumnWidth(
          (r) => r.quantity,
          quantityDigits,
          true,
          quantityTail,
        ),
      ),
      math.max(
        60 * textScale,
        requiredColumnWidth((r) => r.amount, amountDigits, true, amountTail),
      ),
    ];
    final columnFlex = [for (final width in columnWidths) (width * 100).ceil()];
    final tableWidth = math.max(
      220 * textScale,
      12 + columnWidths.reduce((a, b) => a + b),
    );
    Widget row(CryptoBookLevel level, bool bid) {
      final color = bid ? cryptoUp : cryptoDown;
      final id = '${bid ? 'bid' : 'ask'}-${level.price}';
      final maxQty = bid ? maxBidQty : maxAskQty;
      final ratio = maxQty > 0
          ? (level.quantity / maxQty).clamp(0.0, 1.0)
          : 0.0;
      return MouseRegion(
        onEnter: (_) => setState(() => _hoveredLevel = id),
        onExit: (_) {
          if (_hoveredLevel == id) setState(() => _hoveredLevel = null);
        },
        child: SizedBox(
          key: ValueKey('crypto-book-row-$id'),
          height: rowHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.centerRight,
                    // Keep very small positive orders findable without changing
                    // the displayed quantities or the otherwise linear scale.
                    child: SizedBox(
                      key: ValueKey('crypto-book-depth-$id'),
                      width: math.min(
                        box.maxWidth,
                        math.max(2, box.maxWidth * ratio),
                      ),
                      height: rowHeight,
                      child: ColoredBox(color: color.withValues(alpha: .23)),
                    ),
                  ),
                ),
              ),
              if (_hoveredLevel == id)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .045),
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: color.withValues(alpha: .45),
                          width: .5,
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: columnFlex[0],
                      child: cell(
                        level.price,
                        digits,
                        color: color,
                        label: '价格(USDT)',
                      ),
                    ),
                    Expanded(
                      flex: columnFlex[1],
                      child: cell(
                        level.quantity,
                        quantityDigits,
                        abbreviate: true,
                        reservedTail: quantityTail,
                        label: '数量(${cryptoAssets[widget.symbol]!.$1})',
                      ),
                    ),
                    Expanded(
                      flex: columnFlex[2],
                      child: cell(
                        level.amount,
                        amountDigits,
                        abbreviate: true,
                        reservedTail: amountTail,
                        label: '金额(USDT)',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget viewButton(
      _BookView view,
      String label,
      IconData icon,
      Color color,
    ) => IconButton(
      key: ValueKey('crypto-book-view-${view.name}'),
      tooltip: label,
      style: IconButton.styleFrom(
        backgroundColor: _view == view
            ? const Color(0xFF2C4058)
            : Colors.transparent,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      onPressed: () => setState(() => _view = view),
      icon: Icon(icon, color: color, size: 16),
    );
    final panel = DecoratedBox(
      key: const Key('crypto-order-book'),
      decoration: BoxDecoration(
        color: const Color(0xFF101C2B),
        border: Border.all(color: dashboardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF21364D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  '订单簿 ${cryptoAssets[widget.symbol]!.$1}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  status,
                  key: const Key('crypto-book-status'),
                  style: TextStyle(
                    fontSize: 10,
                    color: live ? cryptoUp : dashboardMuted,
                  ),
                ),
                PopupMenuButton<int>(
                  key: const Key('crypto-book-levels'),
                  tooltip: '显示档位',
                  initialValue: levels,
                  onSelected: (value) {
                    setState(() => _visibleLevels = value);
                    widget.onLevelsChanged?.call(value);
                  },
                  itemBuilder: (context) => [
                    for (final n in [5, 10, 20])
                      CheckedPopupMenuItem(
                        value: n,
                        checked: levels == n,
                        child: Text('$n 档'),
                      ),
                  ],
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: dashboardMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    viewButton(
                      _BookView.both,
                      '显示买卖盘',
                      Icons.view_agenda_outlined,
                      dashboardAccent,
                    ),
                    viewButton(
                      _BookView.bids,
                      '只看买盘',
                      Icons.call_received,
                      cryptoUp,
                    ),
                    viewButton(
                      _BookView.asks,
                      '只看卖盘',
                      Icons.call_made,
                      cryptoDown,
                    ),
                  ],
                ),
                Tooltip(
                  message: '价格档位',
                  child: DropdownButton<double>(
                    key: const Key('crypto-book-grouping'),
                    value: step,
                    isDense: true,
                    underline: const SizedBox(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFE7EEF8),
                      fontFamily: 'ShikeSans',
                    ),
                    items: [
                      for (final n in steps)
                        DropdownMenuItem(value: n, child: Text(rule!.label(n))),
                    ],
                    onChanged: book == null || rule == null
                        ? null
                        : (n) {
                            if (n == null) return;
                            setState(() => _selectedStep = n);
                            widget.onPriceStepChanged?.call(n);
                          },
                    hint: Text(_rulesError ? '档位暂不可用' : '档位加载中…'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: columnFlex[0],
                  child: Text(
                    '价格(USDT)',
                    style: TextStyle(fontSize: 10, color: dashboardMuted),
                  ),
                ),
                Expanded(
                  flex: columnFlex[1],
                  child: Text(
                    '数量(${cryptoAssets[widget.symbol]!.$1})',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: dashboardMuted),
                  ),
                ),
                Expanded(
                  flex: columnFlex[2],
                  child: Text(
                    '金额(USDT)',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: dashboardMuted),
                  ),
                ),
              ],
            ),
          ),
          if (book == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 28),
              child: Text(
                '等待币安订单簿快照…',
                style: TextStyle(color: dashboardMuted, fontSize: 12),
              ),
            )
          else ...[
            if (_view != _BookView.bids)
              Semantics(
                label: '卖盘 ${asks.length} 档',
                child: Column(
                  key: const Key('crypto-book-asks'),
                  children: [
                    for (final level in asks.reversed) row(level, false),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: dashboardBorder),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    widget.lastPrice != null
                        ? '${price(widget.lastPrice!, digits)}${_priceDirection > 0
                              ? ' ↑'
                              : _priceDirection < 0
                              ? ' ↓'
                              : ''}'
                        : '—',
                    key: const Key('crypto-book-last-price'),
                    style: TextStyle(
                      fontSize: 20,
                      color: _priceDirection > 0
                          ? cryptoUp
                          : _priceDirection < 0
                          ? cryptoDown
                          : dashboardAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _conversion(),
                ],
              ),
            ),
            if (_view != _BookView.asks)
              Semantics(
                label: '买盘 ${bids.length} 档',
                child: Column(
                  key: const Key('crypto-book-bids'),
                  children: [for (final level in bids) row(level, true)],
                ),
              ),
            if (bidQuantity + askQuantity > 0)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          '买 ${(bidShare * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(color: cryptoUp, fontSize: 10),
                        ),
                        const Spacer(),
                        Text(
                          '${((1 - bidShare) * 100).toStringAsFixed(1)}% 卖',
                          style: const TextStyle(
                            color: cryptoDown,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: bidShare,
                      minHeight: 4,
                      color: cryptoUp,
                      backgroundColor: cryptoDown,
                    ),
                  ],
                ),
              ),
            if (bidQuantity + askQuantity == 0)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '暂无挂单',
                  style: TextStyle(fontSize: 11, color: dashboardMuted),
                ),
              ),
            if (insufficient)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Text(
                  '${truncated ? '已达每侧5000价位上限' : '当前挂单不足'} · 买${bids.length}/$levels 卖${asks.length}/$levels${truncated ? '（仅完整档）' : ''}',
                  key: const Key('crypto-book-depth-limit'),
                  style: const TextStyle(fontSize: 9, color: dashboardMuted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '买${book.bids.length}/卖${book.asks.length}价位 · 显示档数占比 · ${cryptoTime(book.receivedAt, seconds: true).substring(11)}',
                style: const TextStyle(fontSize: 9, color: dashboardMuted),
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      label: '订单簿面板',
      container: true,
      explicitChildNodes: true,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(box.maxWidth, tableWidth),
            child: panel,
          ),
        ),
      ),
    );
  }
}
