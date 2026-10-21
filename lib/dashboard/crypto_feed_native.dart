import '../platform/native_runtime.dart';
import 'crypto_feed.dart';
import 'crypto_feed_stub.dart' as stub;

CryptoFeed createCryptoFeed() => NativeRuntime.current == null
    ? stub.createCryptoFeed()
    : MacCryptoFeed(NativeRuntime.current!);

class MacCryptoFeed implements CryptoFeed {
  MacCryptoFeed(this.runtime);
  final NativeRuntime runtime;
  String? _token;
  int _epoch = 0;
  @override
  int? resetOrderBook() {
    final token = _token;
    if (token == null) return null;
    runtime.call('resetBook', {'token': token}).catchError((Object _) => null);
    return ++_epoch;
  }

  @override
  Stream<Map<String, dynamic>> subscribe(
    String symbol,
    String interval, {
    bool orderBook = true,
    bool trades = false,
  }) {
    final token = runtime.newToken();
    return runtime.stream(
      token,
      'crypto',
      {
        'symbol': symbol,
        'interval': interval,
        'orderBook': orderBook,
        'trades': trades,
      },
      onListen: () {
        _token = token;
        _epoch = 0;
      },
      onCancel: () {
        if (_token == token) _token = null;
      },
    );
  }
}
