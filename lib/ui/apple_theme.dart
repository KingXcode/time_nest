import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const appleBackground = Color(0xFF1C1C1E);
const appleSidebar = Color(0xFF242426);
const appleSurface = Color(0xFF2C2C2E);
const appleSeparator = Color(0xFF3A3A3C);
const appleBlue = Color(0xFF0A84FF);
const appleSecondary = Color(0xFF98989D);
const appleText = Color(0xFFF5F5F7);
const appleFont = '.AppleSystemUIFont';

bool usesAppleTheme(ThemeData theme) =>
    theme.textTheme.bodyMedium?.fontFamily == appleFont;

ThemeData appleTheme() {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  final button = TextButton.styleFrom(
    minimumSize: const Size(32, 30),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    shape: shape,
    textStyle: const TextStyle(fontFamily: appleFont, fontSize: 13),
  );
  return ThemeData(
    platform: TargetPlatform.macOS,
    brightness: Brightness.dark,
    fontFamily: appleFont,
    fontFamilyFallback: const ['PingFang SC', 'Helvetica Neue', 'ShikeSans'],
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, height: 1.35),
      bodySmall: TextStyle(fontSize: 11, height: 1.35, color: appleSecondary),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    scaffoldBackgroundColor: appleBackground,
    colorScheme: const ColorScheme.dark(
      primary: appleBlue,
      onPrimary: Colors.white,
      surface: appleSurface,
      onSurface: appleText,
      outline: appleSeparator,
      secondary: appleBlue,
    ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: appleBlue,
      scaffoldBackgroundColor: appleBackground,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: appleBackground,
      toolbarHeight: 46,
      titleTextStyle: TextStyle(
        fontFamily: appleFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: appleText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        side: const WidgetStatePropertyAll(BorderSide(color: appleSeparator)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: button),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(30, 30),
        padding: const EdgeInsets.all(5),
        iconSize: 18,
        shape: shape,
        foregroundColor: appleSecondary,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: appleSidebar,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: const TextStyle(
        fontFamily: appleFont,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: appleText,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: appleFont,
        fontSize: 13,
        height: 1.4,
        color: appleText,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: appleSurface,
      selectedColor: appleBlue.withValues(alpha: .22),
      side: BorderSide.none,
      checkmarkColor: appleBlue,
      shape: shape,
      labelStyle: const TextStyle(
        fontFamily: appleFont,
        fontSize: 12,
        color: appleText,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    dividerTheme: const DividerThemeData(
      color: appleSeparator,
      thickness: .5,
      space: 16,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: appleBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: appleSeparator),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: appleSeparator, width: .5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: appleBlue, width: 1.5),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
  );
}
