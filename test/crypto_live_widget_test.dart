import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_feed.dart';
import 'package:time_nest/dashboard/crypto_indicators.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';

import 'crypto_fixture.dart';
import 'dashboard_widget_test.dart' as fixture;

List<Map<String, dynamic>> history() =>
    (jsonDecode(
              File('test/fixtures/crypto_talib.json').readAsStringSync(),
            )['rows']
            as List)
        .cast<Map<String, dynamic>>();

class Feed implements CryptoFeed {
  final controllers = <StreamController<Map<String, dynamic>>>[];
  final selections = <String>[];
  int cancelled = 0;
  @override
  Stream<Map<String, dynamic>> subscribe(String symbol, String interval) {
    selections.add('$symbol:$interval');
    final c = StreamController<Map<String, dynamic>>(
      sync: true,
      onCancel: () => cancelled++,
    );
    controllers.add(c);
    return c.stream;
  }

  void send(Map<String, dynamic> event) => controllers.last.add(event);
}

class Client extends fixture.FixtureDashboardClient {
  List<Map<String, dynamic>> rows = history();
  Completer<DashboardData>? historyPending;
  Completer<DashboardData>? quotePending;
  int candleRequests = 0, quoteRequests = 0;
  DashboardData snapshot(String symbol, String interval) => DashboardData(
    data: {'symbol': symbol, 'interval': interval, 'candles': rows},
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      (rows.last['time'] as int) + 1000,
    ),
  );
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module == 'cryptoQuotes') {
      quoteRequests++;
      return quotePending?.future ??
          DashboardData(
            data: cryptoQuotesFixture(),
            fetchedAt: DateTime.utc(2026, 10, 18),
          );
    }
    candleRequests++;
    return historyPending?.future ??
        snapshot(args['symbol'] as String, args['interval'] as String);
  }
}

Widget live(Client client, Feed feed) {
  var symbol = 'BTCUSDT', interval = '1h';
  return fixture.app(
    Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => CryptoPanel(
            client: client,
            feed: feed,
            symbol: symbol,
            interval: interval,
            onChanged: (s, i) => update(() {
              symbol = s;
              interval = i;
            }),
          ),
        ),
      ),
    ),
  );
}

Map<String, dynamic> candleEvent(
  Map<String, dynamic> row,
  int at, {
  String symbol = 'BTCUSDT',
  String interval = '1h',
}) => {
  'type': 'candle',
  'candle': row,
  'eventTime': at,
  'symbol': symbol,
  'interval': interval,
};
void main() {
  test('stored study choices deduplicate, separate categories and enforce 8+8 limits', () {
    final p = DashboardPreferences.decode(
      jsonEncode({
        'cryptoOverlays': [
          'invalid',
          ...cryptoIndicators.keys,
          ...cryptoIndicators.keys,
        ],
        'cryptoPanes': cryptoIndicators.keys.toList(),
        'cryptoInfoRight': true,
      }),
    );
    expect(p.cryptoOverlays, hasLength(8));
    expect(p.cryptoPanes, hasLength(8));
    expect(
      p.cryptoOverlays.every((id) => cryptoIndicators[id]!.overlay),
      isTrue,
    );
    expect(p.cryptoPanes.every((id) => !cryptoIndicators[id]!.overlay), isTrue);
    final restored = DashboardPreferences.decode(p.encode());
    expect(restored.cryptoPanes, p.cryptoPanes);
    expect(restored.cryptoInfoRight, isTrue);
  });
  for (final viewport in [
    (const Size(320, 900), 2.0),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets(
      '8 overlays and 8 panes keep price height and save preferences at $viewport',
      (tester) async {
        fixture.setSize(tester, viewport.$1);
        final client = Client();
        await tester.pumpWidget(
          fixture.app(DashboardScreen(client: client), scale: viewport.$2),
        );
        await tester.pumpAndSettle();
        await fixture.openModule(tester, 'crypto');
        final height = tester
            .getSize(find.byKey(const Key('crypto-price-plot')))
            .height;
        expect(height, cryptoPriceHeight);
        final settings = find.byKey(
          const PageStorageKey('crypto-indicator-settings'),
        );
        await tester.ensureVisible(settings);
        await tester.tap(find.text('指标设置'));
        await tester.pumpAndSettle();
        for (final overlay in [true, false]) {
          for (final entry in cryptoIndicators.entries.where(
            (e) => e.value.overlay == overlay,
          )) {
            final chip = tester.widget<FilterChip>(
              find.byKey(ValueKey('indicator-${entry.key}')),
            );
            if (!chip.selected && chip.onSelected != null) {
              chip.onSelected!(true);
              await tester.pumpAndSettle();
            }
          }
        }
        final chart = tester.widget<CryptoChart>(find.byType(CryptoChart));
        expect(chart.overlays, hasLength(8));
        expect(chart.panes, hasLength(8));
        final ninthOverlay = tester.widget<FilterChip>(
          find.byKey(const ValueKey('indicator-tema')),
        );
        expect(ninthOverlay.selected, isFalse);
        expect(ninthOverlay.onSelected, isNull);
        for (final id in chart.panes) {
          expect(
            tester.getSize(find.byKey(ValueKey('crypto-pane-$id'))).height,
            cryptoPaneHeight,
          );
        }
        expect(
          tester.getSize(find.byKey(const Key('crypto-price-plot'))).height,
          height,
        );
        // Selected chips remain removable at the limit.
        expect(
          tester
              .widget<FilterChip>(find.byKey(const ValueKey('indicator-ma')))
              .onSelected,
          isNotNull,
        );
        final toggle = find.byKey(const Key('crypto-info-position'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          tester.widget<CryptoChart>(find.byType(CryptoChart)).infoRight,
          isTrue,
        );
        expect(find.textContaining('成交额 '), findsWidgets);
        final saved = DashboardPreferences.decode(client.preferences);
        expect(saved.cryptoInfoRight, isTrue);
        expect(saved.cryptoOverlays, hasLength(8));
        expect(saved.cryptoPanes, hasLength(8));
        final slider = find.byKey(const Key('crypto-candle-slider'));
        tester.widget<Slider>(slider).onChanged!(0);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            cryptoTime(CryptoCandle.fromJson(client.rows[130]).time),
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'push survives delayed snapshot; duplicate frames and old subscriptions cannot overwrite',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = Client(), feed = Feed();
      client.historyPending = Completer<DashboardData>();
      client.quotePending = Completer<DashboardData>();
      await tester.pumpWidget(live(client, feed));
      await tester.pumpAndSettle();
      final row = {
        ...client.rows.last,
        'high': 200.0,
        'close': 150.0,
        'volume': 2000.0,
        'quoteVolume': 300000.0,
      };
      final at = (row['time'] as int) + 2000;
      feed.send(candleEvent(row, at));
      final quoteTime = DateTime.utc(2026, 10, 19).millisecondsSinceEpoch;
      feed.send({
        'type': 'quote',
        'eventTime': quoteTime,
        'quote': {
          ...(cryptoQuotesFixture()['quotes'] as List).first as Map,
          'price': 150.0,
          'high': 200.0,
          'closeTime': quoteTime,
        },
      });
      client.quotePending!.complete(
        DashboardData(
          data: cryptoQuotesFixture(),
          fetchedAt: DateTime.utc(2026, 10, 18),
        ),
      );
      client.quotePending = null;
      client.historyPending!.complete(client.snapshot('BTCUSDT', '1h'));
      client.historyPending = null;
      feed.send({'type': 'status', 'status': 'live'});
      await tester.pumpAndSettle();
      CryptoChart chart() =>
          tester.widget<CryptoChart>(find.byType(CryptoChart));
      expect(chart().candles.last.close, 150);
      expect(find.text('150.00'), findsOneWidget);
      expect(chart().canAdvise, isTrue);
      feed.send(candleEvent({...row, 'close': 149.0}, at - 1));
      await tester.pumpAndSettle();
      expect(chart().candles.last.close, 150);
      final calls = client.candleRequests;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(client.candleRequests, calls);
      final eth = find.byKey(const ValueKey('crypto-select-ETHUSDT'));
      await tester.ensureVisible(eth);
      await tester.tap(eth);
      await tester.pumpAndSettle();
      expect(feed.cancelled, 1);
      expect(feed.selections.last, 'ETHUSDT:1h');
      expect(chart().asset, 'ETH');
      expect(chart().candles.last.close, isNot(150));
      feed.controllers.first.add(candleEvent(row, at + 1000));
      await tester.pumpAndSettle();
      expect(chart().asset, 'ETH');
      expect(chart().candles.last.close, isNot(150));
      await tester.pumpWidget(const SizedBox());
      expect(feed.cancelled, 2);
    },
  );
  testWidgets(
    'missing interval causes resync, reconnect suppresses advice, background closes subscription',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(live(client, feed));
      await tester.pumpAndSettle();
      feed.send({'type': 'status', 'status': 'live'});
      final last = client.rows.last, t = (last['time'] as int) + 7200000;
      final gap = {...last, 'time': t, 'closeTime': t + 3599999};
      client.historyPending = Completer<DashboardData>();
      final previousRequests = client.candleRequests;
      feed.send(candleEvent(gap, t + 1000));
      await tester.pumpAndSettle();
      CryptoChart chart() =>
          tester.widget<CryptoChart>(find.byType(CryptoChart));
      expect(client.candleRequests, previousRequests + 1);
      expect(chart().candles.last.time, last['time']);
      expect(chart().canAdvise, isFalse);
      client.rows = [
        ...client.rows,
        {...last, 'time': t - 3600000, 'closeTime': t - 1},
        gap,
      ];
      client.historyPending!.complete(client.snapshot('BTCUSDT', '1h'));
      client.historyPending = null;
      await tester.pumpAndSettle();
      expect(chart().candles.last.time, t);
      expect(chart().canAdvise, isTrue);
      feed.send({'type': 'status', 'status': 'reconnecting'});
      await tester.pumpAndSettle();
      expect(chart().canAdvise, isFalse);
      expect(find.textContaining('暂不提供买入参考'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      expect(feed.cancelled, 1);
      final count = client.candleRequests;
      await tester.pump(const Duration(minutes: 2));
      expect(client.candleRequests, count);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(feed.selections, hasLength(2));
      expect(client.candleRequests, count + 1);
      await tester.pumpWidget(const SizedBox());
      expect(feed.cancelled, 2);
    },
  );
}
