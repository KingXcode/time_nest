import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';
import 'package:time_nest/dashboard/market_chart.dart';
import 'package:time_nest/dashboard/market_config.dart';

import 'dashboard_widget_test.dart' as fixture;

void main() {
  test(
    'market preferences migrate safely and whitelist symbols and periods',
    () {
      final old = DashboardPreferences.decode(
        '{"version":3,"order":["news","weather","fx","releases"],"favorites":["news"]}',
      );
      expect(old.order, ['news', 'weather', 'releases', 'market', 'crypto']);
      expect(old.favorites, ['news']);
      expect(old.marketIndex, 'shanghai');
      expect(old.marketInterval, 'D');
      final bad = DashboardPreferences.decode(
        jsonEncode({
          'marketIndex': 'https://evil.test',
          'marketInterval': '1',
          'favorites': ['market'],
        }),
      );
      expect(bad.marketIndex, 'shanghai');
      expect(bad.marketInterval, 'D');
      expect(bad.favorites, ['market']);
      expect(marketIndexFor('__proto__').id, 'shanghai');
      for (final index in marketIndices) {
        final prefs = DashboardPreferences(
          marketIndex: index.id,
          marketInterval: 'M',
        );
        expect(
          DashboardPreferences.decode(prefs.encode()).marketIndex,
          index.id,
        );
        expect(DashboardPreferences.decode(prefs.encode()).marketInterval, 'M');
        expect(Uri.parse(index.sourceUrl).host, 'www.tradingview.com');
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'market page fits 320px at $scale text, choices persist and leaving disposes',
      (tester) async {
        fixture.setSize(tester, const Size(320, 900));
        final client = fixture.FixtureDashboardClient();
        await tester.pumpWidget(
          fixture.app(DashboardScreen(client: client), scale: scale),
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
          findsNothing,
        );
        expect(client.calls, isEmpty);
        await fixture.openModule(tester, 'market');
        expect(
          find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
          findsOneWidget,
        );
        expect(find.text('日线与历史走势 · 不保证实时'), findsOneWidget);
        final technical = find.byWidgetPredicate(
          (w) => w is MarketChart && w.technical,
        );
        expect(technical, findsOneWidget);
        expect(tester.widget<MarketChart>(technical).interval, 'D');
        expect(find.text('所选指数技术面 · 日线'), findsOneWidget);
        final shenzhen = find.widgetWithText(ChoiceChip, '深证成指');
        await tester.ensureVisible(shenzhen);
        await tester.tap(shenzhen);
        await tester.pumpAndSettle();
        final month = find.widgetWithText(ChoiceChip, '月线');
        await tester.ensureVisible(month);
        await tester.tap(month);
        await tester.pumpAndSettle();
        expect(
          DashboardPreferences.decode(client.preferences).marketIndex,
          'shenzhen',
        );
        expect(
          DashboardPreferences.decode(client.preferences).marketInterval,
          'M',
        );
        expect(
          tester
              .widget<MarketChart>(
                find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
              )
              .interval,
          'M',
        );
        final source = find.widgetWithText(TextButton, '打开来源');
        await tester.ensureVisible(source);
        await tester.tap(source);
        expect(client.opened, [
          'https://www.tradingview.com/symbols/SZSE-399001/',
        ]);
        final retry = find.widgetWithText(TextButton, '重新加载图表');
        await tester.ensureVisible(retry);
        final oldKey = tester
            .widget<MarketChart>(
              find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
            )
            .key;
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MarketChart>(
                find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
              )
              .key,
          isNot(oldKey),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(MarketChart), findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
          findsNothing,
        );
        expect(client.calls, isEmpty);
        await fixture.openModule(tester, 'market');
        expect(
          tester
              .widget<MarketChart>(
                find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
              )
              .indexId,
          'shenzhen',
        );
        expect(
          tester
              .widget<MarketChart>(
                find.byWidgetPredicate((w) => w is MarketChart && !w.technical),
              )
              .interval,
          'M',
        );
        final star = find.widgetWithText(ChoiceChip, '科创50');
        await tester.ensureVisible(star);
        await tester.tap(star);
        await tester.pumpAndSettle();
        expect(technical, findsNothing);
        expect(find.textContaining('科创50 技术评级暂缺'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
