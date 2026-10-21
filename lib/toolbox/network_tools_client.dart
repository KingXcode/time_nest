import 'network_tools_client_stub.dart'
    if (dart.library.js_interop) 'network_tools_client_web.dart'
    as implementation;

/// Network work begins only when [run] is listened to. Cancelling the stream
/// aborts in-flight requests. Only bounded metric summaries are saved locally;
/// DNS queries and IP addresses are never persisted.
abstract class NetworkToolsClient {
  Map<String, dynamic> environment();
  Map<String, dynamic> history();
  bool clearHistory();
  Stream<Map<String, dynamic>> run(
    String kind, {
    Map<String, dynamic> args = const {},
  });
  void openUrl(String url);
}

NetworkToolsClient createNetworkToolsClient() =>
    implementation.createNetworkToolsClient();
