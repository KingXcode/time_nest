import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'crypto_feed.dart';

@JS('timeNestDashboard.subscribeCrypto')
external JSString _subscribe(JSString args, JSFunction callback);
@JS('timeNestDashboard.unsubscribeCrypto')
external void _unsubscribe(JSString id);
@JS('timeNestDashboard.resetCryptoBook')
external JSNumber? _resetBook(JSString id);

CryptoFeed createCryptoFeed() => _WebFeed();

class _WebFeed implements CryptoFeed {
  JSString? _activeId;

  @override
  int? resetOrderBook() =>
      _activeId == null ? null : _resetBook(_activeId!)?.toDartInt;

  @override
  Stream<Map<String, dynamic>> subscribe(
    String symbol,
    String interval, {
    bool orderBook = true,
    bool trades = false,
  }) {
    JSString? id;
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController(
      onListen: () {
        try {
          id = _subscribe(
            jsonEncode({
              'symbol': symbol,
              'interval': interval,
              'orderBook': orderBook,
              'trades': trades,
            }).toJS,
            ((JSString raw) {
              if (controller.isClosed) return;
              try {
                controller.add(jsonDecode(raw.toDart) as Map<String, dynamic>);
              } catch (_) {
                controller.add({'type': 'status', 'status': 'error'});
              }
            }).toJS,
          );
          _activeId = id;
        } catch (_) {
          controller.add({'type': 'status', 'status': 'unavailable'});
        }
      },
      onCancel: () {
        if (id != null) _unsubscribe(id!);
        if (_activeId == id) _activeId = null;
      },
    );
    return controller.stream;
  }
}
