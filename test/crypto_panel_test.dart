import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';

import 'crypto_fixture.dart';
import 'dashboard_widget_test.dart' as fixture;

class MarketClient extends fixture.FixtureDashboardClient {
  bool quoteFailure = false, candleFailure = false;
  Completer<DashboardData>? pendingBtc;
  final marketCalls = <String>[];
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module == 'cryptoConversion' || module == 'cryptoBookRules') {
      return super.load(module, args, refresh: refresh);
    }
    marketCalls.add(
      '$module:${args['symbol'] ?? ''}:${args['interval'] ?? ''}',
    );
    if ((module == 'cryptoQuotes' && quoteFailure) ||
        (module == 'cryptoCandles' && candleFailure)) {
      throw const DashboardException('连接超时，请重试。');
    }
    if (module == 'cryptoCandles' &&
        args['symbol'] == 'BTCUSDT' &&
        pendingBtc != null) {
      return pendingBtc!.future;
    }
    return DashboardData(
      fetchedAt: DateTime.utc(2026, 10, 18),
      data: module == 'cryptoQuotes'
          ? cryptoQuotesFixture()
          : cryptoCandlesFixture(
              args['symbol'] as String,
              args['interval'] as String,
            ),
    );
  }
}

Widget panel(MarketClient client) {
  var symbol = 'BTCUSDT', interval = '1h';
  return fixture.app(
    Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => CryptoPanel(
            client: client,
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

void main() {
  test(
    'upgrade preserves active choices, adds crypto, and validates selection',
    () {
      final old = DashboardPreferences.decode(
        jsonEncode({
          'version': 4,
          'order': ['news', 'fx', 'weather', 'market', 'releases'],
          'favorites': ['market'],
          'cryptoSymbol': 'https://evil.test',
          'cryptoInterval': 'bad',
          'marketIndex': 'shenzhen',
          'feed': 'show',
        }),
      );
      expect(old.order, ['news', 'weather', 'releases', 'crypto']);
      expect(old.favorites, isEmpty);
      expect(old.cryptoSymbol, 'BTCUSDT');
      expect(old.cryptoInterval, '1h');
      old.cryptoSymbol = 'ETHUSDT';
      old.cryptoInterval = '4h';
      final read = DashboardPreferences.decode(old.encode());
      expect(read.cryptoSymbol, 'ETHUSDT');
      expect(read.cryptoInterval, '4h');
      expect(jsonDecode(read.encode()).containsKey('marketIndex'), isFalse);
      expect(read.feed, 'show');
    },
  );

  test('market values reject invalid OHLC and retain sub-dollar precision', () {
    final row =
        (cryptoCandlesFixture('BTCUSDT', '1h')['candles'] as List).first as Map;
    expect(
      () => CryptoCandle.fromJson({...row, 'high': 1}),
      throwsFormatException,
    );
    expect(
      () => CryptoCandle.fromJson({...row, 'volume': -1}),
      throwsFormatException,
    );
    expect(
      () => CryptoCandle.fromJson({...row, 'close': double.nan}),
      throwsFormatException,
    );
    expect(cryptoPrice(.123456), '0.123456');
    expect(cryptoPrice(12345.67), '12,345.67');
  });

  testWidgets(
    'resized pane heights persist locally across series, routes and fresh screens',
    (tester) async {
      fixture.setSize(tester, const Size(1000, 1200));
      final client = MarketClient();
      await tester.pumpWidget(fixture.app(DashboardScreen(client: client)));
      await tester.pumpAndSettle();
      await fixture.openModule(tester, 'crypto');
      final pane = find.byKey(const Key('crypto-pane-vol'));
      final handle = find.byKey(const Key('crypto-resize-vol'));
      await tester.ensureVisible(handle);
      final before = client.preferences;
      final drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(0, 22));
      await tester.pump();
      await drag.moveBy(const Offset(0, 60));
      await tester.pump();
      final height = tester.getSize(pane).height;
      expect(height, greaterThan(cryptoPaneHeight));
      expect(
        client.preferences,
        before,
        reason: 'drag updates the chart without writing storage every frame',
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        DashboardPreferences.decode(client.preferences)
            .cryptoPaneHeights['vol'],
        height,
      );
      final eth = find.byKey(const ValueKey('crypto-select-ETHUSDT'));
      await tester.ensureVisible(eth);
      await tester.tap(eth);
      await tester.pumpAndSettle();
      expect(tester.getSize(pane).height, height);
      final daily = find.widgetWithText(ChoiceChip, '日线');
      await tester.ensureVisible(daily);
      await tester.tap(daily);
      await tester.pumpAndSettle();
      expect(tester.getSize(pane).height, height);
      expect(
        tester.getSize(find.byKey(const Key('crypto-pane-macd'))).height,
        cryptoPaneHeight,
      );
      await tester.ensureVisible(find.byType(BackButton));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await fixture.openModule(tester, 'crypto');
      expect(tester.getSize(pane).height, height);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(fixture.app(DashboardScreen(client: client)));
      await tester.pumpAndSettle();
      await fixture.openModule(tester, 'crypto');
      expect(tester.getSize(pane).height, height);
      expect(tester.widget<CryptoChart>(find.byType(CryptoChart)).asset, 'ETH');
      expect(
        DashboardPreferences.decode(client.preferences).cryptoInterval,
        '1d',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final viewport in [
    (const Size(320, 900), 2.0),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets(
      'crypto entry, selection, chart and saved choices fit $viewport',
      (tester) async {
        fixture.setSize(tester, viewport.$1);
        final client = MarketClient();
        await tester.pumpWidget(
          fixture.app(DashboardScreen(client: client), scale: viewport.$2),
        );
        await tester.pumpAndSettle();
        expect(client.marketCalls, isNot(contains('cryptoCandles:BTCUSDT:1h')));
        client.marketCalls.clear();
        await fixture.openModule(tester, 'crypto');
        expect(find.byType(CryptoChart), findsOneWidget);
        expect(find.text('100.25'), findsNWidgets(6));
        final eth = find.byKey(const ValueKey('crypto-select-ETHUSDT'));
        await tester.ensureVisible(eth);
        await tester.tap(eth);
        await tester.pumpAndSettle();
        final day = find.widgetWithText(ChoiceChip, '日线');
        await tester.ensureVisible(day);
        await tester.tap(day);
        await tester.pumpAndSettle();
        expect(client.marketCalls.last, 'cryptoCandles:ETHUSDT:1d');
        expect(
          tester.widget<CryptoChart>(find.byType(CryptoChart)).asset,
          'ETH',
        );
        final plot = find.byKey(const Key('crypto-price-plot'));
        await tester.ensureVisible(plot);
        final calls = client.marketCalls.length;
        await tester.ensureVisible(plot);
        await tester.longPressAt(tester.getTopLeft(plot) + const Offset(5, 40));
        await tester.pumpAndSettle();
        expect(client.marketCalls.length, calls);
        expect(find.textContaining('2026-10-17 08:00\nUTC+8'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 31));
        expect(client.marketCalls.length, calls);
        await fixture.openModule(tester, 'crypto');
        expect(
          DashboardPreferences.decode(client.preferences).cryptoSymbol,
          'ETHUSDT',
        );
        expect(
          DashboardPreferences.decode(client.preferences).cryptoInterval,
          '1d',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('polling pauses in background, resumes, and stops on disposal', (
    tester,
  ) async {
    final client = MarketClient();
    await tester.pumpWidget(panel(client));
    await tester.pumpAndSettle();
    expect(client.marketCalls, hasLength(2));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(client.marketCalls, hasLength(4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 2));
    expect(client.marketCalls, hasLength(4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(client.marketCalls, hasLength(6));
    await tester.tap(find.text('实时推送已开启'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(client.marketCalls, hasLength(6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(client.marketCalls, hasLength(6));
  });

  testWidgets(
    'switching ignores delayed old candles and failures retain labelled data',
    (tester) async {
      final pending = Completer<DashboardData>();
      final client = MarketClient()..pendingBtc = pending;
      await tester.pumpWidget(panel(client));
      await tester.pumpAndSettle();
      final eth = find.byKey(const ValueKey('crypto-select-ETHUSDT'));
      await tester.ensureVisible(eth);
      await tester.tap(eth);
      await tester.pumpAndSettle();
      pending.complete(
        DashboardData(
          fetchedAt: DateTime.utc(2026, 10, 18),
          data: cryptoCandlesFixture('BTCUSDT', '1h'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CryptoChart>(find.byType(CryptoChart)).asset, 'ETH');
      client.candleFailure = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.textContaining('可能已过时'), findsWidgets);
      expect(find.byType(CryptoChart), findsOneWidget);
      expect(find.text('100.25'), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('first request failure provides retry without invented quotes', (
    tester,
  ) async {
    final client = MarketClient()
      ..quoteFailure = true
      ..candleFailure = true;
    await tester.pumpWidget(panel(client));
    await tester.pumpAndSettle();
    expect(find.text('暂无报价'), findsNWidgets(6));
    expect(find.byType(CryptoChart), findsNothing);
    client.quoteFailure = false;
    client.candleFailure = false;
    await tester.tap(find.text('刷新行情'));
    await tester.pumpAndSettle();
    expect(find.text('100.25'), findsNWidgets(6));
    expect(find.byType(CryptoChart), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
