import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/ui/clock_face.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

void main() {
  testWidgets(
    'landscape bedside digits avoid indicator without shrinking canvas',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(736, 320);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ShikeApp(
          browser: MemoryBrowserClient(
            introSeen: true,
            settings: const ClockSettings(
              showSeconds: false,
              showDate: true,
            ).encode(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getRect(find.byKey(const Key('display-area'))).bottom, 320);
      expect(
        tester.getRect(find.byType(ClockFace)).bottom,
        lessThanOrEqualTo(286),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 393.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'single row header and footer-free canvas respect safe areas at $width scale $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.view.physicalSize = Size(width, 852);
          tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ShikeApp(browser: MemoryBrowserClient(introSeen: true)),
          );
          await tester.tapAt(const Offset(10, 200));
          await tester.pump(const Duration(milliseconds: 200));
          final title = tester.getRect(find.byTooltip('切换模式'));
          final settings = tester.getRect(find.byTooltip('展示设置'));
          final toolbox = tester.getRect(find.byKey(const Key('home-toolbox')));
          expect((title.center.dy - settings.center.dy).abs(), lessThan(24));
          expect((settings.center.dy - toolbox.center.dy).abs(), lessThan(1));
          expect(settings.left, greaterThanOrEqualTo(title.right));
          expect(find.byTooltip('横竖屏切换'), findsNothing);
          expect(find.byKey(const Key('home-status-footer')), findsNothing);
          expect(find.textContaining('轻点屏幕唤出操作'), findsNothing);
          final display = tester.getRect(find.byKey(const Key('display-area')));
          // The canvas reaches the physical bottom; no global reserved strip.
          expect(display.bottom, 852);
          await tester.pump(const Duration(seconds: 5));
          expect(
            tester.getRect(find.byKey(const Key('display-area'))),
            display,
          );
          expect(find.textContaining('轻点屏幕唤出操作'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
