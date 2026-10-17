import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const toolAccent = Color(0xFF9AE3CF);

Widget toolField(
  TextEditingController controller,
  String label, {
  String? hint,
  int lines = 1,
  int? maxLength,
  ValueChanged<String>? onChanged,
  Widget? suffix,
  TextInputType? keyboard,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextField(
    controller: controller,
    minLines: lines,
    maxLines: lines == 1 ? 1 : lines + 3,
    maxLength: maxLength,
    keyboardType: keyboard,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: const Color(0xFF1C2026),
    ),
  ),
);
Widget toolChoice(
  String label,
  String value,
  Iterable<String> choices,
  ValueChanged<String> changed,
) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: DropdownButtonFormField<String>(
    key: ValueKey('$label$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: choices
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(v, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) {
      if (v != null) changed(v);
    },
  ),
);
Widget toolAction(
  String label,
  VoidCallback? action, {
  IconData icon = Icons.arrow_forward_rounded,
}) => FilledButton.icon(
  style: FilledButton.styleFrom(
    backgroundColor: toolAccent,
    foregroundColor: const Color(0xFF10251F),
    minimumSize: const Size(0, 48),
  ),
  onPressed: action,
  icon: Icon(icon, size: 18),
  label: Text(label),
);

class ToolSplit extends StatelessWidget {
  const ToolSplit({super.key, required this.input, required this.output});
  final Widget input, output;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      if (box.maxWidth >= 660) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: input),
            const SizedBox(width: 24),
            Expanded(child: output),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [input, const SizedBox(height: 24), output],
      );
    },
  );
}

class ToolSection extends StatelessWidget {
  const ToolSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      ...children,
    ],
  );
}

class ToolResult extends StatelessWidget {
  const ToolResult({super.key, required this.value, this.error, this.child});
  final String value;
  final String? error;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF171C21),
      border: Border.all(color: const Color(0xFF2D393D)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('结果', style: TextStyle(color: toolAccent)),
            ),
            if (value.isNotEmpty && error == null)
              IconButton(
                tooltip: '复制结果',
                onPressed: () => copyToolText(context, value),
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (error != null)
          Text(error!, style: const TextStyle(color: Color(0xFFFFB4AB)))
        else if (child != null)
          child!
        else
          SelectableText(
            value.isEmpty ? '完成输入后，结果会显示在这里。' : value,
            style: TextStyle(
              fontSize: value.length < 40 ? 22 : 15,
              height: 1.6,
              color: value.isEmpty ? Colors.white54 : Colors.white,
            ),
          ),
      ],
    ),
  );
}

Future<void> copyToolText(BuildContext context, String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('复制未成功，可以长按结果手动复制')));
    }
  }
}

abstract class ToolState<T extends StatefulWidget> extends State<T> {
  String result = '';
  String? error;
  bool busy = false;
  void perform(String Function() work) {
    try {
      final value = work();
      setState(() {
        result = value;
        error = null;
      });
    } catch (e) {
      setState(() {
        error = e is FormatException ? e.message : '处理失败，请检查输入内容';
      });
    }
  }

  Future<void> performAsync(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '处理失败，请检查文件格式或重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
