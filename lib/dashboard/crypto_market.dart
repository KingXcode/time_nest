const cryptoAssets = {
  'BTCUSDT': ('BTC', '比特币'),
  'ETHUSDT': ('ETH', '以太坊'),
  'BNBUSDT': ('BNB', '币安币'),
  'SOLUSDT': ('SOL', 'Solana'),
  'XRPUSDT': ('XRP', '瑞波币'),
  'DOGEUSDT': ('DOGE', '狗狗币'),
};
const cryptoIntervals = {
  '15m': '15 分钟',
  '1h': '1 小时',
  '4h': '4 小时',
  '1d': '日线',
  '1w': '周线',
};

String cryptoSourceUrl(String symbol) =>
    'https://www.binance.com/en/trade/${cryptoAssets[symbol]!.$1}_USDT?type=spot';

double _number(Map value, String key, {bool positive = false}) {
  final number = value[key];
  if (number is! num || !number.isFinite || (positive && number <= 0)) {
    throw const FormatException('Invalid market number');
  }
  return number.toDouble();
}

int _time(Map value, String key) {
  final time = value[key];
  if (time is! int || time <= 0 || time >= 8640000000000000) {
    throw const FormatException('Invalid market time');
  }
  return time;
}

class CryptoQuote {
  CryptoQuote.fromJson(Map value)
    : symbol = value['symbol'] as String,
      price = _number(value, 'price', positive: true),
      changePercent = _number(value, 'changePercent'),
      high = _number(value, 'high', positive: true),
      low = _number(value, 'low', positive: true),
      volume = _number(value, 'volume'),
      quoteVolume = _number(value, 'quoteVolume'),
      closeTime = _time(value, 'closeTime') {
    if (!cryptoAssets.containsKey(symbol) ||
        high < price ||
        low > price ||
        volume < 0 ||
        quoteVolume < 0 ||
        changePercent < -100) {
      throw const FormatException('Invalid quote');
    }
  }
  final String symbol;
  final double price, changePercent, high, low, volume, quoteVolume;
  final int closeTime;
}

class CryptoCandle {
  CryptoCandle.fromJson(Map value)
    : time = _time(value, 'time'),
      closeTime = _time(value, 'closeTime'),
      open = _number(value, 'open', positive: true),
      high = _number(value, 'high', positive: true),
      low = _number(value, 'low', positive: true),
      close = _number(value, 'close', positive: true),
      volume = _number(value, 'volume'),
      quoteVolume = _number(value, 'quoteVolume') {
    if (closeTime < time ||
        high < open ||
        high < close ||
        low > open ||
        low > close ||
        volume < 0 ||
        quoteVolume < 0) {
      throw const FormatException('Invalid candle');
    }
  }
  final int time, closeTime;
  final double open, high, low, close, volume, quoteVolume;
}

String cryptoPrice(double value) {
  final digits = value.abs() >= 10
      ? 2
      : value.abs() >= 1
      ? 4
      : 6;
  final parts = value.toStringAsFixed(digits).split('.');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return parts.join('.');
}

String cryptoVolume(double value) {
  final magnitude = value.abs();
  final body = magnitude >= 100000000
      ? '${(magnitude / 100000000).toStringAsFixed(2)} 亿'
      : magnitude >= 10000
      ? '${(magnitude / 10000).toStringAsFixed(2)} 万'
      : magnitude.toStringAsFixed(2);
  return '${value < 0 ? '−' : ''}$body';
}

String cryptoTime(int milliseconds, {bool seconds = false}) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    milliseconds,
    isUtc: true,
  ).add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}${seconds ? ':${two(date.second)}' : ''}';
}

/// UI aggregation steps derive from Binance PRICE_FILTER, never the decimals
/// accidentally present in a particular depth snapshot.
class CryptoPriceRule {
  CryptoPriceRule.fromJson(Map value) {
    final raw = value['tickSize'];
    if (!cryptoAssets.containsKey(value['symbol']) ||
        raw is! String ||
        !RegExp(r'^\d{1,12}(?:\.\d{1,8})?$').hasMatch(raw)) {
      throw const FormatException('Invalid price rule');
    }
    symbol = value['symbol'] as String;
    tickSize = double.parse(raw);
    if (!tickSize.isFinite || tickSize <= 0 || tickSize > 1e8) {
      throw const FormatException('Invalid tick size');
    }
    final fraction = raw.contains('.') ? raw.split('.')[1] : '';
    decimals = fraction.replaceFirst(RegExp(r'0+$'), '').length;
  }
  late final String symbol;
  late final double tickSize;
  late final int decimals;
  List<double> get steps => [
    for (final multiplier in [1, 10, 100, 1000, 10000])
      double.parse((tickSize * multiplier).toStringAsFixed(decimals)),
  ];
  String label(double step) {
    final value = step.toStringAsFixed(decimals);
    return value.contains('.')
        ? value.replaceFirst(RegExp(r'\.?0+$'), '')
        : value;
  }
}
