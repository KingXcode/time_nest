import 'crypto_feed.dart';

CryptoFeed createCryptoFeed() => _UnavailableFeed();

class _UnavailableFeed implements CryptoFeed {
  @override
  Stream<Map<String, dynamic>> subscribe(String symbol, String interval) =>
      Stream.value({'type': 'status', 'status': 'unavailable'});
}
