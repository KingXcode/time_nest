import 'dashboard_client_stub.dart'
    if (dart.library.io) 'dashboard_client_native.dart'
    if (dart.library.js_interop) 'dashboard_client_web.dart'
    as implementation;

/// A normalized response. A stale result always retains its original fetch time.
class DashboardData {
  const DashboardData({
    required this.data,
    required this.fetchedAt,
    this.stale = false,
    this.cached = false,
    this.warning,
  });

  final Map<String, dynamic> data;
  final DateTime fetchedAt;
  final bool stale;
  final bool cached;
  final String? warning;
}

abstract class DashboardClient {
  String? readPreferences();
  bool writePreferences(String raw);
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  });
  void openUrl(String url);
}

DashboardClient createDashboardClient() =>
    implementation.createDashboardClient();

class DashboardException implements Exception {
  const DashboardException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Optional live updates for cache-first exchange rules.
abstract interface class CryptoRulesUpdates {
  Stream<DashboardData> watchCryptoRules();
}

/// Optional cancellation for the selected market's transient REST requests.
abstract interface class CryptoRequestCancellation {
  void cancelCryptoRequests(String symbol);
}
