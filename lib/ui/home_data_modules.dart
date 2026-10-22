import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../dashboard/crypto_chart.dart';
import '../dashboard/crypto_market.dart';
import '../dashboard/crypto_view_settings.dart';
import '../dashboard/dashboard_client.dart';

/// A read-only forecast card. City selection remains in dashboard settings.
class HomeWeatherModule extends StatelessWidget {
  const HomeWeatherModule({
    super.key,
    required this.client,
    required this.city,
    required this.active,
    this.now,
  });
  final DashboardClient client;
  final Map<String, dynamic>? city;
  final bool active;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final latitude = city?['latitude'], longitude = city?['longitude'];
    final valid =
        latitude is num &&
        latitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude is num &&
        longitude.isFinite &&
        longitude.abs() <= 180;
    return _HomeDataCard(
      client: client,
      module: 'weather',
      args: valid ? {'latitude': latitude, 'longitude': longitude} : const {},
      active: active,
      enabled: valid,
      title: city?['name']?.toString() ?? '天气',
      emptySetup: '在布局设置中选择城市',
      period: const Duration(minutes: 10),
      staleAfter: const Duration(minutes: 30),
      now: now,
      width: 320,
      builder: (response) {
        final offset = response.data['utcOffsetSeconds'];
        final local = (now ?? DateTime.now)().toUtc().add(
          Duration(
            seconds: offset is num && offset.isFinite ? offset.toInt() : 0,
          ),
        );
        final hour = DateTime.utc(
          local.year,
          local.month,
          local.day,
          local.hour,
        );
        final rows = response.data['hours'];
        final forecasts = <({DateTime time, double temperature, bool feels})>[];
        if (rows is List) {
          for (final row in rows.whereType<Map>()) {
            // Provider timestamps are city-local wall-clock fields, not device time.
            final raw = row['time'];
            if (raw is! String) continue;
            final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})')
                .firstMatch(raw);
            if (match == null) continue;
            final parts = [
              for (var i = 1; i <= 5; i++) int.parse(match.group(i)!),
            ];
            final time = DateTime.utc(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
            );
            if (time.month != parts[1] ||
                time.day != parts[2] ||
                time.hour != parts[3] ||
                time.minute != parts[4]) {
              continue;
            }
            final temp = row['temperature'], feels = row['feels'];
            final useTemp = temp is num && temp.isFinite;
            final value = useTemp ? temp : feels;
            if (value is! num || !value.isFinite || time.isBefore(hour)) {
              continue;
            }
            forecasts.add((
              time: time,
              temperature: value.toDouble(),
              feels: !useTemp,
            ));
          }
        }
        forecasts.sort((a, b) => a.time.compareTo(b.time));
        if (forecasts.isEmpty) return const Text('暂无可用的后续小时预报');
        final current = forecasts.first;
        final label = current.time == hour
            ? '当前小时预报'
            : '${current.time.month}/${current.time.day} ${current.time.hour}:00 预报';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${current.temperature.round()}°C',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w500),
            ),
            Text('$label · ${current.feels ? '体感温度' : '气温'}'),
            const SizedBox(height: 6),
            const Text(
              '所选城市当地时间 · Open-Meteo',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        );
      },
    );
  }
}

/// A compact, real OHLC snapshot of the selected market (not a live feed).
class HomeCryptoModule extends StatelessWidget {
  const HomeCryptoModule({
    super.key,
    required this.client,
    required this.symbol,
    required this.interval,
    required this.active,
    this.now,
  });
  final DashboardClient client;
  final String symbol, interval;
  final bool active;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => _HomeDataCard(
    client: client,
    module: 'cryptoCandles',
    args: {'symbol': symbol, 'interval': interval},
    active: active,
    enabled: isCryptoSymbol(symbol) && cryptoIntervals.containsKey(interval),
    title: '$symbol · ${cryptoIntervals[interval] ?? interval}',
    emptySetup: '请选择有效币种和 K 线周期',
    period: const Duration(seconds: 30),
    staleAfter: const Duration(minutes: 2),
    now: now,
    width: 520,
    validate: (response) => _candles(response),
    builder: (response) {
      final candles = _candles(response);
      if (candles.isEmpty) return const Text('暂未返回该周期的 K 线');
      return IgnorePointer(
        child: ExcludeFocus(
          child: CryptoChart(
            key: ValueKey('$symbol:$interval'),
            candles: candles,
            compact: true,
            asset: cryptoBaseAsset(symbol),
            quoteAsset: cryptoQuoteAsset(symbol),
            fetchedAt: response.fetchedAt,
            interval: interval,
            overlays: const [],
            panes: const [],
            viewSettings: const CryptoViewSettings(
              timeline: false,
              indicatorValues: false,
              assessment: false,
            ),
          ),
        ),
      );
    },
  );

  List<CryptoCandle> _candles(DashboardData response) {
    if (response.data['symbol'] != symbol ||
        response.data['interval'] != interval) {
      throw const FormatException('Mismatched candle series');
    }
    final values = response.data['candles'];
    if (values is! List || values.length > 500) {
      throw const FormatException('Invalid candles');
    }
    final rows = values
        .map((value) => CryptoCandle.fromJson(value as Map))
        .toList();
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].time != rows[i - 1].closeTime + 1) {
        throw const FormatException('Unordered candles');
      }
    }
    return rows;
  }
}

class _HomeDataCard extends StatefulWidget {
  const _HomeDataCard({
    required this.client,
    required this.module,
    required this.args,
    required this.active,
    required this.enabled,
    required this.title,
    required this.emptySetup,
    required this.period,
    required this.staleAfter,
    required this.width,
    required this.builder,
    this.validate,
    this.now,
  });
  final DashboardClient client;
  final String module, title, emptySetup;
  final Map<String, dynamic> args;
  final bool active, enabled;
  final Duration period, staleAfter;
  final double width;
  final Widget Function(DashboardData) builder;
  final void Function(DashboardData)? validate;
  final DateTime Function()? now;
  @override
  State<_HomeDataCard> createState() => _HomeDataCardState();
}

class _HomeDataCardState extends State<_HomeDataCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _version = 0;
  bool _busy = false;
  bool _foreground = true;
  DashboardData? _data;
  String? _error;
  bool get _running => widget.active && widget.enabled && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    if (_running) _load();
  }

  void _stop() {
    _version++;
    _timer?.cancel();
    _timer = null;
    _busy = false;
    // Cancellation is symbol-wide in DashboardClient, so do not cancel here:
    // a dashboard or preview may legitimately share this client and symbol.
    // Version guards discard obsolete in-flight results without affecting peers.
  }

  @override
  void didUpdateWidget(_HomeDataCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.client != widget.client ||
        oldWidget.module != widget.module ||
        jsonEncode(oldWidget.args) != jsonEncode(widget.args);
    if (changed ||
        oldWidget.active != widget.active ||
        oldWidget.enabled != widget.enabled) {
      _stop();
      if (changed) {
        _data = null;
        _error = null;
      }
      if (_running) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _stop();
    if (_running) _load();
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!_running || _busy) return;
    final version = ++_version;
    _busy = true;
    try {
      final data = await widget.client.load(
        widget.module,
        widget.args,
        refresh: _data != null,
      );
      if (!mounted || version != _version || !_running) return;
      widget.validate?.call(data);
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (_) {
      if (!mounted || version != _version || !_running) return;
      setState(() => _error = '暂时无法更新，请稍后重试');
    } finally {
      if (mounted && version == _version) {
        _busy = false;
        if (_running) _timer = Timer(widget.period, _load);
      }
    }
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final now = (widget.now ?? DateTime.now)();
    final stale =
        data != null &&
        (data.stale ||
            _error != null ||
            now.difference(data.fetchedAt) > widget.staleAfter);
    final fetched = data?.fetchedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final status = data == null
        ? (_error ?? (_running ? '正在加载…' : '已暂停更新'))
        : '${stale ? '旧数据 · ' : ''}${!_running ? '已暂停 · ' : ''}${widget.module == 'cryptoCandles' ? '币安快照 · ' : ''}'
              '${fetched!.month}/${fetched.day} ${two(fetched.hour)}:${two(fetched.minute)} 更新';
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: SizedBox(
          width: widget.width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xCC242426),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    if (!widget.enabled)
                      Text(widget.emptySetup)
                    else if (data != null)
                      widget.builder(data),
                    if (widget.enabled) ...[
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          color: stale || _error != null
                              ? const Color(0xFFFFCF70)
                              : Colors.white60,
                        ),
                      ),
                      if (_error != null && data != null)
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFFCF70),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
