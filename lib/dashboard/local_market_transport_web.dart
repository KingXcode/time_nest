// Isolated to this project's JavaScript Web build, like the existing bridge.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'local_market_config.dart';

Future<Map<String, dynamic>> requestLocalMarket(
  String indexId, {
  bool refresh = false,
}) async {
  final base = Uri.base;
  if (base.scheme != 'http' ||
      !const {'127.0.0.1', 'localhost'}.contains(base.host) ||
      base.userInfo.isNotEmpty ||
      !localMarketCodes.containsKey(indexId)) {
    throw UnsupportedError(
      'Personal research transport is available only on localhost.',
    );
  }
  final uri = base.replace(
    path: '/api/market-history',
    fragment: '',
    queryParameters: {'index': indexId, if (refresh) 'refresh': '1'},
  );
  final request = html.HttpRequest();
  final result = Completer<Map<String, dynamic>>();
  void fail(Object error) {
    if (!result.isCompleted) result.completeError(error);
  }

  request.open('GET', uri.toString());
  request.timeout = 97000;
  final subscriptions = [
    request.onLoad.listen((_) {
      if (result.isCompleted) return;
      try {
        if (request.status != 200) {
          throw StateError('Local provider request failed');
        }
        final body = request.responseText ?? '';
        if (body.length > 1000000) {
          throw const FormatException('Response too large');
        }
        final value = jsonDecode(body);
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid response');
        }
        result.complete(value);
      } catch (error) {
        fail(error);
      }
    }),
    request.onError.listen(
      (_) => fail(StateError('Local provider connection failed')),
    ),
    request.onTimeout.listen(
      (_) => fail(TimeoutException('Local provider timed out')),
    ),
    request.onAbort.listen(
      (_) => fail(StateError('Local provider request aborted')),
    ),
  ];
  try {
    request.send();
    return await result.future;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    if (request.readyState != html.HttpRequest.DONE) request.abort();
  }
}
