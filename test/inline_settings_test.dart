import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_stub.dart';
import 'package:time_nest/ui/settings_panel.dart';

void main() {
  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(320, 568),
    bool introSeen = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShikeApp(
        browser: MemoryBrowserClient(introSeen: introSeen),
        now: () => DateTime(2026, 10, 17, 12),
      ),
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byTooltip('展示设置'));
    await tester.pump();
  }

  testWidgets(
    'inline settings preview changes and toggle restores full space',
    (tester) async {
      await launch(tester);
      final panel = find.byType(SettingsPanel);
      final display = find.byKey(const Key('display-area'));
      final previewHeight = tester.getSize(display).height;
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('极简'));
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(find.byKey(const Key('clock-date')), findsNothing);
      expect(find.byKey(const Key('clock-seconds')), findsNothing);
      expect(find.text('12:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      expect(find.byTooltip('展示设置').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('展示设置'));
      await tester.pump();
      expect(panel, findsNothing);
      expect(tester.getSize(display).height, greaterThan(previewHeight));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resize keeps settings open and retains independent scroll', (
    tester,
  ) async {
    await launch(tester);
    await tester.ensureVisible(find.text('暖色文字'));
    await tester.pump();
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(SettingsPanel),
        matching: find.byType(Scrollable),
      ),
    );
    final offset = scroll.position.pixels;
    expect(offset, greaterThan(0));
    tester.view.physicalSize = const Size(568, 320);
    await tester.pump();
    final settings = tester.getRect(find.byKey(const Key('settings-dock')));
    final display = tester.getRect(find.byKey(const Key('display-area')));
    expect(settings.left, greaterThan(display.right));
    expect(scroll.position.pixels, offset);
    await tester.ensureVisible(find.text('暖色文字'));
    await tester.tap(find.text('暖色文字'));
    await tester.pump();
    final panel = tester.widget<SettingsPanel>(find.byType(SettingsPanel));
    expect(ClockSettings.decode(panel.browser.readSettings()).tone, 'warm');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(SettingsPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('timer controls remain usable beside the settings', (
    tester,
  ) async {
    await launch(tester, size: const Size(736, 320));
    await tester.tap(find.byTooltip('切换模式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('倒计时'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsPanel), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('timer-primary')));
    await tester.tap(find.byKey(const Key('timer-primary')));
    await tester.pump();
    expect(find.text('倒计时进行中'), findsOneWidget);
    expect(find.byType(SettingsPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('start presentation closes settings on first visit', (
    tester,
  ) async {
    await launch(tester, introSeen: false);
    // Mobile presentation now lives in the single-row header menu.
    await tester.tap(find.byTooltip('切换模式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('开始展示'));
    await tester.pump();
    expect(find.byType(SettingsPanel), findsNothing);
    expect(find.text('知道了'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
