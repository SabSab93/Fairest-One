import 'package:flutter/material.dart';

class MinimalPalette {
  const MinimalPalette._();

  static const Color ink = Color(0xFF11100E);
  static const Color paper = Color(0xFFFAF9F6);
  static const Color linen = Color(0xFFE9E4DA);
  static const Color stone = Color(0xFFC9BFAE);
  static const Color sage = Color(0xFF71806E);
  static const Color paleSage = Color(0xFFD9E0D5);
  static const Color dustyRose = Color(0xFFE7D8D2);
  static const Color mist = Color(0xFFF1F1EF);
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: MinimalPalette.stone,
      brightness: Brightness.light,
      surface: MinimalPalette.paper,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: MinimalPalette.ink,
        secondary: MinimalPalette.sage,
        surface: MinimalPalette.paper,
        onSurface: MinimalPalette.ink,
      ),
      scaffoldBackgroundColor: MinimalPalette.paper,
      fontFamily: 'Helvetica',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Cormorant Garamond',
          fontSize: 70,
          height: 0.9,
          fontWeight: FontWeight.w400,
          color: MinimalPalette.ink,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Cormorant Garamond',
          fontSize: 36,
          height: 1,
          fontWeight: FontWeight.w400,
          color: MinimalPalette.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.4,
          color: MinimalPalette.ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.45,
          color: MinimalPalette.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: MinimalPalette.ink,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MinimalPalette.paper,
        foregroundColor: MinimalPalette.ink,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MinimalPalette.ink),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MinimalPalette.linen),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MinimalPalette.ink, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: MinimalPalette.ink,
          foregroundColor: MinimalPalette.paper,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MinimalPalette.ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: MinimalPalette.ink),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}
