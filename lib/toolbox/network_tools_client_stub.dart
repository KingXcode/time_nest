import 'network_tools_client.dart';

NetworkToolsClient createNetworkToolsClient() => _UnavailableClient();

class _UnavailableClient implements NetworkToolsClient {
  @override
  Map<String, dynamic> environment() => const {};

  @override
  Map<String, dynamic> history() => const {'available': false, 'items': []};

  @override
  bool clearHistory() => false;

  @override
  Stream<Map<String, dynamic>> run(
    String kind, {
    Map<String, dynamic> args = const {},
  }) => Stream.value({
    'kind': kind,
    'status': 'error',
    'stage': 'done',
    'message': '此工具需要支持网络请求的浏览器环境。',
    'result': <String, dynamic>{},
  });

  @override
  void openUrl(String url) {}
}
