import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

void main() {
  Future<void> reveal(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> mode(WidgetTester tester, String label) async {
    await reveal(tester);
    await tester.tap(find.byTooltip('切换模式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final size in [
    const Size(320, 568),
    const Size(736, 320),
    const Size(1280, 720),
  ]) {
    testWidgets('presets, rotation, dialogs and timer controls work at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final browser = MemoryBrowserClient(introSeen: true);
      var now = DateTime(2026, 10, 17, 12);
      await tester.pumpWidget(ShikeApp(browser: browser, now: () => now));
      await tester.pump();
      for (final entry in {
        '手动横屏': 'landscape',
        '手动竖屏': 'portrait',
        '自动方向': 'auto',
      }.entries) {
        await reveal(tester);
        await tester.tap(
          find.byTooltip('横竖屏切换').evaluate().isNotEmpty
              ? find.byTooltip('横竖屏切换')
              : find.byTooltip('切换模式'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.ancestor(
            of: find.text(entry.key),
            matching: find.byType(CheckedPopupMenuItem<String>),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(ClockSettings.decode(browser.settings).orientation, entry.value);
        final scaffoldSize = tester.getSize(find.byType(Scaffold));
        if (entry.value == 'landscape') {
          expect(scaffoldSize.width, greaterThan(scaffoldSize.height));
        }
        if (entry.value == 'portrait') {
          expect(scaffoldSize.height, greaterThan(scaffoldSize.width));
        }
        await reveal(tester);
        await tester.tap(find.byTooltip('展示设置'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // Settings share the page with the live display even after manual
        // rotation; compare positions inside the rotated scaffold.
        final scaffold = tester.renderObject<RenderBox>(find.byType(Scaffold));
        Rect bounds(String key) {
          final box = tester.renderObject<RenderBox>(find.byKey(Key(key)));
          return box.localToGlobal(Offset.zero, ancestor: scaffold) & box.size;
        }

        final display = bounds('display-area');
        final settings = bounds('settings-dock');
        if (scaffoldSize.width > scaffoldSize.height) {
          expect(settings.left, greaterThan(display.right));
          expect(settings.top, display.top);
        } else {
          expect(settings.top, greaterThan(display.bottom));
          expect(settings.left, display.left);
        }
        expect(find.byType(Dialog), findsNothing);
        for (final preset in ['办公', '床头', '极简']) {
          await tester.tap(
            find.ancestor(
              of: find.text(preset),
              matching: find.byType(ChoiceChip),
            ),
          );
          await tester.pump();
        }
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('clock-date')), findsNothing);
        expect(find.byKey(const Key('clock-seconds')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await mode(tester, '倒计时');
      expect(find.text('05:00'), findsOneWidget);
      await tester.tap(
        find.ancestor(
          of: find.text('15 分钟'),
          matching: find.byType(ChoiceChip),
        ),
      );
      await tester.pump();
      expect(find.text('15:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('timer-primary')));
      await tester.pump();
      now = now.add(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('14:48'), findsOneWidget);
      await tester.tap(find.byKey(const Key('timer-primary')));
      await tester.pump();
      expect(find.text('已暂停'), findsOneWidget);
      await mode(tester, '番茄钟');
      await tester.tap(find.text('计时设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('请输入 1～180 的整数'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '1');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('01:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('timer-primary')));
      await tester.pump();
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('专注结束'), findsOneWidget);
      expect(find.text('开始休息'), findsOneWidget);
      await tester.tap(find.text('开始休息'));
      await tester.pump();
      expect(find.text('短休息进行中'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ShikeApp(browser: browser, now: () => now));
      await tester.pump();
      expect(find.text('短休息进行中'), findsOneWidget);
      await mode(tester, '倒计时');
      expect(find.text('14:48'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
