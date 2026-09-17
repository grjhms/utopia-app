// lib/widgets/sciwordle_badge.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A sleek, minimal monochrome badge displaying SciWordle titles.
class SciwordleBadge extends StatelessWidget {
  const SciwordleBadge({
    super.key,
    required this.title,
    this.compact = false,
  });

  final String title;
  final bool compact;

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

    final icon = getTitleIcon(cleanTitle);

    final padH = compact ? 6.0 : 9.0;
    final padV = compact ? 2.5 : 4.0;
    final fontSize = compact ? 8.5 : 10.5;
    final iconSize = compact ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF3F3F46),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: const Color(0xFFFAFAFA),
            size: iconSize,
          ),
          SizedBox(width: compact ? 3.0 : 4.5),
          Text(
            cleanTitle,
            style: GoogleFonts.robotoFlex(
              color: const Color(0xFFFAFAFA),
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
