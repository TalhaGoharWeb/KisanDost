import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF2E7D32); // Deep Green
  static const Color accentColor = Color(0xFF81C784); // Light Green
  static const Color backgroundColor = Color(0xFFF1F8E9); // Off-white/Light Greenish
  static const Color cardColor = Colors.white;
  static const Color errorColor = Color(0xFFD32F2F); // Red
  static const Color successColor = Color(0xFF388E3C); // Green
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentColor,
        surface: backgroundColor,
        error: errorColor,
      ),
      fontFamily: 'Jameel Noori Nastaleeq', // Enforcing Nastaleeq
      // Safety net: any glyph Nastaleeq lacks falls back to Noto Sans
      // (not the reverse — Nastaleeq HAS decorative digit glyphs, which is
      // why money/quantities use the DigitText widget instead).
      fontFamilyFallback: const ['Noto Sans'],
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.normal),
        bodyMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
        bodySmall: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
        labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ).apply(
        fontFamily: 'Jameel Noori Nastaleeq',
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Jameel Noori Nastaleeq',
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontFamily: 'Jameel Noori Nastaleeq',
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.all(8),
      ),
    );
  }
}
