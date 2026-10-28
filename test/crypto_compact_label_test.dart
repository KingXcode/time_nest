import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/dashboard/crypto_market.dart';

void main() {
  testWidgets('compact current candle shows price without forming label', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 28, 12);
    final candle = CryptoCandle.fromJson({
      'time': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'closeTime': DateTime.utc(2026, 10, 29).millisecondsSinceEpoch - 1,
      'open': 100.0,
      'high': 105.0,
      'low': 95.0,
      'close': 102.0,
      'volume': 1.0,
      'quoteVolume': 102.0,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CryptoChart(
            candles: [candle],
            asset: 'BTC',
            fetchedAt: now,
            compact: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('形成中'), findsNothing);
    expect(find.textContaining('USDT'), findsWidgets);
    expect(find.byKey(const Key('crypto-compact-price-plot')), findsOneWidget);
    final chart = tester.widget<CryptoChart>(find.byType(CryptoChart));
    expect(chart.candles.single.closeTime, candle.closeTime);
    expect(chart.fetchedAt, now);
    expect(tester.takeException(), isNull);
  });
}
