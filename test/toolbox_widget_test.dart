import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_stub.dart';
import 'package:time_nest/tools/basic_tools.dart';
import 'package:time_nest/tools/toolbox_screen.dart';

void main() {
  Future<void> launch(WidgetTester tester, Widget child, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    );
    await tester.pump();
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(736, 320),
    const Size(1280, 720),
  ]) {
    testWidgets('all tools render and scroll with keyboard at $size', (
      tester,
    ) async {
      for (final tool in toolboxTools) {
        await launch(
          tester,
          ToolPage(key: ValueKey(tool.title), tool: tool),
          size,
        );
        expect(find.text(tool.title), findsOneWidget);
        expect(tester.takeException(), isNull, reason: tool.title);
        final fields = find.byType(TextField);
        if (fields.evaluate().isNotEmpty) {
          await tester.tap(fields.first);
          await tester.pump();
          tester.view.viewInsets = FakeViewPadding(bottom: size.height * .4);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${tool.title} keyboard',
          );
          tester.view.resetViewInsets();
          await tester.pump();
        }
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -450),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${tool.title} scroll');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'calculator input and result survive rotation and can be copied',
    (tester) async {
      await launch(
        tester,
        ToolPage(tool: toolboxTools.first),
        const Size(390, 844),
      );
      await tester.enterText(find.byType(TextField), '12*(3+4)');
      await tester.ensureVisible(find.text('计算结果'));
      await tester.tap(find.text('计算结果'));
      await tester.pump();
      expect(find.text('84'), findsOneWidget);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12*(3+4)',
      );
      expect(find.text('84'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'clock toolbox entry returns without changing saved settings or timer',
    (tester) async {
      final browser = MemoryBrowserClient(introSeen: true);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ShikeApp(browser: browser));
      await tester.pump();
      final settings = browser.settings, timer = browser.timer;
      await tester.tapAt(const Offset(100, 150));
      await tester.pump();
      await tester.tap(find.byTooltip('工具箱'));
      await tester.pumpAndSettle();
      expect(find.text('让日常小事，简单一点。'), findsOneWidget);
      await tester.tap(find.text('计算器'));
      await tester.pumpAndSettle();
      expect(find.byType(CalculatorTool), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      expect(browser.settings, settings);
      expect(browser.timer, timer);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
