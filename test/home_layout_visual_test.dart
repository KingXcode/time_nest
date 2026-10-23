// Deterministic rendering fixtures, not real-time market/weather screenshots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_controller.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/home_layout.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/ui/home_layout_canvas.dart';
import 'package:time_nest/ui/home_layout_editor.dart';

import 'crypto_fixture.dart';

class VisualClient implements DashboardClient {
  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) {}
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async => DashboardData(
    fetchedAt: DateTime.now(),
    data: module == 'weather'
        ? {
            'utcOffsetSeconds': 0,
            'hours': [
              {
                'time':
                    '${DateTime.now().toIso8601String().substring(0, 13)}:00',
                'temperature': 22,
                'feels': 21,
              },
            ],
          }
        : cryptoCandlesFixture(
            args['symbol'] as String,
            args['interval'] as String,
          ),
  );
}

class VisualPage extends StatefulWidget {
  const VisualPage({super.key, required this.desktop, required this.editor});
  final bool desktop, editor;
  @override
  State<VisualPage> createState() => _VisualPageState();
}

class _VisualPageState extends State<VisualPage>
    with SingleTickerProviderStateMixin {
  late final clock = ClockController(
    vsync: this,
    settings: const ClockSettings(showMilliseconds: false),
    now: () => DateTime(2026, 10, 22, 10, 24, 36),
  )..setVisible(false);
  final prefs = DashboardPreferences(
    city: {'name': '杭州', 'latitude': 30.25, 'longitude': 120.17},
  );
  final client = VisualClient();
  late final layout = HomeLayout(
    enabled: true,
    portrait: HomeLayout.defaults(false)
        .map((k, v) => MapEntry(k, v.copyWith(visible: true))),
    landscape: HomeLayout.defaults(true)
        .map((k, v) => MapEntry(k, v.copyWith(visible: true))),
  );
  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.editor
      ? HomeLayoutEditor(
          layout: layout,
          clock: clock,
          settings: const ClockSettings(showMilliseconds: false),
          client: client,
          preferences: prefs,
          desktop: widget.desktop,
          landscape: widget.desktop,
        )
      : Scaffold(
          backgroundColor: const Color(0xFF08090B),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: HomeLayoutCanvas(
                layout: layout,
                landscape: widget.desktop,
                clock: clock,
                settings: const ClockSettings(showMilliseconds: false),
                client: client,
                preferences: prefs,
                active: true,
              ),
            ),
          ),
        );
}

void main() {
  testWidgets('Render mobile and desktop layout previews and home', (
    tester,
  ) async {
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('ShikeSans', 'assets/fonts/ShikeSans-Regular.ttf'),
      ('ClockDigits', 'assets/fonts/RobotoMono-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    for (final item in [
      (true, true, const Size(1280, 800), 'desktop-editor'),
      (false, true, const Size(390, 844), 'mobile-editor'),
      (true, false, const Size(1280, 800), 'desktop-home'),
      (false, false, const Size(390, 844), 'mobile-home'),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = item.$3;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            platform: item.$1 ? TargetPlatform.linux : TargetPlatform.android,
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'ShikeSans',
            ),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: VisualPage(
              key: ValueKey(item.$4),
              desktop: item.$1,
              editor: item.$2,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (item.$2) {
        await tester.tap(find.byKey(const ValueKey('select-weather')));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['HOME_LAYOUT_SCREENSHOTS'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/home-layout-previews/${item.$4}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
