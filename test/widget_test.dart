import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/app_version.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

class TestBrowser extends MemoryBrowserClient {
  TestBrowser({super.settings, super.introSeen = true});
  BrowserState current = const BrowserState();
  bool? requestedAwake;
  int starts = 0;
  int refreshes = 0;
  @override
  BrowserState get state => current;
  void update(BrowserState state) {
    current = state;
    notifyListeners();
  }

  @override
  void setKeepAwake(bool enabled) => requestedAwake = enabled;
  @override
  void startPresentation() => starts++;
  @override
  void refreshPage() => refreshes++;
}

void main() {
  final fixed = DateTime(2026, 10, 16, 14, 47, 8, 357);

  Future<void> launch(
    WidgetTester tester,
    TestBrowser browser, {
    DateTime Function()? now,
    Size size = const Size(736, 414),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShikeApp(browser: browser, now: now ?? () => fixed),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    await tester.tap(find.byTooltip('展示设置'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('renders one snapshot with date and three digit groups', (
    tester,
  ) async {
    await launch(tester, TestBrowser());
    expect(find.text('2026年10月16日  星期五'), findsOneWidget);
    expect(find.text('14:47'), findsOneWidget);
    expect(find.text(':08'), findsOneWidget);
    expect(find.text('.3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'small version sits below the clock title and follows its visibility',
    (tester) async {
      await launch(tester, TestBrowser(), size: const Size(320, 568));
      await tester.tapAt(const Offset(100, 100));
      await tester.pump();
      final version = find.byKey(const Key('home-version'));
      expect(find.text('版本 $appVersion'), findsOneWidget);
      final titleRect = tester.getRect(find.text('此刻'));
      final versionRect = tester.getRect(version);
      expect(versionRect.top, greaterThanOrEqualTo(titleRect.bottom));
      expect(versionRect.left, titleRect.left);
      expect(tester.widget<Text>(version).style!.fontSize, 9);
      await tester.pump(const Duration(seconds: 5));
      expect(version.hitTestable(), findsNothing);
      await tester.tapAt(const Offset(100, 100));
      await tester.pump();
      await tester.tap(find.byTooltip('切换模式'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('倒计时'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(version, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(414, 736),
    const Size(320, 568),
    const Size(736, 320),
    const Size(1280, 720),
  ]) {
    testWidgets('clock does not overflow $size', (tester) async {
      await launch(tester, TestBrowser(introSeen: false), size: size);
      expect(find.text('14:47'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('intro never blocks time and dismissal persists', (tester) async {
    final browser = TestBrowser(introSeen: false);
    await launch(tester, browser);
    expect(find.text('14:47'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    expect(browser.introSeen, isTrue);
    expect(find.text('横放手机，让时间安静一点。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Mac introduction and settings describe native capabilities', (
    tester,
  ) async {
    final browser = TestBrowser(introSeen: false)
      ..current = const BrowserState(nativeApp: true);
    await launch(tester, browser, size: const Size(1200, 900));
    expect(find.text('让时间在桌面上安静一点。'), findsOneWidget);
    expect(find.textContaining('Safari'), findsNothing);
    await openSettings(tester);
    expect(find.text('Mac 应用'), findsOneWidget);
    expect(find.text('检查更新'), findsNothing);
    expect(find.text('刷新页面'), findsNothing);
    expect(find.textContaining('Safari'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('start explicitly enables wake preference', (tester) async {
    final browser = TestBrowser(introSeen: false);
    await launch(tester, browser);
    await tester.tap(find.text('开始展示'));
    await tester.pump();
    expect(browser.requestedAwake, isTrue);
    expect(browser.starts, 1);
    expect(ClockSettings.decode(browser.settings).keepAwake, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('toolbar hides after idle and settings remain open', (
    tester,
  ) async {
    await launch(tester, TestBrowser());
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await openSettings(tester);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('时间格式'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(); // Start the route's reverse transition.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('时间格式'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing format and hiding seconds persists preferences', (
    tester,
  ) async {
    final browser = TestBrowser();
    await launch(tester, browser);
    await openSettings(tester);
    await tester.ensureVisible(find.text('12 小时'));
    await tester.tap(find.text('12 小时'));
    await tester.pump();
    expect(ClockSettings.decode(browser.settings).hourCycle, 'h12');
    await tester.ensureVisible(find.text('显示秒'));
    await tester.tap(find.text('显示秒'));
    await tester.pump();
    final settings = ClockSettings.decode(browser.settings);
    expect(settings.showSeconds, isFalse);
    expect(settings.showMilliseconds, isTrue);
    expect(settings.effectiveMilliseconds, isFalse);
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('02:47'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
    expect(find.byKey(const Key('clock-seconds')), findsNothing);
    expect(find.byKey(const Key('clock-milliseconds')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden page pauses and resume immediately reads wall clock', (
    tester,
  ) async {
    final browser = TestBrowser();
    var now = fixed;
    await launch(tester, browser, now: () => now);
    browser.update(const BrowserState(visible: false));
    await tester.pump();
    now = DateTime(2027, 1, 1, 0, 0, 0, 7);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('14:47'), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      browser.update(BrowserState(resumeSerial: i));
      await tester.pump();
    }
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('.0'), findsOneWidget);
    expect(find.text('2027年1月1日  星期五'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refresh button invokes browser and disables while loading', (
    tester,
  ) async {
    final browser = TestBrowser();
    await launch(tester, browser);
    await openSettings(tester);
    await tester.ensureVisible(find.text('刷新页面'));
    await tester.tap(find.text('刷新页面'));
    expect(browser.refreshes, 1);
    browser.update(const BrowserState(refreshing: true));
    await tester.pump();
    expect(find.text('正在刷新…'), findsOneWidget);
    await tester.tap(find.text('正在刷新…'));
    expect(browser.refreshes, 1);
    browser.update(const BrowserState(updateError: true));
    await tester.pump();
    expect(find.text('刷新页面'), findsOneWidget);
    expect(find.text('更新检查或加载失败，当前版本仍可使用。请联网后重试。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(736, 320),
    const Size(1280, 720),
  ]) {
    testWidgets('update notice stays visible with hidden toolbar at $size', (
      tester,
    ) async {
      final browser = TestBrowser();
      await launch(tester, browser, size: size);
      expect(find.text('立即更新'), findsNothing);
      browser.update(const BrowserState(updateAvailable: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('新版本已就绪'), findsOneWidget);
      expect(find.text('立即更新').hitTestable(), findsOneWidget);
      expect(browser.refreshes, 0);
      await tester.tap(find.text('立即更新'));
      expect(browser.refreshes, 1);
      browser.update(
        const BrowserState(updateAvailable: true, refreshing: true),
      );
      await tester.pump();
      await tester.tap(find.text('正在更新…'));
      expect(browser.refreshes, 1);
      // A failed activation may remove the waiting worker. Keep the retry
      // action visible even when updateAvailable becomes false.
      browser.update(const BrowserState(updateError: true));
      await tester.pump();
      expect(find.text('更新失败，请重试'), findsOneWidget);
      await tester.tap(find.text('重试更新'));
      expect(browser.refreshes, 2);
      await openSettings(tester);
      expect(find.text('重试更新').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      browser.update(const BrowserState());
      await tester.pump();
      expect(find.text('新版本已就绪'), findsNothing);
      expect(find.text('重试更新'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'visible inactive window keeps ticking while another window has focus',
    (tester) async {
      var now = fixed;
      await launch(tester, TestBrowser(), now: () => now);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      now = fixed.add(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text(':10'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('corrupt saved settings never prevents the clock', (
    tester,
  ) async {
    await launch(tester, TestBrowser(settings: '{broken'));
    expect(find.text('14:47'), findsOneWidget);
    expect(find.text('.3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
