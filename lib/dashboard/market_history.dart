import 'market_config.dart';

/// Public deployments require separate permission for public display. The
/// localhost personal-research adapter is opt-in; there is no default provider.
abstract interface class MarketHistorySource {
  Future<MarketHistory> load(String indexId, {bool refresh = false});
}

enum HistoryFreshness { unverified, verifiedThroughDate, stale }

/// An exchange session date, not an instant. Never convert it to local time.
class MarketSessionDate implements Comparable<MarketSessionDate> {
  MarketSessionDate._(this.label, this._order);

  factory MarketSessionDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid session date');
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final date = DateTime.utc(year, month, day);
    if (year < 1900 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const FormatException('Invalid session date');
    }
    return MarketSessionDate._(value, year * 10000 + month * 100 + day);
  }

  final String label;
  final int _order;

  @override
  int compareTo(MarketSessionDate other) => _order.compareTo(other._order);
}

class MarketClose {
  MarketClose({required this.date, required this.close}) {
    if (!close.isFinite || close <= 0) {
      throw const FormatException('Invalid closing value');
    }
  }

  final MarketSessionDate date;
  final double close;
}

class MarketHistoryAttribution {
  MarketHistoryAttribution({
    required this.name,
    required this.url,
    required this.timingNote,
  }) {
    if (name.trim().isEmpty ||
        timingNote.trim().isEmpty ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const FormatException('Invalid source attribution');
    }
  }

  final String name;
  final Uri url;
  final String timingNote;
}

/// Normalized official daily closes, in index points, dated Asia/Shanghai.
/// [fetchedAt] is retrieval time, never a replacement for the last session date.
/// Freshness must come from a verified provider/calendar rule, not a guessed
/// weekday rule. The safe default is unverified, including on holidays.
class MarketHistory {
  MarketHistory({
    required this.indexId,
    required Iterable<MarketClose> closes,
    required this.source,
    required DateTime fetchedAt,
    this.freshness = HistoryFreshness.unverified,
  }) : closes = List.unmodifiable(closes),
       fetchedAt = fetchedAt.toUtc() {
    if (!marketIndices.any((index) => index.id == indexId) ||
        this.closes.length > 5000) {
      throw const FormatException('Invalid history identity or size');
    }
    final shanghai = this.fetchedAt.add(const Duration(hours: 8));
    final lastPossibleDate = MarketSessionDate.parse(
      shanghai.toIso8601String().substring(0, 10),
    );
    for (var i = 0; i < this.closes.length; i++) {
      final date = this.closes[i].date;
      if (date.compareTo(lastPossibleDate) > 0 ||
          (i > 0 && date.compareTo(this.closes[i - 1].date) <= 0)) {
        throw const FormatException('Unordered, repeated or future session');
      }
    }
  }

  /// A small transport-neutral decoder. Attribution and retrieval metadata
  /// are supplied by the trusted adapter, never accepted from arbitrary URLs.
  factory MarketHistory.fromRows({
    required String indexId,
    required List<Object?> rows,
    required MarketHistoryAttribution source,
    required DateTime fetchedAt,
    HistoryFreshness freshness = HistoryFreshness.unverified,
  }) {
    if (rows.length > 5000) {
      throw const FormatException('Too many history rows');
    }
    return MarketHistory(
      indexId: indexId,
      closes: rows.map((row) {
        if (row is! Map || row['date'] is! String || row['close'] is! num) {
          throw const FormatException('Invalid history row');
        }
        return MarketClose(
          date: MarketSessionDate.parse(row['date'] as String),
          close: (row['close'] as num).toDouble(),
        );
      }),
      source: source,
      fetchedAt: fetchedAt,
      freshness: freshness,
    );
  }

  final String indexId;
  final List<MarketClose> closes;
  final MarketHistoryAttribution source;
  final DateTime fetchedAt;
  final HistoryFreshness freshness;
  MarketSessionDate? get asOf => closes.isEmpty ? null : closes.last.date;
}
