import 'package:flutter/material.dart';
import 'delve_theme.dart';

/// Clean minimalist monochrome dark themes for Delve.
class DelveThemes {
  /// OLED Pitch Black
  static const wisteriaDark = DelveTheme(
    name: 'OLED Black',
    background: Color(0xFF000000),
    text: Color(0xFFFFFFFF),
    botanicalInk: Color(0xFF71717A), 
    accent: Color(0xFFFFFFFF), 
    accentSecondary: Color(0xFFD4D4D8),
    isDark: true,
    feel: 'Pure black content-first focus.',
    flowerType: FlowerType.wisteria,
  );

  /// Obsidian Minimal
  static const bauhiniaDark = DelveTheme(
    name: 'Obsidian',
    background: Color(0xFF09090B),
    text: Color(0xFFFAFAFA),
    botanicalInk: Color(0xFF52525B), 
    accent: Color(0xFFFAFAFA), 
    accentSecondary: Color(0xFFE4E4E7),
    isDark: true,
    feel: 'Deep matte dark sanctuary.',
    flowerType: FlowerType.bauhinia,
  );

  /// Charcoal Contrast
  static const sakuraDark = DelveTheme(
    name: 'Charcoal',
    background: Color(0xFF121214),
    text: Color(0xFFF4F4F5),
    botanicalInk: Color(0xFF71717A), 
    accent: Color(0xFFFFFFFF), 
    accentSecondary: Color(0xFFE4E4E7),
    isDark: true,
    feel: 'Sleek high contrast grayscale.',
    flowerType: FlowerType.sakura,
  );

  /// Midnight Graphite
  static const mapleDark = DelveTheme(
    name: 'Graphite',
    background: Color(0xFF16181A),
    text: Color(0xFFE6E8EB),
    botanicalInk: Color(0xFF6B7280), 
    accent: Color(0xFFFFFFFF), 
    accentSecondary: Color(0xFFD1D5DB),
    isDark: true,
    feel: 'Refined cool graphite.',
    flowerType: FlowerType.maple,
  );

  /// Grayscale Dark 1
  static const wisteriaLight = DelveTheme(
    name: 'Monochrome 1',
    background: Color(0xFF080808),
    text: Color(0xFFFAFAFA),
    botanicalInk: Color(0xFF71717A),
    accent: Color(0xFFFFFFFF), 
    accentSecondary: Color(0xFFE4E4E7),
    isDark: true,
    feel: 'Ultra minimalist dark tone.',
    flowerType: FlowerType.wisteria,
  );

  /// Grayscale Dark 2
  static const bauhiniaLight = DelveTheme(
    name: 'Monochrome 2',
    background: Color(0xFF0D0D0E),
    text: Color(0xFFF4F4F5),
    botanicalInk: Color(0xFF52525B),
    accent: Color(0xFFFAFAFA), 
    accentSecondary: Color(0xFFD4D4D8),
    isDark: true,
    feel: 'Crisp structural dark workspace.',
    flowerType: FlowerType.bauhinia,
  );

  /// Grayscale Dark 3
  static const sakuraLight = DelveTheme(
    name: 'Monochrome 3',
    background: Color(0xFF141416),
    text: Color(0xFFFFFFFF),
    botanicalInk: Color(0xFF71717A),
    accent: Color(0xFFFFFFFF), 
    accentSecondary: Color(0xFFE4E4E7),
    isDark: true,
    feel: 'Clean typography focus.',
    flowerType: FlowerType.sakura,
  );

  /// Grayscale Dark 4
  static const mapleLight = DelveTheme(
    name: 'Monochrome 4',
    background: Color(0xFF18181B),
    text: Color(0xFFFAFAFA),
    botanicalInk: Color(0xFFA1A1AA),
    accent: Color(0xFFFFFFFF), 
    accentSecondary: Color(0xFFD4D4D8),
    isDark: true,
    feel: 'Subtle slate elegance.',
    flowerType: FlowerType.maple,
  );

  static const List<DelveTheme> all = [
    wisteriaDark,
    bauhiniaDark,
    sakuraDark,
    mapleDark,
    wisteriaLight,
    bauhiniaLight,
    sakuraLight,
    mapleLight,
  ];

  static List<DelveTheme> get darkThemes => all;
  static List<DelveTheme> get lightThemes => [];

  static DelveTheme getByName(String name) {
    return all.firstWhere((t) => t.name == name, orElse: () => wisteriaDark);
  }

  static DelveTheme getByNameAndMode(String name, bool isDark) {
    return getByName(name);
  }
}
