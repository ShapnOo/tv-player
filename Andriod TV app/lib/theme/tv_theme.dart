import 'package:flutter/material.dart';

class TVTheme {
  static const Color background = Color(0xFF0A0B0E);
  static const Color surface = Color(0xFF12151C);
  static const Color surfaceElevated = Color(0xFF1A1E27);
  static const Color surfaceGlass = Color(0xCC141720);
  
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldGlow = Color(0x6610B981);
  static const Color crimson = Color(0xFFE50914);
  static const Color cyan = Color(0xFF38BDF8);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0x1AFFFFFF);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: emerald,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: emerald,
        secondary: cyan,
        surface: surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
