import 'package:flutter/material.dart';

import '../clock/clock_settings.dart';
import '../platform/browser_client.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.browser,
  });

  final ValueNotifier<ClockSettings> settings;
  final ValueChanged<ClockSettings> onChanged;
  final BrowserClient browser;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
    child: AnimatedBuilder(
      animation: Listenable.merge([settings, browser]),
      builder: (context, _) {
        final value = settings.value;
        final state = browser.state;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '展示设置',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭设置',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Section('时间格式'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'h23', label: Text('24 小时')),
                        ButtonSegment(value: 'h12', label: Text('12 小时')),
                      ],
                      selected: {value.hourCycle},
                      onSelectionChanged: (values) =>
                          onChanged(value.copyWith(hourCycle: values.first)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示秒'),
                      value: value.showSeconds,
                      onChanged: (enabled) =>
                          onChanged(value.copyWith(showSeconds: enabled)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示毫秒'),
                      subtitle: const Text('三位数字，按屏幕刷新；关闭可减少耗电'),
                      value: value.effectiveMilliseconds,
                      onChanged: value.showSeconds
                          ? (enabled) => onChanged(
                              value.copyWith(showMilliseconds: enabled),
                            )
                          : null,
                    ),
                    const _Section('文字亮度'),
                    _IntensitySlider(
                      value: value.textIntensity,
                      label: '日常文字亮度',
                      onChanged: (brightness) =>
                          onChanged(value.copyWith(textIntensity: brightness)),
                    ),
                    const _Note('只改变文字配色，不控制系统屏幕亮度。夜间请同时降低设备背光。'),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('夜间模式'),
                      subtitle: const Text('按设备本地时间自动切换'),
                      value: value.nightEnabled,
                      onChanged: (enabled) =>
                          onChanged(value.copyWith(nightEnabled: enabled)),
                    ),
                    if (value.nightEnabled) ...[
                      _TimeField(
                        label: '夜间开始',
                        value: value.nightStart,
                        onChanged: (time) =>
                            onChanged(value.copyWith(nightStart: time)),
                      ),
                      _TimeField(
                        label: '夜间结束',
                        value: value.nightEnd,
                        onChanged: (time) =>
                            onChanged(value.copyWith(nightEnd: time)),
                      ),
                      _IntensitySlider(
                        value: value.nightIntensity,
                        label: '夜间文字亮度',
                        onChanged: (brightness) => onChanged(
                          value.copyWith(nightIntensity: brightness),
                        ),
                      ),
                      const _Note('包含开始、不含结束；支持跨午夜。起止相同不启用该时段。夜间不会比日常更亮。'),
                    ],
                    const _Section('展示与常亮'),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('保持屏幕常亮'),
                      subtitle: Text(state.wakeLabel),
                      value: value.keepAwake,
                      onChanged: (enabled) =>
                          onChanged(value.copyWith(keepAwake: enabled)),
                    ),
                    if (value.keepAwake && state.wakeStatus != 'active')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: state.wakeSupported
                              ? () => browser.setKeepAwake(true)
                              : null,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重试常亮'),
                        ),
                      ),
                    const _Note(
                      '若常亮不可用，可在系统“显示与亮度 → 自动锁定”中选择“永不”（设备策略允许时）。这是系统设置，离开展示后建议恢复。',
                    ),
                    if (state.fullscreenSupported)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: browser.toggleFullscreen,
                          icon: Icon(
                            state.fullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                          ),
                          label: Text(state.fullscreen ? '退出全屏' : '进入全屏'),
                        ),
                      ),
                    if (state.fullscreenError) const _Note('全屏申请未成功，仍可正常使用时钟。'),
                    const _Section('主屏幕与离线'),
                    Text(state.standalone ? '已从主屏幕独立运行' : 'Safari：分享 → 添加到主屏幕'),
                    const SizedBox(height: 6),
                    const _Note('横放手机，并手动关闭方向锁定。网页不能保证自动横屏或隐藏全部系统界面。'),
                    const SizedBox(height: 12),
                    Text(
                      state.offlineLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (!state.secureContext)
                      const _Note('当前不是安全上下文；请使用 HTTPS 验证常亮与离线能力。'),
                    const _Note('首次联网并完成缓存后才能离线使用。清理浏览器数据或系统回收存储后，需要重新联网缓存。'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: browser.checkForUpdate,
                          child: const Text('检查更新'),
                        ),
                        if (state.updateAvailable)
                          FilledButton(
                            onPressed: browser.applyUpdate,
                            child: const Text('更新并重新加载'),
                          ),
                      ],
                    ),
                    if (state.updateAvailable)
                      const _Note('新版本已就绪。仅在你确认后刷新，当前展示不会被中断。'),
                    if (state.updateError)
                      const _Note('更新检查或加载失败，当前版本仍可使用。请联网后重试。'),
                    const _Section('关于此刻'),
                    const Text('此刻 1.0.0', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 6),
                    const _Note('使用设备系统时间与本地时区，不进行网络校时，也不保证毫秒级精度。'),
                    const _Note('长期展示注意散热和电池健康；发现鼓包或异常发热应停止充电使用。'),
                    const SizedBox(height: 16),
                    Text(
                      state.storageAvailable
                          ? '设置自动保存在此浏览器中'
                          : '本地存储不可用：设置仅在当前页面生效',
                      style: TextStyle(
                        fontSize: 12,
                        color: state.storageAvailable
                            ? const Color(0xFF989DA5)
                            : const Color(0xFFE7BB88),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => onChanged(const ClockSettings()),
                      child: const Text('恢复默认设置'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        color: Color(0xFFAAAEB6),
        fontSize: 12,
        letterSpacing: 1.5,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        height: 1.7,
        color: Color(0xFF989DA5),
      ),
    ),
  );
}

class _IntensitySlider extends StatelessWidget {
  const _IntensitySlider({
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final double value;
  final String label;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label  ${(value * 100).round()}%',
        style: const TextStyle(fontSize: 13),
      ),
      Slider(
        value: value,
        min: .15,
        max: 1,
        divisions: 17,
        label: '${(value * 100).round()}%',
        semanticFormatterCallback: (value) =>
            '$label ${(value * 100).round()}%',
        onChanged: onChanged,
      ),
    ],
  );
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final parts = value.split(':');
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Semantics(
          label: '$label 小时',
          child: DropdownButton<int>(
            value: int.parse(parts[0]),
            items: List.generate(
              24,
              (hour) => DropdownMenuItem(
                value: hour,
                child: Text(hour.toString().padLeft(2, '0')),
              ),
            ),
            onChanged: (hour) {
              if (hour != null) {
                onChanged('${hour.toString().padLeft(2, '0')}:${parts[1]}');
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(':'),
        ),
        Semantics(
          label: '$label 分钟',
          child: DropdownButton<int>(
            value: int.parse(parts[1]),
            items: List.generate(
              60,
              (minute) => DropdownMenuItem(
                value: minute,
                child: Text(minute.toString().padLeft(2, '0')),
              ),
            ),
            onChanged: (minute) {
              if (minute != null) {
                onChanged('${parts[0]}:${minute.toString().padLeft(2, '0')}');
              }
            },
          ),
        ),
      ],
    );
  }
}
