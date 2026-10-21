import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_stub.dart';
import 'package:time_nest/toolbox/toolbox_screen.dart';

import 'dashboard_widget_test.dart' show FixtureDashboardClient, app, setSize;

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(736, 320),
    const Size(1280, 720),
  ]) {
    testWidgets(
      'home toolbox remains accessible without disturbing clock $size',
      (tester) async {
        setSize(tester, size);
        final browser = MemoryBrowserClient(introSeen: true);
        await tester.pumpWidget(ShikeApp(browser: browser));
        await tester.pump();
        expect(find.byKey(const Key('home-toolbox')), findsOneWidget);
        await tester.tap(find.byKey(const Key('home-toolbox')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byType(ToolboxScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(BackButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byType(ToolboxScreen), findsNothing);
        expect(find.byKey(const Key('home-toolbox')), findsOneWidget);
        expect(find.byTooltip('每日看板'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('home toolbar and toolbox fit 320px at double text scale', (
    tester,
  ) async {
    setSize(tester, const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ShikeApp(browser: MemoryBrowserClient(introSeen: true)),
    );
    await tester.pump();
    for (final mode in ['时钟', '倒计时', '番茄钟']) {
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('切换模式'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(mode).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const Key('home-toolbox')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(ToolboxScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dashboard toolbox is independent of snapshot loading', (
    tester,
  ) async {
    setSize(tester, const Size(390, 844));
    final client = FixtureDashboardClient();
    await tester.pumpWidget(app(DashboardScreen(client: client)));
    await tester.pumpAndSettle();
    final calls = List<String>.of(client.calls);
    await tester.tap(find.byKey(const ValueKey('dashboard-entry-toolbox')));
    await tester.pumpAndSettle();
    expect(find.byType(ToolboxScreen), findsOneWidget);
    expect(client.calls, calls);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('数据总览'), findsOneWidget);
    expect(client.calls, calls);
    expect(tester.takeException(), isNull);
  });
}
