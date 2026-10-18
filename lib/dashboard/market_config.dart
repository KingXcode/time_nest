/// Fixed public symbols only. Never accept a URL or arbitrary widget options.
class MarketIndex {
  const MarketIndex(this.id, this.name, this.symbol, this.description);
  final String id;
  final String name;
  final String symbol;
  final String description;
  String get sourceUrl =>
      'https://www.tradingview.com/symbols/${symbol.replaceAll(':', '-')}/';
}

const marketIndices = [
  MarketIndex('shanghai', '上证指数', 'SSE:000001', '观察上海市场整体走势'),
  MarketIndex('shenzhen', '深证成指', 'SZSE:399001', '观察深圳市场代表性公司'),
  MarketIndex('csi300', '沪深300', 'SSE:000300', '观察沪深大盘股走势'),
  MarketIndex('chinext', '创业板指', 'SZSE:399006', '观察创业板代表性公司'),
  MarketIndex('star50', '科创50', 'SSE:000688', '观察科创板代表性公司'),
  MarketIndex('allshare', '中证全指', 'SSE:000985', '从更广范围观察 A 股走势'),
];
const marketIntervals = {'D': '日线', 'W': '周线', 'M': '月线'};
MarketIndex marketIndexFor(String id) => marketIndices.firstWhere(
  (index) => index.id == id,
  orElse: () => marketIndices.first,
);
