import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../clock/clock_controller.dart';
import '../clock/clock_settings.dart';
import '../clock/timer_controller.dart';
import 'timer_face.dart';
import '../platform/browser_client.dart';
import 'clock_face.dart';
import 'settings_panel.dart';
import '../dashboard/dashboard_screen.dart';
import '../toolbox/toolbox_screen.dart';

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
  final _settingsFocus = FocusNode(debugLabel: 'Display settings');
  Timer? _hideTimer;
  bool _toolbarVisible = false;
  bool _panelOpen = false;
  bool _updateRequested = false;
  bool _lifecycleVisible = true;
  late bool _introVisible;
  int _resumeSerial = 0;

  bool get _showUpdateNotice =>
      _browser.state.updateAvailable ||
      (_updateRequested &&
          (_browser.state.refreshing || _browser.state.updateError));

  void _updateFromNotice() {
    setState(() => _updateRequested = true);
    _browser.refreshPage();
  }

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
    if (!state.updateAvailable && !state.refreshing && !state.updateError) {
      _updateRequested = false;
    }
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
    setState(() => _panelOpen = false);
    _sceneFocus.requestFocus();
    _reveal();
  }

  void _toggleSettings() {
    if (_panelOpen) {
      _closeSettings();
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _panelOpen = true;
      _toolbarVisible = true;
    });
    _settingsFocus.requestFocus();
  }

  void _closeSettings() {
    setState(() => _panelOpen = false);
    _sceneFocus.requestFocus();
    _reveal();
  }

  Future<void> _openDashboard() async {
    _hideTimer?.cancel();
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DashboardScreen(now: widget.now)),
    );
    if (mounted) _reveal();
  }

  Future<void> _openToolbox() async {
    _hideTimer?.cancel();
    FocusScope.of(context).unfocus();
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ToolboxScreen()));
    if (mounted) _reveal();
  }

  bool get _compactToolbar =>
      MediaQuery.sizeOf(context).width /
          MediaQuery.textScalerOf(context).scale(1) <
      500;

  List<Widget> _toolbarControls() => [
    if (!_introVisible || _panelOpen)
      if (_compactToolbar)
        IconButton(
          tooltip: '开始展示',
          onPressed: _startPresentation,
          icon: const Icon(Icons.play_arrow_rounded),
        )
      else
        TextButton(onPressed: _startPresentation, child: const Text('开始展示')),
    PopupMenuButton<String>(
      tooltip: '横竖屏切换',
      icon: const Icon(Icons.screen_rotation_rounded, size: 22),
      initialValue: _settings.value.orientation,
      onSelected: (value) =>
          _changeSettings(_settings.value.copyWith(orientation: value)),
      itemBuilder: (_) => [
        for (final entry in const {
          'auto': '自动方向',
          'landscape': '手动横屏',
          'portrait': '手动竖屏',
        }.entries)
          CheckedPopupMenuItem(
            value: entry.key,
            checked: _settings.value.orientation == entry.key,
            child: Text(entry.value),
          ),
      ],
    ),
    IconButton(
      tooltip: '展示设置',
      onPressed: _toggleSettings,
      isSelected: _panelOpen,
      selectedIcon: const Icon(
        Icons.tune_rounded,
        color: Colors.white,
        size: 22,
      ),
      icon: const Icon(Icons.tune_rounded, size: 22),
    ),
  ];

  Widget _workspace(BoxConstraints box) {
    // OrientationFrame supplies the effective page orientation, including
    // manual rotation. Keep one Flex so rotating preserves the panel's scroll.
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Flex(
      direction: landscape ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            key: const Key('display-area'),
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _timer.mode == 'clock'
                      ? ClockFace(clock: _clock, settings: _settings.value)
                      : TimerFace(
                          timer: _timer,
                          settings: _settings.value,
                          intensity: _clock.intensity,
                          armSound: _browser.armTimerSound,
                        ),
                ),
              ),
              if (!_panelOpen)
                if (_introVisible && _timer.mode == 'clock')
                  _Intro(
                    nativeApp: _browser.state.nativeApp,
                    onDismiss: _dismissIntro,
                    onStart: _startPresentation,
                  )
                else
                  SizedBox(height: _timer.mode == 'clock' ? 52 : 28),
            ],
          ),
        ),
        if (_panelOpen) ...[
          SizedBox(width: landscape ? 16 : 0, height: landscape ? 0 : 12),
          SizedBox(
            key: const Key('settings-dock'),
            width: landscape ? (box.maxWidth * .44).clamp(260, 380) : null,
            height: landscape ? null : box.maxHeight * .60,
            child: Focus(
              focusNode: _settingsFocus,
              child: SettingsPanel(
                settings: _settings,
                onChanged: _changeSettings,
                browser: _browser,
                onClose: _closeSettings,
              ),
            ),
          ),
        ],
      ],
    );
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
    _settingsFocus.dispose();
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
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _panelOpen) {
          _closeSettings();
          return KeyEventResult.handled;
        }
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
                  top: _compactToolbar ? 112 : 52,
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, box) => _workspace(box),
                        ),
                      ),
                      if (_showUpdateNotice)
                        _UpdateNotice(
                          state: _browser.state,
                          onUpdate: _updateFromNotice,
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 96),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      PopupMenuButton<String>(
                                        tooltip: '切换模式',
                                        initialValue: _timer.mode,
                                        onSelected: (value) {
                                          if (value == 'dashboard') {
                                            _openDashboard();
                                            return;
                                          }
                                          if (value == 'toolbox') {
                                            _openToolbox();
                                            return;
                                          }
                                          if (value == 'presentation') {
                                            _startPresentation();
                                            return;
                                          }
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
                                          PopupMenuDivider(),
                                          PopupMenuItem(
                                            value: 'toolbox',
                                            child: Text('工具箱'),
                                          ),
                                          PopupMenuItem(
                                            value: 'presentation',
                                            child: Text('开始展示'),
                                          ),
                                          PopupMenuItem(
                                            value: 'dashboard',
                                            child: Text('每日看板'),
                                          ),
                                        ],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    switch (_timer.mode) {
                                                      'countdown' => '倒计时',
                                                      'focus' => '番茄钟',
                                                      _ => '此刻',
                                                    },
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (_timer.mode == 'clock')
                                                    const Text(
                                                      '版本 $appVersion',
                                                      key: Key('home-version'),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        height: 1.4,
                                                        color: Color(
                                                          0xFF8995A5,
                                                        ),
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                ],
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
                                      if (!_compactToolbar)
                                        ..._toolbarControls(),
                                    ],
                                  ),
                                  if (_compactToolbar)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: _toolbarControls(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('home-toolbox'),
                        tooltip: '工具箱',
                        onPressed: _openToolbox,
                        icon: const Icon(Icons.handyman_outlined, size: 22),
                      ),
                      IconButton(
                        tooltip: '每日看板',
                        onPressed: _openDashboard,
                        icon: const Icon(Icons.dashboard_outlined, size: 22),
                      ),
                    ],
                  ),
                ),
                if (!_introVisible &&
                    _toolbarVisible &&
                    !_panelOpen &&
                    !_showUpdateNotice)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_browser.state.wakeLabel} · 轻点屏幕唤出操作',
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

class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice({required this.state, required this.onUpdate});
  final BrowserState state;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.only(left: 14, right: 6, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF17191E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF343840)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                state.updateError ? '更新失败，请重试' : '新版本已就绪',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: state.refreshing ? null : onUpdate,
              child: Text(
                state.refreshing
                    ? '正在更新…'
                    : state.updateError
                    ? '重试更新'
                    : '立即更新',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.nativeApp,
    required this.onDismiss,
    required this.onStart,
  });
  final bool nativeApp;
  final VoidCallback onDismiss;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          nativeApp ? '让时间在桌面上安静一点。' : '横放手机，让时间安静一点。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFB5B9C1), fontSize: 13),
        ),
        const SizedBox(height: 5),
        Text(
          nativeApp
              ? '点击窗口打开设置 · 开始展示可进入全屏并保持常亮'
              : 'Safari 分享 → 添加到主屏幕 · 轻点屏幕打开设置',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF989DA5),
            fontSize: 11,
            height: 1.6,
          ),
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
