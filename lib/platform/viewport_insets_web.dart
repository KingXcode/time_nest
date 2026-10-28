import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('shikeViewport.getBottomInset')
external JSNumber _getBottomInset();
@JS('shikeViewport.subscribe')
external void _subscribe(JSFunction callback);
@JS('shikeViewport.unsubscribe')
external void _unsubscribe(JSFunction callback);

ValueNotifier<double> createViewportBottomInset() => _ViewportBottomInset();

class _ViewportBottomInset extends ValueNotifier<double> {
  _ViewportBottomInset() : super(0) {
    _callback = _refresh.toJS;
    try {
      _subscribe(_callback);
      _subscribed = true;
      _refresh();
    } catch (_) {
      // Older/offline hosts without this optional bridge still render normally.
    }
  }
  late final JSFunction _callback;
  bool _subscribed = false;

  void _refresh() {
    try {
      final inset = _getBottomInset().toDartDouble;
      value = inset.isFinite && inset > 0 ? inset : 0;
    } catch (_) {
      value = 0;
    }
  }

  @override
  void dispose() {
    if (_subscribed) {
      try {
        _unsubscribe(_callback);
      } catch (_) {
        // The host may have been replaced during navigation.
      }
    }
    super.dispose();
  }
}
