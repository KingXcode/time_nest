import 'dart:convert';
import 'dart:js_interop';

import 'browser_client.dart';
import 'browser_client_stub.dart' show MemoryBrowserClient;

@JS('shike.getState')
external JSString _getState();
@JS('shike.subscribe')
external void _subscribe(JSFunction callback);
@JS('shike.unsubscribe')
external void _unsubscribe();
@JS('shike.readSettings')
external JSString? _readSettings();
@JS('shike.writeSettings')
external JSBoolean _writeSettings(JSString settings);
@JS('shike.readIntroSeen')
external JSBoolean _readIntroSeen();
@JS('shike.markIntroSeen')
external JSBoolean _markIntroSeen();
@JS('shike.setKeepAwake')
external void _setKeepAwake(JSBoolean enabled);
@JS('shike.startPresentation')
external void _startPresentation();
@JS('shike.toggleFullscreen')
external void _toggleFullscreen();
@JS('shike.checkForUpdate')
external void _checkForUpdate();
@JS('shike.applyUpdate')
external void _applyUpdate();

BrowserClient createBrowserClient() {
  try {
    return WebBrowserClient();
  } catch (_) {
    // Optional platform integration must never prevent the core clock.
    return MemoryBrowserClient(persistent: false);
  }
}

class WebBrowserClient extends BrowserClient {
  WebBrowserClient() {
    _state = _readState();
    _callback = (() {
      _state = _readState();
      notifyListeners();
    }).toJS;
    _subscribe(_callback);
  }

  late BrowserState _state;
  late final JSFunction _callback;
  BrowserState _readState() => BrowserState.fromJson(
    jsonDecode(_getState().toDart) as Map<String, dynamic>,
  );
  @override
  BrowserState get state => _state;
  @override
  String? readSettings() => _readSettings()?.toDart;
  @override
  bool writeSettings(String settings) => _writeSettings(settings.toJS).toDart;
  @override
  bool readIntroSeen() => _readIntroSeen().toDart;
  @override
  bool markIntroSeen() => _markIntroSeen().toDart;
  @override
  void setKeepAwake(bool enabled) => _setKeepAwake(enabled.toJS);
  @override
  void startPresentation() => _startPresentation();
  @override
  void toggleFullscreen() => _toggleFullscreen();
  @override
  void checkForUpdate() => _checkForUpdate();
  @override
  void applyUpdate() => _applyUpdate();
  @override
  void dispose() {
    _unsubscribe();
    _setKeepAwake(false.toJS);
    super.dispose();
  }
}
