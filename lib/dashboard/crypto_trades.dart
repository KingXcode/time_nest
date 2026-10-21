import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_chart.dart' show cryptoUp, cryptoDown;
import 'crypto_market.dart';
import 'dashboard_client.dart';
import 'dashboard_widgets.dart';

class CryptoTrade {
  CryptoTrade.fromJson(Map raw) {
    if (raw['id'] is! int ||
        (raw['id'] as int) < 0 ||
        (raw['id'] as int) > 9007199254740991 ||
        raw['time'] is! int ||
        (raw['time'] as int) <= 0 ||
        (raw['time'] as int) >= 8640000000000000 ||
        raw['buyerMaker'] is! bool ||
        !['price', 'quantity'].every(
          (k) =>
              raw[k] is num && (raw[k] as num).isFinite && (raw[k] as num) > 0,
        ) ||
        !((raw['price'] as num) * (raw['quantity'] as num)).isFinite) {
      throw const FormatException('Invalid market trade');
    }
    id = raw['id'] as int;
    time = raw['time'] as int;
    price = (raw['price'] as num).toDouble();
    quantity = (raw['quantity'] as num).toDouble();
    buyerMaker = raw['buyerMaker'] as bool;
  }
  late final int id, time;
  late final double price, quantity;
  late final bool buyerMaker;
  double get amount => price * quantity;
}

class CryptoTrades extends StatefulWidget {
  const CryptoTrades({
    super.key,
    required this.symbol,
    required this.trades,
    required this.status,
    required this.client,
    this.rows = 50,
    this.showAmount = true,
    this.active = true,
  });
  final String symbol, status;
  final List<CryptoTrade> trades;
  final DashboardClient client;
  final int rows;
  final bool active, showAmount;
  @override
  State<CryptoTrades> createState() => _CryptoTradesState();
}

class _CryptoTradesState extends State<CryptoTrades> {
  CryptoPriceRule? _rule;
  DateTime? _ruleTime;
  StreamSubscription<DashboardData>? _updates;
  Timer? _timer;
  int _serial = 0;
  bool _ruleError = false;
  List<CryptoTrade>? _frozen;
  final _scroll = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    _watch();
    _load();
  }

  void _apply(DashboardData data) {
    try {
      if (_ruleTime != null && data.fetchedAt.isBefore(_ruleTime!)) return;
      if (data.data['symbol'] != null && data.data['symbol'] != widget.symbol) {
        return;
      }
      final raw = (data.data['rules'] as List).whereType<Map>().firstWhere(
        (r) => r['symbol'] == widget.symbol,
      );
      final rule = CryptoPriceRule.fromJson(raw);
      setState(() {
        _rule = rule;
        _ruleTime = data.fetchedAt;
        _ruleError = data.stale;
      });
    } catch (_) {
      /* Preserve a usable rule when a refresh is malformed. */
    }
  }

  void _watch() {
    _updates?.cancel();
    final client = widget.client, serial = _serial;
    if (client is CryptoRulesUpdates) {
      _updates = (client as CryptoRulesUpdates).watchCryptoRules().listen((
        data,
      ) {
        if (mounted && serial == _serial) _apply(data);
      }, onError: (Object _) {});
    }
  }

  Future<void> _load() async {
    _timer?.cancel();
    if (!widget.active) return;
    final serial = _serial;
    try {
      final data = await widget.client.load('cryptoBookRules', {
        'symbol': widget.symbol,
      });
      if (mounted && serial == _serial) _apply(data);
    } catch (_) {
      if (mounted && serial == _serial) setState(() => _ruleError = true);
    }
    if (mounted && serial == _serial && widget.active) {
      _timer = Timer(Duration(seconds: _ruleError ? 60 : 300), _load);
    }
  }

  @override
  void didUpdateWidget(CryptoTrades old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client || old.symbol != widget.symbol) {
      _serial++;
      _rule = null;
      _ruleTime = null;
      _ruleError = false;
      _frozen = null;
      _watch();
      _load();
    } else if (old.active != widget.active) {
      _serial++;
      _watch();
      _timer?.cancel();
      if (widget.active) _load();
    }
  }

  @override
  void dispose() {
    _serial++;
    _updates?.cancel();
    _timer?.cancel();
    _scroll.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  String number(double value, int digits, {bool commas = false}) {
    final parts = value.toStringAsFixed(digits).split('.');
    if (commas) {
      parts[0] = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
    }
    return parts.join('.');
  }

  @override
  Widget build(BuildContext context) {
    final asset = cryptoBaseAsset(widget.symbol);
    final quoteAsset = cryptoQuoteAsset(widget.symbol);
    final rows = (_frozen ?? widget.trades).take(widget.rows).toList();
    final live = widget.status == 'live';
    final status = _frozen != null
        ? '已定格'
        : live
        ? '实时'
        : widget.status == 'paused'
        ? '已暂停'
        : const [
            'reconnecting',
            'retrying',
            'error',
            'unavailable',
          ].contains(widget.status)
        ? '等待重试'
        : '同步中';
    const numeric = TextStyle(
      fontSize: 11,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    Widget cells(
      String price,
      String quantity,
      String amount,
      String time, {
      Color? color,
      String? exactAmount,
      Key? amountKey,
    }) => Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            price,
            style: numeric.copyWith(color: color),
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: Text(
            quantity,
            style: numeric,
            textAlign: TextAlign.right,
            maxLines: 1,
          ),
        ),
        if (widget.showAmount) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Tooltip(
              message: exactAmount == null
                  ? '金额 ($quoteAsset)'
                  : '$exactAmount $quoteAsset',
              excludeFromSemantics: true,
              child: Text(
                amount,
                key: amountKey,
                style: numeric,
                textAlign: TextAlign.right,
                maxLines: 1,
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            time,
            style: numeric,
            textAlign: TextAlign.right,
            maxLines: 1,
          ),
        ),
      ],
    );
    return Semantics(
      label: '最新成交面板',
      container: true,
      explicitChildNodes: true,
      child: Container(
        key: const Key('crypto-trades-panel'),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          border: Border.all(color: dashboardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: const Color(0xFF2C2C2E),
              padding: const EdgeInsets.only(left: 10, right: 4),
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '最新成交 $asset / $quoteAsset',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      color: live && _frozen == null
                          ? cryptoUp
                          : dashboardMuted,
                    ),
                  ),
                  IconButton(
                    key: const Key('crypto-trades-freeze'),
                    tooltip: _frozen == null ? '暂停成交列表' : '继续成交列表',
                    onPressed: rows.isEmpty
                        ? null
                        : () => setState(() {
                            if (_frozen == null) {
                              _frozen = List.of(widget.trades);
                            } else {
                              _frozen = null;
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                            }
                          }),
                    icon: Icon(
                      _frozen == null ? Icons.pause : Icons.play_arrow,
                      size: 15,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, box) {
                final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
                final rowHeight = math.max(22.0, 20 * scale);
                final minWidth = (widget.showAmount ? 312 : 232) * scale;
                return Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: box.maxWidth < minWidth,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(box.maxWidth, minWidth),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: DefaultTextStyle.merge(
                              style: const TextStyle(color: dashboardMuted),
                              child: cells(
                                '价格($quoteAsset)',
                                '数量($asset)',
                                '金额($quoteAsset)',
                                '时间',
                              ),
                            ),
                          ),
                          if (rows.isEmpty)
                            SizedBox(
                              height: 220,
                              child: Center(
                                child: Text(
                                  widget.status == 'paused'
                                      ? '实时推送已暂停'
                                      : '等待最新成交…',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: dashboardMuted,
                                  ),
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              height: math.min(rows.length, 20) * rowHeight,
                              child: Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  key: const Key('crypto-trades-list'),
                                  controller: _scroll,
                                  padding: EdgeInsets.zero,
                                  itemExtent: rowHeight,
                                  itemCount: rows.length,
                                  itemBuilder: (context, i) {
                                    final trade = rows[i], rule = _rule;
                                    final price = rule == null
                                        ? '—'
                                        : number(
                                            trade.price,
                                            rule.decimals,
                                            commas: true,
                                          );
                                    final quantity = rule == null
                                        ? '—'
                                        : number(
                                            trade.quantity,
                                            rule.quantityDecimals,
                                          );
                                    final exactAmount = rule == null
                                        ? '—'
                                        : number(
                                            trade.amount,
                                            rule.amountDecimals,
                                          );
                                    final amount = rule == null
                                        ? '—'
                                        : trade.amount >= 1000000
                                        ? '${(trade.amount / 1000000).toStringAsFixed(2)}M'
                                        : trade.amount >= 1000
                                        ? '${(trade.amount / 1000).toStringAsFixed(2)}K'
                                        : exactAmount;
                                    final time = cryptoTime(
                                      trade.time,
                                      seconds: true,
                                    ).split(' ').last;
                                    return Semantics(
                                      label:
                                          '成交 ${trade.id}，${trade.buyerMaker ? '主动卖出' : '主动买入'}，价格 $price $quoteAsset，数量 $quantity $asset${widget.showAmount ? '，金额 $exactAmount $quoteAsset' : ''}，时间 $time',
                                      child: Tooltip(
                                        message:
                                            '${cryptoTime(trade.time, seconds: true)} UTC+8',
                                        child: Padding(
                                          key: ValueKey(
                                            'crypto-trade-${trade.id}',
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: cells(
                                            price,
                                            quantity,
                                            amount,
                                            time,
                                            exactAmount: exactAmount,
                                            amountKey: ValueKey(
                                              'crypto-trade-amount-${trade.id}',
                                            ),
                                            color: trade.buyerMaker
                                                ? cryptoDown
                                                : cryptoUp,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _ruleError
                          ? '交易规范暂不可用'
                          : '最新在上 · ${rows.length}/${widget.rows} 笔 · UTC+8',
                      style: const TextStyle(
                        color: dashboardMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  if (_ruleError)
                    InkWell(
                      onTap: _load,
                      child: const Text(
                        '重试',
                        style: TextStyle(fontSize: 10, color: dashboardAccent),
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
}
