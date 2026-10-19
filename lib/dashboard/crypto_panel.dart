import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_chart.dart';
import 'crypto_market.dart';
import 'dashboard_client.dart';
import 'dashboard_widgets.dart';

class CryptoPanel extends StatefulWidget {
  const CryptoPanel({
    super.key,
    required this.client,
    required this.symbol,
    required this.interval,
    required this.onChanged,
  });
  final DashboardClient client;
  final String symbol, interval;
  final void Function(String symbol, String interval) onChanged;

  @override
  State<CryptoPanel> createState() => _CryptoPanelState();
}

class _CryptoPanelState extends State<CryptoPanel> with WidgetsBindingObserver {
  DashboardData? _quoteData, _candleData;
  List<CryptoQuote> _quotes = [];
  List<CryptoCandle> _candles = [];
  String? _quoteError, _candleError;
  bool _quotesBusy = false, _candlesBusy = false, _automatic = true;
  bool _visible = true;
  int _quoteSerial = 0, _candleSerial = 0, _failures = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _refresh();
  }

  @override
  void didUpdateWidget(CryptoPanel old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol ||
        old.interval != widget.interval ||
        old.client != widget.client) {
      _candleSerial++;
      _candlesBusy = false;
      _candles = [];
      _candleData = null;
      _candleError = null;
      _loadCandles();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_visible == visible) return;
    _visible = visible;
    _timer?.cancel();
    if (visible && _automatic) _refresh(refresh: true);
  }

  void _schedule() {
    _timer?.cancel();
    if (!mounted || !_visible || !_automatic) return;
    final seconds = math.min(300, 30 * (1 << _failures.clamp(0, 4)));
    _timer = Timer(Duration(seconds: seconds), () => _refresh(refresh: true));
  }

  Future<void> _refresh({bool refresh = false}) async {
    _timer?.cancel();
    if (!_visible) return;
    await Future.wait([
      _loadQuotes(refresh: refresh),
      _loadCandles(refresh: refresh),
    ]);
    if (!mounted) return;
    _failures =
        _quoteError != null ||
            _candleError != null ||
            _quoteData?.stale == true ||
            _candleData?.stale == true
        ? _failures + 1
        : 0;
    _schedule();
  }

  String _message(Object error) => error is FormatException
      ? '行情格式异常，请稍后重试。'
      : error.toString().replaceFirst(RegExp(r'^Exception: '), '');

  Future<void> _loadQuotes({bool refresh = false}) async {
    if (_quotesBusy || !_visible) return;
    final serial = ++_quoteSerial;
    setState(() => _quotesBusy = true);
    try {
      final data = await widget.client.load(
        'cryptoQuotes',
        {},
        refresh: refresh,
      );
      final rows = (data.data['quotes'] as List)
          .map((r) => CryptoQuote.fromJson(r as Map))
          .toList();
      if (rows.isEmpty) throw const FormatException('Empty quotes');
      if (!mounted || serial != _quoteSerial) return;
      setState(() {
        _quotes = rows;
        _quoteData = data;
        _quoteError = null;
      });
    } catch (error) {
      if (mounted && serial == _quoteSerial) {
        setState(() => _quoteError = _message(error));
      }
    } finally {
      if (mounted && serial == _quoteSerial) {
        setState(() => _quotesBusy = false);
      }
    }
  }

  Future<void> _loadCandles({bool refresh = false}) async {
    if (_candlesBusy || !_visible) return;
    final serial = ++_candleSerial;
    final symbol = widget.symbol, interval = widget.interval;
    setState(() => _candlesBusy = true);
    try {
      final data = await widget.client.load('cryptoCandles', {
        'symbol': symbol,
        'interval': interval,
      }, refresh: refresh);
      if (data.data['symbol'] != symbol || data.data['interval'] != interval) {
        throw const FormatException('Mismatched candle series');
      }
      final rows = (data.data['candles'] as List)
          .map((r) => CryptoCandle.fromJson(r as Map))
          .toList();
      if (rows.length > 120) throw const FormatException('Too many candles');
      for (var i = 1; i < rows.length; i++) {
        if (rows[i].time <= rows[i - 1].time) {
          throw const FormatException('Unordered candles');
        }
      }
      if (!mounted || serial != _candleSerial) return;
      setState(() {
        _candles = rows;
        _candleData = data;
        _candleError = null;
      });
    } catch (error) {
      if (mounted && serial == _candleSerial) {
        setState(() => _candleError = _message(error));
      }
    } finally {
      if (mounted && serial == _candleSerial) {
        setState(() => _candlesBusy = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _quoteSerial++;
    _candleSerial++;
    super.dispose();
  }

  Widget _status(DashboardData? data, String? error, bool busy) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy && data == null) const Text('正在获取币安行情…'),
        if (error != null || data?.stale == true || data?.warning != null)
          Text(
            [
              ?error,
              if (data?.stale == true || (error != null && data != null))
                '当前显示上次获取的数据，可能已过时。',
              if (data?.warning != null) data!.warning!,
            ].join(' '),
            style: const TextStyle(color: Color(0xFFFFCA80), height: 1.6),
          ),
        if (data != null)
          Text(
            '${data.cached ? '缓存获取' : '获取'}时间：${cryptoTime(data.fetchedAt.millisecondsSinceEpoch, seconds: true)} UTC+8',
            style: const TextStyle(color: dashboardMuted, fontSize: 11),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = _quotes
        .where((q) => q.symbol == widget.symbol)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '数字货币市场',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text('币安现货 · USDT 计价', style: TextStyle(color: dashboardAccent)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: Text(_automatic ? '每 30 秒更新' : '自动更新已暂停'),
              selected: _automatic,
              onSelected: (value) {
                setState(() => _automatic = value);
                _timer?.cancel();
                if (value) _refresh(refresh: true);
              },
            ),
            TextButton.icon(
              onPressed: _quotesBusy || _candlesBusy
                  ? null
                  : () => _refresh(refresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(_quotesBusy || _candlesBusy ? '更新中' : '刷新行情'),
            ),
          ],
        ),
        _status(_quoteData, _quoteError, _quotesBusy),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 620
                ? 3
                : box.maxWidth >= 340
                ? 2
                : 1;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final asset in cryptoAssets.entries)
                  SizedBox(
                    width: (box.maxWidth - (columns - 1) * 10) / columns,
                    child: _quoteCard(
                      asset.key,
                      _quotes.where((q) => q.symbol == asset.key).firstOrNull,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          '${cryptoAssets[widget.symbol]!.$1} / USDT',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _metric('24h 最高', cryptoPrice(selected.high)),
              _metric('24h 最低', cryptoPrice(selected.low)),
              _metric(
                '24h 成交量 (${cryptoAssets[widget.symbol]!.$1})',
                cryptoVolume(selected.volume),
              ),
              _metric('24h 成交额 (USDT)', cryptoVolume(selected.quoteVolume)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '报价截至 ${cryptoTime(selected.closeTime, seconds: true)} UTC+8',
            style: const TextStyle(color: dashboardMuted, fontSize: 11),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final period in cryptoIntervals.entries)
              ChoiceChip(
                label: Text(period.value),
                selected: widget.interval == period.key,
                onSelected: (_) => widget.onChanged(widget.symbol, period.key),
              ),
          ],
        ),
        _status(_candleData, _candleError, _candlesBusy),
        if (_candleData != null)
          CryptoChart(
            key: ValueKey('${widget.symbol}-${widget.interval}'),
            candles: _candles,
            asset: cryptoAssets[widget.symbol]!.$1,
            fetchedAt: _candleData!.fetchedAt,
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              onPressed: () =>
                  widget.client.openUrl(cryptoSourceUrl(widget.symbol)),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('币安官方来源'),
            ),
            TextButton(
              onPressed: () => widget.client.openUrl(
                'https://developers.binance.com/docs/binance-spot-api-docs/faqs/market_data_only',
              ),
              child: const Text('数据接口说明'),
            ),
          ],
        ),
        const Text(
          '24h 涨跌为滚动 24 小时变化，绿色上涨、红色下跌。这里只展示币安所选现货交易对，不代表全市场市值；USDT 不等同美元。后台暂停更新，断网时可能显示旧数据。',
          style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.7),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: dashboardMuted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 15)),
    ],
  );

  Widget _quoteCard(String symbol, CryptoQuote? quote) {
    final asset = cryptoAssets[symbol]!;
    final active = symbol == widget.symbol;
    final change = quote?.changePercent;
    return Semantics(
      selected: active,
      child: Material(
        color: active ? const Color(0xFF16332D) : const Color(0xFF101617),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: active ? dashboardAccent : const Color(0xFF2A3434),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('crypto-select-$symbol'),
          onTap: () => widget.onChanged(symbol, widget.interval),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${asset.$1} · ${asset.$2}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  quote == null ? '暂无报价' : cryptoPrice(quote.price),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  change == null
                      ? 'USDT'
                      : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}% · 24h',
                  style: TextStyle(
                    color: change == null
                        ? dashboardMuted
                        : change >= 0
                        ? cryptoUp
                        : cryptoDown,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
