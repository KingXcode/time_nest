import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_chart_controls.dart';
import 'package:time_nest/dashboard/crypto_indicators.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';

import 'crypto_live_widget_test.dart' show Client, Feed;
import 'crypto_trades_test.dart' show press;
import 'dashboard_widget_test.dart' as fixture;

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
            overlays: prefs.cryptoOverlays,
            panes: prefs.cryptoPanes,
            paneHeights: const {'vol': 180},
            onChanged: (s, i) => update(() {
              prefs.cryptoSymbol = s;
              prefs.cryptoInterval = i;
              client.writePreferences(prefs.encode());
            }),
            onChartChanged: (o, p, r) => update(() {
              prefs.cryptoOverlays = o;
              prefs.cryptoPanes = p;
              client.writePreferences(prefs.encode());
            }),
          ),
        ),
      ),
    ),
    scale: scale,
  );
}

void main() {
  for (final viewport in [
    (const Size(1440, 1000), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(320, 900), 2.0),
  ]) {
    testWidgets(
      'period, metadata and indicator controls stay inside the chart at $viewport',
      (tester) async {
        fixture.setSize(tester, viewport.$1);
        final client = Client(), feed = Feed();
        await tester.pumpWidget(page(client, feed, scale: viewport.$2));
        await tester.pumpAndSettle();
        final frame = find.byKey(const Key('crypto-chart-surface'));
        for (final key in [
          'crypto-period-1d',
          'crypto-chart-market-info',
          'crypto-pan-older',
          'crypto-chart-indicators',
          'crypto-view-settings',
        ]) {
          expect(
            find.descendant(of: frame, matching: find.byKey(Key(key))),
            findsOneWidget,
          );
        }
        final plot = find.byKey(const Key('crypto-price-plot'));
        expect(
          tester
              .getBottomLeft(find.byKey(const Key('crypto-chart-market-info')))
              .dy,
          lessThan(tester.getTopLeft(plot).dy),
        );
        expect(
          tester
              .getTopLeft(find.byKey(const Key('crypto-chart-indicators')))
              .dy,
          greaterThan(
            tester.getBottomLeft(find.byKey(const Key('crypto-pane-rsi'))).dy,
          ),
        );
        expect(tester.getSize(plot).height, 320);
        expect(tester.takeException(), isNull);
        // Horizontal scrolling keeps every period reachable even at large text sizes.
        await press(tester, 'crypto-period-1w');
        expect(
          tester.widget<CryptoChart>(find.byType(CryptoChart)).interval,
          '1w',
        );
        expect(
          DashboardPreferences.decode(client.preferences).cryptoInterval,
          '1w',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'bottom indicator shortcuts persist without reconnecting or moving historical candles',
    (tester) async {
      fixture.setSize(tester, const Size(1440, 1000));
      final client = Client(), feed = Feed();
      await tester.pumpWidget(page(client, feed));
      await tester.pumpAndSettle();
      await press(tester, 'crypto-pan-older');
      String range() => tester
          .widget<Text>(find.byKey(const Key('crypto-range-start')))
          .data!;
      final before = range(), state = tester.state(find.byType(CryptoChart));
      final connections = feed.selections.length;
      await press(tester, 'crypto-quick-indicator-ema');
      expect(
        tester.widget<CryptoChart>(find.byType(CryptoChart)).overlays,
        contains('ema'),
      );
      expect(
        DashboardPreferences.decode(client.preferences).cryptoOverlays,
        contains('ema'),
      );
      await press(tester, 'crypto-quick-indicator-rsi');
      expect(find.byKey(const Key('crypto-pane-rsi')), findsNothing);
      expect(
        DashboardPreferences.decode(client.preferences).cryptoPanes,
        isNot(contains('rsi')),
      );
      expect(range(), before);
      expect(tester.state(find.byType(CryptoChart)), same(state));
      expect(feed.selections.length, connections);
      expect(
        tester.getSize(find.byKey(const Key('crypto-pane-vol'))).height,
        180,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(client, Feed()));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CryptoChart>(find.byType(CryptoChart)).overlays,
        contains('ema'),
      );
      expect(find.byKey(const Key('crypto-pane-rsi')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'shortcuts respect the same eight-study limit and permit removing selected studies',
    (tester) async {
      final overlays = cryptoIndicators.keys
          .where((id) => cryptoIndicators[id]!.overlay && id != 'bbi')
          .take(8)
          .toList();
      List<String>? changed;
      await tester.pumpWidget(
        fixture.app(
          Scaffold(
            body: CryptoIndicatorBar(
              overlays: overlays,
              panes: defaultCryptoPanes,
              onSettings: () {},
              onChanged: (o, p) => changed = o,
            ),
          ),
        ),
      );
      final blocked = tester.widget<FilterChip>(
        find.byKey(const Key('crypto-quick-indicator-bbi')),
      );
      expect(blocked.onSelected, isNull);
      final selected = tester.widget<FilterChip>(
        find.byKey(const Key('crypto-quick-indicator-ma')),
      );
      selected.onSelected!(false);
      expect(changed, isNot(contains('ma')));
      expect(changed, hasLength(7));
    },
  );

  testWidgets(
    'periods and chart settings remain usable before the initial candles arrive',
    (tester) async {
      fixture.setSize(tester, const Size(390, 844));
      final client = Client()..historyPending = Completer<DashboardData>();
      await tester.pumpWidget(page(client, Feed()));
      await tester.pumpAndSettle();
      expect(find.text('等待 K 线数据…'), findsOneWidget);
      await press(tester, 'crypto-period-1d');
      expect(
        DashboardPreferences.decode(client.preferences).cryptoInterval,
        '1d',
      );
      await press(tester, 'crypto-view-settings');
      expect(find.text('窗口显示'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      client.historyPending!.complete(client.snapshot('BTCUSDT', '1d'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
