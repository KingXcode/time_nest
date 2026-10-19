import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_chart.dart';
import 'crypto_feed.dart';
import 'crypto_indicators.dart';
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
    this.feed,
    this.overlays = defaultCryptoOverlays,
    this.panes = defaultCryptoPanes,
    this.infoRight = false,
    this.onChartChanged,
  });
  final DashboardClient client;
  final String symbol, interval;
  final CryptoFeed? feed;
  final List<String> overlays, panes;
  final bool infoRight;
  final void Function(
    List<String> overlays,
    List<String> panes,
    bool infoRight,
  )?
  onChartChanged;
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
  late CryptoFeed _feed = widget.feed ?? createCryptoFeed();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  int _feedSerial = 0;
  String _streamStatus = 'connecting';
  int _lastCandleEvent = 0;
  bool _historySynchronized = false;
  final Map<int, CryptoCandle> _pendingCandles = {};
  final Map<String, CryptoQuote> _pushedQuotes = {};
  late List<String> _overlays = List.of(widget.overlays),
      _panes = List.of(widget.panes);
  late bool _infoRight = widget.infoRight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _startFeed();
    _refresh();
  }

  @override
  void didUpdateWidget(CryptoPanel old) {
    super.didUpdateWidget(old);
    if (old.overlays != widget.overlays) _overlays = List.of(widget.overlays);
    if (old.panes != widget.panes) _panes = List.of(widget.panes);
    if (old.infoRight != widget.infoRight) _infoRight = widget.infoRight;
    if (old.symbol != widget.symbol ||
        old.interval != widget.interval ||
        old.client != widget.client ||
        old.feed != widget.feed) {
      _candleSerial++;
      _candlesBusy = false;
      _candles = [];
      _candleData = null;
      _candleError = null;
      _historySynchronized = false;
      _lastCandleEvent = 0;
      _pendingCandles.clear();
      _feed = widget.feed ?? _feed;
      _startFeed();
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
    if (visible && _automatic) {
      _startFeed();
      _refresh(refresh: true);
    } else {
      _stopFeed();
      setState(() => _streamStatus = 'paused');
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!mounted || !_visible || !_automatic) return;
    final seconds = math.min(300, 30 * (1 << _failures.clamp(0, 4)));
    _timer = Timer(Duration(seconds: seconds), () {
      if (_streamStatus == 'live' && _historySynchronized) {
        _schedule();
      } else {
        _refresh(refresh: true);
      }
    });
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
        _quotes = [
          for (final quote in rows)
            if ((_pushedQuotes[quote.symbol]?.closeTime ?? 0) > quote.closeTime)
              _pushedQuotes[quote.symbol]!
            else
              quote,
        ];
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
      if (rows.length > 500) throw const FormatException('Too many candles');
      for (var i = 1; i < rows.length; i++) {
        if (rows[i].time != rows[i - 1].closeTime + 1) {
          throw const FormatException('Unordered candles');
        }
      }
      if (!mounted || serial != _candleSerial) return;
      setState(() {
        _candles = rows;
        _historySynchronized = !data.stale;
        for (final row
            in _pendingCandles.values.toList()
              ..sort((a, b) => a.time.compareTo(b.time))) {
          _mergeCandle(row);
        }
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

  void _stopFeed() {
    _feedSerial++;
    _subscription?.cancel();
    _subscription = null;
  }

  void _startFeed() {
    _stopFeed();
    if (!_automatic || !_visible) return;
    _streamStatus = 'connecting';
    final serial = _feedSerial;
    _subscription = _feed
        .subscribe(widget.symbol, widget.interval)
        .listen(
          (event) {
            if (!mounted || serial != _feedSerial) return;
            try {
              final type = event['type'];
              if (type == 'status') {
                setState(() => _streamStatus = event['status'] as String);
                if (event['resync'] == true) {
                  _historySynchronized = false;
                  _refresh(refresh: true);
                }
                return;
              }
              final at = event['eventTime'] as int;
              if (type == 'quote') {
                final quote = CryptoQuote.fromJson(event['quote'] as Map);
                if ((_pushedQuotes[quote.symbol]?.closeTime ?? 0) >=
                    quote.closeTime) {
                  return;
                }
                _pushedQuotes[quote.symbol] = quote;
                setState(() {
                  _quotes = [
                    for (final id in cryptoAssets.keys)
                      if (id == quote.symbol)
                        quote
                      else
                        ?_quotes.where((q) => q.symbol == id).firstOrNull,
                  ];
                  _quoteData = DashboardData(
                    data: const {},
                    fetchedAt: DateTime.fromMillisecondsSinceEpoch(at),
                  );
                  _quoteError = null;
                });
              } else if (type == 'candle' &&
                  event['symbol'] == widget.symbol &&
                  event['interval'] == widget.interval) {
                if (at <= _lastCandleEvent) return;
                final candle = CryptoCandle.fromJson(event['candle'] as Map);
                _lastCandleEvent = at;
                _pendingCandles[candle.time] = candle;
                while (_pendingCandles.length > 500) {
                  _pendingCandles.remove(_pendingCandles.keys.first);
                }
                final rollover =
                    _candles.isNotEmpty && candle.time > _candles.last.time;
                setState(() {
                  _mergeCandle(candle);
                  if (_candleData != null) {
                    _candleData = DashboardData(
                      data: const {},
                      fetchedAt: DateTime.fromMillisecondsSinceEpoch(at),
                    );
                  }
                });
                // Snapshot after a new bar also finalizes the preceding bar if its last frame was missed.
                if (rollover || !_historySynchronized) {
                  _historySynchronized = false;
                  _loadCandles(refresh: true);
                }
              }
            } catch (_) {
              setState(() => _streamStatus = 'error');
            }
          },
          onError: (_) {
            if (mounted && serial == _feedSerial) {
              setState(() => _streamStatus = 'error');
            }
          },
        );
  }

  void _mergeCandle(CryptoCandle candle) {
    if (_candles.isEmpty) return; // A push cannot substitute for history.
    final index = _candles.indexWhere((c) => c.time == candle.time);
    if (index >= 0) {
      // Cumulative base volume prevents an older buffered frame replacing a newer snapshot.
      if (candle.volume < _candles[index].volume) return;
      _candles = List.of(_candles)..[index] = candle;
    } else if (candle.time == _candles.last.closeTime + 1) {
      _candles = [..._candles, candle];
      if (_candles.length > 500) {
        _candles = _candles.sublist(_candles.length - 500);
      }
    } else if (candle.time > _candles.last.time) {
      _historySynchronized = false;
    }
  }

  void _chartChanged(List<String> overlays, List<String> panes, bool right) {
    setState(() {
      _overlays = overlays;
      _panes = panes;
      _infoRight = right;
    });
    widget.onChartChanged?.call(overlays, panes, right);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopFeed();
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
              label: Text(_automatic ? '实时推送已开启' : '实时推送已暂停'),
              selected: _automatic,
              onSelected: (value) {
                setState(() => _automatic = value);
                _timer?.cancel();
                if (value) {
                  _startFeed();
                  _refresh(refresh: true);
                } else {
                  _stopFeed();
                  setState(() => _streamStatus = 'paused');
                }
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
        Text(
          switch (_streamStatus) {
            'live' => '● 币安实时推送 · 报价约 1 秒 / K 线约 2 秒',
            'connected' => '已连接，等待行情推送…',
            'connecting' => '正在连接币安推送…',
            'paused' => '推送已暂停，当前为暂停前的快照',
            _ => '推送暂不可用，正在重连；已启用快照补齐，当前数据可能已过时',
          },
          key: const Key('crypto-stream-status'),
          style: TextStyle(
            color: _streamStatus == 'live' ? dashboardAccent : dashboardMuted,
            fontSize: 12,
          ),
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
        if (_streamStatus == 'live' && !_historySynchronized)
          const Text(
            '正在补齐历史 K 线，技术建议暂时暂停。',
            style: TextStyle(color: Color(0xFFFFCF70), fontSize: 12),
          ),
        if (_candleData != null)
          CryptoChart(
            key: ValueKey('${widget.symbol}-${widget.interval}'),
            candles: _candles,
            asset: cryptoAssets[widget.symbol]!.$1,
            fetchedAt: _candleData!.fetchedAt,
            overlays: _overlays,
            panes: _panes,
            infoRight: _infoRight,
            onSettingsChanged: _chartChanged,
            canAdvise:
                _automatic &&
                _visible &&
                _streamStatus == 'live' &&
                _historySynchronized &&
                _candleError == null,
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
          '24h 涨跌为滚动 24 小时变化，绿色上涨、红色下跌。这里只展示币安所选现货交易对，不代表全市场市值；USDT 不等同美元。后台暂停推送，断网时可能显示旧数据。',
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
