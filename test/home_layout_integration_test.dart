import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/home_layout.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/ui/clock_screen.dart';
import 'package:time_nest/ui/home_layout_canvas.dart';
import 'package:time_nest/platform/browser_client.dart';

import 'widget_test.dart' show TestBrowser;

class _Client implements DashboardClient {
  String? raw;
  int requests = 0;
  @override
  String? readPreferences() => raw;
  @override
  bool writePreferences(String value) {
    raw = value;
    return true;
  }

  @override
  void openUrl(String url) {}
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    requests++;
    throw const DashboardException('offline');
  }
}

class _FailingBrowser extends TestBrowser {
  _FailingBrowser()
    : super(
        settings: const ClockSettings(
          showSeconds: false,
          showMilliseconds: false,
        ).encode(),
      );
  @override
  bool writeSettings(String value) => false;
}

void main() {
  Future<void> launch(
    WidgetTester tester,
    TestBrowser browser,
    _Client client, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(platform: platform),
        home: ClockScreen(
          browser: browser,
          dashboardClient: client,
          now: () => DateTime(2026, 10, 22, 10),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> editor(WidgetTester tester) async {
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    await tester.tap(find.byTooltip('切换模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页布局'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Save persists both orientations; cancel and reload preserve original',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final browser = TestBrowser(
        settings: const ClockSettings(
          showMilliseconds: false,
          showSeconds: false,
        ).encode(),
      );
      final client = _Client();
      await launch(tester, browser, client);
      expect(find.byType(HomeLayoutCanvas), findsNothing);
      expect(client.requests, 0);
      await editor(tester);
      await tester.tap(find.byKey(const Key('edit-portrait')));
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('edit-time')),
        const Offset(0, 30),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('edit-landscape')));
      await tester.pump();
      await tester.tap(find.byTooltip('缩小'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-layout')));
      await tester.pumpAndSettle();
      final saved = browser.settings;
      final layout = ClockSettings.decode(saved).homeLayout!;
      expect(layout.enabled, isTrue);
      expect(layout.portrait['time']!.y, greaterThan(.2));
      expect(layout.landscape['time']!.width, lessThan(.8));
      expect(
        tester
            .widget<HomeLayoutCanvas>(find.byType(HomeLayoutCanvas))
            .landscape,
        isFalse,
      );
      await editor(tester);
      await tester.tap(find.text('重置'));
      await tester.pump();
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(browser.settings, saved);
      await tester.pumpWidget(const SizedBox());
      await launch(tester, browser, client);
      expect(
        tester.widget<HomeLayoutCanvas>(find.byType(HomeLayoutCanvas)).layout,
        layout,
      );
      await tester.tapAt(const Offset(100, 100));
      await tester.pump();
      await tester.tap(find.byTooltip('展示设置'));
      await tester.pump();
      expect(
        tester
            .widget<HomeLayoutCanvas>(find.byType(HomeLayoutCanvas))
            .landscape,
        isFalse,
        reason: 'settings dock must not change portrait profile',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Layout save failure stays usable and warns before reload', (
    tester,
  ) async {
    final browser = _FailingBrowser();
    final client = _Client();
    await launch(tester, browser, client);
    final original = browser.settings;
    await editor(tester);
    await tester.tap(find.byKey(const Key('save-layout')));
    await tester.pumpAndSettle();
    expect(find.text('布局无法保存，当前会话仍可使用，刷新后可能丢失。'), findsOneWidget);
    expect(find.byType(HomeLayoutCanvas), findsOneWidget);
    expect(browser.settings, original);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Desktop remains landscape in tall window, mobile follows page orientation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final browser = TestBrowser(
        settings: ClockSettings(
          homeLayout: HomeLayout(enabled: true),
          showMilliseconds: false,
        ).encode(),
      );
      final client = _Client();
      await launch(tester, browser, client, platform: TargetPlatform.macOS);
      expect(
        tester
            .widget<HomeLayoutCanvas>(find.byType(HomeLayoutCanvas))
            .landscape,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await launch(tester, browser, client);
      expect(
        tester
            .widget<HomeLayoutCanvas>(find.byType(HomeLayoutCanvas))
            .landscape,
        isFalse,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(
        tester
            .widget<HomeLayoutCanvas>(find.byType(HomeLayoutCanvas))
            .landscape,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Home requests stop when browser hidden and on editor route', (
    tester,
  ) async {
    final modules = {...HomeLayout.defaults(true)};
    modules['crypto'] = modules['crypto']!.copyWith(visible: true);
    final browser = TestBrowser(
      settings: ClockSettings(
        homeLayout: HomeLayout(enabled: true, landscape: modules),
        showSeconds: false,
        showMilliseconds: false,
      ).encode(),
    );
    final client = _Client();
    await launch(tester, browser, client, platform: TargetPlatform.linux);
    await tester.pump();
    expect(client.requests, 1);
    browser.update(const BrowserState(visible: false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 90));
    expect(client.requests, 1);
    browser.update(const BrowserState());
    await tester.pump();
    expect(client.requests, 2);
    await editor(tester);
    final afterOpen = client.requests;
    await tester.pump(const Duration(seconds: 31));
    expect(
      client.requests,
      afterOpen + 1,
      reason: 'only preview polls; covered home must be paused',
    );
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    final afterClose = client.requests;
    await tester.pump(const Duration(seconds: 31));
    expect(
      client.requests,
      afterClose + 1,
      reason: 'only restored home polls; disposed preview must stop',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
