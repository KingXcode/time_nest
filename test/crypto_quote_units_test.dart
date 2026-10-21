import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_chart_controls.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/crypto_order_book.dart';
import 'package:time_nest/dashboard/crypto_trades.dart';
import 'package:time_nest/dashboard/crypto_view_settings.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';

import 'dashboard_widget_test.dart' as fixture;

Map<String, dynamic> quoteRule(String symbol, {String tick = '0.00000001'}) => {
  'symbol': symbol,
  'tickSize': tick,
  'stepSize': '0.00010000',
  'baseAssetPrecision': 8,
  'quoteAssetPrecision': 8,
};

Map<String, dynamic> quoteDepth() => {
  'lastUpdateId': 10,
  'priceDecimals': 8,
  'bids': [
    {'price': .05, 'quantity': 2.0},
    {'price': .04999999, 'quantity': 1.0},
  ],
  'asks': [
    {'price': .05000001, 'quantity': 3.0},
  ],
};

DashboardData quoteRates(String base, {double? usd}) => DashboardData(
  data: {
    'base': base,
    'USD': usd ?? (base == 'BTC' ? 60000.0 : .99),
    'CNY': base == 'BTC' ? 420000.0 : 7.1,
  },
  fetchedAt: DateTime.now(),
);

class QuoteUnitClient extends fixture.FixtureDashboardClient
    implements CryptoRulesUpdates {
  final unitRequests = <({String module, Map<String, dynamic> args})>[];
  final updates = StreamController<DashboardData>.broadcast(sync: true);
  final pendingRates = <String, Completer<DashboardData>>{};
  final pendingRules = <String, Completer<DashboardData>>{};
  String? wrongRateBase;
  DashboardData? rules;

  @override
  Stream<DashboardData> watchCryptoRules() => updates.stream;

  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    unitRequests.add((module: module, args: Map.of(args)));
    if (module == 'cryptoConversion') {
      final base = args['base'] as String;
      return pendingRates[base]?.future ?? quoteRates(wrongRateBase ?? base);
    }
    if (module == 'cryptoBookRules') {
      final symbol = args['symbol'] as String;
      return pendingRules[symbol]?.future ??
          rules ??
          DashboardData(
            data: {
              'rules': [quoteRule(symbol)],
            },
            fetchedAt: DateTime.now(),
          );
    }
    return super.load(module, args, refresh: refresh);
  }
}

Widget unitBook(QuoteUnitClient client, String symbol, {bool active = true}) =>
    fixture.app(
      Scaffold(
        body: SingleChildScrollView(
          child: CryptoOrderBook(
            symbol: symbol,
            client: client,
            status: 'live',
            lastPrice: .05,
            active: active,
            book: CryptoBook.fromJson(
              quoteDepth(),
              symbol: symbol,
              receivedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        ),
      ),
    );

CryptoTrade quoteTrade() => CryptoTrade.fromJson({
  'id': 1,
  'time': DateTime.utc(2026, 10, 20).millisecondsSinceEpoch,
  'price': .05,
  'quantity': 2.0,
  'buyerMaker': false,
});

Widget unitTrades(QuoteUnitClient client, String symbol) => fixture.app(
  Scaffold(
    body: CryptoTrades(
      symbol: symbol,
      trades: [quoteTrade()],
      status: 'live',
      client: client,
    ),
  ),
);

void main() {
  setUp(() {
    registerCryptoPairs(const [
      CryptoPair(symbol: 'ETHBTC', baseAsset: 'ETH', quoteAsset: 'BTC'),
      CryptoPair(symbol: 'ETHUSDC', baseAsset: 'ETH', quoteAsset: 'USDC'),
    ]);
  });
  tearDown(() => registerCryptoPairs(const []));

  test('dynamic books and price rules validate symbols without a six-pair whitelist', () {
    final book = CryptoBook.fromJson(
      quoteDepth(),
      symbol: 'ETHBTC',
      receivedAt: 1000,
    );
    expect(book.bids.first.amount, .1);
    expect(CryptoPriceRule.fromJson(quoteRule('ETHBTC')).symbol, 'ETHBTC');
    for (final symbol in ['ETH?BTC', 'ETH/BTC', '', 'ETH BTC']) {
      expect(
        () =>
            CryptoBook.fromJson(quoteDepth(), symbol: symbol, receivedAt: 1000),
        throwsFormatException,
      );
    }
    expect(
      () => CryptoBook.fromJson(
        {...quoteDepth(), 'symbol': 'ETHUSDC'},
        symbol: 'ETHBTC',
        receivedAt: 1000,
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'BTC-quoted book uses base quantities, quote amounts and a real BTC fiat rate',
    (tester) async {
      final client = QuoteUnitClient();
      await tester.pumpWidget(unitBook(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      expect(find.text('订单簿 ETH / BTC'), findsOneWidget);
      expect(find.text('价格(BTC)'), findsOneWidget);
      expect(find.text('数量(ETH)'), findsOneWidget);
      expect(find.text('金额(BTC)'), findsOneWidget);
      expect(find.byTooltip('0.10000000 BTC'), findsOneWidget);
      expect(find.text(r'≈ $3,000.00 USD'), findsOneWidget);
      expect(
        client.unitRequests
            .where((r) => r.module == 'cryptoConversion')
            .single
            .args,
        {'base': 'BTC'},
      );
      expect(
        client.unitRequests
            .where((r) => r.module == 'cryptoBookRules')
            .single
            .args,
        {'symbol': 'ETHBTC'},
      );
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(
        semantics.any((s) => s.properties.label == '金额(BTC) 0.10000000'),
        isTrue,
      );
      final currency = tester.widget<PopupMenuButton<String>>(
        find.byKey(const Key('crypto-book-currency')),
      );
      currency.onSelected!('CNY');
      await tester.pumpAndSettle();
      expect(find.text('≈ ¥21,000.00 CNY'), findsOneWidget);
      expect(find.text('金额(BTC)'), findsOneWidget);
      expect(client.unitRequests, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'changing quote clears a usable old rate while the new conversion loads',
    (tester) async {
      final client = QuoteUnitClient();
      await tester.pumpWidget(unitBook(client, 'BTCUSDT'));
      await tester.pumpAndSettle();
      expect(find.text(r'≈ $0.05 USD'), findsOneWidget);
      final pending = client.pendingRates['BTC'] = Completer<DashboardData>();
      final oldState = tester.state(find.byType(CryptoOrderBook));
      await tester.pumpWidget(unitBook(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CryptoOrderBook)), same(oldState));
      expect(find.text(r'≈ $0.05 USD'), findsNothing);
      expect(find.text('汇率加载中… USD'), findsOneWidget);
      pending.complete(quoteRates('BTC'));
      await tester.pumpAndSettle();
      expect(find.text(r'≈ $3,000.00 USD'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'late conversion from the previous pair cannot overwrite the active quote rate',
    (tester) async {
      final client = QuoteUnitClient();
      final oldRate = client.pendingRates['USDT'] = Completer<DashboardData>();
      await tester.pumpWidget(unitBook(client, 'BTCUSDT'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(unitBook(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      expect(find.text(r'≈ $3,000.00 USD'), findsOneWidget);
      oldRate.complete(quoteRates('USDT'));
      await tester.pumpAndSettle();
      expect(find.text(r'≈ $3,000.00 USD'), findsOneWidget);
      expect(find.text(r'≈ $0.05 USD'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'a mismatched conversion base is unavailable rather than treated as dollar parity',
    (tester) async {
      final client = QuoteUnitClient()..wrongRateBase = 'USDT';
      await tester.pumpWidget(unitBook(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      expect(find.text('汇率暂不可用 USD'), findsOneWidget);
      expect(find.textContaining('≈'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'cached active rules survive unrelated updates and refresh only matching symbols',
    (tester) async {
      final client = QuoteUnitClient()
        ..rules = DashboardData(
          data: {
            'rules': [
              {'symbol': 'BTCUSDT'}, // An irrelevant malformed row is ignored.
              quoteRule('ETHBTC'),
            ],
          },
          fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
          cached: true,
          stale: true,
        );
      await tester.pumpWidget(unitBook(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      DropdownButton<double> grouping() =>
          tester.widget(find.byKey(const Key('crypto-book-grouping')));
      expect(grouping().items!.first.value, .00000001);
      client.updates.add(
        DashboardData(
          data: {
            'rules': [quoteRule('BTCUSDT', tick: '.01')],
          },
          fetchedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(grouping().items!.first.value, .00000001);
      client.updates.add(
        DashboardData(
          data: {
            'rules': [quoteRule('ETHBTC', tick: '0.000001')],
          },
          fetchedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(grouping().items!.first.value, .000001);
      expect(find.byTooltip('0.050000 BTC'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'trade price, quantities, amounts, tooltips and semantics use the selected pair',
    (tester) async {
      final client = QuoteUnitClient();
      await tester.pumpWidget(unitTrades(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      expect(find.text('最新成交 ETH / BTC'), findsOneWidget);
      expect(find.text('价格(BTC)'), findsOneWidget);
      expect(find.text('数量(ETH)'), findsOneWidget);
      expect(find.text('金额(BTC)'), findsOneWidget);
      expect(find.byTooltip('0.10000000 BTC'), findsOneWidget);
      final label = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>()
          .firstWhere((s) => s.startsWith('成交 1，'));
      expect(label, contains('价格 0.05000000 BTC'));
      expect(label, contains('数量 2.0000 ETH'));
      expect(label, contains('金额 0.10000000 BTC'));
      expect(client.unitRequests.single.args, {'symbol': 'ETHBTC'});
      await tester.pumpWidget(unitTrades(client, 'ETHUSDC'));
      await tester.pumpAndSettle();
      expect(find.text('金额(USDC)'), findsOneWidget);
      expect(find.byTooltip('0.10000000 USDC'), findsOneWidget);
      client.updates.add(
        DashboardData(
          data: {
            'rules': [quoteRule('ETHBTC', tick: '0.01')],
          },
          fetchedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.05000000'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'late rules from a previous trade pair do not change active precision',
    (tester) async {
      final client = QuoteUnitClient();
      final oldRule = client.pendingRules['ETHBTC'] =
          Completer<DashboardData>();
      await tester.pumpWidget(unitTrades(client, 'ETHBTC'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(unitTrades(client, 'ETHUSDC'));
      await tester.pumpAndSettle();
      oldRule.complete(
        DashboardData(
          data: {
            'rules': [quoteRule('ETHBTC', tick: '0.01')],
          },
          fetchedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.05000000'), findsOneWidget);
      expect(find.text('金额(USDC)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'chart header, amount panes, settings and crosshair show BTC quote units',
    (tester) async {
      fixture.setSize(tester, const Size(1200, 1100));
      final time = DateTime.utc(2026, 10, 20).millisecondsSinceEpoch;
      final candle = CryptoCandle.fromJson({
        'time': time,
        'closeTime': time + 3599999,
        'open': .049,
        'close': .05,
        'high': .051,
        'low': .048,
        'volume': 2.0,
        'quoteVolume': .1,
      });
      final quote = CryptoQuote.fromJson({
        'symbol': 'ETHBTC',
        'price': .05,
        'high': .051,
        'low': .048,
        'volume': 2.0,
        'quoteVolume': .1,
        'changePercent': 1.0,
        'closeTime': time,
      });
      await tester.pumpWidget(
        fixture.app(
          Scaffold(
            body: SingleChildScrollView(
              child: CryptoChart(
                candles: [candle],
                asset: 'ETH',
                quoteAsset: 'BTC',
                quote: quote,
                fetchedAt: DateTime.now(),
                overlays: const [],
                panes: const ['amount', 'vol'],
                viewSettings: const CryptoViewSettings(assessment: false),
                onSettingsChanged: (_, _, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CryptoChartHeader>(find.byType(CryptoChartHeader))
            .quoteAsset,
        'BTC',
      );
      expect(find.text('ETH / BTC'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CryptoChartHeader),
          matching: find.textContaining('成交额 (BTC)', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.text('AMOUNT 成交额 (BTC)'), findsOneWidget);
      expect(find.text('VOL 成交量 (ETH)'), findsOneWidget);
      final plot = find.byKey(const Key('crypto-price-plot'));
      await tester.longPressAt(tester.getCenter(plot));
      await tester.pumpAndSettle();
      expect(find.text('${cryptoVolume(.1)} BTC'), findsOneWidget);
      expect(find.text('${cryptoVolume(2)} ETH'), findsOneWidget);
      await tester.tap(
        find.byKey(const PageStorageKey('crypto-indicator-settings')),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('当前计价币成交额（BTC）'), findsOneWidget);
      expect(find.textContaining('USDT'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
