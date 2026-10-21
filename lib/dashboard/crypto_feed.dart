import 'crypto_feed_stub.dart'
    if (dart.library.io) 'crypto_feed_native.dart'
    if (dart.library.js_interop) 'crypto_feed_web.dart'
    as implementation;

abstract class CryptoFeed {
  Stream<Map<String, dynamic>> subscribe(
    String symbol,
    String interval, {
    bool orderBook = true,
    bool trades = false,
  });

  /// Rebootstrap the active order book without interrupting quotes or candles.
  /// Returns its new generation, or null when no subscription is active.
  int? resetOrderBook();
}

CryptoFeed createCryptoFeed() => implementation.createCryptoFeed();
