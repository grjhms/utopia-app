// lib/widgets/sciwordle_badge.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bold SciWordle achievement badge — solid gradient pill with crisp borders,
/// animated gradient rotation, and high-contrast text. No glow, no blur.
class SciwordleBadge extends StatefulWidget {
  const SciwordleBadge({
    super.key,
    required this.title,
    this.compact = false,
    this.showEmoji = true,
  });

  final String title;
  final bool compact;
  final bool showEmoji;

  static String getTitleEmoji(String title) {
    switch (title.toUpperCase().trim()) {
      case 'FIRE':
        return '🔥';
      case 'ALPHA':
        return '⚡';
      case 'PRIME':
        return '👑';
      case 'TOP 2':
        return '🥈';
      case 'TOP 3':
        return '🥉';
      case 'TOP 10':
        return '🎖️';
      default:
        return '🧠';
    }
  }

  static Color getTitleThemeColor(String title) {
    switch (title.toUpperCase().trim()) {
      case 'FIRE':
        return const Color(0xFFFF5200);
      case 'ALPHA':
        return const Color(0xFF00E5FF);
      case 'PRIME':
        return const Color(0xFFFFC107);
      case 'TOP 2':
        return const Color(0xFF38BDF8);
      case 'TOP 3':
        return const Color(0xFFC084FC);
      default:
        return const Color(0xFFA855F7);
    }
  }

  /// Returns the badge color palette for the given title.
  static _BadgePalette _getPalette(String title) {
    switch (title.toUpperCase().trim()) {
      case 'FIRE':
        return const _BadgePalette(
          gradStart: Color(0xFFFF3D00),
          gradEnd: Color(0xFFFF8F00),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFFFF6D00),
          bgColor: Color(0xFF2D0E00),
        );
      case 'ALPHA':
        return const _BadgePalette(
          gradStart: Color(0xFF0091EA),
          gradEnd: Color(0xFF00E5FF),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFF00B8D4),
          bgColor: Color(0xFF002533),
        );
      case 'PRIME':
        return const _BadgePalette(
          gradStart: Color(0xFFFF8F00),
          gradEnd: Color(0xFFFFD54F),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFFFFB300),
          bgColor: Color(0xFF332600),
        );
      case 'TOP 2':
        return const _BadgePalette(
          gradStart: Color(0xFF0284C7),
          gradEnd: Color(0xFF38BDF8),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFF0EA5E9),
          bgColor: Color(0xFF001B2E),
        );
      case 'TOP 3':
        return const _BadgePalette(
          gradStart: Color(0xFF7E22CE),
          gradEnd: Color(0xFFC084FC),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFF9333EA),
          bgColor: Color(0xFF1A0533),
        );
      case 'TOP 10':
        return const _BadgePalette(
          gradStart: Color(0xFF059669),
          gradEnd: Color(0xFF34D399),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFF10B981),
          bgColor: Color(0xFF002E1F),
        );
      default:
        return const _BadgePalette(
          gradStart: Color(0xFF7C3AED),
          gradEnd: Color(0xFFA855F7),
          textColor: Color(0xFFFFFFFF),
          borderColor: Color(0xFF9333EA),
          bgColor: Color(0xFF1A0533),
        );
    }
  }

  @override
  State<SciwordleBadge> createState() => _SciwordleBadgeState();
}

class _SciwordleBadgeState extends State<SciwordleBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cleanTitle = widget.title.toUpperCase().trim();
    if (cleanTitle.isEmpty) return const SizedBox.shrink();

    final emoji = SciwordleBadge.getTitleEmoji(cleanTitle);
    final palette = SciwordleBadge._getPalette(cleanTitle);

    final padH = widget.compact ? 8.0 : 12.0;
    final padV = widget.compact ? 4.0 : 5.5;
    final fontSize = widget.compact ? 9.0 : 10.5;
    final emojiSize = widget.compact ? 10.0 : 12.0;
    final borderWidth = widget.compact ? 1.2 : 1.5;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final angle = t * 2 * math.pi;

        return Container(
          margin: EdgeInsets.all(widget.compact ? 2.0 : 3.0),
          child: CustomPaint(
            painter: _GradientBorderPainter(
              angle: angle,
              gradStart: palette.gradStart,
              gradEnd: palette.gradEnd,
              borderWidth: borderWidth,
              compact: widget.compact,
            ),
            child: Container(
              margin: EdgeInsets.all(borderWidth),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: palette.bgColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    // Subtle inner top highlight strip — gives a 3D engraved feel
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: widget.compact ? 8.0 : 10.0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              palette.gradStart.withValues(alpha: 0.25),
                              Colors.transparent,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: padH,
                        vertical: padV,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.showEmoji) ...[
                            Text(
                              emoji,
                              style: TextStyle(
                                fontSize: emojiSize,
                                height: 1.1,
                              ),
                            ),
                            SizedBox(width: widget.compact ? 3.5 : 5.0),
                          ],
                          Text(
                            cleanTitle,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            style: GoogleFonts.robotoFlex(
                              color: palette.textColor,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints an animated rotating gradient border around a pill shape.
class _GradientBorderPainter extends CustomPainter {
  final double angle;
  final Color gradStart;
  final Color gradEnd;
  final double borderWidth;
  final bool compact;

  _GradientBorderPainter({
    required this.angle,
    required this.gradStart,
    required this.gradEnd,
    required this.borderWidth,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.height / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Rotating gradient sweep for the border
    final paint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: angle,
        endAngle: angle + 2 * math.pi,
        colors: [
          gradStart,
          gradEnd,
          gradStart.withValues(alpha: 0.4),
          gradEnd,
          gradStart,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(angle),
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter oldDelegate) {
    return oldDelegate.angle != angle;
  }
}

/// Internal palette data for each badge tier.
class _BadgePalette {
  final Color gradStart;
  final Color gradEnd;
  final Color textColor;
  final Color borderColor;
  final Color bgColor;

  const _BadgePalette({
    required this.gradStart,
    required this.gradEnd,
    required this.textColor,
    required this.borderColor,
    required this.bgColor,
  });
}
