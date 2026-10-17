import 'package:flutter/material.dart';

import 'tool_logic.dart';
import 'tool_widgets.dart';

class DeveloperTool extends StatefulWidget {
  const DeveloperTool({super.key});
  @override
  State<DeveloperTool> createState() => _DeveloperToolState();
}

class _DeveloperToolState extends ToolState<DeveloperTool> {
  final input = TextEditingController(), second = TextEditingController();
  String mode = 'JSON 格式化';
  bool milliseconds = false;
  static const modes = [
    'JSON 格式化',
    'JSON 压缩',
    '时间戳转日期',
    '日期转时间戳',
    'URL 编码',
    'URL 解码',
    'Base64 编码',
    'Base64 解码',
    '文本对比',
  ];
  @override
  void dispose() {
    input.dispose();
    second.dispose();
    super.dispose();
  }

  String get hint => switch (mode) {
    'JSON 格式化' || 'JSON 压缩' => '{"name":"此刻","count":1}',
    '日期转时间戳' => '2026-10-17T12:00:00+08:00',
    '时间戳转日期' => '1792209600',
    _ => '粘贴需要处理的内容',
  };
  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '常用开发处理',
      children: [
        toolChoice(
          '处理方式',
          mode,
          modes,
          (v) => setState(() {
            mode = v;
            result = '';
            error = null;
          }),
        ),
        if (mode.contains('时间戳')) ...[
          toolChoice('时间戳单位', milliseconds ? '毫秒' : '秒', [
            '秒',
            '毫秒',
          ], (v) => setState(() => milliseconds = v == '毫秒')),
          TextButton.icon(
            onPressed: () => setState(() {
              final now = DateTime.now();
              input.text = mode == '日期转时间戳'
                  ? now.toUtc().toIso8601String()
                  : '${milliseconds ? now.millisecondsSinceEpoch : now.millisecondsSinceEpoch ~/ 1000}';
            }),
            icon: const Icon(Icons.schedule),
            label: const Text('填入当前时间'),
          ),
        ],
        toolField(
          input,
          mode == '文本对比' ? '原文本' : '输入内容',
          hint: hint,
          lines: mode.contains('时间戳') ? 2 : 6,
          maxLength: mode == '文本对比' ? 30000 : 100000,
        ),
        if (mode == '文本对比')
          toolField(second, '新文本', lines: 6, maxLength: 30000),
        toolAction(
          '开始处理',
          () => perform(
            () => developerTransform(
              mode,
              input.text,
              second: second.text,
              milliseconds: milliseconds,
            ),
          ),
          icon: Icons.code_rounded,
        ),
        const SizedBox(height: 12),
        Text(
          mode == '文本对比'
              ? '按行比较：− 为删除，+ 为新增；每份最多 500 行。'
              : mode.startsWith('URL')
              ? '按单个 URL 参数编码／解码，不会访问输入的网址。'
              : '内容只在本地处理。',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
    output: ToolResult(value: result, error: error),
  );
}
