// lib/widgets/sciwordle_badge.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Animated game badge featuring dynamic animated fire flame licks / energy sparks
/// rising out of the pill container edges, matching fire-themed UI effects.
class SciwordleBadge extends StatefulWidget {
  const SciwordleBadge({
    super.key,
    required this.title,
    this.compact = false,
  });

  final String title;
  final bool compact;

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
      duration: const Duration(milliseconds: 1200),
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

    final padH = widget.compact ? 7.0 : 10.0;
    final padV = widget.compact ? 3.0 : 4.5;
    final fontSize = widget.compact ? 9.0 : 11.0;
    final emojiSize = widget.compact ? 11.0 : 13.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;

        // Colors per title type
        List<Color> pillGradient;
        Color flameOuterColor;
        Color flameInnerColor;
        Color glowColor;

        switch (cleanTitle) {
          case 'FIRE':
            pillGradient = const [
              Color(0xFFFF3D00),
              Color(0xFFFF9100),
              Color(0xFFFFAB00),
            ];
            flameOuterColor = const Color(0xFFFF3D00);
            flameInnerColor = const Color(0xFFFFD600);
            glowColor = const Color(0xFFFF6D00);
            break;

          case 'ALPHA':
            pillGradient = const [
              Color(0xFF00B0FF),
              Color(0xFF00E5FF),
              Color(0xFF80D8FF),
            ];
            flameOuterColor = const Color(0xFF0091EA);
            flameInnerColor = const Color(0xFFE0F7FA);
            glowColor = const Color(0xFF00E5FF);
            break;

          case 'PRIME':
            pillGradient = const [
              Color(0xFFFF8F00),
              Color(0xFFFFC107),
              Color(0xFFFFECB3),
            ];
            flameOuterColor = const Color(0xFFFF8F00);
            flameInnerColor = const Color(0xFFFFF8E1);
            glowColor = const Color(0xFFFFB300);
            break;

          case 'TOP 2':
            pillGradient = const [
              Color(0xFF0284C7),
              Color(0xFF38BDF8),
              Color(0xFFBAE6FD),
            ];
            flameOuterColor = const Color(0xFF0284C7);
            flameInnerColor = const Color(0xFFE0F2FE);
            glowColor = const Color(0xFF38BDF8);
            break;

          case 'TOP 3':
            pillGradient = const [
              Color(0xFF7E22CE),
              Color(0xFFC084FC),
              Color(0xFFF3E8FF),
            ];
            flameOuterColor = const Color(0xFF7E22CE);
            flameInnerColor = const Color(0xFFFAF5FF);
            glowColor = const Color(0xFFC084FC);
            break;

          default:
            pillGradient = const [
              Color(0xFFBE185D),
              Color(0xFFF472B6),
              Color(0xFFFCE7F3),
            ];
            flameOuterColor = const Color(0xFFBE185D);
            flameInnerColor = const Color(0xFFFFF1F2);
            glowColor = const Color(0xFFF472B6);
            break;
        }

        return Container(
          margin: EdgeInsets.all(widget.compact ? 4.0 : 6.0), // space for flame licks
          child: CustomPaint(
            painter: _FirePillPainter(
              animValue: t,
              pillGradient: pillGradient,
              flameOuterColor: flameOuterColor,
              flameInnerColor: flameInnerColor,
              glowColor: glowColor,
              compact: widget.compact,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    emoji,
                    style: TextStyle(
                      fontSize: emojiSize,
                      height: 1.1,
                      shadows: const [
                        Shadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: widget.compact ? 3.5 : 5.0),
                  Flexible(
                    child: Text(
                      cleanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.robotoFlex(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        height: 1.1,
                        shadows: const [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FirePillPainter extends CustomPainter {
  final double animValue;
  final List<Color> pillGradient;
  final Color flameOuterColor;
  final Color flameInnerColor;
  final Color glowColor;
  final bool compact;

  _FirePillPainter({
    required this.animValue,
    required this.pillGradient,
    required this.flameOuterColor,
    required this.flameInnerColor,
    required this.glowColor,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.height / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 1. Draw outer ambient glow shadow
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, compact ? 6.0 : 9.0);
    canvas.drawRRect(rrect, glowPaint);

    // 2. Draw animated flame licks sprouting off corners & edges
    _drawFlameLicks(canvas, size, animValue, flameOuterColor, flameInnerColor, compact);

    // 3. Draw pill body gradient
    final pillPaint = Paint()
      ..shader = LinearGradient(
        colors: pillGradient,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);
    canvas.drawRRect(rrect, pillPaint);

    // 4. Draw pill border highlight
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.8),
          Colors.white.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.6),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(rrect, borderPaint);
  }

  void _drawFlameLicks(
    Canvas canvas,
    Size size,
    double t,
    Color outerColor,
    Color innerColor,
    bool compact,
  ) {
    final outerPaint = Paint()
      ..color = outerColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final innerPaint = Paint()
      ..color = innerColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    // Defined flame tongue positions along top, corners, bottom
    final flameSpurs = [
      _FlameData(0.06, 0.2, compact ? 6.0 : 9.0, compact ? 7.0 : 10.0, 0.0, true),
      _FlameData(0.18, 0.0, compact ? 5.0 : 7.0, compact ? 6.0 : 9.0, 1.2, true),
      _FlameData(0.82, 0.0, compact ? 5.0 : 7.0, compact ? 6.0 : 9.0, 2.4, true),
      _FlameData(0.94, 0.2, compact ? 6.0 : 9.0, compact ? 7.0 : 10.0, 3.6, true),
      _FlameData(0.04, 0.8, compact ? 5.0 : 7.0, compact ? 5.0 : 8.0, 4.2, false),
      _FlameData(0.96, 0.8, compact ? 5.0 : 7.0, compact ? 5.0 : 8.0, 5.0, false),
    ];

    for (final spur in flameSpurs) {
      final cx = size.width * spur.xRatio;
      final cy = size.height * spur.yRatio;

      final p = (t * 2 * math.pi) + spur.phaseShift;
      final currentH = spur.maxH * (0.65 + 0.35 * math.sin(p));
      final sway = (compact ? 2.0 : 3.5) * math.cos(p * 1.5);
      final dir = spur.isUpward ? -1.0 : 1.0;

      // Outer Flame Tongue Path
      final outerPath = Path()
        ..moveTo(cx - spur.baseWidth / 2, cy)
        ..cubicTo(
          cx - spur.baseWidth / 4 + sway * 0.5,
          cy + dir * currentH * 0.5,
          cx + sway,
          cy + dir * currentH * 0.8,
          cx + sway,
          cy + dir * currentH,
        )
        ..cubicTo(
          cx + sway * 0.5,
          cy + dir * currentH * 0.6,
          cx + spur.baseWidth / 4,
          cy + dir * currentH * 0.3,
          cx + spur.baseWidth / 2,
          cy,
        )
        ..close();

      canvas.drawPath(outerPath, outerPaint);

      // Inner Flame Core Path
      final innerPath = Path()
        ..moveTo(cx - spur.baseWidth / 3, cy)
        ..cubicTo(
          cx + sway * 0.3,
          cy + dir * currentH * 0.4,
          cx + sway * 0.7,
          cy + dir * currentH * 0.6,
          cx + sway * 0.7,
          cy + dir * currentH * 0.75,
        )
        ..cubicTo(
          cx + sway * 0.3,
          cy + dir * currentH * 0.5,
          cx + spur.baseWidth / 6,
          cy + dir * currentH * 0.2,
          cx + spur.baseWidth / 3,
          cy,
        )
        ..close();

      canvas.drawPath(innerPath, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FirePillPainter oldDelegate) {
    return oldDelegate.animValue != animValue || oldDelegate.pillGradient != pillGradient;
  }
}

class _FlameData {
  final double xRatio;
  final double yRatio;
  final double baseWidth;
  final double maxH;
  final double phaseShift;
  final bool isUpward;

  _FlameData(this.xRatio, this.yRatio, this.baseWidth, this.maxH, this.phaseShift, this.isUpward);
}









