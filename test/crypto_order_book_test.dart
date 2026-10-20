import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_order_book.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';

import 'crypto_live_widget_test.dart' show Client, Feed;
import 'dashboard_widget_test.dart' as fixture;

Map<String, dynamic> snapshot({int id = 10}) => {
  'lastUpdateId': id,
  'priceDecimals': 2,
  'bids': [
    {'price': 100.00, 'quantity': 2.0},
    {'price': 99.99, 'quantity': 1.0},
    {'price': 99.96, 'quantity': 3.0},
  ],
  'asks': [
    {'price': 100.01, 'quantity': 4.0},
    {'price': 100.02, 'quantity': 2.0},
    {'price': 100.03, 'quantity': 1.0},
  ],
};
Map<String, dynamic> depth({int id = 10, String symbol = 'BTCUSDT'}) => {
  'type': 'depth',
  'symbol': symbol,
  'eventTime': DateTime.now().millisecondsSinceEpoch,
  'book': snapshot(id: id),
};

Widget bookPage(Client client, Feed feed, {double scale = 1}) {
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
    scale: scale,
  );
}

void main() {
  test('full snapshots reject bad sides, crossed or duplicate levels and invalid numeric data', () {
    CryptoBook parse(Map row) =>
        CryptoBook.fromJson(row, symbol: 'BTCUSDT', receivedAt: 1000);
    final book = parse(snapshot());
    expect(book.bids.length, 3);
    expect(book.asks.length, 3);
    expect(book.bidShare, closeTo(6 / 13, 1e-12));
    for (final invalid in [
      {...snapshot(), 'lastUpdateId': -1},
      {...snapshot(), 'priceDecimals': 9},
      {
        ...snapshot(),
        'bids': [
          {'price': 101, 'quantity': 1},
        ],
      },
      {
        ...snapshot(),
        'bids': [
          {'price': 100, 'quantity': 1},
          {'price': 100, 'quantity': 2},
        ],
      },
      {
        ...snapshot(),
        'asks': [
          {'price': 100.02, 'quantity': 1},
          {'price': 100.01, 'quantity': 1},
        ],
      },
      {
        ...snapshot(),
        'asks': [
          {'price': 100.02, 'quantity': double.nan},
        ],
      },
      {
        ...snapshot(),
        'asks': [
          {'price': 100.02, 'quantity': 0},
        ],
      },
    ]) {
      expect(() => parse(invalid), throwsFormatException);
    }
    final empty = parse({...snapshot(), 'bids': [], 'asks': []});
    expect(empty.bidShare, 0);
    expect(empty.bids, isEmpty);
  });

  test('grouping rounds bids down, asks up, retaining exact displayed-source totals', () {
    final book = CryptoBook.fromJson(
      snapshot(),
      symbol: 'BTCUSDT',
      receivedAt: 1000,
    );
    final bids = book.grouped(bid: true, multiplier: 10);
    final asks = book.grouped(bid: false, multiplier: 10);
    expect(bids.map((r) => r.price), [100.0, 99.9]);
    expect(asks.map((r) => r.price), [100.1]);
    expect(bids.fold<double>(0, (s, r) => s + r.quantity), 6);
    expect(asks.single.quantity, 7);
    expect(bids.fold<double>(0, (s, r) => s + r.amount), closeTo(599.87, 1e-9));
    expect(asks.single.amount, closeTo(700.11, 1e-9));
  });

  for (final viewport in [
    (const Size(1280, 900), 1.0, true),
    (const Size(844, 390), 1.0, true),
    (const Size(568, 320), 1.0, true),
    (const Size(390, 844), 1.0, false),
    (const Size(320, 900), 2.0, false),
  ]) {
    testWidgets(
      'book is responsive at $viewport with correct rows, modes and grouping',
      (tester) async {
        fixture.setSize(tester, viewport.$1);
        final client = Client(), feed = Feed();
        // The fixture helper keeps the same page state when its viewport rotates.
        await tester.pumpWidget(bookPage(client, feed, scale: viewport.$2));
        await tester.pumpAndSettle();
        feed.send({'type': 'status', 'status': 'live'});
        feed.send(depth());
        await tester.pumpAndSettle();
        final plot = find.byKey(const Key('crypto-price-plot'));
        final book = find.byKey(const Key('crypto-order-book'));
        if (viewport.$3) {
          final surface = find.byKey(const Key('crypto-chart-surface'));
          expect(
            tester.getTopLeft(book).dy,
            closeTo(tester.getTopLeft(surface).dy, .01),
            reason: 'order book and plot frame start below the shared toolbar',
          );
          expect(
            tester.getTopLeft(book).dx,
            greaterThanOrEqualTo(tester.getTopRight(plot).dx),
          );
        } else {
          expect(
            tester.getTopLeft(book).dy,
            greaterThan(
              tester.getBottomLeft(find.byKey(const Key('crypto-pane-rsi'))).dy,
            ),
          );
          expect(
            tester.getTopLeft(book).dy,
            lessThan(
              tester.getTopLeft(find.byKey(const Key('crypto-assessment'))).dy,
            ),
          );
        }
        expect(tester.getSize(plot).height, cryptoPriceHeight);
        final widget = tester.widget<CryptoOrderBook>(
          find.byType(CryptoOrderBook),
        );
        expect(widget.book!.bids.length, 3);
        expect(widget.book!.symbol, 'BTCUSDT');
        final asks = find.byKey(const Key('crypto-book-asks'));
        final prices = tester
            .widgetList<Text>(
              find.descendant(of: asks, matching: find.byType(Text)),
            )
            .where((t) => t.style?.color == cryptoDown)
            .map((t) => t.data);
        expect(prices, ['100.03', '100.02', '100.01']);
        final calls = client.candleRequests;
        final bidsButton = find.byKey(const Key('crypto-book-view-bids'));
        await tester.ensureVisible(bidsButton);
        await tester.tap(bidsButton);
        await tester.pumpAndSettle();
        expect(asks, findsNothing);
        expect(find.byKey(const Key('crypto-book-bids')), findsOneWidget);
        final bothButton = find.byKey(const Key('crypto-book-view-both'));
        await tester.ensureVisible(bothButton);
        await tester.tap(bothButton);
        await tester.pumpAndSettle();
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const Key('crypto-book-grouping')),
            )
            .onChanged!(10);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: asks, matching: find.text('100.10')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: asks, matching: find.text('700.11')),
          findsOneWidget,
        );
        expect(client.candleRequests, calls);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'depth bars use each side quantity scale, stay right aligned and update with grouping',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send(depth());
      await tester.pumpAndSettle();
      Rect bar(String side, double price) => tester.getRect(
        find.byKey(ValueKey('crypto-book-depth-$side-$price')),
      );
      final bidMax = bar('bid', 99.96), askMax = bar('ask', 100.01);
      expect(bar('bid', 100.0).width, closeTo(bidMax.width * 2 / 3, .01));
      expect(bar('ask', 100.02).width, closeTo(askMax.width / 2, .01));
      expect(bar('bid', 100.0).right, bidMax.right);
      expect(bar('ask', 100.02).right, askMax.right);
      expect(bidMax.width, askMax.width);
      final event = depth(id: 11);
      event['book'] = {
        ...snapshot(id: 11),
        'bids': [
          {'price': 100.0, 'quantity': .00000001},
          {'price': 99.99, 'quantity': 100.0},
        ],
      };
      feed.send(event);
      await tester.pumpAndSettle();
      expect(bar('bid', 100.0).width, 2);
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('crypto-book-grouping')),
          )
          .onChanged!(10);
      await tester.pumpAndSettle();
      expect(bar('ask', 100.1).width, askMax.width);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('landscape uses five closest levels and can reveal all twenty', (
    tester,
  ) async {
    fixture.setSize(tester, const Size(844, 390));
    final client = Client(), feed = Feed();
    await tester.pumpWidget(bookPage(client, feed));
    await tester.pumpAndSettle();
    final event = depth();
    event['book'] = {
      ...snapshot(),
      'bids': [
        for (var i = 0; i < 20; i++)
          {'price': 100.0 - i * .01, 'quantity': 1.0},
      ],
      'asks': [
        for (var i = 0; i < 20; i++)
          {'price': 100.01 + i * .01, 'quantity': 1.0},
      ],
    };
    feed.send(event);
    await tester.pumpAndSettle();
    final asks = find.byKey(const Key('crypto-book-asks'));
    Iterable<Text> prices() => tester
        .widgetList<Text>(
          find.descendant(of: asks, matching: find.byType(Text)),
        )
        .where((t) => t.style?.color == cryptoDown);
    expect(prices(), hasLength(5));
    expect(prices().last.data, '100.01');
    tester
        .widget<PopupMenuButton<int>>(
          find.byKey(const Key('crypto-book-levels')),
        )
        .onSelected!(20);
    await tester.pumpAndSettle();
    expect(prices(), hasLength(20));
    expect(
      tester.widget<CryptoOrderBook>(find.byType(CryptoOrderBook)).book!.asks,
      hasLength(20),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'snapshot replacement, stale-frame rejection, symbol isolation and pause labels',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send({'type': 'status', 'status': 'live'});
      feed.send(depth(id: 20));
      await tester.pumpAndSettle();
      CryptoOrderBook book() =>
          tester.widget<CryptoOrderBook>(find.byType(CryptoOrderBook));
      feed.send(depth(id: 19));
      feed.send(depth(id: 30, symbol: 'ETHUSDT'));
      await tester.pumpAndSettle();
      expect(book().book!.updateId, 20);
      final changed = depth(id: 21);
      changed['book'] = {
        ...snapshot(id: 21),
        'bids': [
          {'price': 100.0, 'quantity': 5.0},
        ],
      };
      feed.send(changed);
      await tester.pumpAndSettle();
      expect(book().book!.bids, hasLength(1));
      feed.send({'type': 'status', 'status': 'reconnecting'});
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('crypto-book-status'))).data,
        contains('旧快照'),
      );
      feed.send({'type': 'status', 'status': 'paused'});
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('crypto-book-status'))).data,
        '已暂停',
      );
      final eth = find.byKey(const Key('crypto-select-ETHUSDT'));
      await tester.ensureVisible(eth);
      await tester.tap(eth);
      await tester.pumpAndSettle();
      expect(book().book, isNull);
      expect(book().symbol, 'ETHUSDT');
      feed.controllers.first.add(depth(id: 100));
      await tester.pumpAndSettle();
      expect(book().book, isNull);
      feed.send(depth(id: 1, symbol: 'ETHUSDT'));
      await tester.pumpAndSettle();
      expect(book().book!.symbol, 'ETHUSDT');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'order-book synchronization status is independent of live quotes and freezes the displayed copy',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send({'type': 'status', 'status': 'live'});
      feed.send(depth(id: 20));
      await tester.pumpAndSettle();
      String label() => tester
          .widget<Text>(find.byKey(const Key('crypto-book-status')))
          .data!;
      CryptoOrderBook book() =>
          tester.widget<CryptoOrderBook>(find.byType(CryptoOrderBook));
      expect(label(), contains('实时'));
      feed.send({
        'type': 'depthStatus',
        'symbol': 'BTCUSDT',
        'status': 'syncing',
      });
      await tester.pumpAndSettle();
      expect(label(), '同步中 · 旧快照');
      expect(book().book!.updateId, 20);
      expect(
        tester.widget<Text>(find.byKey(const Key('crypto-stream-status'))).data,
        contains('实时推送'),
      );
      feed.send({
        'type': 'depthStatus',
        'symbol': 'ETHUSDT',
        'status': 'retrying',
      });
      await tester.pumpAndSettle();
      expect(label(), '同步中 · 旧快照');
      feed.send({
        'type': 'depthStatus',
        'symbol': 'BTCUSDT',
        'status': 'retrying',
      });
      await tester.pumpAndSettle();
      expect(label(), '同步重试 · 旧快照');
      // A reinitialized copy may start a new sequence; ordinary late frames
      // within the new live sequence are still rejected.
      feed.send(depth(id: 1));
      await tester.pumpAndSettle();
      expect(book().book!.updateId, 1);
      expect(label(), contains('实时'));
      feed.send({'type': 'status', 'status': 'paused'});
      await tester.pumpAndSettle();
      expect(label(), '已暂停');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rotation repositions the order book without resetting the candle viewport',
    (tester) async {
      fixture.setSize(tester, const Size(844, 390));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send(depth());
      await tester.pumpAndSettle();
      final older = find.byKey(const Key('crypto-pan-older'));
      await tester.ensureVisible(older);
      await tester.tap(older);
      await tester.pumpAndSettle();
      final range = tester
          .widget<Text>(find.byKey(const Key('crypto-range-start')))
          .data;
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('crypto-range-start'))).data,
        range,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('crypto-range-start'))).data,
        range,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
