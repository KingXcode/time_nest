import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'platform/browser_client.dart';
import 'ui/clock_face.dart';
import 'ui/clock_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShikeApp());
}

class ShikeApp extends StatelessWidget {
  const ShikeApp({super.key, this.browser, this.now});

  final BrowserClient? browser;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '此刻',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
      ),
    ),
    home: ClockScreen(browser: browser, now: now),
  );
}
