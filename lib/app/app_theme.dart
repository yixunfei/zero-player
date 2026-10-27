import 'package:flutter/material.dart';
import 'app_fonts.dart';

ThemeData buildAppTheme(
  Brightness brightness,
  bool television,
  String style, {
  String font = 'xiaolai',
}) {
  final family = appFontFamily(font);
  final baseText = Typography.englishLike2021;
  TextStyle regular(TextStyle? value) =>
      value!.copyWith(fontWeight: FontWeight.w400);
  final text = font == 'xiaolai'
      ? TextTheme(
          displayLarge: regular(baseText.displayLarge),
          displayMedium: regular(baseText.displayMedium),
          displaySmall: regular(baseText.displaySmall),
          headlineLarge: regular(baseText.headlineLarge),
          headlineMedium: regular(baseText.headlineMedium),
          headlineSmall: regular(baseText.headlineSmall),
          titleLarge: regular(baseText.titleLarge),
          titleMedium: regular(baseText.titleMedium),
          titleSmall: regular(baseText.titleSmall),
          bodyLarge: regular(baseText.bodyLarge),
          bodyMedium: regular(baseText.bodyMedium),
          bodySmall: regular(baseText.bodySmall),
          labelLarge: regular(baseText.labelLarge),
          labelMedium: regular(baseText.labelMedium),
          labelSmall: regular(baseText.labelSmall),
        )
      : baseText;
  final dark = brightness == Brightness.dark;
  final cinema = dark && style != 'dark';
  final background = dark
      ? (cinema ? const Color(0xff08090d) : const Color(0xff12191d))
      : const Color(0xfff6f3ed);
  final scheme = ColorScheme.fromSeed(
    seedColor: cinema ? const Color(0xffd9b77b) : const Color(0xff577f79),
    brightness: brightness,
    surface: background,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: family,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: television
        ? VisualDensity.comfortable
        : VisualDensity.standard,
    focusColor: scheme.primary.withValues(alpha: .35),
    textTheme: text.apply(
      fontFamily: family,
      fontSizeFactor: television ? 1.2 : 1,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      toolbarHeight: television ? 56 : 48,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 17,
        fontFamily: family,
        fontWeight: font == 'xiaolai' ? FontWeight.w400 : FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: background),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outline, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
  );
}
