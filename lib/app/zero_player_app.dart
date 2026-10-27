import 'package:flutter/material.dart';

import '../features/lab/application/lab_controller.dart';
import '../features/lab/presentation/lab_page.dart';

final class ZeroPlayerApp extends StatelessWidget {
  const ZeroPlayerApp({super.key, required this.controller});
  final LabController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zero Player · 媒体验证',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: controller.dark ? ThemeMode.dark : ThemeMode.light,
      home: LabPage(controller: controller),
    ),
  );

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF71A8FF),
      brightness: brightness,
      surface: brightness == Brightness.dark ? const Color(0xFF111722) : null,
    );
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: scheme.primary, width: 3)
            : null,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF0B1019)
          : null,
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
