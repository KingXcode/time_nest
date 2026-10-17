import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/tools/tool_logic.dart';
import 'package:time_nest/tools/media_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'arithmetic precedence, parentheses, signs and percent are deterministic',
    () {
      expect(calculate('(12 + 8) × 5'), 100);
      expect(calculate('200*10%'), 20);
      expect(calculate('2+3*4'), 14);
      expect(calculate('-.5+2*-3'), -6.5);
      expect(numberText(calculate('0.1+0.2')), '0.3');
      expect(calculate('1e3/4'), 250);
      for (final text in [
        '1/0',
        '1+',
        'abc',
        '2(3)',
        '(1+2',
        '1e999',
        '9' * 301,
      ]) {
        expect(() => calculate(text), throwsFormatException, reason: text);
      }
    },
  );
  test('calendar calculations validate leap days and do not depend on DST', () {
    expect(
      dateText(addCalendarDays(calendarDate('2024-02-28'), 2)),
      '2024-03-01',
    );
    expect(
      calendarDate('2026-03-09').difference(calendarDate('2026-03-07')).inDays,
      2,
    );
    expect(
      dateText(addCalendarDays(calendarDate('2026-01-01'), -1)),
      '2025-12-31',
    );
    for (final date in [
      '2025-02-29',
      '2026-04-31',
      '0000-01-01',
      '2026-13-01',
    ]) {
      expect(() => calendarDate(date), throwsFormatException);
    }
    expect(
      () => addCalendarDays(calendarDate('9999-12-31'), 1),
      throwsFormatException,
    );
  });
  test('unit conversion handles offsets, physical limits and unit factors', () {
    expect(convertUnit(32, '温度', '华氏度', '摄氏度'), closeTo(0, 1e-9));
    expect(convertUnit(0, '温度', '摄氏度', '开尔文'), closeTo(273.15, 1e-9));
    expect(convertUnit(1, '长度', '英寸', '厘米'), closeTo(2.54, 1e-9));
    expect(convertUnit(2, '重量', '斤', '千克'), 1);
    expect(() => convertUnit(-1, '温度', '开尔文', '摄氏度'), throwsFormatException);
    expect(
      () => convertUnit(double.nan, '长度', '米', '厘米'),
      throwsFormatException,
    );
  });
  test(
    'random draws are bounded, inclusive and unique without retry loops',
    () {
      final all = randomNumbers(-5, 5, 11, random: Random(5));
      expect(all.toSet(), {for (var i = -5; i <= 5; i++) i});
      expect(randomNumbers(7, 7, 10, unique: false), List.filled(10, 7));
      expect(() => randomNumbers(1, 2, 3), throwsFormatException);
      expect(() => randomNumbers(2, 1, 1), throwsFormatException);
      expect(() => randomNumbers(1, 10, 0), throwsFormatException);
    },
  );
  test(
    'color and developer transforms preserve unicode and expose bad inputs',
    () {
      expect(hexText(hexColor('#aBc')), '#AABBCC');
      expect(() => hexColor('#12345678'), throwsFormatException);
      expect(() => hexColor('FF#0000'), throwsFormatException);
      const text = '此刻 🌟 + / ?';
      expect(
        developerTransform('URL 解码', developerTransform('URL 编码', text)),
        text,
      );
      expect(
        developerTransform('Base64 解码', developerTransform('Base64 编码', text)),
        text,
      );
      expect(developerTransform('JSON 压缩', '{ "a": [1, 2] }'), '{"a":[1,2]}');
      expect(() => developerTransform('JSON 格式化', '{'), throwsFormatException);
      expect(() => developerTransform('URL 解码', '%QZ'), throwsFormatException);
      expect(developerTransform('日期转时间戳', '1970-01-01T08:00:00+08:00'), '0');
      expect(developerTransform('日期转时间戳', '1969-12-31T23:59:59.999Z'), '-1');
      expect(
        () => developerTransform('日期转时间戳', '2026-02-30T12:00:00Z'),
        throwsFormatException,
      );
      expect(
        () => developerTransform('日期转时间戳', '2026-01-01T24:00:00Z'),
        throwsFormatException,
      );
      for (final offset in ['+24:00', '-08:60']) {
        expect(
          () => developerTransform('日期转时间戳', '2026-01-01T12:00:00$offset'),
          throwsFormatException,
        );
      }
      expect(
        developerTransform('时间戳转日期', '0'),
        contains('1970-01-01T00:00:00.000Z'),
      );
    },
  );
  test('line diff distinguishes insertion, deletion and unchanged content', () {
    expect(lineDiff('a\nb', 'a\nx\nb'), '  a\n+ x\n  b');
    expect(lineDiff('a\nb', 'b'), '- a\n  b');
    expect(lineDiff('a', 'a'), '两份文本完全一致');
    expect(
      () => lineDiff(List.filled(501, 'x').join('\n'), ''),
      throwsFormatException,
    );
  });
  test('exported QR has a quiet zone and decodes UTF-8 payload', () async {
    const content = '此刻工具箱 🌟 https://example.com/?x=1&y=2';
    final qr = makeQr(content);
    final png = await qrPng(qr);
    expect(png.take(4), [137, 80, 78, 71]);
    expect(await readQr(png), content);
    expect(() => makeQr(''), throwsFormatException);
    expect(() => makeQr('中' * 501), throwsFormatException);
  });
}
