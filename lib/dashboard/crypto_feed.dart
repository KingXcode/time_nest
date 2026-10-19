import 'crypto_feed_stub.dart'
    if (dart.library.js_interop) 'crypto_feed_web.dart'
    as implementation;

abstract class CryptoFeed {
  Stream<Map<String, dynamic>> subscribe(String symbol, String interval);
}

CryptoFeed createCryptoFeed() => implementation.createCryptoFeed();
