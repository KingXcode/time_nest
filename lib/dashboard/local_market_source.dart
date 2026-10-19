import 'market_history.dart';
import 'local_market_config.dart';
import 'local_market_transport_stub.dart'
    if (dart.library.js_interop) 'local_market_transport_web.dart'
    as transport;

typedef LocalMarketRequest = Future<Map<String, dynamic>> Function(
  String indexId, {
  bool refresh,
});

class LocalMarketHistorySource implements MarketHistorySource {
  LocalMarketHistorySource({
    LocalMarketRequest? request,
    DateTime Function()? now,
  }) : _request = request ?? transport.requestLocalMarket,
       _now = now ?? DateTime.now;
  final LocalMarketRequest _request;
  final DateTime Function() _now;

  @override
  Future<MarketHistory> load(String indexId, {bool refresh = false}) async {
    if (!localMarketCodes.containsKey(indexId)) {
      throw const FormatException('Unsupported local index');
    }
    final value = await _request(indexId, refresh: refresh);
    if (value['schemaVersion'] != 1 ||
        value['indexId'] != indexId ||
        value['code'] != localMarketCodes[indexId] ||
        value['frequency'] != 'd' ||
        value['timezone'] != 'Asia/Shanghai' ||
        value['cached'] is! bool ||
        !const {'unverified', 'stale'}.contains(value['freshness'])) {
      throw const FormatException('Invalid local history identity');
    }
    final rawTime = value['fetchedAt'];
    if (rawTime is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|\+00:00)$',
        ).hasMatch(rawTime)) {
      throw const FormatException('Invalid retrieval timestamp');
    }
    MarketSessionDate.parse(rawTime.substring(0, 10));
    final fetchedAt = DateTime.tryParse(rawTime);
    if (fetchedAt == null ||
        fetchedAt.isAfter(_now().toUtc().add(const Duration(minutes: 5)))) {
      throw const FormatException('Future retrieval timestamp');
    }
    final startValue = value['startDate'], endValue = value['endDate'];
    if (startValue is! String || endValue is! String) {
      throw const FormatException('Missing query dates');
    }
    final start = MarketSessionDate.parse(startValue);
    final end = MarketSessionDate.parse(endValue);
    final shanghaiToday = MarketSessionDate.parse(
      fetchedAt
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(0, 10),
    );
    if (DateTime.parse('${end.label}T00:00:00Z')
                .difference(DateTime.parse('${start.label}T00:00:00Z'))
                .inDays !=
            29 ||
        end.compareTo(shanghaiToday) >= 0) {
      throw const FormatException('Invalid closed-day window');
    }
    final rows = value['rows'];
    if (rows is! List || rows.length > 30) {
      throw const FormatException('Invalid history rows');
    }
    final result = MarketHistory.fromRows(
      indexId: indexId,
      rows: rows.cast<Object?>(),
      fetchedAt: fetchedAt,
      freshness: value['freshness'] == 'stale'
          ? HistoryFreshness.stale
          : HistoryFreshness.unverified,
      source: MarketHistoryAttribution(
        name: 'BaoStock · 本机个人研究',
        url: Uri.parse(
          'https://www.baostock.com/mainContent?file=indexData.md',
        ),
        timingNote:
            '查询范围：${start.label} 至 ${end.label}，不包含今日未收盘数据。'
            '仅展示 BaoStock 返回的日线收盘记录，尚未核实最新交易日是否齐全。'
            '${value['cached'] == true ? '本次读取本地缓存。' : ''}'
            '${value['freshness'] == 'stale' ? '本次更新未成功或缓存已过期，请稍后重试。' : ''}',
      ),
    );
    if (result.closes.any(
      (row) => row.date.compareTo(start) < 0 || row.date.compareTo(end) > 0,
    )) {
      throw const FormatException('Session outside query window');
    }
    return result;
  }
}
