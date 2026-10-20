import 'crypto_feed.dart';

CryptoFeed createCryptoFeed() => _UnavailableFeed();

class _UnavailableFeed implements CryptoFeed {
  @override
  int? resetOrderBook() => null;

  @override
  Stream<Map<String, dynamic>> subscribe(
    String symbol,
    String interval, {
    bool orderBook = true,
    bool trades = false,
  }) => Stream.value({'type': 'status', 'status': 'unavailable'});
}
