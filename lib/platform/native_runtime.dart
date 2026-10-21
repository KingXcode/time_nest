import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_store.dart';

Future<void> initializeNativeRuntime() async {
  if (!Platform.isMacOS || NativeRuntime.current != null) return;
  final runtime = NativeRuntime();
  try {
    await runtime.initialize();
    NativeRuntime.current = runtime;
  } catch (_) {
    runtime.dispose();
    rethrow;
  }
}

class NativeRuntime extends ChangeNotifier {
  NativeRuntime({
    this.channel = const MethodChannel('com.kingxcode.shike/macos'),
  });
  static NativeRuntime? current;
  final MethodChannel channel;
  late NativeStore store;
  Map<String, dynamic> hostState = {};
  Map<String, dynamic> environment = {};
  final _pending = <String, Completer<dynamic>>{};
  final _streams = <String, StreamController<Map<String, dynamic>>>{};
  int _serial = 0;

  Future<void> initialize() async {
    channel.setMethodCallHandler(_event);
    final path = await channel.invokeMethod<String>('supportDirectory');
    if (path == null) throw StateError('无法创建 Mac 本地存储目录。');
    store = NativeStore(Directory(path));
    final scripts = await Future.wait([
      rootBundle.loadString('assets/macos_runtime.js'),
      rootBundle.loadString('web/dashboard.js'),
      rootBundle.loadString('web/network_tools.js'),
    ]);
    await channel
        .invokeMethod<void>('startService', {
          'scripts': scripts,
          'storage': store.snapshot,
        })
        .timeout(const Duration(seconds: 15));
    hostState = Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('state') ?? {},
    );
    environment = Map<String, dynamic>.from(
      jsonDecode(await call('environment', {}) as String) as Map,
    );
  }

  Future<dynamic> _event(MethodCall event) async {
    if (event.method != 'serviceEvent') return;
    final raw = event.arguments is String
        ? jsonDecode(event.arguments as String)
        : event.arguments;
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    switch (data['type']) {
      case 'reply':
        final pending = _pending.remove(data['id']);
        if (data['error'] is String) {
          pending?.completeError(StateError(data['error'] as String));
        } else {
          pending?.complete(data['value']);
        }
      case 'event':
        final stream = _streams[data['token']];
        if (stream != null && !stream.isClosed && data['value'] is Map) {
          stream.add(Map<String, dynamic>.from(data['value'] as Map));
        }
      case 'storage':
        if (data['key'] is String &&
            (data['value'] == null || data['value'] is String)) {
          store.write(data['key'] as String, data['value'] as String?);
          notifyListeners();
        }
      case 'state':
        hostState = Map<String, dynamic>.from(data['state'] as Map);
        notifyListeners();
      case 'engineError':
        for (final pending in _pending.values) {
          pending.completeError(StateError('数据服务已中断，请重新打开应用。'));
        }
        _pending.clear();
        for (final stream in _streams.values) {
          if (!stream.isClosed) stream.addError(StateError('Mac 数据服务已中断。'));
        }
    }
  }

  Future<dynamic> call(String method, Map<String, dynamic> args) async {
    final id = '${++_serial}', pending = Completer<dynamic>();
    _pending[id] = pending;
    // Attach the handler before dispatch, including synchronous host failures.
    final result = pending.future.timeout(const Duration(seconds: 60));
    try {
      unawaited(
        channel
            .invokeMethod<void>('serviceCall', {
              'id': id,
              'method': method,
              'args': args,
            })
            .catchError((Object e, StackTrace stack) {
              if (!pending.isCompleted) pending.completeError(e, stack);
            }),
      );
      return await result;
    } finally {
      _pending.remove(id);
    }
  }

  String newToken() => 'stream-${++_serial}';
  Stream<Map<String, dynamic>> stream(
    String token,
    String kind,
    Map<String, dynamic> args, {
    void Function()? onListen,
    void Function()? onCancel,
  }) {
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController(
      onListen: () {
        onListen?.call();
        _streams[token] = controller;
        call('subscribe', {
          'token': token,
          'kind': kind,
          'args': args,
        }).catchError((Object e) {
          if (!controller.isClosed) controller.addError(e);
          return null;
        });
      },
      onCancel: () {
        onCancel?.call();
        _streams.remove(token);
        unawaited(
          call('cancel', {'token': token}).catchError((Object _) => null),
        );
      },
    );
    return controller.stream;
  }

  bool write(String key, String? value) {
    final saved = store.write(key, value);
    if (saved) {
      unawaited(
        call('storageSet', {
          'key': key,
          'value': value,
        }).catchError((Object _) => null),
      );
    }
    notifyListeners();
    return saved;
  }

  void host(String method, [dynamic args]) {
    unawaited(
      channel.invokeMethod<void>(method, args).catchError((Object _) {}),
    );
  }

  void openUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    host('openUrl', raw);
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Mac 数据服务已关闭。'));
      }
    }
    _pending.clear();
    super.dispose();
  }
}
