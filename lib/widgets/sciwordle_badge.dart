// lib/widgets/sciwordle_badge.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A sleek, glowing badge displaying elite SciWordle titles (ALPHA, PRIME, FIRE, TOP 2, TOP 3, TOP 10).
class SciwordleBadge extends StatelessWidget {
  const SciwordleBadge({
    super.key,
    required this.title,
    this.compact = false,
  });

  final String title;
  final bool compact;

  static Color getTitleColor(String title) {
    switch (title.toUpperCase().trim()) {
      case 'ALPHA':
        return const Color(0xFFEF4444); // Crimson Flame
      case 'PRIME':
        return const Color(0xFFF59E0B); // Amber Gold
      case 'FIRE':
        return const Color(0xFFFB923C); // Radiant Orange
      case 'TOP 2':
        return const Color(0xFF38BDF8); // Electric Sky
      case 'TOP 3':
        return const Color(0xFFC084FC); // Purple Royalty
      case 'TOP 10':
        return const Color(0xFF10B981); // Emerald Elite
      default:
        return const Color(0xFF6366F1);
    }
  }

  static IconData getTitleIcon(String title) {
    switch (title.toUpperCase().trim()) {
      case 'ALPHA':
        return Icons.bolt_rounded;
      case 'PRIME':
        return Icons.workspace_premium_rounded;
      case 'FIRE':
        return Icons.whatshot_rounded;
      case 'TOP 2':
      case 'TOP 3':
      case 'TOP 10':
        return Icons.military_tech_rounded;
      default:
        return Icons.psychology_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanTitle = title.toUpperCase().trim();
    if (cleanTitle.isEmpty) return const SizedBox.shrink();

    final baseColor = getTitleColor(cleanTitle);
    final icon = getTitleIcon(cleanTitle);

    final padH = compact ? 5.5 : 8.0;
    final padV = compact ? 2.0 : 3.0;
    final fontSize = compact ? 8.0 : 10.0;
    final iconSize = compact ? 9.5 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            baseColor,
            Color.lerp(baseColor, Colors.black, 0.28) ?? baseColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.65),
          width: 0.85,
        ),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: 0.45),
            blurRadius: compact ? 6 : 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: iconSize,
          ),
          SizedBox(width: compact ? 2.5 : 4.0),
          Text(
            cleanTitle,
            style: GoogleFonts.robotoFlex(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
