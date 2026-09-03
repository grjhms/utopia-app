import 'package:flutter/material.dart';

/// The four botanical themes, each mapped to a real flower.
/// 
/// - wisteria  → PURPLE  — cascading drooping clusters, hanging vine geometry
/// - bauhinia  → WHITE   — orchid-tree open petals + dandelion wisps
/// - sakura    → PINK    — 5-petal blossoms on branches, drifting petals
/// - maple     → YELLOW  — pointed maple leaves + golden shower cascades
enum FlowerType { wisteria, bauhinia, sakura, maple }

class DelveTheme {
  final String name;
  final Color background;
  final Color text;
  final Color botanicalInk;
  final Color accent;
  final bool isDark;
  final String feel;
  final FlowerType flowerType;

  /// Secondary accent for gradients / subtle overlays.
  final Color accentSecondary;

  const DelveTheme({
    required this.name,
    required this.background,
    required this.text,
    required this.botanicalInk,
    required this.accent,
    required this.isDark,
    required this.feel,
    required this.flowerType,
    required this.accentSecondary,
  });

  Color get cardBackground => isDark
      ? Color.lerp(background, Colors.white, 0.06)!
      : Color.lerp(background, Colors.black, 0.04)!;

  Color get surfaceDim => isDark
      ? Color.lerp(background, Colors.white, 0.03)!
      : Color.lerp(background, Colors.black, 0.02)!;

  Color get textSecondary => text.withValues(alpha: 0.75);

  Color get divider => text.withValues(alpha: 0.12);

  ThemeData toThemeData() {
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: isDark ? Colors.black : Colors.white,
        secondary: botanicalInk,
        onSecondary: text,
        error: const Color(0xFFCF6679),
        onError: Colors.black,
        surface: cardBackground,
        onSurface: text,
      ),
      cardColor: cardBackground,
      dividerColor: divider,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: text,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDim,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
    );
  }
}
