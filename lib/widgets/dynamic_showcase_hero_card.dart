import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/project_model.dart';
import '../services/project_service.dart';
import '../theme/m3_expressive_theme.dart';
import '../utils/responsive_scale.dart';
import '../widgets/app_motion.dart';

/// Material 3 Expressive Dynamic Showcase Hero Card
/// Displayed on the Home/Focus Screen for non-Aditya colleges in place of the Attendance card.
/// Simple, clean, and without duplicate copy or bloat.
class DynamicShowcaseHeroCard extends StatefulWidget {
  final VoidCallback? onTap;

  const DynamicShowcaseHeroCard({
    super.key,
    this.onTap,
    VoidCallback? onCreateTap, // Kept for backwards compatibility if needed
  });

  @override
  State<DynamicShowcaseHeroCard> createState() => _DynamicShowcaseHeroCardState();
}

class _DynamicShowcaseHeroCardState extends State<DynamicShowcaseHeroCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = appThemeNotifier.value;

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
          boxShadow: [
            BoxShadow(
              color: U.primary.withValues(alpha: isDark ? 0.08 : 0.04),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // ── Background Expressive Ambient Gradient ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  final glow = _glowController.value;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          U.primary.withValues(
                            alpha: isDark ? (0.14 + 0.06 * glow) : (0.08 + 0.04 * glow),
                          ),
                          theme.teal.withValues(
                            alpha: isDark ? (0.08 + 0.04 * (1 - glow)) : (0.05 + 0.02 * (1 - glow)),
                          ),
                          U.surfaceContainerHigh,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Watermark Background Rocket Icon ──
            Positioned(
              right: -rs.s(12, min: 8, max: 18),
              bottom: -rs.vs(16, min: 10, max: 22),
              child: Opacity(
                opacity: isDark ? 0.06 : 0.035,
                child: Icon(
                  Icons.rocket_launch_rounded,
                  size: rs.s(160, min: 120, max: 190),
                  color: U.primary,
                ),
              ),
            ),

            // ── Main Content ──
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: rs.s(22, min: 16, max: 26),
                vertical: rs.vs(20, min: 14, max: 24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Row: Status Pill & Forward Squircle Action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Live Status Pill
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: rs.s(12, min: 9, max: 15),
                          vertical: rs.s(6, min: 4.5, max: 8),
                        ),
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
                            AnimatedBuilder(
                              animation: _glowController,
                              builder: (context, child) {
                                final p = _glowController.value;
                                return Container(
                                  width: rs.s(8, min: 6, max: 10),
                                  height: rs.s(8, min: 6, max: 10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: U.primary.withValues(
                                      alpha: (0.3 + 0.6 * math.sin(p * math.pi)).clamp(0.2, 0.9),
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: rs.s(5, min: 3.5, max: 6),
                                      height: rs.s(5, min: 3.5, max: 6),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: U.primary,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            SizedBox(width: rs.s(7, min: 5, max: 9)),
                            Text(
                              'EXPLORE',
                              style: GoogleFonts.robotoFlex(
                                fontSize: rs.font(10, min: 9, max: 12),
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
                        width: rs.s(38, min: 32, max: 44),
                        height: rs.s(38, min: 32, max: 44),
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
                            size: rs.s(17, min: 14, max: 20),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: rs.vs(18, min: 12, max: 24)),

                  // Center Row: Title + Project Count
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
                              'Showcase',
                              style: GoogleFonts.newsreader(
                                fontSize: rs.font(28, min: 22, max: 34),
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                                color: U.text,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Explore campus projects',
                              style: GoogleFonts.robotoFlex(
                                fontSize: rs.font(13, min: 11, max: 15),
                                color: U.sub,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Right: Expressive live count
                      StreamBuilder<List<ProjectModel>>(
                        stream: ProjectService().getProjectsStream(),
                        builder: (context, snapshot) {
                          final count = snapshot.data?.length ?? 0;
                          return Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$count',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: rs.font(38, min: 28, max: 46),
                                      fontWeight: FontWeight.w900,
                                      height: 0.95,
                                      letterSpacing: -1.2,
                                      color: U.text,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 3),
                                    child: Text(
                                      count == 1 ? 'project' : 'projects',
                                      style: GoogleFonts.robotoFlex(
                                        fontSize: rs.font(13, min: 11, max: 15),
                                        fontWeight: FontWeight.w600,
                                        color: U.sub,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
