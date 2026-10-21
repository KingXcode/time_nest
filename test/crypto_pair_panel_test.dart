import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/crypto_order_book.dart';
import 'package:time_nest/dashboard/crypto_trades.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';

import 'crypto_fixture.dart';
import 'crypto_live_widget_test.dart' show Feed;
import 'dashboard_widget_test.dart' as fixture;

class PairClient extends fixture.FixtureDashboardClient
    implements CryptoRequestCancellation {
  final cancelled = <String>[];
  final quotesPending = <String, Completer<DashboardData>>{};
  final candlesPending = <String, Completer<DashboardData>>{};
  @override
  void cancelCryptoRequests(String symbol) => cancelled.add(symbol);
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) {
    final symbol = args['symbol'] as String?;
    if (module == 'cryptoQuotes' && quotesPending.containsKey(symbol)) {
      return quotesPending[symbol]!.future;
    }
    if (module == 'cryptoCandles' && candlesPending.containsKey(symbol)) {
      return candlesPending[symbol]!.future;
    }
    return super.load(module, args, refresh: refresh);
  }
}

Widget pairPanel(PairClient client, Feed feed, {String initial = 'BTCUSDT'}) {
  var symbol = initial, interval = '1h';
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

Future<void> choose(WidgetTester tester, String symbol) async {
  await openCryptoPairPicker(tester);
  await tester.enterText(find.byKey(const Key('crypto-pair-search')), symbol);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('crypto-select-$symbol')));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'pair parser validates identity, bounded catalog and preference migration',
    () {
      expect(
        () => CryptoPair.fromJson({
          'symbol': 'ETHBTC',
          'baseAsset': 'ETH',
          'quoteAsset': 'USDT',
        }),
        throwsFormatException,
      );
      expect(
        () => CryptoPair.fromJson({
          'symbol': 'BTCBTC',
          'baseAsset': 'BTC',
          'quoteAsset': 'BTC',
        }),
        throwsFormatException,
      );
      final pairs = readCryptoPairs(cryptoPairsFixture());
      expect(pairs.any((p) => p.symbol == 'ETHBTC'), isTrue);
      expect(
        () => readCryptoPairs({
          'pairs': [
            cryptoPairsFixture()['pairs'][0],
            cryptoPairsFixture()['pairs'][0],
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => readCryptoPairs({'pairs': List.filled(10001, {})}),
        throwsFormatException,
      );
      final old = DashboardPreferences.decode(
        jsonEncode({'cryptoSymbol': 'ETHUSDT', 'cryptoInterval': '4h'}),
      );
      expect(old.cryptoSymbol, 'ETHUSDT');
      old.cryptoSymbol = 'ETHBTC';
      old.cryptoBookSteps = {'ETHBTC': .00000001};
      final restored = DashboardPreferences.decode(old.encode());
      expect(restored.cryptoSymbol, 'ETHBTC');
      expect(restored.cryptoInterval, '4h');
      expect(restored.cryptoBookSteps['ETHBTC'], .00000001);
      final unicode = CryptoPair.fromJson({
        'symbol': '币安人生USDT',
        'baseAsset': '币安人生',
        'quoteAsset': 'USDT',
      });
      registerCryptoPairs([unicode]);
      expect(
        DashboardPreferences.decode(
          jsonEncode({'cryptoSymbol': unicode.symbol}),
        ).cryptoSymbol,
        unicode.symbol,
      );
      expect(
        Uri.decodeComponent(Uri.parse(cryptoSourceUrl(unicode.symbol)).path),
        '/en/trade/币安人生_USDT',
      );
      expect(cryptoPrice(.05000001), '0.05000001');
      expect(cryptoPrice(1.00000001), '1.00000001');
      expect(cryptoPrice(.00000001), '0.00000001');
      expect(cryptoVolume(.00000001), '0.00000001');
    },
  );

  testWidgets(
    'quote choice resets entire series and late prior pair cannot restore it',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 1000));
      final client = PairClient(), feed = Feed();
      await tester.pumpWidget(pairPanel(client, feed));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crypto-current-quote')), findsOneWidget);
      expect(find.text('100.25'), findsOneWidget);
      expect(
        client.requests
            .where((r) => r['module'] == 'cryptoQuotes')
            .single['symbol'],
        'BTCUSDT',
      );
      client.quotesPending['BTCUSDC'] = Completer<DashboardData>();
      client.candlesPending['BTCUSDC'] = Completer<DashboardData>();
      await openCryptoPairPicker(tester, quote: true);
      await tester.tap(find.byKey(const Key('crypto-quote-USDC')));
      await tester.pumpAndSettle();
      expect(feed.selections.last, 'BTCUSDC:1h');
      expect(client.cancelled, contains('BTCUSDT'));
      expect(find.text('100.25'), findsNothing);
      expect(find.text('暂无报价'), findsOneWidget);
      expect(find.byType(CryptoChart), findsNothing);
      expect(
        tester.widget<CryptoOrderBook>(find.byType(CryptoOrderBook)).book,
        isNull,
      );
      expect(
        tester.widget<CryptoTrades>(find.byType(CryptoTrades)).trades,
        isEmpty,
      );
      await choose(tester, 'ETHUSDC');
      expect(client.cancelled, contains('BTCUSDC'));
      client.quotesPending['BTCUSDC']!.complete(
        DashboardData(
          data: cryptoQuotesFixture('BTCUSDC'),
          fetchedAt: DateTime.now(),
        ),
      );
      client.candlesPending['BTCUSDC']!.complete(
        DashboardData(
          data: cryptoCandlesFixture('BTCUSDC', '1h'),
          fetchedAt: DateTime.now(),
        ),
      );
      feed.controllers.first.add({
        'type': 'quote',
        'eventTime': 1792368000001,
        'quote': {
          ...(cryptoQuotesFixture('BTCUSDT')['quotes'] as List).first as Map,
          'price': 999.0,
          'high': 999.0,
        },
      });
      await tester.pumpAndSettle();
      final chart = tester.widget<CryptoChart>(find.byType(CryptoChart));
      expect(chart.asset, 'ETH');
      expect(chart.quoteAsset, 'USDC');
      expect(chart.interval, '1h');
      expect(find.text('999.00'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(client.cancelled.last, 'ETHUSDC');
    },
  );

  testWidgets(
    'unresolved saved pair does not guess units or start a market stream',
    (tester) async {
      final client = PairClient(), feed = Feed();
      await tester.pumpWidget(pairPanel(client, feed, initial: 'UNKNOWNBTC'));
      await tester.pumpAndSettle();
      expect(feed.selections, isEmpty);
      expect(client.calls, ['cryptoPairs']);
      expect(find.textContaining('暂时无法确认已保存的交易对'), findsOneWidget);
      expect(find.byType(CryptoOrderBook), findsNothing);
      await choose(tester, 'ETHUSDT');
      expect(feed.selections.last, 'ETHUSDT:1h');
      expect(
        tester.widget<CryptoChart>(find.byType(CryptoChart)).quoteAsset,
        'USDT',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
