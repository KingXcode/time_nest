import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/home_layout.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

void main() {
  testWidgets('manual rotation and fullscreen keep edge-to-edge home stable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    final browser = MemoryBrowserClient(
      introSeen: true,
      settings: ClockSettings(
        orientation: 'landscape',
        homeLayout: HomeLayout(enabled: true),
      ).encode(),
    );
    await tester.pumpWidget(ShikeApp(browser: browser));
    await tester.tapAt(const Offset(10, 100));
    await tester.pump(const Duration(milliseconds: 250));
    final before = tester.getRect(find.byKey(const Key('display-area')));
    await tester.tap(find.byTooltip('展示设置'));
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('display-area'))), before);
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    tester.view.padding = const FakeViewPadding(top: 59);
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('display-area'))), before);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = const FakeViewPadding();
    tester.view.viewPadding = const FakeViewPadding();
    await tester.pump();
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pump();
    expect(find.byKey(const Key('settings-dock')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(320, 568),
    const Size(393, 852),
    const Size(852, 393),
  ]) {
    for (final introSeen in [false, true]) {
      testWidgets(
        'settings do not resize saved modules at $size intro=$introSeen',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
          addTearDown(tester.view.reset);
          final settings = ClockSettings(
            homeLayout: HomeLayout(enabled: true),
            showMilliseconds: false,
          );
          final browser = MemoryBrowserClient(
            settings: settings.encode(),
            introSeen: introSeen,
          );
          await tester.pumpWidget(ShikeApp(browser: browser));
          await tester.tapAt(const Offset(10, 100));
          await tester.pump(const Duration(milliseconds: 250));
          final keys = ['display-area', 'home-time', 'home-date'];
          final before = {
            for (final key in keys)
              key: tester.getRect(find.byKey(ValueKey(key))),
          };
          final raw = browser.settings;
          for (var attempt = 0; attempt < 2; attempt++) {
            await tester.tap(find.byTooltip('展示设置'));
            await tester.pump();
            for (final key in keys) {
              expect(tester.getRect(find.byKey(ValueKey(key))), before[key]);
            }
            await tester.tap(find.text('展示设置'));
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            expect(
              FocusManager
                  .instance
                  .primaryFocus
                  ?.nearestScope
                  ?.traversalEdgeBehavior,
              TraversalEdgeBehavior.closedLoop,
            );
            final panel = tester.getRect(
              find.byKey(const Key('settings-dock')),
            );
            expect(panel.bottom, size.height);
            // Keyboard insets affect only the settings overlay, not the home canvas.
            tester.view.viewInsets = const FakeViewPadding(bottom: 180);
            tester.view.padding = const FakeViewPadding(top: 24);
            await tester.pump();
            for (final key in keys) {
              expect(tester.getRect(find.byKey(ValueKey(key))), before[key]);
            }
            expect(
              tester.getRect(find.byKey(const Key('settings-dock'))).bottom,
              lessThanOrEqualTo(size.height - 180),
            );
            tester.view.viewInsets = const FakeViewPadding();
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
            await tester.pump();
            if (attempt == 0) {
              await tester.tap(find.byTooltip('关闭设置'));
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            }
            await tester.pump();
            expect(find.byKey(const Key('settings-dock')), findsNothing);
            for (final key in keys) {
              expect(tester.getRect(find.byKey(ValueKey(key))), before[key]);
            }
            expect(browser.settings, raw);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
