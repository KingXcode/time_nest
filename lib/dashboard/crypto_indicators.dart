import 'dart:math' as math;

import 'crypto_market.dart';

typedef Values = List<double?>;

class IndicatorSpec {
  const IndicatorSpec(this.name, this.formula, {this.overlay = false});
  final String name, formula;
  final bool overlay;
}

// Parameters are explicit and stable. Missing warm-up values stay null, never 0.
const cryptoIndicators = <String, IndicatorSpec>{
  'ma': IndicatorSpec('MA 均线', 'SMA(5,10,20)，收盘价算术平均', overlay: true),
  'ema': IndicatorSpec(
    'EMA 指数均线',
    'EMA(12,26)，SMA 种子，α=2/(N+1)',
    overlay: true,
  ),
  'wma': IndicatorSpec('WMA 加权均线', 'WMA(20)，近期权重 20，远期权重 1', overlay: true),
  'boll': IndicatorSpec('BOLL 布林带', 'SMA(20) ± 2×总体标准差(20)', overlay: true),
  'donchian': IndicatorSpec('DC 唐奇安通道', '20 根最高、最低及中线，包含当前 K 线', overlay: true),
  'keltner': IndicatorSpec('KC 肯特纳通道', 'EMA(20) ± 2×ATR(10)', overlay: true),
  'vwma': IndicatorSpec('VWMA 量加权均线', 'Σ(收盘×成交量)/Σ成交量，20 根', overlay: true),
  'hma': IndicatorSpec(
    'HMA 赫尔均线',
    'WMA(2×WMA(C,10)−WMA(C,20),4)',
    overlay: true,
  ),
  'dema': IndicatorSpec(
    'DEMA 双指数均线',
    '2×EMA(C,20)−EMA(EMA(C,20),20)',
    overlay: true,
  ),
  'tema': IndicatorSpec(
    'TEMA 三指数均线',
    '3×EMA1−3×EMA2+EMA3，各级周期20',
    overlay: true,
  ),
  'bbi': IndicatorSpec('BBI 多空均线', '(SMA3+SMA6+SMA12+SMA24)/4', overlay: true),
  'env': IndicatorSpec('ENV 包络线', 'SMA(20) 上下 2% 包络', overlay: true),
  'vol': IndicatorSpec('VOL 成交量', '基础币成交量及 SMA(5,10)'),
  'amount': IndicatorSpec('AMOUNT 成交额', '当前计价币成交额'),
  'macd': IndicatorSpec('MACD', 'DIF=EMA12−EMA26；DEA=EMA(DIF,9)；柱=DIF−DEA'),
  'rsi': IndicatorSpec('RSI 相对强弱', 'Wilder RMA(涨幅/跌幅,14)，平盘为50'),
  'kdj': IndicatorSpec('KDJ 随机指标', 'RSV(9)；K、D 递归平滑1/3，初始50；J=3K−2D'),
  'stoch': IndicatorSpec('STOCH 随机振荡', 'RSV(14) 的 SMA3 为K，K 的 SMA3 为D'),
  'stochrsi': IndicatorSpec('Stoch RSI', 'RSI(14) 的14根区间归一化，K/D各平滑3'),
  'wr': IndicatorSpec('WR 威廉指标', '−100×(HH14−C)/(HH14−LL14)，平盘为−50'),
  'cci': IndicatorSpec('CCI 顺势指标', '(典型价−SMA20)/(0.015×平均绝对偏差20)'),
  'atr': IndicatorSpec('ATR 真实波幅', 'Wilder RMA(TR,14)，TR含前收跳空'),
  'natr': IndicatorSpec('NATR 归一化波幅', '100×ATR(14)/收盘价'),
  'adx': IndicatorSpec('DMI / ADX', '+DI、−DI、ADX，Wilder 平滑14'),
  'obv': IndicatorSpec('OBV 能量潮', '收盘上涨加量、下跌减量；以加载窗口首根量为基准'),
  'cmf': IndicatorSpec('CMF 资金流', 'Σ[(2C−H−L)/(H−L)×V]/ΣV，20根'),
  'mfi': IndicatorSpec('MFI 资金流量', '典型价×量的正负资金流比，14根'),
  'roc': IndicatorSpec('ROC 变动率', '100×(C/C[12]−1)'),
  'mom': IndicatorSpec('MOM 动量', 'C−C[10]'),
  'trix': IndicatorSpec('TRIX', '三次 EMA(15) 的单根变化率(%)'),
  'ao': IndicatorSpec('AO 动量震荡', '中间价(H+L)/2 的 SMA5−SMA34'),
  'bias': IndicatorSpec('BIAS 乖离率', '100×(C/SMA(C,N)−1)，N=6,12,24'),
  'dpo': IndicatorSpec('DPO 去趋势', 'C[11]−SMA(C,20)，不向未来移动'),
  'bbw': IndicatorSpec('BBW 布林带宽', '100×(BOLL上轨−下轨)/中轨'),
  'ppo': IndicatorSpec('PPO 价格振荡', '100×(EMA12−EMA26)/EMA26；信号线EMA9'),
  'tsi': IndicatorSpec('TSI 真实强度', '100×EMA13(EMA25(ΔC))/EMA13(EMA25(|ΔC|))'),
};

const defaultCryptoOverlays = ['ma', 'boll'];
const defaultCryptoPanes = ['vol', 'macd', 'rsi'];

List<String> cleanIndicators(
  Object? value, {
  required bool overlay,
  required List<String> fallback,
}) => value is List
    ? value
          .whereType<String>()
          .where((id) => cryptoIndicators[id]?.overlay == overlay)
          .toSet()
          .take(8)
          .toList()
    : List.of(fallback);

class IndicatorLine {
  const IndicatorLine(this.name, this.values, {this.bars = false});
  final String name;
  final Values values;
  final bool bars;
}

class IndicatorStudy {
  const IndicatorStudy(this.id, this.lines, {this.levels = const []});
  final String id;
  final List<IndicatorLine> lines;
  final List<double> levels;
}

Values _map(Values a, double Function(double) fn) => [
  for (final v in a) v == null ? null : fn(v),
];
Values _zip(Values a, Values b, double Function(double, double) fn) => [
  for (var i = 0; i < a.length; i++)
    a[i] == null || b[i] == null ? null : fn(a[i]!, b[i]!),
];
Values _window(Values a, int n, double Function(List<double>) fn) =>
    List.generate(a.length, (i) {
      if (i < n - 1) return null;
      final w = a.sublist(i - n + 1, i + 1);
      return w.any((v) => v == null) ? null : fn(w.cast<double>());
    });
Values sma(Values a, int n) =>
    _window(a, n, (w) => w.reduce((a, b) => a + b) / n);
Values wma(Values a, int n) => _window(a, n, (w) {
  var s = 0.0;
  for (var j = 0; j < n; j++) {
    s += w[j] * (j + 1);
  }
  return s / (n * (n + 1) / 2);
});
Values ema(Values a, int n, {double? alpha}) {
  final out = List<double?>.filled(a.length, null), seed = <double>[];
  double? previous;
  for (var i = 0; i < a.length; i++) {
    final v = a[i];
    if (v == null) {
      previous = null;
      seed.clear();
      continue;
    }
    if (previous == null) {
      seed.add(v);
      if (seed.length < n) continue;
      previous = seed.reduce((a, b) => a + b) / n;
    } else {
      previous += (alpha ?? 2 / (n + 1)) * (v - previous);
    }
    out[i] = previous;
  }
  return out;
}

Values _rma(Values a, int n) => ema(a, n, alpha: 1 / n);
Values _shift(Values a, int n) => [
  for (var i = 0; i < a.length; i++) i < n ? null : a[i - n],
];
Values _ratio(Values a, Values b, {double flat = 0, double scale = 1}) =>
    _zip(a, b, (x, y) => y == 0 ? flat : scale * x / y);

Map<String, IndicatorStudy> calculateCryptoIndicators(List<CryptoCandle> rows) {
  final c = <double?>[for (final r in rows) r.close],
      h = <double?>[for (final r in rows) r.high],
      l = <double?>[for (final r in rows) r.low],
      v = <double?>[for (final r in rows) r.volume];
  final out = <String, IndicatorStudy>{};
  void add(
    String id,
    Map<String, Values> lines, {
    Set<String> bars = const {},
    List<double> levels = const [],
  }) => out[id] = IndicatorStudy(id, [
    for (final e in lines.entries)
      IndicatorLine(e.key, e.value, bars: bars.contains(e.key)),
  ], levels: levels);
  final ma20 = sma(c, 20), e12 = ema(c, 12), e26 = ema(c, 26), e20 = ema(c, 20);
  final e2 = ema(e20, 20), e3 = ema(ema(e20, 20), 20);
  final sd = _window(c, 20, (w) {
    final avg = w.reduce((a, b) => a + b) / 20;
    return math.sqrt(
      w.fold<double>(0, (s, x) => s + math.pow(x - avg, 2)) / 20,
    );
  });
  final upper = _zip(ma20, sd, (m, s) => m + 2 * s),
      lower = _zip(ma20, sd, (m, s) => m - 2 * s);
  final tr = <double?>[
    for (var i = 0; i < rows.length; i++)
      i == 0
          ? rows[i].high - rows[i].low
          : math.max(
              rows[i].high - rows[i].low,
              math.max(
                (rows[i].high - rows[i - 1].close).abs(),
                (rows[i].low - rows[i - 1].close).abs(),
              ),
            ),
  ];
  final atr = _rma(tr, 14), atr10 = _rma(tr, 10);
  final hh20 = _window(h, 20, (w) => w.reduce(math.max)),
      ll20 = _window(l, 20, (w) => w.reduce(math.min));
  add('ma', {'MA5': sma(c, 5), 'MA10': sma(c, 10), 'MA20': ma20});
  add('ema', {'EMA12': e12, 'EMA26': e26});
  add('wma', {'WMA20': wma(c, 20)});
  add('boll', {'中轨': ma20, '上轨': upper, '下轨': lower});
  add('donchian', {
    'DC上': hh20,
    'DC中': _zip(hh20, ll20, (a, b) => (a + b) / 2),
    'DC下': ll20,
  });
  add('keltner', {
    'KC中': e20,
    'KC上': _zip(e20, atr10, (a, b) => a + 2 * b),
    'KC下': _zip(e20, atr10, (a, b) => a - 2 * b),
  });
  add('vwma', {
    'VWMA20': _ratio(
      sma(_zip(c, v, (a, b) => a * b), 20),
      sma(v, 20),
      flat: double.nan,
    ),
  });
  add('hma', {
    'HMA20': wma(_zip(wma(c, 10), wma(c, 20), (a, b) => 2 * a - b), 4),
  });
  add('dema', {'DEMA20': _zip(e20, e2, (a, b) => 2 * a - b)});
  add('tema', {
    'TEMA20': _zip(_zip(e20, e2, (a, b) => 3 * a - 3 * b), e3, (a, b) => a + b),
  });
  add('bbi', {
    'BBI': _map(
      _zip(
        _zip(sma(c, 3), sma(c, 6), (a, b) => a + b),
        _zip(sma(c, 12), sma(c, 24), (a, b) => a + b),
        (a, b) => a + b,
      ),
      (x) => x / 4,
    ),
  });
  add('env', {
    'ENV上': _map(ma20, (x) => x * 1.02),
    'ENV中': ma20,
    'ENV下': _map(ma20, (x) => x * .98),
  });
  add('vol', {'量': v, 'MA5': sma(v, 5), 'MA10': sma(v, 10)}, bars: {'量'});
  add(
    'amount',
    {
      '额': <double?>[for (final r in rows) r.quoteVolume],
    },
    bars: {'额'},
  );
  final dif = _zip(e12, e26, (a, b) => a - b),
      dea = ema(_zip(e12, e26, (a, b) => a - b), 9);
  add(
    'macd',
    {'DIF': dif, 'DEA': dea, '柱': _zip(dif, dea, (a, b) => a - b)},
    bars: {'柱'},
    levels: [0],
  );
  final delta = _zip(c, _shift(c, 1), (a, b) => a - b);
  final gain = _rma(_map(delta, (x) => math.max(x, 0)), 14),
      loss = _rma(_map(delta, (x) => math.max(-x, 0)), 14);
  final rsi = _zip(gain, loss, (g, b) => g + b == 0 ? 50 : 100 * g / (g + b));
  add('rsi', {'RSI14': rsi}, levels: [30, 70]);
  Values stoch(Values input, Values high, Values low, int n) => _ratio(
    _zip(input, _window(low, n, (w) => w.reduce(math.min)), (a, b) => a - b),
    _zip(
      _window(high, n, (w) => w.reduce(math.max)),
      _window(low, n, (w) => w.reduce(math.min)),
      (a, b) => a - b,
    ),
    scale: 100,
    flat: 50,
  );
  final rsv = stoch(c, h, l, 9),
      k = List<double?>.filled(c.length, null),
      d = List<double?>.filled(c.length, null);
  double pk = 50, pd = 50;
  for (var i = 0; i < c.length; i++) {
    if (rsv[i] == null) continue;
    pk = pk * 2 / 3 + rsv[i]! / 3;
    pd = pd * 2 / 3 + pk / 3;
    k[i] = pk;
    d[i] = pd;
  }
  add(
    'kdj',
    {'K': k, 'D': d, 'J': _zip(k, d, (a, b) => 3 * a - 2 * b)},
    levels: [20, 80],
  );
  final sk = sma(stoch(c, h, l, 14), 3), srk = sma(stoch(rsi, rsi, rsi, 14), 3);
  add('stoch', {'%K': sk, '%D': sma(sk, 3)}, levels: [20, 80]);
  add('stochrsi', {'K': srk, 'D': sma(srk, 3)}, levels: [20, 80]);
  add(
    'wr',
    {'WR14': _map(stoch(c, h, l, 14), (x) => x - 100)},
    levels: [-80, -20],
  );
  final tp = <double?>[for (final r in rows) (r.high + r.low + r.close) / 3];
  final md = _window(tp, 20, (w) {
    final avg = w.reduce((a, b) => a + b) / 20;
    return w.fold<double>(0, (s, x) => s + (x - avg).abs()) / 20;
  });
  add(
    'cci',
    {
      'CCI20': _ratio(
        _zip(tp, sma(tp, 20), (a, b) => a - b),
        _map(md, (x) => .015 * x),
      ),
    },
    levels: [-100, 100],
  );
  add('atr', {'ATR14': atr});
  add('natr', {'NATR14': _ratio(atr, c, scale: 100)});
  final plus = <double?>[], minus = <double?>[];
  for (var i = 0; i < rows.length; i++) {
    final up = i == 0 ? 0.0 : rows[i].high - rows[i - 1].high,
        down = i == 0 ? 0.0 : rows[i - 1].low - rows[i].low;
    plus.add(
      i == 0
          ? null
          : up > down && up > 0
          ? up
          : 0,
    );
    minus.add(
      i == 0
          ? null
          : down > up && down > 0
          ? down
          : 0,
    );
  }
  // DM/TR begin on the same second bar for Wilder DMI.
  final dmiTr = List<double?>.of(tr);
  if (dmiTr.isNotEmpty) dmiTr[0] = null;
  final pdi = _ratio(_rma(plus, 14), _rma(dmiTr, 14), scale: 100),
      mdi = _ratio(_rma(minus, 14), _rma(dmiTr, 14), scale: 100);
  final dx = _ratio(
    _zip(pdi, mdi, (a, b) => (a - b).abs()),
    _zip(pdi, mdi, (a, b) => a + b),
    scale: 100,
  );
  add('adx', {'+DI': pdi, '−DI': mdi, 'ADX': _rma(dx, 14)}, levels: [25]);
  double obv = 0;
  final obvs = <double?>[];
  for (var i = 0; i < rows.length; i++) {
    obv += i == 0
        ? rows[i].volume
        : rows[i].close > rows[i - 1].close
        ? rows[i].volume
        : rows[i].close < rows[i - 1].close
        ? -rows[i].volume
        : 0;
    obvs.add(obv);
  }
  add('obv', {'OBV': obvs});
  final flow = <double?>[
    for (final r in rows)
      r.high == r.low
          ? 0
          : (2 * r.close - r.high - r.low) / (r.high - r.low) * r.volume,
  ];
  add('cmf', {'CMF20': _ratio(sma(flow, 20), sma(v, 20))}, levels: [0]);
  final pos = <double?>[], neg = <double?>[];
  for (var i = 0; i < rows.length; i++) {
    final money = tp[i]! * v[i]!;
    pos.add(
      i == 0
          ? null
          : tp[i]! > tp[i - 1]!
          ? money
          : 0,
    );
    neg.add(
      i == 0
          ? null
          : tp[i]! < tp[i - 1]!
          ? money
          : 0,
    );
  }
  add(
    'mfi',
    {
      'MFI14': _zip(
        sma(pos, 14),
        sma(neg, 14),
        (a, b) => a + b == 0 ? 50 : 100 * a / (a + b),
      ),
    },
    levels: [20, 80],
  );
  add(
    'roc',
    {'ROC12': _map(_ratio(c, _shift(c, 12)), (x) => 100 * (x - 1))},
    levels: [0],
  );
  add('mom', {'MOM10': _zip(c, _shift(c, 10), (a, b) => a - b)}, levels: [0]);
  final triple = ema(ema(ema(c, 15), 15), 15);
  add(
    'trix',
    {'TRIX15': _map(_ratio(triple, _shift(triple, 1)), (x) => 100 * (x - 1))},
    levels: [0],
  );
  final median = _zip(h, l, (a, b) => (a + b) / 2);
  add(
    'ao',
    {'AO': _zip(sma(median, 5), sma(median, 34), (a, b) => a - b)},
    bars: {'AO'},
    levels: [0],
  );
  add(
    'bias',
    {
      for (final n in [6, 12, 24])
        'BIAS$n': _map(_ratio(c, sma(c, n)), (x) => 100 * (x - 1)),
    },
    levels: [0],
  );
  add(
    'dpo',
    {'DPO20': _zip(_shift(c, 11), ma20, (a, b) => a - b)},
    levels: [0],
  );
  add('bbw', {
    'BBW20': _ratio(_zip(upper, lower, (a, b) => a - b), ma20, scale: 100),
  });
  final ppo = _ratio(dif, e26, scale: 100),
      signal = ema(_ratio(dif, e26, scale: 100), 9);
  add(
    'ppo',
    {'PPO': ppo, '信号': signal, '柱': _zip(ppo, signal, (a, b) => a - b)},
    bars: {'柱'},
    levels: [0],
  );
  add(
    'tsi',
    {
      'TSI(25,13)': _ratio(
        ema(ema(delta, 25), 13),
        ema(ema(_map(delta, (x) => x.abs()), 25), 13),
        scale: 100,
      ),
    },
    levels: [0],
  );
  // Undefined division (for example VWMA on zero volume) is unavailable.
  for (final study in out.values) {
    for (final line in study.lines) {
      for (var i = 0; i < line.values.length; i++) {
        if (line.values[i]?.isFinite == false) line.values[i] = null;
      }
    }
  }
  return out;
}

class TechnicalVote {
  const TechnicalVote(this.name, this.value, this.direction, this.reason);
  final String name, value, reason;
  final int direction;
}

class CryptoAssessment {
  const CryptoAssessment(this.time, this.votes, this.atrPercent);
  final int time;
  final List<TechnicalVote> votes;
  final double atrPercent;
  int get score => votes.fold(0, (s, v) => s + v.direction);
  String get title => score >= 3
      ? '偏多 · 买入观察'
      : score <= -3
      ? '偏空 · 暂缓买入'
      : '信号分歧 · 观望';
  String get suggestion => score >= 3
      ? '趋势偏多，可关注回踩后再确认的买入机会；不追涨，先确定自己可承受的风险。'
      : score <= -3
      ? '下行信号较多，暂缓新增买入，等待趋势和动量改善。'
      : '指标方向尚未一致，优先观望，等待趋势、动量和量能共同确认。';
}

// Fixed transparent rules, independent of which studies the user chooses to draw.
// Use the latest CLOSED bar only; never derive advice from the live forming bar.
CryptoAssessment? assessCrypto(List<CryptoCandle> rows, int asOf) {
  final closed = rows.where((r) => r.closeTime < asOf).toList();
  if (closed.length < 60) return null;
  final studies = calculateCryptoIndicators(closed), i = closed.length - 1;
  double value(String id, int line) => studies[id]!.lines[line].values[i]!;
  final e12 = value('ema', 0),
      e26 = value('ema', 1),
      hist = value('macd', 2),
      rsi = value('rsi', 0),
      p = value('adx', 0),
      m = value('adx', 1),
      adx = value('adx', 2),
      cmf = value('cmf', 0),
      k = value('stoch', 0),
      d = value('stoch', 1);
  int sign(double x) => x > 0
      ? 1
      : x < 0
      ? -1
      : 0;
  final votes = [
    TechnicalVote(
      'EMA12 / EMA26',
      '${cryptoPrice(e12)} / ${cryptoPrice(e26)}',
      sign(e12 - e26),
      '短均线高于长均线偏多，低于偏空',
    ),
    TechnicalVote(
      'MACD 柱',
      hist.toStringAsFixed(4),
      sign(hist),
      'DIF 高于 DEA 偏多，低于偏空',
    ),
    TechnicalVote(
      'RSI14',
      rsi.toStringAsFixed(2),
      rsi > 70
          ? -1
          : rsi < 30
          ? 0
          : rsi >= 50
          ? 1
          : -1,
      '50–70 偏多；30–50 或高于70偏谨慎；低于30等待反转',
    ),
    TechnicalVote(
      'DMI / ADX',
      'ADX ${adx.toStringAsFixed(2)}',
      adx >= 25 ? sign(p - m) : 0,
      'ADX≥25 时依据 +DI 与 −DI；否则趋势不足',
    ),
    TechnicalVote(
      'CMF20',
      cmf.toStringAsFixed(3),
      cmf > .05
          ? 1
          : cmf < -.05
          ? -1
          : 0,
      '大于0.05量能偏多，小于−0.05偏空，否则中性',
    ),
    TechnicalVote(
      'STOCH K / D',
      '${k.toStringAsFixed(1)} / ${d.toStringAsFixed(1)}',
      k > 80
          ? -1
          : k < 20
          ? 0
          : sign(k - d),
      '20–80 区间看 K/D 方向；超买谨慎，超卖等待确认',
    ),
  ];
  return CryptoAssessment(closed.last.closeTime, votes, value('natr', 0));
}
