import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/timer_controller.dart';
import 'package:time_nest/dashboard/crypto_panel.dart';
import 'package:time_nest/dashboard/dashboard_screen.dart';
import 'package:time_nest/dashboard/news_panel.dart';
import 'package:time_nest/dashboard/weather_panel.dart';
import 'package:time_nest/platform/browser_client.dart';
import 'package:time_nest/platform/browser_client_stub.dart';
import 'package:time_nest/toolbox/toolbox_screen.dart';
import 'package:time_nest/ui/apple_button.dart';
import 'package:time_nest/ui/apple_theme.dart';
import 'package:time_nest/ui/settings_panel.dart';
import 'package:time_nest/ui/timer_face.dart';

import 'dashboard_widget_test.dart' show FixtureDashboardClient, setSize;
import 'toolbox_widget_test.dart' show FixtureNetworkToolsClient;

class _MacBrowser extends MemoryBrowserClient {
  @override
  BrowserState get state => const BrowserState(
    nativeApp: true,
    fullscreenSupported: true,
    wakeSupported: true,
  );
}

Widget _frame(Widget page, double scale) => MaterialApp(
  theme: appleTheme(),
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

Widget _scroll(Widget child) => Scaffold(
  body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
);

// The integration entry point runs these same layouts with real macOS fonts.
void main() {
  for (final viewport in [
    (const Size(640, 480), 1.0),
    (const Size(640, 480), 2.0),
    (const Size(1280, 800), 1.0),
    (const Size(1280, 800), 2.0),
  ]) {
    testWidgets(
      'Apple pages retain their layout without overflow at $viewport',
      (tester) async {
        setSize(tester, viewport.$1);
        final client = FixtureDashboardClient();
        final browser = _MacBrowser();
        final settings = ValueNotifier(
          const ClockSettings(nightEnabled: true, keepAwake: true),
        );
        final intensity = ValueNotifier(1.0);
        final timer =
            TimerController(
                save: (_) => true,
                now: () => DateTime(2026, 10, 21, 12),
              )
              ..mode = 'countdown'
              ..setVisible(false);
        addTearDown(browser.dispose);
        addTearDown(settings.dispose);
        addTearDown(intensity.dispose);
        addTearDown(timer.dispose);

        for (final page in [
          DashboardScreen(client: client),
          _scroll(
            NewsPanel(client: client, feed: 'top', onFeedChanged: (_) {}),
          ),
          _scroll(
            CryptoPanel(
              client: client,
              symbol: 'BTCUSDT',
              interval: '1d',
              onChanged: (_, _) {},
            ),
          ),
          ToolboxScreen(client: FixtureNetworkToolsClient()),
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: SettingsPanel(
                  settings: settings,
                  onChanged: (value) => settings.value = value,
                  browser: browser,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ]) {
          await tester.pumpWidget(_frame(page, viewport.$2));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
          await tester.pumpWidget(const SizedBox());
        }

        await tester.pumpWidget(
          _frame(
            Scaffold(
              body: TimerFace(
                timer: timer,
                settings: settings.value,
                intensity: intensity,
                armSound: () {},
              ),
            ),
            viewport.$2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('timer-digits')), findsOneWidget);
        await tester.tap(find.text('计时设置'));
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(
          _frame(
            _scroll(
              WeatherPanel(client: client, city: null, onCityChanged: (_) {}),
            ),
            viewport.$2,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '上海');
        await tester.tap(find.text('搜索'));
        await tester.pumpAndSettle();
        final result = find.ancestor(
          of: find.text('上海'),
          matching: find.byType(AppleButton),
        );
        expect(result, findsOneWidget);
        expect(
          tester
              .getTopLeft(
                find.descendant(of: result, matching: find.text('上海')),
              )
              .dx,
          closeTo(tester.getTopLeft(result).dx + 12, .01),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
