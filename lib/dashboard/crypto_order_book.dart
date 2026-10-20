import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_chart.dart' show cryptoUp, cryptoDown;
import 'crypto_market.dart';
import 'dashboard_widgets.dart';

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
      if (raw is! List || raw.length > 20) {
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
      return rows;
    }

    bids = side(value['bids'], true);
    asks = side(value['asks'], false);
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

  List<CryptoBookLevel> grouped({required bool bid, int multiplier = 1}) {
    final rows = bid ? bids : asks;
    if (multiplier == 1) return rows;
    final scale = math.pow(10, priceDecimals).toDouble();
    final groups = <int, CryptoBookLevel>{};
    for (final row in rows) {
      final ticks = (row.price * scale).round();
      final bucket =
          (bid ? ticks ~/ multiplier : (ticks + multiplier - 1) ~/ multiplier) *
          multiplier;
      final old = groups[bucket];
      groups[bucket] = CryptoBookLevel(
        bucket / scale,
        row.quantity + (old?.quantity ?? 0),
        row.amount + (old?.amount ?? 0),
      );
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => bid ? b.compareTo(a) : a.compareTo(b));
    return [for (final key in keys) groups[key]!];
  }

  double get bidQuantity => bids.fold(0, (sum, row) => sum + row.quantity);
  double get askQuantity => asks.fold(0, (sum, row) => sum + row.quantity);
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
  });
  final String symbol, status;
  final CryptoBook? book;
  final double? lastPrice;
  @override
  State<CryptoOrderBook> createState() => _CryptoOrderBookState();
}

class _CryptoOrderBookState extends State<CryptoOrderBook> {
  _BookView _view = _BookView.both;
  int _multiplier = 1;
  int? _visibleLevels;
  int _priceDirection = 0;
  String? _hoveredLevel;
  @override
  void didUpdateWidget(CryptoOrderBook old) {
    super.didUpdateWidget(old);
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
    return value.toStringAsFixed(precision).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String price(double value, int digits) {
    final parts = value.toStringAsFixed(digits).split('.');
    parts[0] = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return parts.join('.');
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final digits = book?.priceDecimals ?? 2;
    final size = MediaQuery.sizeOf(context);
    final compactLandscape = size.width > size.height && size.height < 600;
    final levels = _visibleLevels ?? (compactLandscape ? 5 : 20);
    final bids =
        book
            ?.grouped(bid: true, multiplier: _multiplier)
            .take(levels)
            .toList() ??
        <CryptoBookLevel>[];
    final asks =
        book
            ?.grouped(bid: false, multiplier: _multiplier)
            .take(levels)
            .toList() ??
        <CryptoBookLevel>[];
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
        : live
        ? '实时 · 20档'
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
    const rowStyle = TextStyle(
      fontSize: 11,
      fontFeatures: [FontFeature.tabularFigures()],
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
                      flex: 36,
                      child: Text(
                        price(level.price, digits),
                        style: rowStyle.copyWith(color: color),
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      flex: 31,
                      child: Text(
                        compact(level.quantity, precision: 8),
                        textAlign: TextAlign.right,
                        style: rowStyle,
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      flex: 33,
                      child: Text(
                        compact(level.amount, precision: 2),
                        textAlign: TextAlign.right,
                        style: rowStyle,
                        maxLines: 1,
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
                  onSelected: (value) => setState(() => _visibleLevels = value),
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
                DropdownButton<int>(
                  key: const Key('crypto-book-grouping'),
                  value: _multiplier,
                  isDense: true,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE7EEF8),
                    fontFamily: 'ShikeSans',
                  ),
                  items: [
                    for (final n in [1, 10, 100])
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          (n / math.pow(10, digits)).toStringAsFixed(digits),
                        ),
                      ),
                  ],
                  onChanged: book == null
                      ? null
                      : (n) => setState(() => _multiplier = n!),
                  hint: const Text('价格档位'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 36,
                  child: Text(
                    '价格(USDT)',
                    style: TextStyle(fontSize: 10, color: dashboardMuted),
                  ),
                ),
                Expanded(
                  flex: 31,
                  child: Text(
                    '数量(${cryptoAssets[widget.symbol]!.$1})',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: dashboardMuted),
                  ),
                ),
                Expanded(
                  flex: 33,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: dashboardBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.lastPrice != null
                        ? '${cryptoPrice(widget.lastPrice!)}${_priceDirection > 0
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
                  if (book.bids.isNotEmpty && book.asks.isNotEmpty)
                    Text(
                      '价差 ${(book.asks.first.price - book.bids.first.price).toStringAsFixed(digits)} USDT',
                      style: const TextStyle(
                        fontSize: 10,
                        color: dashboardMuted,
                      ),
                    ),
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
            if (book.bidQuantity + book.askQuantity > 0)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          '买 ${(book.bidShare * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(color: cryptoUp, fontSize: 10),
                        ),
                        const Spacer(),
                        Text(
                          '${((1 - book.bidShare) * 100).toStringAsFixed(1)}% 卖',
                          style: const TextStyle(
                            color: cryptoDown,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: book.bidShare,
                      minHeight: 4,
                      color: cryptoUp,
                      backgroundColor: cryptoDown,
                    ),
                  ],
                ),
              ),
            if (book.bidQuantity + book.askQuantity == 0)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '暂无挂单',
                  style: TextStyle(fontSize: 11, color: dashboardMuted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '显示$levels档 / 前20档数量占比 · 接收 ${cryptoTime(book.receivedAt, seconds: true).substring(11)}',
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
            width: math.max(box.maxWidth, 220 * textScale),
            child: panel,
          ),
        ),
      ),
    );
  }
}
