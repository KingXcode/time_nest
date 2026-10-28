import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/platform/browser_client.dart';
import 'package:time_nest/platform/browser_client_stub.dart';
import 'package:time_nest/ui/settings_panel.dart';

class UpdateBrowser extends MemoryBrowserClient {
  BrowserState current = const BrowserState();
  int checks = 0;
  @override
  BrowserState get state => current;
  void setStatus(String status) {
    current = BrowserState(updateCheckStatus: status);
    notifyListeners();
  }

  @override
  void checkForUpdate() {
    checks++;
    setStatus('checking');
  }
}

void main() {
  test('browser state parses check states without inventing progress', () {
    expect(BrowserState.fromJson({}).updateCheckStatus, 'idle');
    for (final status in [
      'checking',
      'downloading',
      'current',
      'available',
      'failed',
      'timeout',
    ]) {
      final state = BrowserState.fromJson({'updateCheckStatus': status});
      expect(state.updateCheckStatus, status);
      expect(state.updateCheckLabel, isNotNull);
      expect(
        state.checkingUpdate,
        ['checking', 'downloading'].contains(status),
      );
      expect(state.updateCheckLabel, isNot(contains('%')));
    }
  });

  testWidgets(
    'update spinner disables repeats, shows results and safely reopens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final browser = UpdateBrowser();
      final settings = ValueNotifier(const ClockSettings());
      addTearDown(browser.dispose);
      addTearDown(settings.dispose);
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsPanel(
                settings: settings,
                onChanged: (value) => settings.value = value,
                browser: browser,
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.ensureVisible(
          find.text(browser.state.checkingUpdate ? '检查更新中' : '检查更新'),
        );
      }

      await open();
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      expect(find.text('检查更新中'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('检查更新中'));
      expect(browser.checks, 1);

      // A closed settings panel owns no request timer or completion callback.
      await tester.pumpWidget(const SizedBox());
      browser.setStatus('downloading');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await open();
      expect(find.text('检查更新中'), findsOneWidget);
      expect(find.text('发现新版本，正在准备更新资源…'), findsOneWidget);
      for (final status in ['current', 'available', 'failed', 'timeout']) {
        browser.setStatus(status);
        await tester.pump();
        expect(find.text(browser.state.updateCheckLabel!), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.ensureVisible(find.text('检查更新'));
        await tester.tap(find.text('检查更新'));
        await tester.pump();
        expect(find.text('检查更新中'), findsOneWidget);
      }
      expect(browser.checks, 5);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
