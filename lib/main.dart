import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'platform/browser_client.dart';
import 'platform/viewport_insets.dart';
import 'platform/native_runtime_stub.dart'
    if (dart.library.io) 'platform/native_runtime.dart'
    as native;
import 'ui/clock_face.dart';
import 'ui/orientation_frame.dart';
import 'clock/clock_settings.dart';
import 'ui/clock_screen.dart';
import 'ui/apple_theme.dart';
import 'ui/apple_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await native.initializeNativeRuntime();
    runApp(const ShikeApp());
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Mac 数据服务启动失败，请重新打开应用。'),
                AppleButton.text(onPressed: main, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShikeApp extends StatefulWidget {
  const ShikeApp({super.key, this.browser, this.now});

  final BrowserClient? browser;
  final DateTime Function()? now;

  @override
  State<ShikeApp> createState() => _ShikeAppState();
}

class _ShikeAppState extends State<ShikeApp> {
  late final BrowserClient browser = widget.browser ?? createBrowserClient();
  late String orientation = ClockSettings.decode(browser.readSettings())
      .orientation;

  @override
  void dispose() {
    if (widget.browser == null) browser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '此刻',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: browser.state.nativeApp
        ? appleTheme()
        : ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: 'ShikeSans',
            scaffoldBackgroundColor: clockBackground,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFBBC4D4),
              brightness: Brightness.dark,
              surface: const Color(0xFF14161B),
              primary: const Color(0xFFD1D8E3),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF14161B),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            ),
          ),
    builder: (context, child) => BrowserViewportInsets(
      child: OrientationFrame(orientation: orientation, child: child!),
    ),
    home: ClockScreen(
      browser: browser,
      now: widget.now,
      onOrientationChanged: (value) {
        if (orientation != value) setState(() => orientation = value);
      },
    ),
  );
}
