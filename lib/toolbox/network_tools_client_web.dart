import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'network_tools_client.dart';

@JS('timeNestNetwork.environment')
external JSString _environment();
@JS('timeNestNetwork.history')
external JSString _history();
@JS('timeNestNetwork.clearHistory')
external JSBoolean _clearHistory();
@JS('timeNestNetwork.start')
external JSString _start(JSString kind, JSString args, JSFunction callback);
@JS('timeNestNetwork.cancel')
external void _cancel(JSString id);
@JS('timeNestNetwork.openUrl')
external void _openUrl(JSString url);

NetworkToolsClient createNetworkToolsClient() => _WebNetworkClient();

class _WebNetworkClient implements NetworkToolsClient {
  @override
  Map<String, dynamic> environment() {
    try {
      return jsonDecode(_environment().toDart) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  Map<String, dynamic> history() {
    try {
      return jsonDecode(_history().toDart) as Map<String, dynamic>;
    } catch (_) {
      return {'available': false, 'items': []};
    }
  }

  @override
  bool clearHistory() {
    try {
      return _clearHistory().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<Map<String, dynamic>> run(
    String kind, {
    Map<String, dynamic> args = const {},
  }) {
    JSString? id;
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController(
      onListen: () {
        try {
          id = _start(
            kind.toJS,
            jsonEncode(args).toJS,
            ((JSString raw) {
              if (controller.isClosed) return;
              try {
                final value = jsonDecode(raw.toDart) as Map<String, dynamic>;
                controller.add(value);
                if (value['status'] != 'running') controller.close();
              } catch (_) {
                controller.add({
                  'kind': kind,
                  'status': 'error',
                  'message': '网络工具返回格式异常，请重新打开工具箱。',
                  'result': <String, dynamic>{},
                });
                controller.close();
              }
            }).toJS,
          );
        } catch (_) {
          controller.add({
            'kind': kind,
            'status': 'error',
            'message': '网络工具未加载，请刷新页面后重试。',
            'result': <String, dynamic>{},
          });
          controller.close();
        }
      },
      onCancel: () {
        if (id != null) {
          try {
            _cancel(id!);
          } catch (_) {
            // Navigation/disposal must remain safe if the bridge is gone.
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  void openUrl(String url) {
    try {
      _openUrl(url.toJS);
    } catch (_) {
      // Source links are optional and may be blocked by the browser.
    }
  }
}
