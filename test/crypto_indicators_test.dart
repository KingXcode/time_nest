import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_indicators.dart';
import 'package:time_nest/dashboard/crypto_market.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/crypto_talib.json').readAsStringSync(),
  ) as Map;
  final raw = (fixture['rows'] as List).cast<Map>();
  final rows = raw.map(CryptoCandle.fromJson).toList();
  test(
    '22 indicator series agree with independently generated TA-Lib references',
    () {
      final result = calculateCryptoIndicators(rows);
      for (final entry in (fixture['expected'] as Map).entries) {
        final keys = (entry.key as String).split(':'),
            values = result[keys[0]]!.lines[int.parse(keys[1])].values;
        for (final check in (entry.value as Map).entries) {
          expect(
            values[int.parse(check.key as String)],
            closeTo((check.value as num).toDouble(), 1e-7),
            reason: '${entry.key} at ${check.key}',
          );
        }
      }
    },
  );
  test('36 studies are causal, aligned, finite and preserve warm-up gaps', () {
    final full = calculateCryptoIndicators(rows),
        prefix = calculateCryptoIndicators(rows.take(120).toList());
    expect(full.keys.toSet(), cryptoIndicators.keys.toSet());
    expect(full.length, 36);
    for (final study in full.values) {
      for (var j = 0; j < study.lines.length; j++) {
        final line = study.lines[j];
        expect(line.values.length, rows.length);
        expect(
          line.values.whereType<double>().every((v) => v.isFinite),
          isTrue,
          reason: study.id,
        );
        expect(
          line.values.take(120).toList(),
          prefix[study.id]!.lines[j].values,
          reason: '${study.id} looks ahead',
        );
      }
    }
    expect(full['ma']!.lines[0].values.take(4), everyElement(isNull));
    expect(full['rsi']!.lines[0].values.take(14), everyElement(isNull));
    expect(full['macd']!.lines[1].values.take(33), everyElement(isNull));
    expect(full['tema']!.lines[0].values.take(57), everyElement(isNull));
  });
  test('flat zero-volume markets never produce infinity or invented volume-weighted values', () {
    final flat = [
      for (final r in raw)
        CryptoCandle.fromJson({
          ...r,
          'open': 100.0,
          'high': 100.0,
          'low': 100.0,
          'close': 100.0,
          'volume': 0.0,
          'quoteVolume': 0.0,
        }),
    ];
    final studies = calculateCryptoIndicators(flat);
    for (final s in studies.values) {
      for (final l in s.lines) {
        expect(
          l.values.whereType<double>().every((v) => v.isFinite),
          isTrue,
          reason: s.id,
        );
      }
    }
    expect(studies['rsi']!.lines[0].values.last, 50);
    expect(studies['atr']!.lines[0].values.last, 0);
    expect(studies['vwma']!.lines[0].values.last, isNull);
    expect(studies['mfi']!.lines[0].values.last, 50);
  });
  test('channels, custom studies and Wilder ranges match an analytic rising series', () {
    final linear = [
      for (var i = 0; i < raw.length; i++)
        CryptoCandle.fromJson({
          ...raw[i],
          'open': 100.0 + i,
          'close': 100.0 + i,
          'high': 102.0 + i,
          'low': 99.0 + i,
          'volume': 10.0,
          'quoteVolume': (100.0 + i) * 10,
        }),
    ];
    final result = calculateCryptoIndicators(linear);
    double last(String id, [int line = 0]) =>
        result[id]!.lines[line].values.last!;
    expect(last('donchian'), 351);
    expect(last('donchian', 2), 329);
    expect(last('vwma'), 339.5);
    expect(last('hma'), closeTo(348.3333333333333, 1e-9));
    expect(last('bbi'), 343.875);
    expect(last('keltner', 1), closeTo(345.5, 1e-9));
    expect(last('keltner', 2), closeTo(333.5, 1e-9));
    expect(last('env'), closeTo(339.5 * 1.02, 1e-9));
    expect(last('atr'), 3);
    expect(last('natr'), closeTo(300 / 349, 1e-9));
    expect(last('adx', 2), closeTo(100, 1e-9));
    expect(last('cmf'), closeTo(-1 / 3, 1e-9));
    expect(last('tsi'), closeTo(100, 1e-9));
    expect(last('stochrsi'), 50);
    expect(last('ao'), 14.5);
    expect(last('dpo'), -1.5);
    expect(last('vol'), 10);
    expect(last('amount'), 3490);
  });
  test('buying reference excludes forming candles and requires sufficient closed history', () {
    final asOf = rows.last.time + 1000;
    final before = assessCrypto(rows, asOf)!;
    final altered = [
      ...rows.take(rows.length - 1),
      CryptoCandle.fromJson({
        ...raw.last,
        'high': 10000.0,
        'close': 9999.0,
        'volume': 9999999.0,
      }),
    ];
    final after = assessCrypto(altered, asOf)!;
    expect(after.time, rows[rows.length - 2].closeTime);
    expect(after.title, before.title);
    expect(after.votes.map((v) => v.value), before.votes.map((v) => v.value));
    expect(assessCrypto(rows.take(59).toList(), asOf), isNull);
    expect(before.votes.length, 6);
  });
}
