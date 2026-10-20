import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/crypto_order_book.dart';
import 'package:time_nest/dashboard/crypto_trades.dart';
import 'package:time_nest/dashboard/crypto_view_settings.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';

import 'crypto_live_widget_test.dart' show Client, Feed;
import 'crypto_order_book_test.dart' show RulesClient, precisionRules;
import 'dashboard_widget_test.dart' as fixture;

Map<String, dynamic> trade(int id, {bool maker = false}) => {
  'id': id,
  'time': DateTime.utc(2026, 10, 20, 11, 21, 20).millisecondsSinceEpoch,
  'price': 81472.01,
  'quantity': .0005,
  'buyerMaker': maker,
};
Map<String, dynamic> fills(int id, {String symbol = 'BTCUSDT'}) => {
  'type': 'trades',
  'symbol': symbol,
  'trades': [trade(id), trade(id - 1, maker: true)],
};
Widget page(Client client, Feed feed, {double scale = 1}) {
  final prefs = DashboardPreferences.decode(client.preferences);
  return fixture.app(
    Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => CryptoPanel(
            client: client,
            feed: feed,
            symbol: prefs.cryptoSymbol,
            interval: prefs.cryptoInterval,
            viewSettings: prefs.cryptoView,
            paneHeights: const {'vol': 180},
            onViewSettingsChanged: (settings) => update(() {
              prefs.cryptoView = settings;
              client.writePreferences(prefs.encode());
            }),
            onChanged: (s, i) => update(() {
              prefs.cryptoSymbol = s;
              prefs.cryptoInterval = i;
            }),
          ),
        ),
      ),
    ),
    scale: scale,
  );
}

Future<void> press(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  test('view preferences validate fields individually, preserve choices, and migrate old preferences', () {
    final p = DashboardPreferences.decode(
      '{"cryptoCurrency":"CNY","cryptoView":{"orderBook":false,"trades":false,"timeline":false,"tradeRows":100,"assessment":"no"}}',
    );
    final r = DashboardPreferences.decode(p.encode());
    expect(r.cryptoCurrency, 'CNY');
    expect(r.cryptoView.orderBook, false);
    expect(r.cryptoView.trades, false);
    expect(r.cryptoView.timeline, false);
    expect(r.cryptoView.tradeRows, 100);
    expect(r.cryptoView.assessment, true);
    for (final value in [
      null,
      0,
      'bad',
      {'tradeRows': 20.0},
      {'tradeRows': 500},
    ]) {
      expect(CryptoViewSettings.decode(value).tradeRows, 50);
    }
    expect(DashboardPreferences.decode('{}').cryptoView.trades, true);
    expect(
      () => CryptoTrade.fromJson({...trade(1), 'quantity': double.nan}),
      throwsFormatException,
    );
    expect(
      () => CryptoTrade.fromJson({...trade(1), 'buyerMaker': 'true'}),
      throwsFormatException,
    );
    expect(
      () => CryptoTrade.fromJson({...trade(1), 'id': -1}),
      throwsFormatException,
    );
    expect(
      () => CryptoTrade.fromJson({
        ...trade(1),
        'price': 1e308,
        'quantity': 1e308,
      }),
      throwsFormatException,
    );
  });

  testWidgets(
    'public fills use exchange precision and aggressor colors; freeze/resume does not interrupt the feed',
    (tester) async {
      fixture.setSize(tester, const Size(1440, 1000));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      expect(feed.windows.single, (orderBook: true, trades: true));
      feed.send(fills(102));
      await tester.pumpAndSettle();
      final row = find.byKey(const Key('crypto-trade-102'));
      expect(
        find.descendant(of: row, matching: find.text('81,472.01')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('0.00050')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('crypto-trade-amount-102')), findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('40.73600500')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('19:21:20')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: row, matching: find.text('81,472.01')),
            )
            .style!
            .color,
        cryptoUp,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('crypto-trade-101')),
                matching: find.text('81,472.01'),
              ),
            )
            .style!
            .color,
        cryptoDown,
      );
      await press(tester, 'crypto-trades-freeze');
      feed.send(fills(103));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crypto-trade-103')), findsNothing);
      expect(find.text('已定格'), findsOneWidget);
      await press(tester, 'crypto-trades-freeze');
      expect(find.byKey(const Key('crypto-trade-103')), findsOneWidget);
      expect(feed.selections, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'trade amounts use the raw price times quantity, retain tiny amounts and shorten large amounts with exact tooltips',
    (tester) async {
      fixture.setSize(tester, const Size(1440, 1000));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      feed.send({
        'type': 'trades',
        'symbol': 'BTCUSDT',
        'trades': [
          trade(204),
          {...trade(203), 'quantity': 1},
          {...trade(202), 'quantity': 20},
          {...trade(201), 'price': .01, 'quantity': .00001},
          {...trade(200), 'price': 1, 'quantity': 999.99999999},
        ],
      });
      await tester.pumpAndSettle();
      for (final entry in {
        204: '40.73600500',
        203: '81.47K',
        202: '1.63M',
        201: '0.00000010',
        200: '999.99999999',
      }.entries) {
        expect(
          tester
              .widget<Text>(find.byKey(Key('crypto-trade-amount-${entry.key}')))
              .data,
          entry.value,
        );
      }
      expect(find.byTooltip('81472.01000000 USDT'), findsOneWidget);
      expect(find.byTooltip('1629440.20000000 USDT'), findsOneWidget);
      expect(feed.selections, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cached quote precision renders immediately and a refreshed rule reformats the amount column',
    (tester) async {
      final now = DateTime.utc(2026, 10, 20);
      final client = RulesClient()
        ..savedRules = DashboardData(
          data: precisionRules(),
          fetchedAt: now,
          cached: true,
          stale: true,
        );
      final feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      feed.send(fills(100));
      await tester.pumpAndSettle();
      String amount() => tester
          .widget<Text>(find.byKey(const Key('crypto-trade-amount-100')))
          .data!;
      expect(amount(), '40.73600500');
      client.updates.add(
        DashboardData(
          data: precisionRules(quote: 6),
          fetchedAt: now.add(const Duration(hours: 9)),
        ),
      );
      await tester.pumpAndSettle();
      expect(amount(), '40.736005');
      client.updates.add(client.savedRules!);
      await tester.pumpAndSettle();
      expect(
        amount(),
        '40.736005',
        reason: 'late cached rules never revert the new precision',
      );
      expect(feed.selections, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await client.updates.close();
    },
  );

  testWidgets(
    'bad or foreign trade batches never replace good data or mark the quote stream broken',
    (tester) async {
      final client = Client(), feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      feed.send({'type': 'status', 'status': 'live'});
      feed.send(fills(100));
      await tester.pumpAndSettle();
      for (final event in [
        fills(102, symbol: 'ETHUSDT'),
        {
          'type': 'trades',
          'symbol': 'BTCUSDT',
          'trades': [trade(101), trade(101)],
        },
        {
          'type': 'trades',
          'symbol': 'BTCUSDT',
          'trades': [trade(99), trade(100)],
        },
        {
          'type': 'trades',
          'symbol': 'BTCUSDT',
          'trades': [
            {'bad': 1},
          ],
        },
        fills(90),
      ]) {
        feed.send(event);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CryptoTrades>(find.byType(CryptoTrades))
              .trades
              .first
              .id,
          100,
        );
        expect(find.textContaining('● 币安实时推送'), findsOneWidget);
      }
      final old = feed.controllers.last;
      await press(tester, 'crypto-select-ETHUSDT');
      old.add(fills(999));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CryptoTrades>(find.byType(CryptoTrades)).trades,
        isEmpty,
      );
      feed.send(fills(200, symbol: 'ETHUSDT'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CryptoTrades>(find.byType(CryptoTrades)).trades.first.id,
        200,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'settings cancel preserves layout; apply persists windows without replacing chart state or cached heights',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 1000));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      final chart = tester.state(find.byType(CryptoChart));
      await press(tester, 'crypto-view-settings');
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('crypto-setting-orderBook')),
          )
          .onChanged!(false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(CryptoOrderBook), findsOneWidget);
      expect(feed.selections, hasLength(1));
      await press(tester, 'crypto-view-settings');
      for (final key in [
        'orderBook',
        'trades',
        'timeline',
        'indicatorValues',
        'assessment',
      ]) {
        tester
            .widget<SwitchListTile>(find.byKey(Key('crypto-setting-$key')))
            .onChanged!(false);
        await tester.pumpAndSettle();
      }
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('crypto-setting-tradeRows')),
          )
          .onChanged!(20);
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.byType(CryptoOrderBook), findsNothing);
      expect(find.byType(CryptoTrades), findsNothing);
      expect(find.byType(CryptoTimeline), findsNothing);
      expect(find.byKey(const Key('crypto-assessment')), findsNothing);
      expect(find.textContaining('MA MA5'), findsNothing);
      expect(identical(tester.state(find.byType(CryptoChart)), chart), true);
      expect(
        tester.getSize(find.byKey(const Key('crypto-pane-vol'))).height,
        180,
      );
      expect(feed.windows.last, (orderBook: false, trades: false));
      final saved = DashboardPreferences.decode(client.preferences).cryptoView;
      expect(saved.toJson(), {
        'orderBook': false,
        'trades': false,
        'timeline': false,
        'indicatorValues': false,
        'assessment': false,
        'tradeRows': 20,
      });
      await tester.pumpWidget(const SizedBox());
      final restored = Feed();
      await tester.pumpWidget(page(client, restored));
      await tester.pumpAndSettle();
      expect(restored.windows.single, (orderBook: false, trades: false));
      expect(find.byType(CryptoTrades), findsNothing);
      expect(find.byKey(const Key('crypto-view-settings')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'trade count and visual settings do not restart subscriptions; window changes respect manual pause',
    (tester) async {
      final client = Client(), feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      await press(tester, 'crypto-view-settings');
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('crypto-setting-tradeRows')),
          )
          .onChanged!(100);
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(feed.selections, hasLength(1));
      expect(tester.widget<CryptoTrades>(find.byType(CryptoTrades)).rows, 100);
      final pause = find.widgetWithText(FilterChip, '实时推送已开启');
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await tester.pumpAndSettle();
      final calls = client.candleRequests;
      await press(tester, 'crypto-view-settings');
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('crypto-setting-trades')),
          )
          .onChanged!(false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(feed.selections, hasLength(1));
      expect(client.candleRequests, calls);
      expect(find.textContaining('推送已暂停'), findsWidgets);
      expect(find.byType(CryptoTrades), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(1440, 1000),
    const Size(844, 390),
    const Size(390, 844),
    const Size(320, 900),
  ]) {
    testWidgets('trade placement and settings fit $size', (tester) async {
      fixture.setSize(tester, size);
      final feed = Feed(), client = Client();
      await tester.pumpWidget(
        page(client, feed, scale: size.width == 320 ? 2 : 1),
      );
      await tester.pumpAndSettle();
      feed.send(fills(100));
      await tester.pumpAndSettle();
      final tape = find.byKey(const Key('crypto-trades-panel')),
          book = find.byKey(const Key('crypto-order-book'));
      final plot = find.byKey(const Key('crypto-price-plot'));
      final amount = find.byKey(const Key('crypto-trade-amount-100'));
      expect(amount, findsOneWidget);
      final tradeRow = find.byKey(const Key('crypto-trade-100'));
      final quantity = find.descendant(
        of: tradeRow,
        matching: find.text('0.00050'),
      );
      final time = find.descendant(
        of: tradeRow,
        matching: find.text('19:21:20'),
      );
      expect(
        tester.getTopLeft(amount).dx,
        greaterThan(tester.getTopLeft(quantity).dx),
      );
      expect(
        tester.getTopLeft(time).dx,
        greaterThan(tester.getTopLeft(amount).dx),
      );
      if (size.width >= 1180) {
        expect(
          tester.getTopLeft(tape).dx,
          greaterThanOrEqualTo(tester.getTopRight(book).dx),
        );
        expect(
          tester.getTopLeft(tape).dy,
          closeTo(tester.getTopLeft(book).dy, .01),
        );
      } else if (size.width > size.height) {
        expect(
          tester.getTopLeft(tape).dx,
          greaterThanOrEqualTo(tester.getTopRight(plot).dx),
        );
      } else {
        expect(
          tester.getTopLeft(tape).dy,
          greaterThan(tester.getBottomLeft(book).dy),
        );
      }
      expect(tester.getSize(plot).height, cryptoPriceHeight);
      await press(tester, 'crypto-view-settings');
      expect(find.text('图表设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
