import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clock/clock_controller.dart';
import '../clock/clock_settings.dart';
import '../platform/browser_client.dart';
import 'clock_face.dart';
import 'settings_panel.dart';

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key, this.browser, this.now});
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
    _clock.setVisible(_browser.state.visible);
    _resumeSerial = _browser.state.resumeSerial;
    _browser.addListener(_browserChanged);
    WidgetsBinding.instance.addObserver(this);
    // This restores an explicit, previously persisted user preference.
    if (_settings.value.keepAwake) _browser.setKeepAwake(true);
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
  }

  void _browserChanged() {
    if (!mounted) return;
    final state = _browser.state;
    _clock.setVisible(
      _lifecycleVisible && state.visible,
      resample: state.resumeSerial != _resumeSerial,
    );
    _resumeSerial = state.resumeSerial;
    setState(() {});
  }

  void _changeSettings(ClockSettings value) {
    final wasAwake = _settings.value.keepAwake;
    if (_settings.value == value) return;
    _settings.value = value;
    _clock.updateSettings(value);
    _browser.writeSettings(value.encode());
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
                          child: ClockFace(
                            clock: _clock,
                            settings: _settings.value,
                          ),
                        ),
                      ),
                      if (_introVisible)
                        _Intro(
                          onDismiss: _dismissIntro,
                          onStart: _startPresentation,
                        )
                      else
                        const SizedBox(height: 52),
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
                                const Text(
                                  '此刻',
                                  style: TextStyle(
                                    fontSize: 18,
                                    letterSpacing: 4,
                                    color: Color(0xFFB5B9C1),
                                  ),
                                ),
                                const Spacer(),
                                if (!_introVisible)
                                  TextButton(
                                    onPressed: _startPresentation,
                                    child: const Text('开始展示'),
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
