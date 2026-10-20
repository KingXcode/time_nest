import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_order_book.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';

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
  final prefs = DashboardPreferences.decode(client.readPreferences());
  var symbol = prefs.cryptoSymbol, interval = prefs.cryptoInterval;
  return fixture.app(
    Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => CryptoPanel(
            client: client,
            feed: feed,
            symbol: symbol,
            interval: interval,
            bookLevels: prefs.cryptoBookLevels,
            bookSteps: prefs.cryptoBookSteps,
            onBookSettingsChanged: (levels, steps) => update(() {
              prefs.cryptoBookLevels = levels;
              prefs.cryptoBookSteps = Map.of(steps);
              client.writePreferences(prefs.encode());
            }),
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

class RateClient extends Client {
  bool rateFails = false;
  int rateCalls = 0;
  DateTime? rateTime;
  Completer<DashboardData>? pendingRate;
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module != 'cryptoConversion') {
      return super.load(module, args, refresh: refresh);
    }
    rateCalls++;
    if (rateFails) throw const DashboardException('offline');
    return pendingRate?.future ??
        DashboardData(
          data: {'base': 'USDT', 'USD': .99, 'CNY': 7.1},
          fetchedAt: rateTime ?? DateTime.now(),
        );
  }
}

class RulesClient extends Client implements CryptoRulesUpdates {
  final updates = StreamController<DashboardData>.broadcast(sync: true);
  DashboardData? savedRules;
  @override
  Stream<DashboardData> watchCryptoRules() => updates.stream;
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module == 'cryptoBookRules' && savedRules != null) return savedRules!;
    return super.load(module, args, refresh: refresh);
  }
}

Map<String, dynamic> precisionRules({
  String tick = '0.01000000',
  String step = '0.00001000',
  int quote = 8,
}) => {
  'rules': [
    {
      'symbol': 'BTCUSDT',
      'tickSize': tick,
      'stepSize': step,
      'baseAssetPrecision': 8,
      'quoteAssetPrecision': quote,
    },
  ],
};

Map<String, dynamic> deepSnapshot({double spacing = .5}) {
  final bids = [
    for (var i = 0; i < 5000; i++)
      {
        'price': double.parse((100000 - i * spacing).toStringAsFixed(2)),
        'quantity': 1.0,
      },
  ];
  final asks = [
    for (var i = 0; i < 5000; i++)
      {
        'price': double.parse((100000.01 + i * spacing).toStringAsFixed(2)),
        'quantity': 2.0,
      },
  ];
  return {
    'lastUpdateId': 10,
    'priceDecimals': 2,
    'bids': bids,
    'asks': asks,
    'bidFloor': bids.last['price'],
    'askCeiling': asks.last['price'],
  };
}

void main() {
  test('exchange precision separates price ticks, quantity steps and quote asset precision', () {
    for (final entry in [
      ('BTCUSDT', '0.00001000', 5),
      ('ETHUSDT', '0.00010000', 4),
      ('BNBUSDT', '0.00100000', 3),
      ('XRPUSDT', '0.10000000', 1),
      ('DOGEUSDT', '1.00000000', 0),
    ]) {
      final rule = CryptoPriceRule.fromJson({
        'symbol': entry.$1,
        'tickSize': '0.01000000',
        'stepSize': entry.$2,
        'baseAssetPrecision': 8,
        'quoteAssetPrecision': 8,
      });
      expect(rule.decimals, 2);
      expect(rule.quantityDecimals, entry.$3);
      expect(rule.amountDecimals, 8);
    }
    for (final invalid in [
      {
        'stepSize': '0.00001000',
        'baseAssetPrecision': 4,
        'quoteAssetPrecision': 8,
      },
      {'stepSize': '0', 'baseAssetPrecision': 8, 'quoteAssetPrecision': 8},
      {
        'stepSize': '0.00001000',
        'baseAssetPrecision': 8,
        'quoteAssetPrecision': 21,
      },
    ]) {
      expect(
        () => CryptoPriceRule.fromJson({
          'symbol': 'BTCUSDT',
          'tickSize': '0.01',
          ...invalid,
        }),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'cached rules render first, fresh rules update the table without restarting feeds, and numeric decimals align',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = RulesClient()
        ..savedRules = DashboardData(
          data: precisionRules(),
          fetchedAt: DateTime.now().subtract(const Duration(days: 60)),
          stale: true,
          cached: true,
        );
      final feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send({
        ...depth(),
        'book': {
          ...snapshot(),
          'bids': [
            {'price': 100.0, 'quantity': .00007},
            {'price': 99.99, 'quantity': 20.12345},
            {'price': 9.99, 'quantity': .1},
          ],
          'asks': [
            {'price': 100.01, 'quantity': .00014},
            {'price': 100.02, 'quantity': 10.0},
            {'price': 1000.03, 'quantity': 10000.0},
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('0.00007'), findsOneWidget);
      expect(find.text('20.12345'), findsOneWidget);
      expect(find.text('0.00700000'), findsOneWidget);
      expect(find.text('1.00K'), findsOneWidget);
      List<Finder> cells(String id) => find
          .descendant(
            of: find.byKey(ValueKey('crypto-book-row-$id')),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => find.byWidget(e.widget))
          .toList();
      final rowA = cells('bid-100.0'),
          rowB = cells('bid-99.99'),
          rowC = cells('ask-1000.03');
      double dot(Finder f) {
        final text = tester.widget<Text>(f).data!;
        final index = text.indexOf('.');
        expect(index, greaterThanOrEqualTo(0));
        final paragraph = tester.renderObject<RenderParagraph>(f);
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: index, extentOffset: index + 1),
            )
            .single;
        return tester.getTopLeft(f).dx + box.left;
      }

      for (var column = 0; column < 3; column++) {
        expect(dot(rowA[column]), closeTo(dot(rowB[column]), .25));
        expect(dot(rowA[column]), closeTo(dot(rowC[column]), .25));
      }
      final subscriptions = feed.controllers.length;
      final now = DateTime.now();
      client.updates.add(
        DashboardData(
          data: precisionRules(
            tick: '0.10000000',
            step: '0.00100000',
            quote: 6,
          ),
          fetchedAt: now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('20.123'), findsOneWidget);
      expect(find.text('0.007000'), findsOneWidget);
      expect(find.text('100.0'), findsOneWidget);
      expect(feed.controllers.length, subscriptions);
      client.updates.add(client.savedRules!);
      await tester.pumpAndSettle();
      expect(find.text('20.123'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(client.updates.hasListener, isFalse);
      await client.updates.close();
      expect(tester.takeException(), isNull);
    },
  );

  test('full trusted depth is merged before limiting, retains totals and caches immutable groups', () {
    final value = deepSnapshot();
    final book = CryptoBook.fromJson(
      value,
      symbol: 'BTCUSDT',
      receivedAt: 1000,
    );
    expect(book.bids, hasLength(5000));
    expect(book.asks, hasLength(5000));
    for (final step in [10.0, 100.0]) {
      final bids = book.grouped(bid: true, step: step),
          asks = book.grouped(bid: false, step: step);
      expect(bids.length, greaterThanOrEqualTo(20));
      expect(asks.length, greaterThanOrEqualTo(20));
      expect(bids.take(20), hasLength(20));
      expect(asks.take(20), hasLength(20));
      expect(identical(bids, book.grouped(bid: true, step: step)), isTrue);
      expect(() => bids.clear(), throwsUnsupportedError);
      for (final group in [...bids.take(20), ...asks.take(20)]) {
        final bid = bids.contains(group);
        final source = (bid ? book.bids : book.asks).where(
          (r) => bid
              ? r.price >= group.price && r.price < group.price + step
              : r.price > group.price - step && r.price <= group.price,
        );
        expect(
          group.quantity,
          source.fold<double>(0, (sum, r) => sum + r.quantity),
        );
        expect(
          group.amount,
          closeTo(source.fold<double>(0, (sum, r) => sum + r.amount), .0001),
        );
      }
    }
    expect(() => book.bids.clear(), throwsUnsupportedError);
    expect(
      () => CryptoBook.fromJson(
        {...value, 'bidFloor': 100001},
        symbol: 'BTCUSDT',
        receivedAt: 1000,
      ),
      throwsFormatException,
    );
    expect(
      () => CryptoBook.fromJson(
        {...value, 'askCeiling': double.nan},
        symbol: 'BTCUSDT',
        receivedAt: 1000,
      ),
      throwsFormatException,
    );
  });

  test('partial boundary buckets and unknown outer levels cannot masquerade as full depth', () {
    final value = deepSnapshot(spacing: .1);
    final book = CryptoBook.fromJson(
      value,
      symbol: 'BTCUSDT',
      receivedAt: 1000,
    );
    final bids = book.grouped(bid: true, step: 100),
        asks = book.grouped(bid: false, step: 100);
    expect(bids.map((r) => r.price), [100000, 99900, 99800, 99700, 99600]);
    expect(asks.map((r) => r.price), [100100, 100200, 100300, 100400]);
    expect(bids.every((r) => r.price >= book.bidFloor!), isTrue);
    expect(asks.every((r) => r.price <= book.askCeiling!), isTrue);
    final whole = CryptoBook.fromJson(
      {...value, 'bidFloor': null, 'askCeiling': null},
      symbol: 'BTCUSDT',
      receivedAt: 1000,
    );
    expect(whole.grouped(bid: true, step: 100).last.price, 99500);
    expect(whole.grouped(bid: false, step: 100).last.price, 100500);
  });

  testWidgets(
    'every price step clears the whole book and rejects queued old generations without restarting charts',
    (tester) async {
      final client = Client(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send(depth(id: 100));
      await tester.pumpAndSettle();
      final candleRequests = client.candleRequests;
      final quoteRequests = client.quoteRequests;
      final chartState = tester.state(find.byType(CryptoChart));
      for (final step in [.1, 1.0, 10.0, 100.0, .01]) {
        final oldEpoch = feed.bookEpoch;
        tester
            .widget<DropdownButton<double>>(
              find.byKey(const Key('crypto-book-grouping')),
            )
            .onChanged!(step);
        await tester.pumpAndSettle();
        CryptoOrderBook book() => tester.widget(find.byType(CryptoOrderBook));
        expect(book().book, isNull);
        expect(book().status, 'syncing');
        expect(find.byKey(const Key('crypto-book-bids')), findsNothing);
        expect(find.byKey(const Key('crypto-book-asks')), findsNothing);
        expect(find.text('等待币安订单簿快照…'), findsOneWidget);
        feed.send({...depth(id: 999), 'bookEpoch': oldEpoch});
        feed.send({
          'type': 'depthStatus',
          'symbol': 'BTCUSDT',
          'status': 'live',
          'bookEpoch': oldEpoch,
        });
        await tester.pumpAndSettle();
        expect(book().book, isNull);
        expect(book().status, 'syncing');
        feed.send(depth(id: 10)); // A fresh snapshot starts a new ID fence.
        await tester.pumpAndSettle();
        expect(book().book!.updateId, 10);
        expect(book().status, 'live');
        expect(book().priceStep, step);
        expect(
          DashboardPreferences.decode(client.preferences)
              .cryptoBookSteps['BTCUSDT'],
          step,
        );
        expect(
          identical(tester.state(find.byType(CryptoChart)), chartState),
          isTrue,
        );
      }
      expect(feed.bookResets, 5);
      expect(feed.selections, hasLength(1));
      expect(feed.cancelled, 0);
      expect(client.candleRequests, candleRequests);
      expect(client.quoteRequests, quoteRequests);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'large aggregation fills the selected row count and shows a real depth-limit hint when needed',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 900));
      final client = Client()
        ..preferences =
            '{"cryptoBookLevels":20,"cryptoBookSteps":{"BTCUSDT":100}}';
      final feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send({...depth(), 'book': deepSnapshot()});
      await tester.pumpAndSettle();
      Iterable<Text> sideRows(bool bid) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(
                Key(bid ? 'crypto-book-bids' : 'crypto-book-asks'),
              ),
              matching: find.byType(Text),
            ),
          )
          .where((t) => t.style?.color == (bid ? cryptoUp : cryptoDown));
      expect(sideRows(true), hasLength(20));
      expect(sideRows(false), hasLength(20));
      expect(find.byKey(const Key('crypto-book-depth-limit')), findsNothing);
      final grouping = tester.widget<DropdownButton<double>>(
        find.byKey(const Key('crypto-book-grouping')),
      );
      grouping.onChanged!(10);
      await tester.pumpAndSettle();
      expect(sideRows(true), isEmpty);
      feed.send({...depth(), 'book': deepSnapshot()});
      await tester.pumpAndSettle();
      expect(sideRows(true), hasLength(20));
      expect(sideRows(false), hasLength(20));
      grouping.onChanged!(100);
      await tester.pumpAndSettle();
      feed.send({
        ...depth(id: 11),
        'book': {...deepSnapshot(spacing: .1), 'lastUpdateId': 11},
      });
      await tester.pumpAndSettle();
      expect(sideRows(true), hasLength(5));
      expect(sideRows(false), hasLength(4));
      expect(find.textContaining('已达每侧5000价位上限'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'price steps follow symbol tick sizes including non-power-of-ten ticks',
    () {
      for (final example in [
        ('BTCUSDT', '0.01000000', ['0.01', '0.1', '1', '10', '100']),
        ('XRPUSDT', '0.00010000', ['0.0001', '0.001', '0.01', '0.1', '1']),
        (
          'DOGEUSDT',
          '0.00001000',
          ['0.00001', '0.0001', '0.001', '0.01', '0.1'],
        ),
        ('ETHUSDT', '0.05000000', ['0.05', '0.5', '5', '50', '500']),
      ]) {
        final rule = CryptoPriceRule.fromJson({
          'symbol': example.$1,
          'tickSize': example.$2,
          'stepSize': '0.00001000',
          'baseAssetPrecision': 8,
          'quoteAssetPrecision': 8,
        });
        expect(rule.steps.map(rule.label), example.$3);
      }
      for (final raw in ['0', '-0.01', 'NaN', '1e-2', '0.000000001']) {
        expect(
          () =>
              CryptoPriceRule.fromJson({'symbol': 'BTCUSDT', 'tickSize': raw}),
          throwsFormatException,
        );
      }
      final book = CryptoBook.fromJson(
        snapshot(),
        symbol: 'BTCUSDT',
        receivedAt: 1000,
      );
      final bids = book.grouped(bid: true, step: 10),
          asks = book.grouped(bid: false, step: 10);
      expect(bids.map((r) => r.price), [100, 90]);
      expect(asks.single.price, 110);
      expect(
        bids.fold<double>(0, (sum, r) => sum + r.quantity),
        book.bidQuantity,
      );
      expect(
        asks.single.amount,
        closeTo(book.asks.fold<double>(0, (sum, r) => sum + r.amount), 1e-9),
      );
    },
  );

  testWidgets(
    'grouping and level choices persist separately per symbol and restore after recreation',
    (tester) async {
      final client = Client(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send(depth());
      await tester.pumpAndSettle();
      DropdownButton<double> grouping() =>
          tester.widget<DropdownButton<double>>(
            find.byKey(const Key('crypto-book-grouping')),
          );
      PopupMenuButton<int> levels() => tester.widget<PopupMenuButton<int>>(
        find.byKey(const Key('crypto-book-levels')),
      );
      expect(grouping().items!.map((item) => (item.child as Text).data), [
        '0.01',
        '0.1',
        '1',
        '10',
        '100',
      ]);
      grouping().onChanged!(10);
      levels().onSelected!(5);
      await tester.pumpAndSettle();
      expect(grouping().value, 10);
      expect(levels().initialValue, 5);
      expect(find.text('等待币安订单簿快照…'), findsOneWidget);
      feed.send(depth());
      await tester.pumpAndSettle();
      expect(find.text('实时 · 5档'), findsOneWidget);
      var saved = DashboardPreferences.decode(client.preferences);
      expect(saved.cryptoBookSteps, {'BTCUSDT': 10});
      expect(saved.cryptoBookLevels, 5);
      await tester.tap(find.byKey(const Key('crypto-select-XRPUSDT')));
      await tester.pumpAndSettle();
      feed.send(depth(symbol: 'XRPUSDT'));
      await tester.pumpAndSettle();
      expect(grouping().items!.map((item) => (item.child as Text).data), [
        '0.0001',
        '0.001',
        '0.01',
        '0.1',
        '1',
      ]);
      expect(grouping().value, .0001);
      expect(levels().initialValue, 5);
      grouping().onChanged!(.001);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crypto-select-BTCUSDT')));
      await tester.pumpAndSettle();
      feed.send(depth());
      await tester.pumpAndSettle();
      expect(grouping().value, 10);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(bookPage(client, Feed()));
      await tester.pumpAndSettle();
      expect(grouping().value, 10);
      expect(levels().initialValue, 5);
      saved = DashboardPreferences.decode(client.preferences);
      expect(saved.cryptoBookSteps, {'BTCUSDT': 10, 'XRPUSDT': .001});
      // An explicit device choice wins over the compact landscape default.
      levels().onSelected!(20);
      await tester.pumpAndSettle();
      fixture.setSize(tester, const Size(844, 390));
      await tester.pumpAndSettle();
      expect(levels().initialValue, 20);
      expect(jsonDecode(client.preferences!)['cryptoBookLevels'], 20);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'invalid saved steps fall back to live tick and integer depth does not change the options',
    (tester) async {
      final client = Client()
        ..preferences =
            '{"cryptoBookSteps":{"BTCUSDT":0.03},"cryptoBookLevels":10}';
      final feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      final event = depth();
      event['book'] = {
        ...snapshot(),
        'priceDecimals': 0,
        'bids': [
          {'price': 100, 'quantity': 1},
        ],
        'asks': [
          {'price': 101, 'quantity': 1},
        ],
      };
      feed.send(event);
      await tester.pumpAndSettle();
      final grouping = tester.widget<DropdownButton<double>>(
        find.byKey(const Key('crypto-book-grouping')),
      );
      expect(grouping.value, .01);
      expect(grouping.items!.map((item) => (item.child as Text).data), [
        '0.01',
        '0.1',
        '1',
        '10',
        '100',
      ]);
      expect(find.text('100.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'middle price converts USD/CNY without changing USDT rows or reconnecting market feeds',
    (tester) async {
      final client = RateClient(), feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send(depth());
      feed.send({
        'type': 'quote',
        'eventTime': DateTime.now().millisecondsSinceEpoch,
        'quote': {
          'symbol': 'BTCUSDT',
          'price': 100.0,
          'changePercent': 1.0,
          'high': 101.0,
          'low': 99.0,
          'volume': 2.0,
          'quoteVolume': 200.0,
          'openTime': DateTime.now().millisecondsSinceEpoch - 86400000,
          'closeTime': DateTime.now().millisecondsSinceEpoch,
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('≈ \$99.00 USD'), findsOneWidget);
      expect(find.textContaining('价差'), findsNothing);
      final subscriptions = feed.controllers.length;
      final switcher = find.byKey(const Key('crypto-book-currency'));
      await tester.ensureVisible(switcher);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      await tester.tap(find.text('人民币 CNY'));
      await tester.pumpAndSettle();
      expect(find.text('≈ ¥710.00 CNY'), findsOneWidget);
      expect(find.text('价格(USDT)'), findsOneWidget);
      expect(find.text('金额(USDT)'), findsOneWidget);
      expect(feed.controllers.length, subscriptions);
      expect(client.rateCalls, inInclusiveRange(1, 2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed conversion retries, labels old rates, expires them and pauses with the panel',
    (tester) async {
      final client = RateClient()..rateFails = true;
      final feed = Feed();
      await tester.pumpWidget(bookPage(client, feed));
      await tester.pumpAndSettle();
      feed.send(depth());
      await tester.pumpAndSettle();
      expect(find.text('汇率暂不可用 USD'), findsOneWidget);
      client.rateFails = false;
      client.rateTime = DateTime.now().subtract(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('旧汇率'), findsOneWidget);
      client.rateTime = DateTime.now().subtract(const Duration(days: 2));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(find.text('汇率暂不可用 USD'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      final calls = client.rateCalls;
      await tester.pump(const Duration(minutes: 10));
      expect(client.rateCalls, calls);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.rateCalls, greaterThan(calls));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late conversion responses cannot update a disposed book', (
    tester,
  ) async {
    final pending = Completer<DashboardData>();
    final client = RateClient()..pendingRate = pending;
    await tester.pumpWidget(bookPage(client, Feed()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    pending.complete(
      DashboardData(
        data: {'base': 'USDT', 'USD': 1, 'CNY': 7},
        fetchedAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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
            .widget<DropdownButton<double>>(
              find.byKey(const Key('crypto-book-grouping')),
            )
            .onChanged!(.1);
        await tester.pumpAndSettle();
        feed.send(depth());
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: asks, matching: find.text('100.10')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: asks, matching: find.text('700.11000000')),
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
      expect(bar('bid', 100.0).right, closeTo(bidMax.right, .001));
      expect(bar('ask', 100.02).right, closeTo(askMax.right, .001));
      expect(bidMax.width, closeTo(askMax.width, .001));
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
          .widget<DropdownButton<double>>(
            find.byKey(const Key('crypto-book-grouping')),
          )
          .onChanged!(.1);
      await tester.pumpAndSettle();
      feed.send(event);
      await tester.pumpAndSettle();
      expect(
        bar('ask', 100.1).width,
        closeTo(
          tester
              .getSize(find.byKey(const ValueKey('crypto-book-row-ask-100.1')))
              .width,
          .01,
        ),
      );
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
