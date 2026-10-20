class CryptoViewSettings {
  const CryptoViewSettings({
    this.orderBook = true,
    this.trades = true,
    this.tradeAmount = true,
    this.timeline = true,
    this.indicatorValues = true,
    this.assessment = true,
    this.tradeRows = 50,
  });
  final bool orderBook,
      trades,
      tradeAmount,
      timeline,
      indicatorValues,
      assessment;
  final int tradeRows;

  factory CryptoViewSettings.decode(Object? raw) {
    if (raw is! Map) return const CryptoViewSettings();
    bool enabled(String key) => raw[key] is bool ? raw[key] as bool : true;
    return CryptoViewSettings(
      orderBook: enabled('orderBook'),
      trades: enabled('trades'),
      tradeAmount: enabled('tradeAmount'),
      timeline: enabled('timeline'),
      indicatorValues: enabled('indicatorValues'),
      assessment: enabled('assessment'),
      tradeRows:
          raw['tradeRows'] is int &&
              const [20, 50, 100].contains(raw['tradeRows'])
          ? raw['tradeRows'] as int
          : 50,
    );
  }
  Map<String, dynamic> toJson() => {
    'orderBook': orderBook,
    'trades': trades,
    'tradeAmount': tradeAmount,
    'timeline': timeline,
    'indicatorValues': indicatorValues,
    'assessment': assessment,
    'tradeRows': tradeRows,
  };
  CryptoViewSettings change(String key, Object value) =>
      CryptoViewSettings.decode({...toJson(), key: value});
}
