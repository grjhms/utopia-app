import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';

/// Clean, compact badge displaying wave count (icon and number).
/// Dynamically adapts to the active Utopia theme.
class WaveCountBadge extends StatelessWidget {
  const WaveCountBadge({
    super.key,
    required this.count,
    this.iconSize = 12.0,
    this.fontSize = 11.5,
    this.compact = false,
    this.showZero = true,
  });

  final int count;
  final double iconSize;
  final double fontSize;
  final bool compact;
  final bool showZero;

  static String formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    if (!showZero && count <= 0) return const SizedBox.shrink();

    final countStr = formatCount(count);
    final accentColor = U.peach;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.35),
            width: 0.7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '👋',
              style: TextStyle(fontSize: iconSize * 0.85, height: 1.1),
            ),
            const SizedBox(width: 3),
            Text(
              countStr,
              style: GoogleFonts.outfit(
                color: accentColor,
                fontSize: fontSize * 0.85,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '👋',
            style: TextStyle(fontSize: iconSize, height: 1.1),
          ),
          const SizedBox(width: 4),
          Text(
            countStr,
            style: GoogleFonts.plusJakartaSans(
              color: accentColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
