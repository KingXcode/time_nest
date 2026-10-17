import 'dart:convert';
import 'dart:math';

String numberText(num value) {
  if (!value.isFinite) throw const FormatException('结果超出可计算范围');
  if (value == 0) return '0';
  return double.parse(value.toStringAsPrecision(12))
      .toString()
      .replaceFirst(RegExp(r'\.0$'), '');
}

/// Bounded arithmetic parser, never evaluates executable code.
double calculate(String expression) => _Calculator(expression).parse();

class _Calculator {
  _Calculator(String value)
    : source = value
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll(RegExp(r'\s'), '');
  final String source;
  int at = 0;
  bool take(String value) {
    if (source.startsWith(value, at)) {
      at += value.length;
      return true;
    }
    return false;
  }

  double parse() {
    if (source.isEmpty || source.length > 300) {
      throw const FormatException('请输入有效算式（最多 300 字）');
    }
    final result = sum();
    if (at != source.length || !result.isFinite) {
      throw const FormatException('算式不完整或结果超出范围');
    }
    return result;
  }

  double sum() {
    var n = product();
    while (true) {
      if (take('+')) {
        n += product();
      } else if (take('-')) {
        n -= product();
      } else {
        return n;
      }
    }
  }

  double product() {
    var n = atom();
    while (true) {
      if (take('*')) {
        n *= atom();
      } else if (take('/')) {
        final d = atom();
        if (d == 0) throw const FormatException('不能除以零');
        n /= d;
      } else {
        return n;
      }
    }
  }

  double atom() {
    if (take('+')) return atom();
    if (take('-')) return -atom();
    double n;
    if (take('(')) {
      n = sum();
      if (!take(')')) throw const FormatException('括号不匹配');
    } else {
      final match = RegExp(r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
          .matchAsPrefix(source, at);
      if (match == null) throw const FormatException('请输入数字和四则运算符');
      at = match.end;
      n = double.parse(match[0]!);
    }
    if (take('%')) n /= 100;
    return n;
  }
}

DateTime calendarDate(String text) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text.trim());
  if (m == null) throw const FormatException('日期格式为 YYYY-MM-DD');
  final y = int.parse(m[1]!), month = int.parse(m[2]!), day = int.parse(m[3]!);
  final date = DateTime.utc(y, month, day);
  if (y < 1 ||
      y > 9999 ||
      date.year != y ||
      date.month != month ||
      date.day != day) {
    throw const FormatException('日期不存在，请检查年月日');
  }
  return date;
}

String dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime addCalendarDays(DateTime date, int days) {
  if (days.abs() > 3650000) throw const FormatException('天数超出范围');
  final result = date.add(Duration(days: days));
  if (result.year < 1 || result.year > 9999) {
    throw const FormatException('结果日期须在 0001～9999 年之间');
  }
  return result;
}

const unitGroups = <String, Map<String, double>>{
  '长度': {
    '米': 1,
    '千米': 1000,
    '厘米': .01,
    '毫米': .001,
    '英寸': .0254,
    '英尺': .3048,
    '英里': 1609.344,
  },
  '重量': {
    '千克': 1,
    '克': .001,
    '毫克': .000001,
    '吨': 1000,
    '斤': .5,
    '磅': .45359237,
    '盎司': .028349523125,
  },
  '面积': {
    '平方米': 1,
    '平方千米': 1000000,
    '公顷': 10000,
    '亩': 2000 / 3,
    '平方英尺': .09290304,
  },
  '容量': {'升': 1, '毫升': .001, '立方米': 1000, '美制加仑': 3.785411784},
  '温度': {'摄氏度': 1, '华氏度': 1, '开尔文': 1},
};
double convertUnit(double value, String group, String from, String to) {
  final units = unitGroups[group];
  if (!value.isFinite ||
      units == null ||
      !units.containsKey(from) ||
      !units.containsKey(to)) {
    throw const FormatException('请输入有效数值和单位');
  }
  if (group != '温度') return value * units[from]! / units[to]!;
  final c = switch (from) {
    '华氏度' => (value - 32) * 5 / 9,
    '开尔文' => value - 273.15,
    _ => value,
  };
  if (c < -273.15000001) throw const FormatException('温度不能低于绝对零度');
  return switch (to) {
    '华氏度' => c * 9 / 5 + 32,
    '开尔文' => c + 273.15,
    _ => c,
  };
}

int hexColor(String value) {
  var hex = value.trim().replaceFirst(RegExp(r'^#'), '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    throw const FormatException('请输入 3 位或 6 位 HEX 颜色');
  }
  return int.parse(hex, radix: 16);
}

String hexText(int rgb) =>
    '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

List<int> randomNumbers(
  int min,
  int max,
  int count, {
  bool unique = true,
  Random? random,
}) {
  if (min < -1000000000 ||
      max > 1000000000 ||
      min > max ||
      count < 1 ||
      count > 100) {
    throw const FormatException('范围须在 ±10 亿内，数量为 1～100，最小值不能大于最大值');
  }
  final span = max - min + 1;
  if (unique && count > span) {
    throw const FormatException('不重复时，数量不能超过范围内的整数个数');
  }
  final rng = random ?? Random.secure();
  if (!unique) return List.generate(count, (_) => min + rng.nextInt(span));
  final picked = <int>{};
  // Floyd sampling: bounded work even when drawing the entire range.
  for (var j = span - count; j < span; j++) {
    final candidate = rng.nextInt(j + 1);
    picked.add(picked.contains(candidate) ? j : candidate);
  }
  return picked.map((n) => min + n).toList()..shuffle(rng);
}

String developerTransform(
  String mode,
  String input, {
  String second = '',
  bool milliseconds = false,
}) {
  if (input.length + second.length > 100000) {
    throw const FormatException('内容较长，请限制在 10 万字以内');
  }
  switch (mode) {
    case 'JSON 格式化':
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(input));
    case 'JSON 压缩':
      return jsonEncode(jsonDecode(input));
    case 'URL 编码':
      return Uri.encodeComponent(input);
    case 'URL 解码':
      try {
        return Uri.decodeComponent(input);
      } on ArgumentError {
        throw const FormatException('URL 编码无效，请检查百分号后的十六进制字符');
      }
    case 'Base64 编码':
      return base64Encode(utf8.encode(input));
    case 'Base64 解码':
      return utf8.decode(base64Decode(input.trim()));
    case '时间戳转日期':
      final value = int.tryParse(input.trim());
      if (value == null ||
          value.abs() > (milliseconds ? 8640000000000000 : 8640000000000)) {
        throw const FormatException('请输入有效的整数时间戳');
      }
      final d = DateTime.fromMillisecondsSinceEpoch(
        value * (milliseconds ? 1 : 1000),
        isUtc: true,
      );
      return 'UTC：${d.toIso8601String()}\n本地：${d.toLocal()}';
    case '日期转时间戳':
      // Round-trip the date portion because DateTime.parse normalizes bad dates.
      if (!RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(input.trim())) {
        throw const FormatException('请输入带时区的日期，如 2026-10-17T12:00:00+08:00');
      }
      calendarDate(input.trim().substring(0, 10));
      final parts = input
          .trim()
          .substring(11, 19)
          .split(':')
          .map(int.parse)
          .toList();
      if (parts[0] > 23 || parts[1] > 59 || parts[2] > 59) {
        throw const FormatException('时间不存在');
      }
      final offset = RegExp(r'[+-](\d{2}):(\d{2})$').firstMatch(input.trim());
      if (offset != null &&
          (int.parse(offset[1]!) > 23 || int.parse(offset[2]!) > 59)) {
        throw const FormatException('时间不存在');
      }
      final d = DateTime.parse(input.trim());
      return '${milliseconds ? d.millisecondsSinceEpoch : (d.millisecondsSinceEpoch / 1000).floor()}';
    case '文本对比':
      return lineDiff(input, second);
    default:
      throw const FormatException('请选择处理方式');
  }
}

String lineDiff(String before, String after) {
  final a = before.split('\n'), b = after.split('\n');
  if (a.length > 500 || b.length > 500) {
    throw const FormatException('文本对比每份最多 500 行');
  }
  if (before == after) return '两份文本完全一致';
  final dp = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  var i = 0, j = 0;
  final lines = <String>[];
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      lines.add('  ${a[i++]}');
      j++;
    } else if (i < a.length &&
        (j == b.length || dp[i + 1][j] >= dp[i][j + 1])) {
      lines.add('- ${a[i++]}');
    } else {
      lines.add('+ ${b[j++]}');
    }
  }
  return lines.join('\n');
}
