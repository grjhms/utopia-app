import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Proportional responsive scaling helper for adaptive screen sizing across the app.
/// Uses a baseline of 390 x 844 (standard modern smartphone viewport).
class ResponsiveScale {
  final double screenWidth;
  final double screenHeight;
  final double scale;
  final double vScale;
  final double horizontalPadding;
  final bool isTablet;

  const ResponsiveScale._({
    required this.screenWidth,
    required this.screenHeight,
    required this.scale,
    required this.vScale,
    required this.horizontalPadding,
    required this.isTablet,
  });

  factory ResponsiveScale.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final height = size.height;
    final isTablet = width >= 600;

    // For wide/tablet screens, clamp the effective layout width to a comfortable card width
    final effectiveWidth = isTablet ? 560.0 : width;

    // Proportional scale factor relative to 390dp baseline
    // Clamped between 0.85 (compact devices <=340dp) and 1.25 (large phablets/tablets)
    final scale = (effectiveWidth / 390.0).clamp(0.85, 1.25);

    // Vertical spacing scale factor relative to 844dp baseline
    // Clamped between 0.85 (shorter displays) and 1.22 (tall displays >=900dp)
    final vScale = (height / 844.0).clamp(0.85, 1.22);

    // Horizontal edge padding: 24dp baseline, scaled smoothly between 16dp and 28dp
    final horizontalPadding = (24.0 * scale).clamp(16.0, 28.0);

    return ResponsiveScale._(
      screenWidth: width,
      screenHeight: height,
      scale: scale,
      vScale: vScale,
      horizontalPadding: horizontalPadding,
      isTablet: isTablet,
    );
  }

  /// Scale horizontal/dimension values with optional clamp limits
  double s(double value, {double? min, double? max}) {
    final result = value * scale;
    if (min != null && max != null) return result.clamp(min, max);
    if (min != null) return math.max(min, result);
    if (max != null) return math.min(max, result);
    return result;
  }

  /// Scale vertical gaps and heights with optional clamp limits
  double vs(double value, {double? min, double? max}) {
    final result = value * vScale;
    if (min != null && max != null) return result.clamp(min, max);
    if (min != null) return math.max(min, result);
    if (max != null) return math.min(max, result);
    return result;
  }

  /// Scale typography with safe lower and upper bounds
  double font(double fontSize, {double? min, double? max}) {
    final result = fontSize * scale;
    final lower = min ?? (fontSize * 0.85);
    final upper = max ?? (fontSize * 1.25);
    return result.clamp(lower, upper);
  }
}
