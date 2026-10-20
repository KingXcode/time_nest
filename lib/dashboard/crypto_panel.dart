import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import 'crypto_chart.dart';
import 'crypto_chart_controls.dart';
import 'crypto_feed.dart';
import 'crypto_indicators.dart';
import 'crypto_market.dart';
import 'crypto_order_book.dart';
import 'crypto_trades.dart';
import 'crypto_view_settings.dart';
import 'crypto_settings_dialog.dart';
import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
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
    this.currency = 'USD',
    this.onCurrencyChanged,
    this.bookLevels,
    this.bookSteps = const {},
    this.onBookSettingsChanged,
    this.paneHeights = const {},
    this.onPaneHeightsChanged,
    this.onChartChanged,
    this.viewSettings = const CryptoViewSettings(),
    this.onViewSettingsChanged,
  });
  final DashboardClient client;
  final String symbol, interval, currency;
  final ValueChanged<String>? onCurrencyChanged;
  final int? bookLevels;
  final Map<String, double> bookSteps;
  final void Function(int? levels, Map<String, double> steps)?
  onBookSettingsChanged;
  final CryptoFeed? feed;
  final List<String> overlays, panes;
  final bool infoRight;
  final CryptoViewSettings viewSettings;
  final ValueChanged<CryptoViewSettings>? onViewSettingsChanged;
  final Map<String, double> paneHeights;
  final ValueChanged<Map<String, double>>? onPaneHeightsChanged;
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
  CryptoBook? _book;
  String _bookStatus = 'syncing', _tradeStatus = 'syncing';
  List<CryptoTrade> _trades = [];
  late CryptoViewSettings _view = widget.viewSettings;
  int _bookEpoch = 0;
  GlobalKey _chartKey = GlobalKey();
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
  bool _olderBusy = false, _hasMoreHistory = true;
  String? _olderError;
  int _olderSerial = 0;
  final Map<int, CryptoCandle> _pendingCandles = {};
  final Map<String, CryptoQuote> _pushedQuotes = {};
  late List<String> _overlays = List.of(widget.overlays),
      _panes = List.of(widget.panes);
  late bool _infoRight = widget.infoRight;
  late int? _bookLevels = cleanCryptoBookLevels(widget.bookLevels);
  late Map<String, double> _bookSteps = cleanCryptoBookSteps(widget.bookSteps);
  late Map<String, double> _paneHeights = cleanCryptoPaneHeights(
    widget.paneHeights,
  );

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
    if (old.viewSettings != widget.viewSettings) _view = widget.viewSettings;
    if (old.bookLevels != widget.bookLevels) {
      _bookLevels = cleanCryptoBookLevels(widget.bookLevels);
    }
    if (!mapEquals(old.bookSteps, widget.bookSteps)) {
      _bookSteps = cleanCryptoBookSteps(widget.bookSteps);
    }
    if (!mapEquals(old.paneHeights, widget.paneHeights)) {
      _paneHeights = cleanCryptoPaneHeights(widget.paneHeights);
    }
    if (old.overlays != widget.overlays) _overlays = List.of(widget.overlays);
    if (old.panes != widget.panes) _panes = List.of(widget.panes);
    if (old.infoRight != widget.infoRight) _infoRight = widget.infoRight;
    if (old.symbol != widget.symbol ||
        old.interval != widget.interval ||
        old.client != widget.client ||
        old.feed != widget.feed) {
      if (old.symbol != widget.symbol) _book = null;
      _chartKey = GlobalKey();
      _candleSerial++;
      _candlesBusy = false;
      _candles = [];
      _candleData = null;
      _candleError = null;
      _historySynchronized = false;
      _olderSerial++;
      _olderBusy = false;
      _hasMoreHistory = true;
      _olderError = null;
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
      setState(() {
        _streamStatus = 'paused';
        _bookStatus = 'paused';
        _tradeStatus = 'paused';
      });
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
      final rows = _readCandles(data, symbol, interval);
      if (!mounted || serial != _candleSerial) return;
      if (rows.isEmpty && _candles.isNotEmpty) {
        throw const FormatException('Empty refresh');
      }
      setState(() {
        // Retain paged history when the current snapshot overlaps or adjoins it.
        // After a very long outage, never bridge a missing interval with fake bars.
        final prefix = rows.isEmpty
            ? <CryptoCandle>[]
            : _candles.where((c) => c.time < rows.first.time).toList();
        final connected =
            prefix.isNotEmpty && prefix.last.closeTime + 1 == rows.first.time;
        if (_candles.isEmpty ||
            (!connected && rows.first.time != _candles.first.time)) {
          _olderSerial++;
          _olderBusy = false;
          _olderError = null;
          _hasMoreHistory = rows.length == 500 || data.stale;
        }
        _candles = [if (connected) ...prefix, ...rows];
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

  List<CryptoCandle> _readCandles(
    DashboardData data,
    String symbol,
    String interval,
  ) {
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
    return rows;
  }

  Future<void> _loadOlder() async {
    if (_olderBusy || !_hasMoreHistory || !_visible || _candles.isEmpty) return;
    final serial = ++_olderSerial;
    final firstTime = _candles.first.time;
    final symbol = widget.symbol, interval = widget.interval;
    setState(() {
      _olderBusy = true;
      _olderError = null;
    });
    try {
      final data = await widget.client.load('cryptoCandles', {
        'symbol': symbol,
        'interval': interval,
        'endTime': firstTime - 1,
      }, refresh: true);
      final rows = _readCandles(data, symbol, interval);
      if (data.stale) throw const DashboardException('历史数据未能更新，请重试。');
      if (rows.any((c) => c.closeTime >= firstTime) ||
          (rows.isNotEmpty && rows.last.closeTime + 1 != firstTime)) {
        throw const FormatException('History page overlaps or skips candles');
      }
      if (!mounted ||
          serial != _olderSerial ||
          _candles.isEmpty ||
          _candles.first.time != firstTime) {
        return;
      }
      setState(() {
        _candles = [...rows, ..._candles];
        _hasMoreHistory = rows.length == 500;
      });
    } catch (error) {
      if (mounted && serial == _olderSerial) {
        setState(() => _olderError = _message(error));
      }
    } finally {
      if (mounted && serial == _olderSerial) {
        setState(() => _olderBusy = false);
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
    _bookStatus = 'syncing';
    _bookEpoch = 0;
    _tradeStatus = 'syncing';
    _trades = [];
    final serial = _feedSerial;
    _subscription = _feed
        .subscribe(
          widget.symbol,
          widget.interval,
          orderBook: _view.orderBook,
          trades: _view.trades,
        )
        .listen(
          (event) {
            if (!mounted || serial != _feedSerial) return;
            try {
              final type = event['type'];
              if (type == 'status') {
                setState(() {
                  _streamStatus = event['status'] as String;
                  if (_streamStatus != 'live') {
                    _tradeStatus =
                        const [
                          'connecting',
                          'connected',
                        ].contains(_streamStatus)
                        ? 'syncing'
                        : _streamStatus;
                    _bookStatus =
                        const [
                          'connecting',
                          'connected',
                        ].contains(_streamStatus)
                        ? 'syncing'
                        : _streamStatus;
                  }
                });
                if (event['resync'] == true) {
                  _book = null;
                  _trades = [];
                  _historySynchronized = false;
                  _refresh(refresh: true);
                }
                return;
              }
              if (type == 'tradeStatus') {
                if (_view.trades &&
                    event['symbol'] == widget.symbol &&
                    const [
                      'syncing',
                      'retrying',
                      'live',
                    ].contains(event['status'])) {
                  setState(() => _tradeStatus = event['status'] as String);
                }
                return;
              }
              if (type == 'trades') {
                if (!_view.trades || event['symbol'] != widget.symbol) return;
                try {
                  final raw = event['trades'] as List;
                  if (raw.length > 100) return;
                  final rows = raw
                      .map((r) => CryptoTrade.fromJson(r as Map))
                      .toList();
                  if (rows.map((r) => r.id).toSet().length != rows.length) {
                    return;
                  }
                  for (var i = 1; i < rows.length; i++) {
                    if (rows[i].id >= rows[i - 1].id) return;
                  }
                  if (rows.isNotEmpty &&
                      _trades.isNotEmpty &&
                      rows.first.id < _trades.first.id) {
                    return;
                  }
                  setState(() {
                    _trades = rows;
                    _tradeStatus = 'live';
                  });
                } catch (_) {
                  /* Invalid trades cannot interrupt quote/candle state. */
                }
                return;
              }
              // A callback queued before a price-step reset must never restore
              // its obsolete copy or status after the new generation starts.
              if ((type == 'depthStatus' || type == 'depth') &&
                  (event['bookEpoch'] as int? ?? 0) < _bookEpoch) {
                return;
              }
              if (type == 'depthStatus') {
                if (event['symbol'] == widget.symbol &&
                    const [
                      'syncing',
                      'retrying',
                      'live',
                    ].contains(event['status'])) {
                  setState(() => _bookStatus = event['status'] as String);
                }
                return;
              }
              if (type == 'depth') {
                if (event['symbol'] != widget.symbol) return;
                try {
                  final book = CryptoBook.fromJson(
                    event['book'] as Map,
                    symbol: widget.symbol,
                    receivedAt: event['eventTime'] as int,
                  );
                  if (_bookStatus == 'live' &&
                      _book != null &&
                      book.updateId < _book!.updateId) {
                    return;
                  }
                  setState(() {
                    _book = book;
                    _bookStatus = 'live';
                  });
                } catch (_) {
                  /* Invalid depth must not change the price/candle connection state. */
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
              setState(() {
                _streamStatus = 'error';
                _bookStatus = 'error';
                _tradeStatus = 'error';
              });
            }
          },
          onError: (_) {
            if (mounted && serial == _feedSerial) {
              setState(() {
                _streamStatus = 'error';
                _bookStatus = 'error';
                _tradeStatus = 'error';
              });
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
    _olderSerial++;
    super.dispose();
  }

  Widget _status(DashboardData? data, String? error, bool busy) {
    if (data != null &&
        !data.cached &&
        !data.stale &&
        error == null &&
        data.warning == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
          if (data != null && (data.cached || data.stale || error != null))
            Text(
              '${data.cached ? '缓存获取' : '获取'}时间：${cryptoTime(data.fetchedAt.millisecondsSinceEpoch, seconds: true)} UTC+8',
              style: const TextStyle(color: dashboardMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Future<void> _showViewSettings() async {
    final next = await showCryptoViewSettings(context, _view);
    if (!mounted || next == null) return;
    final subscriptionsChanged =
        next.orderBook != _view.orderBook || next.trades != _view.trades;
    setState(() {
      _view = next;
      if (subscriptionsChanged) {
        _book = null;
        _trades = [];
        _startFeed();
      }
    });
    widget.onViewSettingsChanged?.call(next);
    if (subscriptionsChanged && _automatic && _visible) _refresh(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _quotes
        .where((q) => q.symbol == widget.symbol)
        .firstOrNull;
    final Widget? orderBook = !_view.orderBook
        ? null
        : CryptoOrderBook(
            key: ValueKey('crypto-book-${widget.symbol}'),
            symbol: widget.symbol,
            book: _book,
            status: _bookStatus,
            lastPrice: selected?.price,
            client: widget.client,
            currency: widget.currency,
            onCurrencyChanged: widget.onCurrencyChanged,
            active: _automatic && _visible,
            levels: _bookLevels,
            priceStep: _bookSteps[widget.symbol],
            onLevelsChanged: (levels) {
              setState(() => _bookLevels = levels);
              widget.onBookSettingsChanged?.call(
                _bookLevels,
                Map.of(_bookSteps),
              );
            },
            onPriceStepChanged: (step) {
              setState(() {
                _bookSteps[widget.symbol] = step;
                _book = null;
                _bookStatus = _automatic && _visible ? 'syncing' : 'paused';
                _bookEpoch = _feed.resetOrderBook() ?? _bookEpoch;
              });
              widget.onBookSettingsChanged?.call(
                _bookLevels,
                Map.of(_bookSteps),
              );
            },
          );
    final Widget? trades = !_view.trades
        ? null
        : CryptoTrades(
            key: ValueKey('crypto-trades-${widget.symbol}'),
            symbol: widget.symbol,
            trades: _trades,
            status: _tradeStatus,
            client: widget.client,
            rows: _view.tradeRows,
            showAmount: _view.tradeAmount,
            active: _automatic && _visible,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '币安现货 / USDT',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
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
                  setState(() {
                    _streamStatus = 'paused';
                    _bookStatus = 'paused';
                    _tradeStatus = 'paused';
                  });
                }
              },
            ),
            TextButton.icon(
              onPressed: _quotesBusy || _candlesBusy
                  ? null
                  : () => _refresh(refresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: Text(_quotesBusy || _candlesBusy ? '更新中' : '刷新行情'),
            ),
            if (selected != null)
              Text(
                '报价截至 ${cryptoTime(selected.closeTime, seconds: true)} UTC+8',
                style: const TextStyle(color: dashboardMuted, fontSize: 11),
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
                color: _streamStatus == 'live'
                    ? dashboardAccent
                    : dashboardMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        _status(_quoteData, _quoteError, _quotesBusy),
        LayoutBuilder(
          builder: (context, box) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final width = math.max(132.0 * scale, (box.maxWidth - 5 * 6) / 6);
            return SingleChildScrollView(
              key: const Key('crypto-quote-strip'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final asset in cryptoAssets.entries)
                    Padding(
                      padding: EdgeInsets.only(
                        right: asset.key == cryptoAssets.keys.last ? 0 : 6,
                      ),
                      child: SizedBox(
                        width: width,
                        child: _quoteCard(
                          asset.key,
                          _quotes
                              .where((q) => q.symbol == asset.key)
                              .firstOrNull,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        _status(_candleData, _candleError, _candlesBusy),
        if (_streamStatus == 'live' && !_historySynchronized)
          const Text(
            '正在补齐历史 K 线，技术建议暂时暂停。',
            style: TextStyle(color: Color(0xFFFFCF70), fontSize: 12),
          ),
        if (_candleData == null)
          CryptoBookLayout(
            orderBook: orderBook,
            trades: trades,
            chart: (belowChart) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CryptoChartHeader(
                  asset: cryptoAssets[widget.symbol]!.$1,
                  interval: widget.interval,
                  quote: selected,
                  onIntervalChanged: (interval) =>
                      widget.onChanged(widget.symbol, interval),
                  onSettings: _showViewSettings,
                ),
                const SizedBox(
                  height: cryptoPriceHeight,
                  child: Center(
                    child: Text(
                      '等待 K 线数据…',
                      style: TextStyle(color: dashboardMuted),
                    ),
                  ),
                ),
                ?belowChart,
              ],
            ),
          )
        else
          CryptoChart(
            key: _chartKey,
            interval: widget.interval,
            quote: selected,
            onIntervalChanged: (interval) =>
                widget.onChanged(widget.symbol, interval),
            viewSettings: _view,
            onViewSettings: _showViewSettings,
            chartLayout: (plots) => CryptoBookLayout(
              orderBook: orderBook,
              trades: trades,
              chart: (belowChart) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [plots, ?belowChart],
              ),
            ),
            candles: _candles,
            asset: cryptoAssets[widget.symbol]!.$1,
            fetchedAt: _candleData!.fetchedAt,
            overlays: _overlays,
            panes: _panes,
            infoRight: _infoRight,
            paneHeights: _paneHeights,
            onPaneHeightsChanged: (heights) {
              setState(() => _paneHeights = cleanCryptoPaneHeights(heights));
              widget.onPaneHeightsChanged?.call(Map.of(_paneHeights));
            },
            onSettingsChanged: _chartChanged,
            onLoadOlder: _loadOlder,
            loadingOlder: _olderBusy,
            hasMoreHistory: _hasMoreHistory,
            historyError: _olderError,
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
          '24h 涨跌为滚动 24 小时变化，行情与 K 线绿色上涨、红色下跌；最新成交绿色为主动买入、红色为主动卖出。这里只展示币安所选现货交易对，不代表全市场市值；USDT 不等同美元。后台暂停推送，断网时可能显示旧数据。',
          style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.7),
        ),
      ],
    );
  }

  Widget _quoteCard(String symbol, CryptoQuote? quote) {
    final asset = cryptoAssets[symbol]!;
    final active = symbol == widget.symbol;
    final change = quote?.changePercent;
    return Semantics(
      label: '${asset.$1} · ${asset.$2}',
      selected: active,
      child: Material(
        color: active ? const Color(0xFF263D5B) : dashboardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: active ? dashboardAccent : dashboardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('crypto-select-$symbol'),
          onTap: () => widget.onChanged(symbol, widget.interval),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quote == null ? '暂无报价' : cryptoPrice(quote.price),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  change == null
                      ? 'USDT'
                      : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}% · 24h',
                  style: TextStyle(
                    fontSize: 11,
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
