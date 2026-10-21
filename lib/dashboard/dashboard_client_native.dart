import 'dart:convert';

import '../platform/native_runtime.dart';
import 'dashboard_client.dart';
import 'dashboard_client_stub.dart';

DashboardClient createDashboardClient() => NativeRuntime.current == null
    ? MemoryDashboardClient(persistent: false)
    : MacDashboardClient(NativeRuntime.current!);

DashboardData decodeNativeData(dynamic raw) {
  final value = jsonDecode(raw as String) as Map<String, dynamic>;
  if (value['error'] is String) {
    throw DashboardException(value['error'] as String);
  }
  final time = DateTime.tryParse(value['fetchedAt'] as String? ?? '');
  if (value['data'] is! Map<String, dynamic> || time == null) {
    throw const DashboardException('数据返回格式异常。');
  }
  return DashboardData(
    data: value['data'] as Map<String, dynamic>,
    fetchedAt: time,
    stale: value['stale'] == true,
    cached: value['cached'] == true,
    warning: value['warning'] as String?,
  );
}

class MacDashboardClient
    implements DashboardClient, CryptoRulesUpdates, CryptoRequestCancellation {
  MacDashboardClient(this.runtime);
  final NativeRuntime runtime;
  @override
  String? readPreferences() =>
      runtime.store.read('shike.dashboard.preferences.v1');
  @override
  bool writePreferences(String raw) =>
      runtime.write('shike.dashboard.preferences.v1', raw);
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    try {
      return decodeNativeData(
        await runtime.call('request', {
          'module': module,
          'args': args,
          'refresh': refresh,
        }),
      );
    } on DashboardException {
      rethrow;
    } catch (e) {
      final text = e.toString().replaceFirst(RegExp(r'^Bad state: '), '');
      throw DashboardException(
        RegExp(r'[\u3400-\u9fff]').hasMatch(text) && text.length < 600
            ? text
            : '无法连接数据服务，请检查网络后重试。',
      );
    }
  }

  @override
  Stream<DashboardData> watchCryptoRules() => runtime
      .stream(runtime.newToken(), 'rules', {})
      .map((value) => decodeNativeData(jsonEncode(value)));
  @override
  void cancelCryptoRequests(String symbol) {
    runtime
        .call('cancelRequests', {'symbol': symbol})
        .catchError((Object _) => null);
  }

  @override
  void openUrl(String url) => runtime.openUrl(url);
}
