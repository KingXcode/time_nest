import 'package:flutter/material.dart';

import '../app_version.dart';
import '../clock/clock_settings.dart';
import '../platform/browser_client.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.browser,
    required this.onClose,
  });

  final ValueNotifier<ClockSettings> settings;
  final ValueChanged<ClockSettings> onChanged;
  final BrowserClient browser;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: Listenable.merge([settings, browser]),
      builder: (context, _) {
        final value = settings.value;
        final state = browser.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '展示设置',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭设置',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Section('展示预设'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final entry in const {
                          'office': '办公',
                          'bedside': '床头',
                          'minimal': '极简',
                        }.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: value.preset == entry.key,
                            onSelected: (_) =>
                                onChanged(value.applyPreset(entry.key)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _Note('办公显示秒，床头使用暖色与夜间调暗，极简只显示时分。仍可继续调整下面的选项。'),
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
                      subtitle: const Text('1 位小数（0.1 秒），关闭可减少耗电'),
                      value: value.effectiveMilliseconds,
                      onChanged: value.showSeconds
                          ? (enabled) => onChanged(
                              value.copyWith(showMilliseconds: enabled),
                            )
                          : null,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示日期'),
                      value: value.showDate,
                      onChanged: (enabled) =>
                          onChanged(value.copyWith(showDate: enabled)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('暖色文字'),
                      value: value.tone == 'warm',
                      onChanged: (enabled) => onChanged(
                        value.copyWith(tone: enabled ? 'warm' : 'neutral'),
                      ),
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
                    const _Note('主界面的方向按钮支持自动、手动横屏与手动竖屏。手动切换只旋转页面，不改变系统方向锁定。'),
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
                        OutlinedButton.icon(
                          onPressed: state.refreshing
                              ? null
                              : browser.refreshPage,
                          icon: state.refreshing
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(state.refreshing ? '正在刷新…' : '刷新页面'),
                        ),
                        OutlinedButton(
                          onPressed: state.refreshing
                              ? null
                              : browser.checkForUpdate,
                          child: const Text('检查更新'),
                        ),
                        if (state.updateAvailable)
                          FilledButton(
                            onPressed: state.refreshing
                                ? null
                                : browser.applyUpdate,
                            child: const Text('更新并重新加载'),
                          ),
                      ],
                    ),
                    const _Note('刷新页面会先检查服务器更新，加载新版后重新打开；保留已保存的设置和计时。'),
                    const _Note('网页会自动检查并加载完整新版；也可以使用上方按钮手动更新。'),
                    if (state.updateError)
                      const _Note('更新检查或加载失败，当前版本仍可使用。请联网后重试。'),
                    const _Section('关于此刻'),
                    const Text(
                      '此刻 $appVersion',
                      style: TextStyle(fontSize: 14),
                    ),
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
