// Deterministic layout fixtures, not a browser or real iPhone acceptance test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/home_layout.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/platform/browser_client_stub.dart';
import 'package:time_nest/ui/clock_screen.dart';

import 'home_layout_visual_test.dart' as fixture;

class _Client extends fixture.VisualClient {
  @override
  String? readPreferences() => DashboardPreferences(
    city: {'name': '杭州', 'latitude': 30.25, 'longitude': 120.17},
  ).encode();
}

void main() {
  testWidgets('complete phone home renders inside safe bounds', (tester) async {
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('ShikeSans', 'assets/fonts/ShikeSans-Regular.ttf'),
      ('ClockDigits', 'assets/fonts/RobotoMono-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    final modules = HomeLayout.defaults(false)
        .map((k, v) => MapEntry(k, v.copyWith(visible: true)));
    final browser = MemoryBrowserClient(
      introSeen: true,
      settings: ClockSettings(
        showMilliseconds: false,
        homeLayout: HomeLayout(
          enabled: true,
          portrait: HomeLayout.arranged(modules, wide: false),
        ),
      ).encode(),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'ShikeSans',
            ),
            scaffoldBackgroundColor: const Color(0xFF08090B),
          ),
          home: ClockScreen(
            browser: browser,
            dashboardClient: _Client(),
            now: () => DateTime(2026, 10, 28, 20, 47, 50),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tapAt(const Offset(10, 180));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    if (Platform.environment['HOME_LAYOUT_SCREENSHOTS'] == '1') {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/home-layout-previews/mobile-full-home-safe-area.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
