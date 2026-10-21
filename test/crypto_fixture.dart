// Synthetic market values for automated tests only; never shipped as live data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:time_nest/dashboard/crypto_market.dart';

Map<String, dynamic> cryptoQuotesFixture([String? selected]) => {
  'quotes': [
    for (final symbol in selected == null ? cryptoAssets.keys : [selected])
      {
        'symbol': symbol,
        'price': 100.25,
        'changePercent': 2.5,
        'high': 105.0,
        'low': 95.0,
        'volume': 1234.0,
        'quoteVolume': 123708.5,
        'openTime': DateTime.utc(2026, 10, 17).millisecondsSinceEpoch,
        'closeTime': DateTime.utc(2026, 10, 18).millisecondsSinceEpoch,
      },
  ],
};

Map<String, dynamic> cryptoCandlesFixture(String symbol, String interval) => {
  'symbol': symbol,
  'interval': interval,
  'candles': [
    for (var i = 0; i < 10; i++)
      {
        'time': DateTime.utc(2026, 10, 17, i).millisecondsSinceEpoch,
        'closeTime':
            DateTime.utc(2026, 10, 17, i + 1).millisecondsSinceEpoch - 1,
        'open': 100.0 + i,
        'high': 103.0 + i,
        'low': 98.0 + i,
        'close': 102.0 + i,
        'volume': 1000.0 + i,
        'quoteVolume': 100000.0 + i,
      },
  ],
};

Map<String, dynamic> cryptoPairsFixture() => {
  'pairs': [
    for (final entry in cryptoAssets.entries)
      {'symbol': entry.key, 'baseAsset': entry.value.$1, 'quoteAsset': 'USDT'},
    for (final base in ['ETH', 'SOL', 'BNB'])
      {'symbol': '${base}BTC', 'baseAsset': base, 'quoteAsset': 'BTC'},
    for (final base in ['BTC', 'ETH'])
      {'symbol': '${base}USDC', 'baseAsset': base, 'quoteAsset': 'USDC'},
  ],
};

Future<void> openCryptoPairPicker(
  WidgetTester tester, {
  bool quote = false,
}) async {
  final button = find.byKey(
    Key(quote ? 'crypto-quote-selector' : 'crypto-base-selector'),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
