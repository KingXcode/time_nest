import 'dart:math';

import 'package:flutter/material.dart';

import 'tool_logic.dart';
import 'tool_widgets.dart';

class CalculatorTool extends StatefulWidget {
  const CalculatorTool({super.key});
  @override
  State<CalculatorTool> createState() => _CalculatorToolState();
}

class _CalculatorToolState extends ToolState<CalculatorTool> {
  final expression = TextEditingController();
  final history = <String>[];
  @override
  void dispose() {
    expression.dispose();
    super.dispose();
  }

  void evaluate() => perform(() {
    final answer = numberText(calculate(expression.text));
    history.insert(0, '${expression.text} = $answer');
    if (history.length > 10) history.removeLast();
    return answer;
  });
  void key(String value) {
    if (value == '=') {
      evaluate();
      return;
    }
    setState(() {
      error = null;
      if (value == 'AC') {
        expression.clear();
        result = '';
      } else if (value == '⌫') {
        final text = expression.text;
        if (text.isNotEmpty) {
          expression.text = text.substring(0, text.length - 1);
        }
      } else if (expression.text.length < 300) {
        expression.text += value;
      }
      expression.selection = TextSelection.collapsed(
        offset: expression.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '随手算一算',
      children: [
        toolField(expression, '算式', hint: '(12 + 8) × 5', maxLength: 300),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.2,
          children:
              [
                    'AC',
                    '(',
                    ')',
                    '⌫',
                    '7',
                    '8',
                    '9',
                    '÷',
                    '4',
                    '5',
                    '6',
                    '×',
                    '1',
                    '2',
                    '3',
                    '-',
                    '0',
                    '.',
                    '%',
                    '+',
                  ]
                  .map(
                    (v) => OutlinedButton(
                      onPressed: () => key(v),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: Text(v, style: const TextStyle(fontSize: 20)),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 12),
        toolAction('计算结果', evaluate, icon: Icons.drag_handle),
        const SizedBox(height: 10),
        const Text(
          '百分号按除以 100 计算，例如 200 × 10% = 20。',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
    output: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolResult(value: result, error: error),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('最近计算 · 点击复制'),
          ...history.map(
            (line) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(line),
              onTap: () => copyToolText(context, line),
            ),
          ),
        ],
      ],
    ),
  );
}

class DateTool extends StatefulWidget {
  const DateTool({super.key});
  @override
  State<DateTool> createState() => _DateToolState();
}

class _DateToolState extends ToolState<DateTool> {
  final first = TextEditingController(text: dateText(DateTime.now()));
  final second = TextEditingController(
    text: dateText(DateTime.now().add(const Duration(days: 30))),
  );
  final days = TextEditingController(text: '30');
  String mode = '日期间隔';
  bool inclusive = false;
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    days.dispose();
    super.dispose();
  }

  Widget dateField(TextEditingController c, String label) => toolField(
    c,
    label,
    hint: 'YYYY-MM-DD',
    suffix: IconButton(
      tooltip: '选择$label',
      icon: const Icon(Icons.calendar_month_outlined),
      onPressed: () async {
        DateTime initial;
        try {
          initial = calendarDate(c.text);
        } catch (_) {
          initial = DateTime.now();
        }
        final chosen = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1),
          lastDate: DateTime(9999, 12, 31),
        );
        if (chosen != null && mounted) {
          setState(() => c.text = dateText(chosen));
        }
      },
    ),
  );
  void compute() => perform(() {
    final start = calendarDate(first.text);
    if (mode == '日期加减') {
      final n = int.tryParse(days.text.trim());
      if (n == null) throw const FormatException('请输入整数天数，可用负数表示往前');
      return dateText(addCalendarDays(start, n));
    }
    final end = calendarDate(second.text);
    if (mode == '年龄计算') {
      if (end.isBefore(start)) throw const FormatException('截止日期不能早于出生日期');
      var years = end.year - start.year;
      if (end.month < start.month ||
          (end.month == start.month && end.day < start.day)) {
        years--;
      }
      return '$years 周岁\n共经历 ${end.difference(start).inDays} 天';
    }
    final delta = end.difference(start).inDays;
    return '${delta.abs() + (inclusive ? 1 : 0)} 天\n${delta < 0 ? '结束日期早于开始日期' : '结束日期不早于开始日期'}${inclusive ? '\n含首尾两天' : '\n按日期差计算，不额外计入结束日'}';
  });
  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '把日期算清楚',
      children: [
        toolChoice(
          '计算方式',
          mode,
          ['日期间隔', '日期加减', '年龄计算'],
          (v) => setState(() {
            mode = v;
            result = '';
            error = null;
          }),
        ),
        dateField(first, mode == '年龄计算' ? '出生日期' : '开始日期'),
        if (mode == '日期加减')
          toolField(
            days,
            '加减天数',
            hint: '30 或 -30',
            keyboard: const TextInputType.numberWithOptions(signed: true),
          )
        else
          dateField(second, mode == '年龄计算' ? '截止日期' : '结束日期'),
        if (mode == '日期间隔')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('包含首尾两天'),
            value: inclusive,
            onChanged: (v) => setState(() => inclusive = v),
          ),
        toolAction('计算日期', compute, icon: Icons.calendar_today_outlined),
      ],
    ),
    output: ToolResult(value: result, error: error),
  );
}

class UnitTool extends StatefulWidget {
  const UnitTool({super.key});
  @override
  State<UnitTool> createState() => _UnitToolState();
}

class _UnitToolState extends ToolState<UnitTool> {
  final value = TextEditingController(text: '1');
  String group = '长度', from = '米', to = '厘米';
  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '常用单位，一步换算',
      children: [
        toolChoice(
          '换算类别',
          group,
          unitGroups.keys,
          (v) => setState(() {
            group = v;
            from = unitGroups[v]!.keys.first;
            to = unitGroups[v]!.keys.elementAt(1);
            result = '';
            error = null;
          }),
        ),
        toolField(
          value,
          '数值',
          keyboard: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
        ),
        toolChoice(
          '从',
          from,
          unitGroups[group]!.keys,
          (v) => setState(() => from = v),
        ),
        Align(
          alignment: Alignment.center,
          child: IconButton(
            tooltip: '交换单位',
            onPressed: () => setState(() {
              final previous = from;
              from = to;
              to = previous;
              result = '';
            }),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ),
        toolChoice(
          '到',
          to,
          unitGroups[group]!.keys,
          (v) => setState(() => to = v),
        ),
        toolAction(
          '换算',
          () => perform(() {
            final n = double.tryParse(value.text.trim());
            if (n == null) throw const FormatException('请输入有效数字');
            return '${numberText(n)} $from\n= ${numberText(convertUnit(n, group, from, to))} $to';
          }),
          icon: Icons.swap_horiz_rounded,
        ),
      ],
    ),
    output: ToolResult(value: result, error: error),
  );
}

class RandomTool extends StatefulWidget {
  const RandomTool({super.key});
  @override
  State<RandomTool> createState() => _RandomToolState();
}

class _RandomToolState extends ToolState<RandomTool> {
  final min = TextEditingController(text: '1'),
      max = TextEditingController(text: '100'),
      count = TextEditingController(text: '1');
  final names = TextEditingController();
  String mode = '随机整数';
  bool unique = true;
  @override
  void dispose() {
    for (final c in [min, max, count, names]) {
      c.dispose();
    }
    super.dispose();
  }

  void generate() => perform(() {
    final n = int.tryParse(count.text);
    if (n == null || n < 1 || n > 100) {
      throw const FormatException('数量须为 1～100');
    }
    if (mode == '名单抽签') {
      final entries = names.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (entries.isEmpty || n > entries.length) {
        throw const FormatException('请填写名单；抽取数量不能超过不同选项的个数');
      }
      entries.shuffle(Random.secure());
      return entries.take(n).join('\n');
    }
    if (mode == '抛硬币') {
      return randomNumbers(
        0,
        1,
        n,
        unique: false,
      ).map((i) => i == 0 ? '正面' : '反面').join('、');
    }
    if (mode == '掷骰子') return randomNumbers(1, 6, n, unique: false).join('、');
    final low = int.tryParse(min.text), high = int.tryParse(max.text);
    if (low == null || high == null) throw const FormatException('范围须为整数');
    return randomNumbers(low, high, n, unique: unique).join('、');
  });
  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '让选择轻松一点',
      children: [
        toolChoice(
          '随机方式',
          mode,
          ['随机整数', '名单抽签', '抛硬币', '掷骰子'],
          (v) => setState(() {
            mode = v;
            result = '';
            error = null;
          }),
        ),
        if (mode == '随机整数') ...[
          toolField(
            min,
            '最小值',
            keyboard: const TextInputType.numberWithOptions(signed: true),
          ),
          toolField(
            max,
            '最大值',
            keyboard: const TextInputType.numberWithOptions(signed: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('结果不重复'),
            value: unique,
            onChanged: (v) => setState(() => unique = v),
          ),
        ],
        if (mode == '名单抽签')
          toolField(
            names,
            '选项名单',
            hint: '每行一个选项，重复项自动合并',
            lines: 4,
            maxLength: 10000,
          ),
        toolField(count, '生成数量', keyboard: TextInputType.number),
        toolAction('随机生成', generate, icon: Icons.casino_outlined),
      ],
    ),
    output: ToolResult(value: result, error: error),
  );
}
