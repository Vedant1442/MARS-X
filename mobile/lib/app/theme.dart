import 'package:flutter/material.dart';

class MarsTheme {
  static const Color ink = Color(0xFFF5F1E8);
  static const Color bg = Color(0xFFF5F1E8);
  static const Color panel = Color(0xFFEEEBE3);
  static const Color paper = Color(0xFFFAF8F2);
  static const Color line = Color(0xFFD9D4C9);
  static const Color lineStrong = Color(0xFFB9B2A3);
  static const Color fg = Color(0xFF263238);
  static const Color dim = Color(0xFF5B676C);
  static const Color mars = Color(0xFFB85C43);
  static const Color marsDeep = Color(0xFF964630);
  static const Color sage = Color(0xFF75837B);
  static const Color atmos = Color(0xFF789BA8);
  static const Color atmosDeep = Color(0xFF46697A);
  static const Color gold = Color(0xFFD3A24C);
  static const Color mapBg = Color(0xFF241B17);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.light(
        primary: marsDeep,
        secondary: atmosDeep,
        surface: paper,
        onPrimary: ink,
        onSecondary: ink,
        onSurface: fg,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: line,
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: line),
        ),
      ),
    );
  }
}
