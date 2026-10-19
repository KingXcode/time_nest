import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'crypto_feed.dart';

@JS('timeNestDashboard.subscribeCrypto')
external JSString _subscribe(JSString args, JSFunction callback);
@JS('timeNestDashboard.unsubscribeCrypto')
external void _unsubscribe(JSString id);

CryptoFeed createCryptoFeed() => _WebFeed();

class _WebFeed implements CryptoFeed {
  @override
  Stream<Map<String, dynamic>> subscribe(String symbol, String interval) {
    JSString? id;
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController(
      onListen: () {
        try {
          id = _subscribe(
            jsonEncode({'symbol': symbol, 'interval': interval}).toJS,
            ((JSString raw) {
              if (controller.isClosed) return;
              try {
                controller.add(jsonDecode(raw.toDart) as Map<String, dynamic>);
              } catch (_) {
                controller.add({'type': 'status', 'status': 'error'});
              }
            }).toJS,
          );
        } catch (_) {
          controller.add({'type': 'status', 'status': 'unavailable'});
        }
      },
      onCancel: () {
        if (id != null) _unsubscribe(id!);
      },
    );
    return controller.stream;
  }
}
