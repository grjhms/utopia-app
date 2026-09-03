import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../theme/m3_expressive_theme.dart';
import 'app_motion.dart';

/// Material 3 Expressive Dynamic Motion Attendance Card
///
/// Inspired by Android 15 Material You Expressive widgets (Weather pebble, Media player).
/// Features:
/// - Giant expressive typography (like the 65° M3 weather widget)
/// - Continuous organic liquid sine wave that ripples and rolls smoothly
/// - Clean, minimal layout with zero clutter (no targets, no criticals)
/// - Tactile squircle geometry and tonal surfaces
class DynamicMotionAttendanceCard extends StatefulWidget {
  const DynamicMotionAttendanceCard({
    super.key,
    required this.isConnected,
    required this.attendancePct,
    required this.studentName,
    this.lastFetched,
    required this.onTap,
  });

  final bool isConnected;
  final double? attendancePct;
  final String studentName;
  final DateTime? lastFetched;
  final VoidCallback onTap;

  @override
  State<DynamicMotionAttendanceCard> createState() => _DynamicMotionAttendanceCardState();
}

class _DynamicMotionAttendanceCardState extends State<DynamicMotionAttendanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  Color _getThemeColor(double? pct) {
    if (pct == null || pct <= 0) return U.primary;
    if (pct >= 75) return U.green;
    if (pct >= 65) return U.peach;
    return U.red;
  }

  String _formatLastFetchedDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sept',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    return '${date.day} $month';
  }

  String get _pillLabel {
    if (!widget.isConnected) {
      return 'PORTAL SYNC';
    }
    if (widget.lastFetched != null) {
      return _formatLastFetchedDate(widget.lastFetched!);
    }
    return 'PORTAL SYNC';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAvailable = widget.isConnected &&
        widget.attendancePct != null &&
        widget.attendancePct! > 0;
    final accentColor = _getThemeColor(widget.attendancePct);
    final pct = isAvailable ? (widget.attendancePct! / 100).clamp(0.0, 1.0) : 0.20;
    final pctString = isAvailable ? widget.attendancePct!.toStringAsFixed(0) : '—';

    return M3Pressable(
      onTap: widget.onTap,
      scaleFactor: 0.98,
      borderRadius: M3Shapes.heroRadius,
      child: Container(
        decoration: BoxDecoration(
          color: U.surfaceContainerHigh,
          borderRadius: M3Shapes.heroRadius,
          border: Border.all(
            color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.45),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            final waveProgress = _waveController.value;

            return Stack(
              children: [
                // ── LAYER 1: Dynamic Rolling Liquid Wave Canvas ──
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LiquidWavePainter(
                      color: accentColor,
                      progress: waveProgress,
                      fillPercent: pct,
                      isDark: isDark,
                    ),
                  ),
                ),

                // ── LAYER 2: Foreground Minimal Expressive Content ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Row: Status Pill & Forward Squircle Action
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Live Indicator Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: U.surfaceContainerLowest.withValues(alpha: 0.85),
                              borderRadius: M3Shapes.fullRadius,
                              border: Border.all(
                                color: U.outlineVariant.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Pulsing Live Dot
                                SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accentColor.withValues(
                                            alpha: (0.3 + 0.5 * math.sin(waveProgress * 2 * math.pi)).clamp(0.1, 0.8),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accentColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _pillLabel,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: U.text,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Squircle Forward Arrow Button
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: U.surfaceContainerLowest.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: U.outlineVariant.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                color: U.text,
                                size: 17,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Center Row: Title + Giant Expressive Percentage
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left text block
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isConnected ? 'Attendance' : 'Connect Portal',
                                  style: GoogleFonts.newsreader(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                    color: U.text,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (!widget.isConnected)
                                  Text(
                                    'Tap to link college portal',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 13,
                                      color: U.sub,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                else if (widget.attendancePct == null)
                                  Text(
                                    'Fetching latest data...',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 13,
                                      color: U.sub,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                else
                                  Text(
                                    widget.studentName.isNotEmpty
                                        ? widget.studentName
                                        : 'Live Portal Sync',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 13,
                                      color: U.sub,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),

                          // Right: Giant M3 Expressive Number Display or Unavailable Dash
                          if (widget.isConnected && isAvailable)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  pctString,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w900,
                                    height: 0.9,
                                    letterSpacing: -2,
                                    color: U.text,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 4, left: 2),
                                  child: Text(
                                    '%',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (widget.isConnected && !isAvailable)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '—',
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    height: 0.9,
                                    letterSpacing: -1,
                                    color: U.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: U.surfaceContainerLowest.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: U.outlineVariant.withValues(alpha: 0.35),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Text(
                                    'Unavailable',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: U.sub,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: U.surfaceContainerLowest.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.sync_lock_rounded,
                                color: U.sub,
                                size: 24,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Bottom Chunky Stadium Wave Track
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: U.surfaceContainerLowest.withValues(alpha: 0.7),
                          borderRadius: M3Shapes.fullRadius,
                          border: Border.all(
                            color: U.outlineVariant.withValues(alpha: 0.25),
                            width: 0.6,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: M3Shapes.fullRadius,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final totalW = constraints.maxWidth;
                              final fillW = isAvailable ? totalW * pct : 0.0;

                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: fillW,
                                  height: double.infinity,
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: M3Shapes.fullRadius,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Custom painter rendering a calm, fluid liquid wave tank synced with the attendance percentage
class _LiquidWavePainter extends CustomPainter {
  _LiquidWavePainter({
    required this.color,
    required this.progress,
    required this.fillPercent,
    required this.isDark,
  });

  final Color color;
  final double progress;
  final double fillPercent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Direct liquid tank fill synced with attendance percentage (50% = half tank, 100% = full tank)
    final clampedFill = fillPercent.clamp(0.0, 1.0);
    if (clampedFill <= 0.0) return;

    final baseHeight = h * clampedFill;
    final waveAmplitude = clampedFill >= 0.98 ? 3.5 : 5.0; // gentle undulating wave height
    final phase = progress * 2 * math.pi;

    // ── WAVE 1 (Back wave - softer opacity) ──
    final backPath = Path();
    backPath.moveTo(0, h);
    backPath.lineTo(0, h - baseHeight);

    for (double x = 0; x <= w; x += 3) {
      final y = h - baseHeight + math.sin((x / w * 2 * math.pi) + phase + 1.2) * waveAmplitude * 0.8;
      backPath.lineTo(x, y);
    }

    backPath.lineTo(w, h);
    backPath.close();

    final backPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isDark ? 0.09 : 0.07),
          color.withValues(alpha: isDark ? 0.03 : 0.02),
        ],
      ).createShader(
        Rect.fromLTWH(
          0,
          math.max(0.0, h - baseHeight - waveAmplitude),
          w,
          math.max(1.0, baseHeight + waveAmplitude),
        ),
      );

    canvas.drawPath(backPath, backPaint);

    // ── WAVE 2 (Front wave - crisper opacity) ──
    final frontPath = Path();
    frontPath.moveTo(0, h);
    frontPath.lineTo(0, h - baseHeight);

    for (double x = 0; x <= w; x += 3) {
      final y = h - baseHeight + math.sin((x / w * 2 * math.pi) + phase) * waveAmplitude;
      frontPath.lineTo(x, y);
    }

    frontPath.lineTo(w, h);
    frontPath.close();

    final frontPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isDark ? 0.16 : 0.12),
          color.withValues(alpha: isDark ? 0.05 : 0.03),
        ],
      ).createShader(
        Rect.fromLTWH(
          0,
          math.max(0.0, h - baseHeight - waveAmplitude),
          w,
          math.max(1.0, baseHeight + waveAmplitude),
        ),
      );

    canvas.drawPath(frontPath, frontPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.fillPercent != fillPercent;
  }
}
