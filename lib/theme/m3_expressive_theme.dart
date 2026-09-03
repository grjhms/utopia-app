import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material 3 Expressive Shape Scale & Dimensions
/// Provides standard M3 Expressive corner radiuses, squircle scales, and stadium capsules.
class M3Shapes {
  const M3Shapes._();

  /// 4dp - Micro tags, tiny badges, small indicators
  static const double extraSmall = 4.0;
  static final BorderRadius extraSmallRadius = BorderRadius.circular(extraSmall);
  static final ShapeBorder extraSmallShape = RoundedRectangleBorder(borderRadius: extraSmallRadius);

  /// 8dp - Micro chips, mini status indicators
  static const double small = 8.0;
  static final BorderRadius smallRadius = BorderRadius.circular(small);
  static final ShapeBorder smallShape = RoundedRectangleBorder(borderRadius: smallRadius);

  /// 12dp - Secondary list items, inner modal buttons
  static const double medium = 12.0;
  static final BorderRadius mediumRadius = BorderRadius.circular(medium);
  static final ShapeBorder mediumShape = RoundedRectangleBorder(borderRadius: mediumRadius);

  /// 16dp - Squircle icon badges, dialogs, inner action cards
  static const double large = 16.0;
  static final BorderRadius largeRadius = BorderRadius.circular(large);
  static final ShapeBorder largeShape = RoundedRectangleBorder(borderRadius: largeRadius);

  /// 24dp - Material 3 Expressive Squircle Cards (Hub Cards, Peer Cards, News)
  static const double card = 24.0;
  static final BorderRadius cardRadius = BorderRadius.circular(card);
  static final ShapeBorder cardShape = RoundedRectangleBorder(borderRadius: cardRadius);

  /// 28dp - Material 3 Expressive Sheet & Panel Radius
  static const double extraLarge = 28.0;
  static final BorderRadius extraLargeRadius = BorderRadius.circular(extraLarge);
  static final ShapeBorder extraLargeShape = RoundedRectangleBorder(borderRadius: extraLargeRadius);

  /// 32dp - Material 3 Expressive Hero Containers (Attendance Hero, Profile Header)
  static const double hero = 32.0;
  static final BorderRadius heroRadius = BorderRadius.circular(hero);
  static final ShapeBorder heroShape = RoundedRectangleBorder(borderRadius: heroRadius);

  /// 999dp - Capsule / Stadium pill shapes (bottom nav dock, search bar, filter chips, action pills)
  static const double full = 999.0;
  static final BorderRadius fullRadius = BorderRadius.circular(full);
  static const ShapeBorder fullShape = StadiumBorder();
}

/// Material 3 Expressive Typography Scale
/// Uses Roboto Flex variable font with expressive weights and optical sizing.
class M3Typography {
  const M3Typography._();

  static TextTheme createTextTheme({required Color textColor, required Color subColor}) {
    final base = GoogleFonts.robotoFlexTextTheme();
    return base.copyWith(
      // Display
      displayLarge: GoogleFonts.robotoFlex(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: textColor,
        height: 1.12,
      ),
      displayMedium: GoogleFonts.robotoFlex(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: textColor,
        height: 1.16,
      ),
      displaySmall: GoogleFonts.robotoFlex(
        fontSize: 36,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: textColor,
        height: 1.22,
      ),

      // Headline
      headlineLarge: GoogleFonts.robotoFlex(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: textColor,
        height: 1.25,
      ),
      headlineMedium: GoogleFonts.robotoFlex(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: textColor,
        height: 1.29,
      ),
      headlineSmall: GoogleFonts.robotoFlex(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: textColor,
        height: 1.33,
      ),

      // Title
      titleLarge: GoogleFonts.robotoFlex(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: textColor,
        height: 1.27,
      ),
      titleMedium: GoogleFonts.robotoFlex(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: textColor,
        height: 1.5,
      ),
      titleSmall: GoogleFonts.robotoFlex(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: textColor,
        height: 1.43,
      ),

      // Body
      bodyLarge: GoogleFonts.robotoFlex(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: textColor,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.robotoFlex(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: textColor.withValues(alpha: 0.85),
        height: 1.43,
      ),
      bodySmall: GoogleFonts.robotoFlex(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: subColor,
        height: 1.33,
      ),

      // Label
      labelLarge: GoogleFonts.robotoFlex(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: textColor,
        height: 1.43,
      ),
      labelMedium: GoogleFonts.robotoFlex(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: textColor,
        height: 1.33,
      ),
      labelSmall: GoogleFonts.robotoFlex(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: subColor,
        height: 1.45,
      ),
    );
  }
}

/// Helper class to create M3 ColorScheme and ThemeData with M3 Expressive aesthetics.
class M3ThemeFactory {
  const M3ThemeFactory._();

  /// Sage green primary seed color for Utopia
  static const Color sageGreenSeed = Color(0xFF94A87C);

  /// Generates full M3 ColorScheme from a seed color with proper tonal surface tiers.
  static ColorScheme createColorScheme({
    required Color seedColor,
    required bool isDark,
    Color? surfaceBackground,
    Color? customSurface,
    Color? customCard,
    Color? customPrimary,
    Color? customSecondary,
    Color? customText,
    Color? customSub,
  }) {
    // Generate baseline M3 color scheme from seed
    final base = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    // Harmonize with M3 tonal roles
    final effectivePrimary = customPrimary ?? base.primary;
    final effectiveSecondary = customSecondary ?? base.secondary;
    final effectiveSurface = surfaceBackground ?? base.surface;
    final effectiveText = customText ?? (isDark ? const Color(0xFFE2E3D8) : const Color(0xFF191C16));
    final effectiveSub = customSub ?? (isDark ? const Color(0xFFC4C8BA) : const Color(0xFF44483E));

    final onPrimary = ThemeData.estimateBrightnessForColor(effectivePrimary) == Brightness.dark
        ? Colors.white
        : const Color(0xFF11140E);

    final onSecondary = ThemeData.estimateBrightnessForColor(effectiveSecondary) == Brightness.dark
        ? Colors.white
        : const Color(0xFF11140E);

    // Material 3 Expressive Tonal Hierarchy
    final primaryContainer = isDark
        ? Color.lerp(effectivePrimary, Colors.black, 0.65)!
        : Color.lerp(effectivePrimary, Colors.white, 0.72)!;

    final onPrimaryContainer = ThemeData.estimateBrightnessForColor(primaryContainer) == Brightness.dark
        ? (isDark ? Color.lerp(effectivePrimary, Colors.white, 0.85)! : Colors.white)
        : (isDark ? Colors.black : Color.lerp(effectivePrimary, Colors.black, 0.75)!);

    final secondaryContainer = isDark
        ? Color.lerp(effectiveSecondary, Colors.black, 0.60)!
        : Color.lerp(effectiveSecondary, Colors.white, 0.75)!;

    final onSecondaryContainer = ThemeData.estimateBrightnessForColor(secondaryContainer) == Brightness.dark
        ? (isDark ? Color.lerp(effectiveSecondary, Colors.white, 0.85)! : Colors.white)
        : (isDark ? Colors.black : Color.lerp(effectiveSecondary, Colors.black, 0.75)!);

    // Compute precise surface container tonal elevation steps
    final surfaceContainerLowest = isDark
        ? Color.lerp(effectiveSurface, Colors.black, 0.45)!
        : Color.lerp(effectiveSurface, Colors.white, 0.70)!;

    final surfaceContainerLow = customSurface ?? (isDark
        ? Color.lerp(effectiveSurface, Colors.white, 0.04)!
        : Color.lerp(effectiveSurface, effectivePrimary, 0.04)!);

    final surfaceContainer = customCard ?? (isDark
        ? Color.lerp(effectiveSurface, Colors.white, 0.08)!
        : Color.lerp(effectiveSurface, effectivePrimary, 0.08)!);

    final surfaceContainerHigh = isDark
        ? Color.lerp(effectiveSurface, Colors.white, 0.13)!
        : Color.lerp(effectiveSurface, effectivePrimary, 0.12)!;

    final surfaceContainerHighest = isDark
        ? Color.lerp(effectiveSurface, Colors.white, 0.19)!
        : Color.lerp(effectiveSurface, effectivePrimary, 0.17)!;

    final outlineVariant = isDark
        ? Color.lerp(effectiveSurface, Colors.white, 0.14)!
        : Color.lerp(effectiveSurface, effectivePrimary, 0.16)!;

    final outline = isDark
        ? Color.lerp(effectiveSurface, Colors.white, 0.28)!
        : Color.lerp(effectiveSurface, Colors.black, 0.25)!;

    return base.copyWith(
      primary: effectivePrimary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: effectiveSecondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      surface: effectiveSurface,
      onSurface: effectiveText,
      onSurfaceVariant: effectiveSub,
      surfaceDim: surfaceContainerLowest,
      surfaceBright: isDark ? surfaceContainerHigh : Colors.white,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      outline: outline,
      outlineVariant: outlineVariant,
    );
  }

  /// Builds a complete Material 3 Expressive ThemeData
  static ThemeData createThemeData({
    required ColorScheme colorScheme,
    required Color text,
    required Color sub,
    required Color border,
  }) {
    final textTheme = M3Typography.createTextTheme(
      textColor: text,
      subColor: sub,
    );

    final isDark = colorScheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,

      // M3 Card Theme with Large 16dp radius and surfaceContainer elevation
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: M3Shapes.largeRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
            width: 0.8,
          ),
        ),
      ),

      // M3 Buttons with Expressive pill / rounded shapes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: GoogleFonts.robotoFlex(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: GoogleFonts.robotoFlex(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: isDark ? 0.4 : 0.6),
            width: 1.0,
          ),
          shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.robotoFlex(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: M3Shapes.smallRadius),
          textStyle: GoogleFonts.robotoFlex(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // M3 Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: M3Shapes.largeRadius,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: M3Shapes.largeRadius,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: M3Shapes.largeRadius,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.5,
          ),
        ),
        hintStyle: GoogleFonts.robotoFlex(
          color: sub,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),

      // M3 Bottom Sheet Theme with Extra Large 28dp radius
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(M3Shapes.extraLarge)),
        ),
        showDragHandle: false,
      ),

      // M3 Dialog Theme with Extra Large 28dp radius
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: M3Shapes.extraLargeRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),

      // M3 Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        labelStyle: GoogleFonts.robotoFlex(
          color: colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: M3Shapes.smallRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // M3 App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.robotoFlex(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 0.8,
        space: 1,
      ),

      iconTheme: IconThemeData(color: sub),
    );
  }
}
