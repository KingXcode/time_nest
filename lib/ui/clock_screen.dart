import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clock/clock_controller.dart';
import '../clock/clock_settings.dart';
import '../clock/timer_controller.dart';
import 'timer_face.dart';
import '../platform/browser_client.dart';
import 'clock_face.dart';
import 'settings_panel.dart';

class ClockScreen extends StatefulWidget {
  const ClockScreen({
    super.key,
    this.browser,
    this.now,
    this.onOrientationChanged,
  });
  final ValueChanged<String>? onOrientationChanged;
  final BrowserClient? browser;
  final DateTime Function()? now;

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BrowserClient _browser;
  late final ValueNotifier<ClockSettings> _settings;
  late final ClockController _clock;
  late final TimerController _timer;
  final _sceneFocus = FocusNode(debugLabel: 'Clock scene');
  final _toolbarFocus = FocusNode(debugLabel: 'Clock toolbar');
  Timer? _hideTimer;
  bool _toolbarVisible = false;
  bool _panelOpen = false;
  bool _lifecycleVisible = true;
  late bool _introVisible;
  int _resumeSerial = 0;

  @override
  void initState() {
    super.initState();
    _browser = widget.browser ?? createBrowserClient();
    _settings = ValueNotifier(ClockSettings.decode(_browser.readSettings()));
    _introVisible = !_browser.readIntroSeen();
    _clock = ClockController(
      vsync: this,
      settings: _settings.value,
      now: widget.now,
    );
    _timer = TimerController(
      save: _browser.writeTimer,
      now: widget.now,
      raw: _browser.readTimer(),
      onComplete: _browser.playTimerSound,
    );
    _timer.setVisible(_browser.state.visible);
    _timer.addListener(_timerChanged);
    if (_timer.mode != 'clock') {
      _clock.updateSettings(
        _settings.value.copyWith(showSeconds: false, showMilliseconds: false),
      );
    }
    _clock.setVisible(_browser.state.visible);
    _resumeSerial = _browser.state.resumeSerial;
    _browser.addListener(_browserChanged);
    WidgetsBinding.instance.addObserver(this);
    // This restores an explicit, previously persisted user preference.
    if (_settings.value.keepAwake) _browser.setKeepAwake(true);
  }

  void _timerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Web window blur is `inactive`, not hidden: a visible desk clock must
    // keep ticking while the user works in another window.
    _lifecycleVisible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _clock.setVisible(
      _lifecycleVisible && _browser.state.visible,
      resample: _lifecycleVisible,
    );
    _timer.setVisible(_lifecycleVisible && _browser.state.visible);
  }

  void _browserChanged() {
    if (!mounted) return;
    final state = _browser.state;
    _clock.setVisible(
      _lifecycleVisible && state.visible,
      resample: state.resumeSerial != _resumeSerial,
    );
    _timer.setVisible(_lifecycleVisible && state.visible);
    _resumeSerial = state.resumeSerial;
    setState(() {});
  }

  void _changeSettings(ClockSettings value) {
    final wasAwake = _settings.value.keepAwake;
    if (_settings.value == value) return;
    _settings.value = value;
    _clock.updateSettings(
      _timer.mode == 'clock'
          ? value
          : value.copyWith(showSeconds: false, showMilliseconds: false),
    );
    _browser.writeSettings(value.encode());
    widget.onOrientationChanged?.call(value.orientation);
    if (wasAwake != value.keepAwake) {
      _browser.setKeepAwake(value.keepAwake);
    }
    setState(() {});
  }

  void _reveal() {
    if (!mounted) return;
    if (!_toolbarVisible) setState(() => _toolbarVisible = true);
    _hideTimer?.cancel();
    if (!_panelOpen && !_toolbarFocus.hasFocus) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && !_panelOpen && !_toolbarFocus.hasFocus) {
          setState(() => _toolbarVisible = false);
        }
      });
    }
  }

  void _dismissIntro() {
    _browser.markIntroSeen();
    setState(() => _introVisible = false);
  }

  void _startPresentation() {
    // Both capability requests originate in this user gesture, not a timer.
    _changeSettings(_settings.value.copyWith(keepAwake: true));
    _browser.startPresentation();
    if (_introVisible) _dismissIntro();
    _sceneFocus.requestFocus();
    _reveal();
  }

  Future<void> _openSettings() async {
    if (_panelOpen) return;
    _panelOpen = true;
    _hideTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (context) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                Navigator.of(context).pop();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: SettingsPanel(
              settings: _settings,
              onChanged: _changeSettings,
              browser: _browser,
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    _panelOpen = false;
    _sceneFocus.requestFocus();
    setState(() => _toolbarVisible = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _browser.removeListener(_browserChanged);
    _timer.removeListener(_timerChanged);
    _timer.dispose();
    _clock.dispose();
    _settings.dispose();
    _sceneFocus.dispose();
    _toolbarFocus.dispose();
    if (widget.browser == null) _browser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: clockBackground,
    body: Focus(
      focusNode: _sceneFocus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && !_panelOpen) _reveal();
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (_) => _reveal(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _sceneFocus.requestFocus();
            _reveal();
          },
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      const SizedBox(height: 52),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _timer.mode == 'clock'
                              ? ClockFace(
                                  clock: _clock,
                                  settings: _settings.value,
                                )
                              : TimerFace(
                                  timer: _timer,
                                  settings: _settings.value,
                                  intensity: _clock.intensity,
                                  armSound: _browser.armTimerSound,
                                ),
                        ),
                      ),
                      if (_introVisible && _timer.mode == 'clock')
                        _Intro(
                          onDismiss: _dismissIntro,
                          onStart: _startPresentation,
                        )
                      else
                        SizedBox(height: _timer.mode == 'clock' ? 52 : 28),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: ExcludeFocus(
                    excluding: !_toolbarVisible,
                    child: ExcludeSemantics(
                      excluding: !_toolbarVisible,
                      child: IgnorePointer(
                        ignoring: !_toolbarVisible,
                        child: AnimatedOpacity(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          opacity: _toolbarVisible ? 1 : 0,
                          child: Focus(
                            focusNode: _toolbarFocus,
                            onFocusChange: (_) => _reveal(),
                            child: Row(
                              children: [
                                PopupMenuButton<String>(
                                  tooltip: '切换模式',
                                  initialValue: _timer.mode,
                                  onSelected: (value) {
                                    _timer.selectMode(value);
                                    _clock.updateSettings(
                                      value == 'clock'
                                          ? _settings.value
                                          : _settings.value.copyWith(
                                              showSeconds: false,
                                              showMilliseconds: false,
                                            ),
                                    );
                                    _reveal();
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'clock',
                                      child: Text('时钟'),
                                    ),
                                    PopupMenuItem(
                                      value: 'countdown',
                                      child: Text('倒计时'),
                                    ),
                                    PopupMenuItem(
                                      value: 'focus',
                                      child: Text('番茄钟'),
                                    ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          switch (_timer.mode) {
                                            'countdown' => '倒计时',
                                            'focus' => '番茄钟',
                                            _ => '此刻',
                                          },
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const Icon(
                                          Icons.expand_more_rounded,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (!_introVisible)
                                  TextButton(
                                    onPressed: _startPresentation,
                                    child: const Text('开始展示'),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: '横竖屏切换',
                                  icon: const Icon(
                                    Icons.screen_rotation_rounded,
                                    size: 22,
                                  ),
                                  initialValue: _settings.value.orientation,
                                  onSelected: (value) => _changeSettings(
                                    _settings.value.copyWith(
                                      orientation: value,
                                    ),
                                  ),
                                  itemBuilder: (_) => [
                                    for (final entry in const {
                                      'auto': '自动方向',
                                      'landscape': '手动横屏',
                                      'portrait': '手动竖屏',
                                    }.entries)
                                      CheckedPopupMenuItem(
                                        value: entry.key,
                                        checked:
                                            _settings.value.orientation ==
                                            entry.key,
                                        child: Text(entry.value),
                                      ),
                                  ],
                                ),
                                IconButton(
                                  tooltip: '展示设置',
                                  onPressed: _openSettings,
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_introVisible && _toolbarVisible)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _browser.state.updateAvailable
                            ? '新版本已就绪 · 打开设置确认更新'
                            : '${_browser.state.wakeLabel} · 轻点屏幕唤出操作',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF989DA5),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onDismiss, required this.onStart});
  final VoidCallback onDismiss;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '横放手机，让时间安静一点。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB5B9C1), fontSize: 13),
        ),
        const SizedBox(height: 5),
        const Text(
          'Safari 分享 → 添加到主屏幕 · 轻点屏幕打开设置',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF989DA5), fontSize: 11, height: 1.6),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            TextButton(onPressed: onDismiss, child: const Text('知道了')),
            TextButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('开始展示'),
            ),
          ],
        ),
      ],
    ),
  );
}
