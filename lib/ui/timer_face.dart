import 'package:flutter/material.dart';

import '../clock/clock_settings.dart';
import '../clock/timer_controller.dart';
import 'clock_face.dart';

class TimerFace extends StatelessWidget {
  const TimerFace({
    super.key,
    required this.timer,
    required this.settings,
    required this.intensity,
    required this.armSound,
  });
  final TimerController timer;
  final ClockSettings settings;
  final ValueNotifier<double> intensity;
  final VoidCallback armSound;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([timer, intensity]),
    builder: (context, _) {
      final focusMode = timer.mode == 'focus';
      final session = focusMode ? timer.focus : timer.countdown;
      final phase = switch (session.phase) {
        'focus' => '专注',
        'shortBreak' => '短休息',
        'longBreak' => '长休息',
        _ => '倒计时',
      };
      final complete = session.status == 'complete';
      final nextLabel = !focusMode
          ? '再来一次'
          : session.phase == 'focus'
          ? (timer.cycleCount % 4 == 0 ? '开始长休息' : '开始休息')
          : '开始专注';
      final color = Color.lerp(
        clockBackground,
        settings.tone == 'warm' ? const Color(0xFFFFC98B) : clockForeground,
        intensity.value,
      )!;
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  focusMode ? '$phase · 今日完成 ${timer.todayFocus} 次专注' : '倒计时',
                  style: TextStyle(color: color, fontSize: 14),
                ),
                SizedBox(height: box.maxHeight < 260 ? 4 : 8),
                SizedBox(
                  height: (box.maxHeight * (box.maxHeight < 260 ? .28 : .42))
                      .clamp(48.0, 180.0),
                  width: box.maxWidth,
                  child: FittedBox(
                    child: Text(
                      session.label,
                      key: const Key('timer-digits'),
                      style: TextStyle(
                        fontFamily: 'ClockDigits',
                        fontSize: 180,
                        height: 1.1,
                        color: color,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: box.maxHeight < 260 ? 4 : 8),
                Text(
                  complete
                      ? '$phase结束'
                      : session.status == 'paused'
                      ? '已暂停'
                      : session.running
                      ? '$phase进行中'
                      : focusMode
                      ? '每 4 次专注后安排长休息'
                      : '选择时长，留一点时间给眼前的事',
                  key: const Key('timer-status'),
                  style: TextStyle(color: color, fontSize: 13),
                ),
                SizedBox(height: box.maxHeight < 260 ? 6 : 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    FilledButton.icon(
                      key: const Key('timer-primary'),
                      onPressed: () {
                        if (session.running) {
                          timer.pause(session);
                        } else {
                          if (timer.sound) armSound();
                          timer.start(session);
                        }
                      },
                      icon: Icon(
                        session.running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        session.running
                            ? '暂停'
                            : session.status == 'paused'
                            ? '继续'
                            : complete
                            ? nextLabel
                            : '开始',
                      ),
                    ),
                    if (session.status != 'idle')
                      TextButton(
                        onPressed: () async {
                          final accepted =
                              !session.active ||
                              await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('重置计时？'),
                                      content: const Text(
                                        '当前进度将清除，已完成的专注次数会保留。',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('重置'),
                                        ),
                                      ],
                                    ),
                                  ) ==
                                  true;
                          if (accepted) timer.reset(session);
                        },
                        child: const Text('重置计时'),
                      ),
                    TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _TimerOptions(
                          timer: timer,
                          focusMode: focusMode,
                          armSound: armSound,
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('计时设置'),
                    ),
                  ],
                ),
                if (!focusMode && !session.active)
                  Padding(
                    padding: EdgeInsets.only(top: box.maxHeight < 260 ? 0 : 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final minutes in [5, 15, 25])
                          ChoiceChip(
                            label: Text('$minutes 分钟'),
                            selected: timer.countdownMinutes == minutes,
                            onSelected: (_) =>
                                timer.configure(countdownValue: minutes),
                          ),
                      ],
                    ),
                  ),
                if (!timer.storageAvailable)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '计时状态未能保存，刷新后可能丢失',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE7BB88)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TimerOptions extends StatefulWidget {
  const _TimerOptions({
    required this.timer,
    required this.focusMode,
    required this.armSound,
  });
  final TimerController timer;
  final bool focusMode;
  final VoidCallback armSound;
  @override
  State<_TimerOptions> createState() => _TimerOptionsState();
}

class _TimerOptionsState extends State<_TimerOptions> {
  final _form = GlobalKey<FormState>();
  late final main = TextEditingController(
    text:
        '${widget.focusMode ? widget.timer.focusMinutes : widget.timer.countdownMinutes}',
  );
  late final short = TextEditingController(
    text: '${widget.timer.shortBreakMinutes}',
  );
  late final long = TextEditingController(
    text: '${widget.timer.longBreakMinutes}',
  );
  late bool sound = widget.timer.sound;
  @override
  void dispose() {
    main.dispose();
    short.dispose();
    long.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active =
        (widget.focusMode ? widget.timer.focus : widget.timer.countdown).active;
    Widget field(String label, TextEditingController controller, int max) =>
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextFormField(
            controller: controller,
            enabled: !active,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              suffixText: '分钟',
              border: const OutlineInputBorder(),
            ),
            validator: (text) {
              final value = int.tryParse(text ?? '');
              return value == null || value < 1 || value > max
                  ? '请输入 1～$max 的整数'
                  : null;
            },
          ),
        );
    return AlertDialog(
      title: Text(widget.focusMode ? '番茄钟设置' : '倒计时设置'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active) const Text('重置当前计时后可修改时长。'),
                field(widget.focusMode ? '专注时长' : '倒计时时长', main, 180),
                if (widget.focusMode) ...[
                  field('短休息', short, 60),
                  field('长休息', long, 60),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('完成提示音'),
                  value: sound,
                  onChanged: (value) {
                    if (value) widget.armSound();
                    setState(() => sound = value);
                  },
                ),
                const Text(
                  '请保持页面在前台。锁屏或切到后台后，不能保证准时响铃；返回时会恢复实际进度。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF989DA5)),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            widget.timer.configure(
              countdownValue: widget.focusMode ? null : int.tryParse(main.text),
              focusValue: widget.focusMode ? int.tryParse(main.text) : null,
              shortValue: int.tryParse(short.text),
              longValue: int.tryParse(long.text),
              soundValue: sound,
            );
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
