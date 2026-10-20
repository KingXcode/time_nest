import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'dashboard_client.dart';

@JS('timeNestDashboard.request')
external JSPromise<JSString> _request(
  JSString module,
  JSString args,
  JSBoolean refresh,
);
@JS('timeNestDashboard.subscribeCryptoRules')
external JSString _subscribeRules(JSFunction callback);
@JS('timeNestDashboard.unsubscribeCryptoRules')
external void _unsubscribeRules(JSString id);
@JS('timeNestDashboard.readPreferences')
external JSString? _readPreferences();
@JS('timeNestDashboard.writePreferences')
external JSBoolean _writePreferences(JSString raw);
@JS('timeNestDashboard.openUrl')
external void _openUrl(JSString url);

DashboardClient createDashboardClient() => WebDashboardClient();

DashboardData _decodeData(String raw) {
  final envelope = jsonDecode(raw) as Map<String, dynamic>;
  final data = envelope['data'];
  final fetchedAt = DateTime.tryParse(envelope['fetchedAt'] as String? ?? '');
  if (data is! Map<String, dynamic> || fetchedAt == null) {
    throw const DashboardException('数据服务返回格式异常，请稍后重试。');
  }
  return DashboardData(
    data: data,
    fetchedAt: fetchedAt,
    stale: envelope['stale'] == true,
    cached: envelope['cached'] == true,
    warning: envelope['warning'] as String?,
  );
}

class WebDashboardClient implements DashboardClient, CryptoRulesUpdates {
  @override
  Stream<DashboardData> watchCryptoRules() {
    JSString? id;
    late StreamController<DashboardData> controller;
    controller = StreamController(
      onListen: () {
        id = _subscribeRules(
          ((JSString raw) {
            if (controller.isClosed) return;
            try {
              controller.add(_decodeData(raw.toDart));
            } catch (_) {
              /* Ignore invalid updates. */
            }
          }).toJS,
        );
      },
      onCancel: () {
        if (id != null) _unsubscribeRules(id!);
      },
    );
    return controller.stream;
  }

  @override
  String? readPreferences() {
    try {
      return _readPreferences()?.toDart;
    } catch (_) {
      return null;
    }
  }

  @override
  bool writePreferences(String raw) {
    try {
      return _writePreferences(raw.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    try {
      final raw = await _request(
        module.toJS,
        jsonEncode(args).toJS,
        refresh.toJS,
      ).toDart;
      final envelope = jsonDecode(raw.toDart);
      if (envelope is! Map<String, dynamic>) {
        throw const DashboardException('数据服务返回格式异常，请稍后重试。');
      }
      if (envelope['error'] case final String error) {
        throw DashboardException(error);
      }
      final data = envelope['data'];
      final fetchedAt = DateTime.tryParse(
        envelope['fetchedAt'] as String? ?? '',
      );
      if (data is! Map<String, dynamic> || fetchedAt == null) {
        throw const DashboardException('数据服务返回格式异常，请稍后重试。');
      }
      return DashboardData(
        data: data,
        fetchedAt: fetchedAt,
        stale: envelope['stale'] == true,
        cached: envelope['cached'] == true,
        warning: envelope['warning'] is String
            ? envelope['warning'] as String
            : null,
      );
    } on DashboardException {
      rethrow;
    } catch (error) {
      // Rejected JavaScript promises retain the provider's Chinese explanation.
      final message = error.toString().replaceFirst(RegExp(r'^Error:\s*'), '');
      if (RegExp(r'[\u3400-\u9FFF]').hasMatch(message) &&
          message.length < 600) {
        throw DashboardException(message);
      }
      throw const DashboardException('无法连接实时看板，请检查网络或刷新页面。');
    }
  }

  @override
  void openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      _openUrl(url.toJS);
    } catch (_) {
      // External links are optional; a blocked popup must not crash the clock.
    }
  }
}
