import 'dart:convert';

import '../platform/native_runtime.dart';
import 'network_tools_client.dart';
import 'network_tools_client_stub.dart' as stub;

NetworkToolsClient createNetworkToolsClient() => NativeRuntime.current == null
    ? stub.createNetworkToolsClient()
    : MacNetworkToolsClient(NativeRuntime.current!);

class MacNetworkToolsClient implements NetworkToolsClient {
  MacNetworkToolsClient(this.runtime);
  final NativeRuntime runtime;
  @override
  Map<String, dynamic> environment() => Map.of(runtime.environment);
  @override
  Map<String, dynamic> history() {
    try {
      final raw = runtime.store.read('shike.network.history.v1');
      final values = raw == null ? [] : jsonDecode(raw);
      return {
        'available': runtime.store.available,
        'items': values is List ? values.take(20).toList() : [],
      };
    } catch (_) {
      return {'available': false, 'items': []};
    }
  }

  @override
  bool clearHistory() {
    final saved = runtime.write('shike.network.history.v1', '[]');
    runtime.call('clearHistory', {}).catchError((Object _) => null);
    return saved;
  }

  @override
  Stream<Map<String, dynamic>> run(
    String kind, {
    Map<String, dynamic> args = const {},
  }) async* {
    await for (final value in runtime.stream(runtime.newToken(), 'network', {
      'kind': kind,
      'args': args,
    })) {
      yield value;
      if (value['status'] != 'running') break;
    }
  }

  @override
  void openUrl(String url) => runtime.openUrl(url);
}
