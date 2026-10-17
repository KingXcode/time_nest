import 'package:flutter/material.dart';

import 'basic_tools.dart';
import 'developer_tool.dart';
import 'media_tools.dart';

class ToolDefinition {
  const ToolDefinition(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.builder,
  );
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() builder;
}

final toolboxTools = <ToolDefinition>[
  ToolDefinition(
    '计算器',
    '四则运算 · 百分比',
    Icons.calculate_outlined,
    const Color(0xFF9AE3CF),
    () => const CalculatorTool(),
  ),
  ToolDefinition(
    '日期计算',
    '日期间隔 · 加减 · 年龄',
    Icons.date_range_outlined,
    const Color(0xFFDAC6FF),
    () => const DateTool(),
  ),
  ToolDefinition(
    '图片工具',
    '压缩 · 缩放 · 居中裁剪',
    Icons.image_outlined,
    const Color(0xFFFFCDAA),
    () => const ImageTool(),
  ),
  ToolDefinition(
    '颜色工具',
    '颜色转换 · 图片取色',
    Icons.palette_outlined,
    const Color(0xFFF6B5CD),
    () => const ColorTool(),
  ),
  ToolDefinition(
    '开发工具',
    'JSON · 时间戳 · 文本对比',
    Icons.data_object_rounded,
    const Color(0xFFA9CFFF),
    () => const DeveloperTool(),
  ),
  ToolDefinition(
    '随机工具',
    '随机数 · 抽签 · 骰子',
    Icons.casino_outlined,
    const Color(0xFFFFDD8D),
    () => const RandomTool(),
  ),
  ToolDefinition(
    '单位换算',
    '长度 · 重量 · 温度',
    Icons.swap_horiz_rounded,
    const Color(0xFFA5DEEF),
    () => const UnitTool(),
  ),
  ToolDefinition(
    '二维码工具',
    '生成二维码 · 图片识别',
    Icons.qr_code_2_rounded,
    const Color(0xFFC8D89A),
    () => const QrTool(),
  ),
];

class ToolboxScreen extends StatelessWidget {
  const ToolboxScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('工具箱'),
      backgroundColor: Colors.transparent,
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '让日常小事，简单一点。',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '八个随手工具 · 本地处理 · 无需登录',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverLayoutBuilder(
                  builder: (_, box) {
                    final columns = box.crossAxisExtent >= 850
                        ? 4
                        : box.crossAxisExtent >= 560
                        ? 3
                        : 2;
                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final tool = toolboxTools[index];
                        return Material(
                          color: const Color(0xFF171B21),
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ToolPage(tool: tool),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: tool.color.withValues(alpha: .1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      tool.icon,
                                      color: tool.color,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    tool.title,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tool.subtitle,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                    maxLines: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }, childCount: toolboxTools.length),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 180,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Text(
                    '返回时钟后，原来的计时会继续。',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ToolPage extends StatelessWidget {
  const ToolPage({super.key, required this.tool});
  final ToolDefinition tool;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tool.title),
      backgroundColor: Colors.transparent,
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: tool.builder(),
          ),
        ),
      ),
    ),
  );
}
