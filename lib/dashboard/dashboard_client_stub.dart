import 'dashboard_client.dart';

typedef DashboardLoader = Future<DashboardData> Function(
  String module,
  Map<String, dynamic> args, {
  bool refresh,
});

DashboardClient createDashboardClient() =>
    MemoryDashboardClient(persistent: false);

/// Injectable for tests; without a loader it never invents live information.
class MemoryDashboardClient implements DashboardClient {
  MemoryDashboardClient({
    this.preferences,
    this.loader,
    this.persistent = true,
  });

  String? preferences;
  final DashboardLoader? loader;
  final bool persistent;
  final List<String> openedUrls = [];

  @override
  String? readPreferences() => preferences;

  @override
  bool writePreferences(String raw) {
    preferences = raw;
    return persistent;
  }

  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    final handler = loader;
    if (handler != null) return handler(module, args, refresh: refresh);
    throw const DashboardException('实时看板目前仅支持联网网页版，当前没有可用缓存。');
  }

  @override
  void openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      openedUrls.add(url);
    }
  }
}
