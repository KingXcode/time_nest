const cryptoAssets = {
  'BTCUSDT': ('BTC', '比特币'),
  'ETHUSDT': ('ETH', '以太坊'),
  'BNBUSDT': ('BNB', '币安币'),
  'SOLUSDT': ('SOL', 'Solana'),
  'XRPUSDT': ('XRP', '瑞波币'),
  'DOGEUSDT': ('DOGE', '狗狗币'),
};
// Symbols are validated syntactically here; the provider verifies availability
// against Binance exchangeInfo before requesting non-default markets.
bool isCryptoSymbol(Object? value) =>
    value is String &&
    RegExp(r'^[\p{L}\p{N}]{2,40}$', unicode: true).hasMatch(value);

class CryptoPair {
  const CryptoPair({
    required this.symbol,
    required this.baseAsset,
    required this.quoteAsset,
  });

  factory CryptoPair.fromJson(Map value) {
    final symbol = value['symbol'];
    final base = value['baseAsset'], quote = value['quoteAsset'];
    final assetPattern = RegExp(r'^[\p{L}\p{N}]{1,20}$', unicode: true);
    if (!isCryptoSymbol(symbol) ||
        base is! String ||
        quote is! String ||
        !assetPattern.hasMatch(base) ||
        !assetPattern.hasMatch(quote) ||
        base == quote ||
        symbol != '$base$quote') {
      throw const FormatException('Invalid spot pair');
    }
    return CryptoPair(
      symbol: symbol as String,
      baseAsset: base,
      quoteAsset: quote,
    );
  }

  final String symbol, baseAsset, quoteAsset;
  String get name => cryptoAssets['${baseAsset}USDT']?.$2 ?? baseAsset;
}

final Map<String, CryptoPair> _cryptoPairs = {
  for (final entry in cryptoAssets.entries)
    entry.key: CryptoPair(
      symbol: entry.key,
      baseAsset: entry.value.$1,
      quoteAsset: 'USDT',
    ),
};

CryptoPair? cryptoPairForSymbol(String symbol) => _cryptoPairs[symbol];
String cryptoBaseAsset(String symbol) =>
    _cryptoPairs[symbol]?.baseAsset ?? symbol;
String cryptoQuoteAsset(String symbol) =>
    _cryptoPairs[symbol]?.quoteAsset ?? '—';

List<CryptoPair> readCryptoPairs(Map<String, dynamic> data) {
  final rows = data['pairs'];
  if (rows is! List || rows.isEmpty || rows.length > 10000) {
    throw const FormatException('Invalid spot catalog');
  }
  final pairs = rows.map((row) => CryptoPair.fromJson(row as Map)).toList();
  if (pairs.map((pair) => pair.symbol).toSet().length != pairs.length) {
    throw const FormatException('Duplicate spot pair');
  }
  return pairs;
}

void registerCryptoPairs(List<CryptoPair> pairs) {
  if (pairs.length > 10000) {
    throw const FormatException('Spot catalog too large');
  }
  // Metadata is not authorization. Retain recently seen names for an active
  // snapshot when a refreshed catalog removes a market, without growing forever.
  for (final pair in pairs) {
    _cryptoPairs.remove(pair.symbol);
    _cryptoPairs[pair.symbol] = pair;
  }
  while (_cryptoPairs.length > 10006) {
    _cryptoPairs.remove(
      _cryptoPairs.keys.firstWhere(
        (symbol) => !cryptoAssets.containsKey(symbol),
      ),
    );
  }
}

const cryptoIntervals = {
  '15m': '15 分钟',
  '1h': '1 小时',
  '4h': '4 小时',
  '1d': '日线',
  '1w': '周线',
};

String cryptoSourceUrl(String symbol) {
  final pair = cryptoPairForSymbol(symbol);
  return pair == null
      ? 'https://www.binance.com/en/markets/overview'
      : Uri.https(
          'www.binance.com',
          '/en/trade/${pair.baseAsset}_${pair.quoteAsset}',
          {'type': 'spot'},
        ).toString();
}

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
    if (!isCryptoSymbol(symbol) ||
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
  final minimumDigits = value.abs() >= 10
      ? 2
      : value.abs() >= 1
      ? 4
      : 6;
  // Never round away a valid 1e-8 exchange tick merely because the price is
  // above 0.0001. Keep the familiar minimum precision without false zeros.
  var text = value.toStringAsFixed(8);
  while (text.endsWith('0') &&
      text.length - text.indexOf('.') - 1 > minimumDigits) {
    text = text.substring(0, text.length - 1);
  }
  final parts = text.split('.');
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
      : magnitude > 0 && magnitude < 1
      ? magnitude
            .toStringAsFixed(8)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
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
    if (!isCryptoSymbol(value['symbol']) ||
        raw is! String ||
        !RegExp(r'^\d{1,12}(?:\.\d{1,8})?$').hasMatch(raw)) {
      throw const FormatException('Invalid price rule');
    }
    final step = value['stepSize'];
    final base = value['baseAssetPrecision'],
        quote = value['quoteAssetPrecision'];
    if (step is! String ||
        !RegExp(r'^\d{1,12}(?:\.\d{1,20})?$').hasMatch(step) ||
        double.parse(step) <= 0 ||
        double.parse(step) > 1e8 ||
        base is! int ||
        base < 0 ||
        base > 20 ||
        quote is! int ||
        quote < 0 ||
        quote > 20) {
      throw const FormatException('Invalid asset precision');
    }
    quantityDecimals = (step.contains('.') ? step.split('.')[1] : '')
        .replaceFirst(RegExp(r'0+$'), '')
        .length;
    if (quantityDecimals > base) {
      throw const FormatException('Invalid quantity precision');
    }
    amountDecimals = quote;
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
  late final int decimals, quantityDecimals, amountDecimals;
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
