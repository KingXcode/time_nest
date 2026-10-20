import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';

import 'crypto_fixture.dart';
import 'crypto_live_widget_test.dart' show Feed, candleEvent;
import 'dashboard_widget_test.dart' as fixture;

const hour = 3600000;
final startTime = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
Map<String, dynamic> bar(int i) => {
  'time': startTime + i * hour,
  'closeTime': startTime + (i + 1) * hour - 1,
  'open': 100.0 + i,
  'high': 110.0 + i,
  'low': 90.0 + i,
  'close': 102.0 + i,
  'volume': 12.0,
  'quoteVolume': 1200.0,
};
List<CryptoCandle> candles(int from, int to) => [
  for (var i = from; i < to; i++) CryptoCandle.fromJson(bar(i)),
];

class HistoryClient extends fixture.FixtureDashboardClient {
  int total = 1500;
  bool historyFailure = false;
  Completer<DashboardData>? olderPending;
  List<Map<String, dynamic>>? historyOverride;
  final olderCalls = <Map<String, dynamic>>[];
  DashboardData page(
    String symbol,
    String interval,
    List<Map<String, dynamic>> rows,
  ) => DashboardData(
    data: {'symbol': symbol, 'interval': interval, 'candles': rows},
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      startTime + (total - 1) * hour + 1000,
    ),
  );
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    if (module == 'cryptoQuotes') {
      return DashboardData(
        data: cryptoQuotesFixture(),
        fetchedAt: DateTime.utc(2026, 10, 19),
      );
    }
    if (args.containsKey('endTime')) {
      olderCalls.add(Map.of(args));
      if (olderPending != null) return olderPending!.future;
      if (historyFailure) throw const DashboardException('连接超时，请重试。');
      final end = ((args['endTime'] as int) + 1 - startTime) ~/ hour;
      return page(
        args['symbol'] as String,
        args['interval'] as String,
        historyOverride ??
            [for (var i = (end - 500).clamp(0, end); i < end; i++) bar(i)],
      );
    }
    return page(args['symbol'] as String, args['interval'] as String, [
      for (var i = total - 500; i < total; i++) bar(i),
    ]);
  }
}

Widget panel(HistoryClient client, Feed feed) {
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

String rangeStart(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('crypto-range-start'))).data!;
Future<void> press(WidgetTester tester, String key) async {
  final control = find.byKey(Key(key));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      '$kind pans main and subcharts, anchors across prepends and pushes, returns to live',
      (tester) async {
        fixture.setSize(
          tester,
          Size(kind == PointerDeviceKind.mouse ? 1280 : 320, 1000),
        );
        var rows = candles(1000, 1500);
        late StateSetter update;
        await tester.pumpWidget(
          fixture.app(
            Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return CryptoChart(
                      candles: rows,
                      asset: 'BTC',
                      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
                        startTime + 1500 * hour,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(rangeStart(tester), cryptoTime(bar(1300)['time'] as int));
        final plot = find.byKey(const Key('crypto-price-plot'));
        await tester.ensureVisible(plot);
        final width = tester.getSize(plot).width;
        await tester.drag(plot, Offset(width * .3, 0), kind: kind);
        await tester.pumpAndSettle();
        final older = rangeStart(tester);
        expect(
          older.compareTo(cryptoTime(bar(1300)['time'] as int)),
          lessThan(0),
        );
        expect(tester.getSize(plot).height, cryptoPriceHeight);
        update(() => rows = [...candles(500, 1000), ...rows]);
        await tester.pumpAndSettle();
        expect(rangeStart(tester), older);
        update(() => rows = [...rows, CryptoCandle.fromJson(bar(1500))]);
        await tester.pumpAndSettle();
        expect(rangeStart(tester), older);
        final pane = find.byKey(const Key('crypto-pane-vol'));
        await tester.ensureVisible(pane);
        await tester.drag(pane, Offset(-width * .15, 0), kind: kind);
        await tester.pumpAndSettle();
        expect(rangeStart(tester).compareTo(older), greaterThan(0));
        await press(tester, 'crypto-latest');
        expect(rangeStart(tester), cryptoTime(bar(1301)['time'] as int));
        update(() => rows = [...rows, CryptoCandle.fromJson(bar(1501))]);
        await tester.pumpAndSettle();
        expect(rangeStart(tester), cryptoTime(bar(1302)['time'] as int));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 1000.0]) {
    testWidgets(
      '200-bar viewport, persistent touch crosshair, pinch and timeline selection at $width',
      (tester) async {
        fixture.setSize(tester, Size(width, 1100));
        var loads = 0;
        await tester.pumpWidget(
          fixture.app(
            Scaffold(
              body: SingleChildScrollView(
                child: CryptoChart(
                  candles: candles(0, 500),
                  asset: 'BTC',
                  fetchedAt: DateTime.utc(2026, 2),
                  onLoadOlder: () => loads++,
                  hasMoreHistory: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        CryptoTimeline timeline() =>
            tester.widget<CryptoTimeline>(find.byType(CryptoTimeline));
        bool horizontal(String key) {
          final dynamic painter = tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter;
          return painter.crosshair && painter.horizontalCrosshair;
        }

        expect(timeline().count, 200);
        expect(timeline().start, 300);
        expect(
          tester.getSize(find.byKey(const Key('crypto-info-window'))).width,
          lessThanOrEqualTo(164),
        );
        final load = find.byKey(const Key('crypto-load-older'));
        expect(tester.widget<IconButton>(load).tooltip, '加载更多历史');
        expect(tester.getSize(load).width, 32);
        expect(
          find.descendant(of: load, matching: find.byType(Text)),
          findsNothing,
        );
        final plot = find.byKey(const Key('crypto-price-plot'));
        await tester.ensureVisible(plot);
        final rect = tester.getRect(plot);
        final finger = await tester.startGesture(rect.center, pointer: 1);
        await tester.pump();
        expect(find.byKey(const Key('crypto-crosshair')), findsOneWidget);
        expect(horizontal('crypto-price-plot'), isTrue);
        expect(horizontal('crypto-pane-vol'), isFalse);
        final selected = tester
            .widget<Text>(find.byKey(const Key('crypto-candle-time')))
            .data;
        await finger.up();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('crypto-crosshair')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('crypto-candle-time'))).data,
          selected,
        );
        await tester.tapAt(rect.center);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('crypto-crosshair')), findsNothing);
        final pane = find.byKey(const Key('crypto-pane-vol'));
        await tester.ensureVisible(pane);
        await tester.tapAt(tester.getCenter(pane));
        await tester.pumpAndSettle();
        expect(horizontal('crypto-pane-vol'), isTrue);
        expect(horizontal('crypto-price-plot'), isFalse);
        // Return the main plot to the same scroll position before pinching.
        await tester.ensureVisible(plot);
        final pinchCenter = tester.getRect(plot).center;
        final one = await tester.startGesture(
          pinchCenter - const Offset(60, 0),
          pointer: 2,
        );
        final two = await tester.startGesture(
          pinchCenter + const Offset(60, 0),
          pointer: 3,
        );
        await tester.pump();
        for (var i = 1; i <= 5; i++) {
          await one.moveTo(pinchCenter - Offset(60 + i * 14, 0));
          await two.moveTo(pinchCenter + Offset(60 + i * 14, 0));
          await tester.pump();
        }
        await one.up();
        await two.up();
        await tester.pumpAndSettle();
        expect(timeline().count, lessThan(200));
        expect(timeline().count, greaterThanOrEqualTo(20));
        final nav = find.byKey(const Key('crypto-timeline'));
        await tester.ensureVisible(nav);
        await tester.tapAt(tester.getTopLeft(nav) + const Offset(5, 20));
        await tester.pumpAndSettle();
        expect(timeline().start, 0);
        final oldCount = timeline().count;
        final navRect = tester.getRect(nav);
        final edge =
            navRect.topLeft + Offset(navRect.width * oldCount / 500, 16);
        final handle = await tester.startGesture(edge);
        // Cross the gesture slop, then resize the right edge.
        await handle.moveBy(const Offset(22, 0));
        await tester.pump();
        await handle.moveBy(Offset(navRect.width * .12, 0));
        await handle.up();
        await tester.pumpAndSettle();
        expect(timeline().count, greaterThan(oldCount));
        expect(timeline().start, 0);
        expect(loads, 0);
        await press(tester, 'crypto-load-older');
        expect(loads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'connected plots resize independently; active crosshair wheel zoom consumes scrolling',
    (tester) async {
      fixture.setSize(tester, const Size(1000, 1100));
      var loads = 0;
      await tester.pumpWidget(
        fixture.app(
          Scaffold(
            body: SingleChildScrollView(
              child: CryptoChart(
                candles: candles(0, 500),
                asset: 'BTC',
                fetchedAt: DateTime.utc(2026, 2),
                onLoadOlder: () => loads++,
                hasMoreHistory: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final plot = find.byKey(const Key('crypto-price-plot'));
      final vol = find.byKey(const Key('crypto-pane-vol'));
      final macd = find.byKey(const Key('crypto-pane-macd'));
      final timeline = find.byKey(const Key('crypto-timeline'));
      expect(
        tester.getTopLeft(vol).dy - tester.getBottomLeft(plot).dy,
        lessThan(140),
      );
      expect(
        tester.getTopLeft(timeline).dy,
        greaterThan(tester.getBottomLeft(plot).dy),
      );
      expect(
        tester.getBottomLeft(timeline).dy,
        lessThan(tester.getTopLeft(vol).dy),
      );
      final dynamic mainPainter = tester
          .widget<CustomPaint>(
            find.descendant(of: plot, matching: find.byType(CustomPaint)),
          )
          .painter;
      final dynamic volPainter = tester
          .widget<CustomPaint>(
            find.descendant(of: vol, matching: find.byType(CustomPaint)),
          )
          .painter;
      expect(mainPainter.axisWidth, volPainter.axisWidth);
      expect(mainPainter.axisWidth, lessThan(72));
      await tester.ensureVisible(plot);
      Offset pointer() => tester.getTopLeft(plot) + const Offset(330, 100);
      int count() =>
          tester.widget<CryptoTimeline>(find.byType(CryptoTimeline)).count;
      final noCursor = count();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer(),
          scrollDelta: const Offset(0, -120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(count(), noCursor);
      await tester.ensureVisible(plot);
      await tester.tapAt(pointer());
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(plot).dy;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer(),
          scrollDelta: const Offset(0, -120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(count(), lessThan(200));
      expect(tester.getTopLeft(plot).dy, top);
      final zoomed = count();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer(),
          scrollDelta: const Offset(0, 120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(count(), greaterThan(zoomed));
      final handle = find.byKey(const Key('crypto-resize-vol'));
      await tester.ensureVisible(handle);
      await tester.drag(handle, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(tester.getSize(vol).height, greaterThan(cryptoPaneHeight));
      expect(tester.getSize(macd).height, cryptoPaneHeight);
      expect(tester.getSize(plot).height, cryptoPriceHeight);
      await tester.ensureVisible(handle);
      await tester.drag(handle, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getSize(vol).height, 64);
      await tester.ensureVisible(handle);
      await tester.drag(handle, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(tester.getSize(vol).height, 400);
      expect(loads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'left edge never auto loads; manual button pages once, preserves viewport and retained history through live refresh',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 1000));
      final client = HistoryClient(), feed = Feed();
      await tester.pumpWidget(panel(client, feed));
      await tester.pumpAndSettle();
      client.olderPending = Completer<DashboardData>();
      for (var i = 0; i < 4; i++) {
        await press(tester, 'crypto-pan-older');
      }
      expect(client.olderCalls, isEmpty);
      await press(tester, 'crypto-load-older');
      expect(client.olderCalls, hasLength(1));
      expect(client.olderCalls.single['endTime'], startTime + 1000 * hour - 1);
      final pinned = rangeStart(tester);
      // A simultaneous latest snapshot must not cancel the older request.
      final refresh = find.widgetWithText(TextButton, '刷新行情');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      client.olderPending!.complete(
        client.page('BTCUSDT', '1h', [for (var i = 500; i < 1000; i++) bar(i)]),
      );
      client.olderPending = null;
      await tester.pumpAndSettle();
      CryptoChart chart() =>
          tester.widget<CryptoChart>(find.byType(CryptoChart));
      expect(chart().candles, hasLength(1000));
      expect(chart().candles.map((c) => c.time).toSet(), hasLength(1000));
      expect(rangeStart(tester), pinned);
      client.total++;
      feed.send(candleEvent(bar(1500), startTime + 1500 * hour + 2000));
      feed.send({'type': 'status', 'status': 'live'});
      await tester.pumpAndSettle();
      expect(chart().candles, hasLength(1001));
      expect(chart().candles.first.time, startTime + 500 * hour);
      expect(rangeStart(tester), pinned);
      await press(tester, 'crypto-load-older');
      expect(chart().candles, hasLength(1501));
      expect(client.olderCalls.last['endTime'], startTime + 500 * hour - 1);
      await press(tester, 'crypto-load-older');
      expect(chart().hasMoreHistory, isFalse);
      final calls = client.olderCalls.length;
      expect(find.byTooltip('已到最早数据'), findsOneWidget);
      await press(tester, 'crypto-pan-older');
      expect(client.olderCalls.length, calls);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pagination failure and invalid pages retain data, explicit retry accepts short final page',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 1000));
      final client = HistoryClient()..historyFailure = true;
      await tester.pumpWidget(panel(client, Feed()));
      await tester.pumpAndSettle();
      CryptoChart chart() =>
          tester.widget<CryptoChart>(find.byType(CryptoChart));
      await press(tester, 'crypto-load-older');
      expect(chart().candles, hasLength(500));
      expect(find.byTooltip('重试加载历史'), findsOneWidget);
      expect(chart().hasMoreHistory, isTrue);
      client.historyFailure = false;
      for (final invalid in [
        [bar(999), bar(1000)],
        [bar(998)],
        [bar(997), bar(999)],
      ]) {
        client.historyOverride = invalid;
        await press(tester, 'crypto-load-older');
        expect(chart().candles, hasLength(500));
        expect(chart().historyError, isNotNull);
      }
      client.historyOverride = [bar(998), bar(999)];
      await press(tester, 'crypto-load-older');
      expect(chart().candles, hasLength(502));
      expect(chart().historyError, isNull);
      expect(chart().hasMoreHistory, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late older page cannot enter a different symbol or interval, and disposal is safe',
    (tester) async {
      fixture.setSize(tester, const Size(1280, 1000));
      final client = HistoryClient(), feed = Feed();
      await tester.pumpWidget(panel(client, feed));
      await tester.pumpAndSettle();
      for (final switchSymbol in [true, false]) {
        client.olderPending = Completer<DashboardData>();
        final pending = client.olderPending!;
        await press(tester, 'crypto-load-older');
        final selection = switchSymbol
            ? find.byKey(const ValueKey('crypto-select-ETHUSDT'))
            : find.widgetWithText(ChoiceChip, '日线');
        await tester.ensureVisible(selection);
        await tester.tap(selection);
        await tester.pumpAndSettle();
        pending.complete(
          client.page(switchSymbol ? 'BTCUSDT' : 'ETHUSDT', '1h', [
            for (var i = 500; i < 1000; i++) bar(i),
          ]),
        );
        client.olderPending = null;
        await tester.pumpAndSettle();
        final chart = tester.widget<CryptoChart>(find.byType(CryptoChart));
        expect(chart.asset, 'ETH');
        expect(chart.candles, hasLength(500));
        expect(chart.loadingOlder, isFalse);
        expect(rangeStart(tester), cryptoTime(bar(1300)['time'] as int));
      }
      client.olderPending = Completer<DashboardData>();
      await press(tester, 'crypto-load-older');
      await tester.pumpWidget(const SizedBox());
      client.olderPending!.complete(client.page('ETHUSDT', '1d', []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
