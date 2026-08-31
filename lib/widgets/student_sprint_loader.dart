import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';

/// A cinematic, high-impact attendance loading and error animation.
/// The journey begins at home with the student asleep in bed (0% - 8%),
/// waking up in panic as a prominent vibrating twin-bell alarm rings (8% - 16%),
/// leaping fluidly out of bed into a sprint (16% - 28%), sprinting through campus (28% - 85%),
/// and arriving at the Academic Block where 5 friends cheer the buzzer-beater 9:30 AM arrival.
///
/// When the portal is unreachable ([isError] is true), a college transit truck
/// collides with the running student, sending them flying in a cartoon arc with loose papers,
/// and leaving them dazed with a "View Saved Attendance" fallback action.
class StudentSprintLoader extends StatefulWidget {
  final double scale;
  final double? progress;
  final bool isError;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onViewSaved;

  const StudentSprintLoader({
    super.key,
    this.scale = 1.0,
    this.progress,
    this.isError = false,
    this.errorMessage,
    this.onRetry,
    this.onViewSaved,
  });

  @override
  State<StudentSprintLoader> createState() => _StudentSprintLoaderState();
}

class _StudentSprintLoaderState extends State<StudentSprintLoader>
    with TickerProviderStateMixin {
  late final AnimationController _runController;
  late final AnimationController _crashController;

  @override
  void initState() {
    super.initState();
    _runController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat();

    _crashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _runController.dispose();
    _crashController.dispose();
    super.dispose();
  }

  String _getCaption(double p) {
    if (widget.isError) {
      return 'Portal unreachable • Server timed out';
    }
    if (p >= 0.99) return 'Attendance synced successfully';
    if (p >= 0.70) return 'Processing attendance records...';
    if (p >= 0.35) return 'Fetching course logs...';
    return 'Connecting to college portal...';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = (widget.progress ?? 0.0).clamp(0.0, 1.0);
    final pct = (effectiveProgress * 100).round();
    final isDone = effectiveProgress >= 0.99 && !widget.isError;

    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, _) {
        final isDark = theme.isDark;
        final primaryColor = U.primary;
        final emerald = const Color(0xFF10B981);
        final bgOverlay = isDark
            ? const Color(0xFF090D16).withValues(alpha: 0.97)
            : const Color(0xFFF8FAFC).withValues(alpha: 0.98);

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: bgOverlay,
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 20.0 * widget.scale,
                  vertical: 20.0 * widget.scale,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── HIGH-IMPACT 9:30 AM DEADLINE CLOCK HUD ──
                    _buildImpactfulClock(effectiveProgress, isDark, primaryColor, emerald),
                    SizedBox(height: 18 * widget.scale),

                    // ── CINEMATIC JOURNEY ARENA (BEDROOM -> SPRINT -> CAMPUS) ──
                    Container(
                      width: math.min(380.0 * widget.scale, MediaQuery.sizeOf(context).width - 32),
                      height: 225.0 * widget.scale,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xFF131D31),
                                  const Color(0xFF0A0F1D),
                                ]
                              : [
                                  const Color(0xFFFFFFFF),
                                  const Color(0xFFEDF2F7),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(28 * widget.scale),
                        border: Border.all(
                          color: widget.isError
                              ? const Color(0xFFEF4444).withValues(alpha: 0.55)
                              : (isDone
                                  ? emerald.withValues(alpha: 0.6)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08))),
                          width: (widget.isError || isDone) ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (widget.isError
                                    ? const Color(0xFFEF4444)
                                    : (isDone ? emerald : primaryColor))
                                .withValues(alpha: isDark ? 0.22 : 0.10),
                            blurRadius: 36 * widget.scale,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28 * widget.scale),
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_runController, _crashController]),
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size.infinite,
                              painter: _StudentSprintPainter(
                                runPhase: _runController.value,
                                crashPhase: _crashController.value,
                                progress: effectiveProgress,
                                isDark: isDark,
                                primaryColor: primaryColor,
                                accentColor: emerald,
                                isDone: isDone,
                                isError: widget.isError,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: 20 * widget.scale),

                    // ── BOTTOM PROGRESS TRACKER OR ERROR CARD ──
                    if (widget.isError)
                      _buildErrorCard(isDark, primaryColor)
                    else
                      _buildProgressBar(
                        effectiveProgress,
                        pct,
                        isDark,
                        primaryColor,
                        emerald,
                      ),

                    SizedBox(height: 14 * widget.scale),

                    // ── STATUS CAPTION ──
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: Text(
                        _getCaption(effectiveProgress),
                        key: ValueKey(_getCaption(effectiveProgress)),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: widget.isError
                              ? const Color(0xFFEF4444)
                              : (isDone
                                  ? emerald
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                          fontSize: 13.5 * widget.scale,
                          fontWeight: (isDone || widget.isError)
                              ? FontWeight.w700
                              : FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
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

  Widget _buildImpactfulClock(
    double progress,
    bool isDark,
    Color primaryColor,
    Color emerald,
  ) {
    return AnimatedBuilder(
      animation: _runController,
      builder: (context, _) {
        final isDone = progress >= 0.99 && !widget.isError;

        final totalSimSecs = 18.0 + progress * 40.5;
        final secDigits = widget.isError
            ? '30:02'
            : (isDone ? '29:58' : '29:${totalSimSecs.floor().toString().padLeft(2, '0')}');

        final millis = widget.isError
            ? '.12'
            : (isDone ? '.80' : '.${((_runController.value * 99).floor()).toString().padLeft(2, '0')}');

        final blink = (_runController.value * 2).toInt() % 2 == 0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '09:$secDigits',
                  style: GoogleFonts.outfit(
                    color: widget.isError
                        ? const Color(0xFFEF4444)
                        : (isDone
                            ? emerald
                            : (isDark ? Colors.white : const Color(0xFF0F172A))),
                    fontSize: 34 * widget.scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                SizedBox(width: 4 * widget.scale),
                Text(
                  millis,
                  style: GoogleFonts.outfit(
                    color: widget.isError
                        ? const Color(0xFFEF4444).withValues(alpha: 0.75)
                        : (isDone ? emerald.withValues(alpha: 0.8) : primaryColor),
                    fontSize: 19 * widget.scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 6 * widget.scale),
                Text(
                  'AM',
                  style: GoogleFonts.outfit(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    fontSize: 13.5 * widget.scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),

            SizedBox(height: 6 * widget.scale),

            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 14 * widget.scale,
                vertical: 5 * widget.scale,
              ),
              decoration: BoxDecoration(
                color: widget.isError
                    ? const Color(0xFFEF4444).withValues(alpha: 0.14)
                    : (isDone
                        ? emerald.withValues(alpha: 0.15)
                        : (isDark
                            ? const Color(0xFF1E293B).withValues(alpha: 0.85)
                            : const Color(0xFFE2E8F0))),
                borderRadius: BorderRadius.circular(20 * widget.scale),
                border: Border.all(
                  color: widget.isError
                      ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                      : (isDone
                          ? emerald.withValues(alpha: 0.45)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : Colors.black.withValues(alpha: 0.08))),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7 * widget.scale,
                    height: 7 * widget.scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isError
                          ? const Color(0xFFEF4444)
                          : (isDone
                              ? emerald
                              : (blink ? const Color(0xFFF59E0B) : const Color(0xFFEF4444))),
                    ),
                  ),
                  SizedBox(width: 7 * widget.scale),
                  Text(
                    widget.isError
                        ? 'CUTOFF MISSED • 09:30:00 AM'
                        : (isDone
                            ? 'ON TIME • ATTENDANCE RECORDED'
                            : 'DEADLINE: 09:30:00 AM ROLL CALL'),
                    style: GoogleFonts.outfit(
                      color: widget.isError
                          ? const Color(0xFFEF4444)
                          : (isDone
                              ? emerald
                              : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))),
                      fontSize: 11.5 * widget.scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgressBar(
    double progress,
    int pct,
    bool isDark,
    Color primaryColor,
    Color emerald,
  ) {
    final barColor = progress >= 0.75 ? emerald : primaryColor;

    return SizedBox(
      width: math.min(380.0 * widget.scale, MediaQuery.sizeOf(context).width - 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sync Progress',
                style: GoogleFonts.outfit(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 12.5 * widget.scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$pct%',
                style: GoogleFonts.outfit(
                  color: progress >= 0.99
                      ? emerald
                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
                  fontSize: 15.5 * widget.scale,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * widget.scale),
          Stack(
            children: [
              Container(
                height: 8 * widget.scale,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10 * widget.scale),
                ),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.02, 1.0),
                child: Container(
                  height: 8 * widget.scale,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor,
                        barColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10 * widget.scale),
                    boxShadow: [
                      BoxShadow(
                        color: barColor.withValues(alpha: 0.45),
                        blurRadius: 8 * widget.scale,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(bool isDark, Color primaryColor) {
    return SizedBox(
      width: math.min(380.0 * widget.scale, MediaQuery.sizeOf(context).width - 32),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * widget.scale,
              vertical: 12 * widget.scale,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(16 * widget.scale),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              widget.errorMessage ?? 'College portal server timed out or is unreachable.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                fontSize: 12.5 * widget.scale,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          SizedBox(height: 14 * widget.scale),
          Wrap(
            spacing: 10 * widget.scale,
            runSpacing: 10 * widget.scale,
            alignment: WrapAlignment.center,
            children: [
              if (widget.onRetry != null)
                FilledButton.icon(
                  onPressed: widget.onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: U.bg,
                    padding: EdgeInsets.symmetric(
                      horizontal: 20 * widget.scale,
                      vertical: 12 * widget.scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14 * widget.scale),
                    ),
                    elevation: 3,
                  ),
                  icon: Icon(Icons.refresh_rounded, size: 16 * widget.scale),
                  label: Text(
                    'Retry Connection',
                    style: GoogleFonts.outfit(
                      fontSize: 13 * widget.scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (widget.onViewSaved != null)
                OutlinedButton.icon(
                  onPressed: widget.onViewSaved,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                    side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black26,
                      width: 1.2,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 18 * widget.scale,
                      vertical: 12 * widget.scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14 * widget.scale),
                    ),
                  ),
                  icon: Icon(Icons.history_rounded, size: 16 * widget.scale),
                  label: Text(
                    'View Saved Attendance',
                    style: GoogleFonts.outfit(
                      fontSize: 13 * widget.scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CANVAS PAINTER: FLUID UNIFIED BEDROOM -> SPRINT -> CAMPUS ENGINE
// ═══════════════════════════════════════════════════════════════════

class _StudentSprintPainter extends CustomPainter {
  final double runPhase;
  final double crashPhase;
  final double progress;
  final bool isDark;
  final Color primaryColor;
  final Color accentColor;
  final bool isDone;
  final bool isError;

  _StudentSprintPainter({
    required this.runPhase,
    required this.crashPhase,
    required this.progress,
    required this.isDark,
    required this.primaryColor,
    required this.accentColor,
    required this.isDone,
    required this.isError,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.77;

    // 1. Screen Shake during Truck Collision
    if (isError && crashPhase >= 0.22 && crashPhase <= 0.34) {
      final shake = math.sin((crashPhase - 0.22) * 35 * math.pi) * 5.0;
      canvas.translate(shake, -shake * 0.4);
    }

    // 2. Parallax Quad Trees & Street Lamps (Fades in seamlessly as bedroom exits)
    if (progress > 0.12) {
      _drawParallaxCampusScenery(canvas, size, groundY);
    }

    // 3. Dynamic Speed Streaks (Only during road sprint)
    if (!isError && progress >= 0.22 && progress < 0.90) {
      _drawSpeedStreaks(canvas, size, groundY);
    }

    // 4. College Campus Building & 5 Cheering Friends (Slides in smoothly at progress > 0.35)
    if (!isError && progress > 0.35) {
      _drawCollegeCampusBuilding(canvas, size, groundY);
    }

    // 5. Road Track with Distance Markers
    _drawGroundTrack(canvas, size, groundY);

    // 6. Home Bedroom Scene with Prominent Animated Alarm Clock
    if (!isError && progress < 0.32) {
      _drawHomeBedroom(canvas, size, groundY);
    }

    // 7. Unified Smooth Kinematic Character (NO SHARP CUTS)
    if (isError) {
      _drawTruckHitCollision(canvas, size, groundY);
    } else {
      _drawFluidKinematicStudent(canvas, size, groundY);
    }

    // 8. High-Five Electric Sparks & Clock Chimes on Arrival
    if (isDone && !isError) {
      _drawArrivalCelebrationEffects(canvas, size, groundY);
    }
  }

  // ═════════════════════════════════════════════════════════════════
  //  METICULOUS HOME BEDROOM WITH PROMINENT RETRO ALARM CLOCK
  // ═════════════════════════════════════════════════════════════════

  void _drawHomeBedroom(Canvas canvas, Size size, double groundY) {
    // Smooth camera pan: room stays still during sleep, pans smoothly from 0.12 -> 0.30
    double roomShift = 0.0;
    if (progress >= 0.12) {
      final t = ((progress - 0.12) / 0.18).clamp(0.0, 1.0);
      roomShift = Curves.easeInOutCubic.transform(t);
    }
    final homeX = -roomShift * (size.width * 0.85 + 120);

    final phi = runPhase * 2 * math.pi;
    final alpha = (1.0 - roomShift * 0.95).clamp(0.0, 1.0);

    // ── 1. Room Background Wall & Flooring ──
    final wallPaint = Paint()
      ..color = (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
          .withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(homeX - 10, groundY - 130, 205, 130), wallPaint);

    // Wallpaper subtle pinstripes
    final stripePaint = Paint()
      ..color = (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))
          .withValues(alpha: alpha * 0.4)
      ..strokeWidth = 1.0;
    for (var i = 0; i < 7; i++) {
      final sx = homeX + 15 + i * 28;
      canvas.drawLine(Offset(sx, groundY - 130), Offset(sx, groundY), stripePaint);
    }

    // Floor Baseboard
    final baseboard = Paint()
      ..color = (isDark ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1))
          .withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(homeX - 10, groundY - 6, 205, 6), baseboard);

    // Cozy Floor Rug / Carpet under bed
    final rugPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: alpha * (isDark ? 0.35 : 0.22))
      ..style = PaintingStyle.fill;
    final rugRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(homeX + 16, groundY - 8, 140, 12),
      const Radius.circular(6),
    );
    canvas.drawRRect(rugRect, rugPaint);

    // ── 2. Wall Window with Morning Sunbeam ──
    final windowPaint = Paint()
      ..color = const Color(0xFFFEF08A).withValues(alpha: alpha * 0.9)
      ..style = PaintingStyle.fill;
    final winFrame = Paint()
      ..color = (isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8))
          .withValues(alpha: alpha)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final winRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(homeX + 18, groundY - 110, 36, 42),
      const Radius.circular(3),
    );
    canvas.drawRRect(winRect, windowPaint);
    canvas.drawRRect(winRect, winFrame);
    canvas.drawLine(Offset(homeX + 18 + 18, groundY - 110), Offset(homeX + 18 + 18, groundY - 68), winFrame);
    canvas.drawLine(Offset(homeX + 18, groundY - 89), Offset(homeX + 18 + 36, groundY - 89), winFrame);

    // Volumetric Sunbeam
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFEF08A).withValues(alpha: alpha * 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(homeX + 18, groundY - 110, 110, 110));
    final beamPath = Path()
      ..moveTo(homeX + 18, groundY - 110)
      ..lineTo(homeX + 54, groundY - 110)
      ..lineTo(homeX + 120, groundY)
      ..lineTo(homeX + 35, groundY)
      ..close();
    canvas.drawPath(beamPath, beamPaint);

    // Micro-Animation: Morning Bird Silhouette outside window
    final birdX = homeX + 22 + (runPhase * 40) % 28;
    final birdY = groundY - 95 + math.sin(phi * 2) * 3;
    final birdPaint = Paint()
      ..color = (isDark ? const Color(0xFF64748B) : const Color(0xFF475569)).withValues(alpha: alpha * 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final birdPath = Path()
      ..moveTo(birdX - 3, birdY - 2)
      ..quadraticBezierTo(birdX - 1.5, birdY + 1, birdX, birdY)
      ..quadraticBezierTo(birdX + 1.5, birdY + 1, birdX + 3, birdY - 2);
    canvas.drawPath(birdPath, birdPaint);

    // Framed Motivational Wall Poster: "09:30 AM CUTOFF ⚡"
    final framePaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A).withValues(alpha: alpha) : Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final frameBorder = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: alpha)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final posterRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(homeX + 66, groundY - 112, 32, 24),
      const Radius.circular(2),
    );
    canvas.drawRRect(posterRect, framePaint);
    canvas.drawRRect(posterRect, frameBorder);
    final posterHeader = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(homeX + 66, groundY - 112, 32, 7), posterHeader);

    // ── 3. Bed Frame & Headboard ──
    const bedX = 22.0;
    const bedW = 90.0;
    const bedH = 34.0;
    final bedTop = groundY - bedH;

    // Wooden Headboard Post & Slats
    final woodPaint = Paint()
      ..color = const Color(0xFF92400E).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(homeX + bedX, bedTop - 24, 11, bedH + 24),
        const Radius.circular(3),
      ),
      woodPaint,
    );
    canvas.drawCircle(Offset(homeX + bedX + 5.5, bedTop - 26), 4.0, woodPaint);

    // Bed Base Mattress Box
    final bedBase = Paint()
      ..color = (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(homeX + bedX + 8, bedTop, bedW - 8, bedH - 2),
        const Radius.circular(4),
      ),
      bedBase,
    );

    // Bed Legs
    final legWood = Paint()..color = const Color(0xFF78350F).withValues(alpha: alpha)..strokeWidth = 3.5;
    canvas.drawLine(Offset(homeX + bedX + 12, groundY - 2), Offset(homeX + bedX + 12, groundY), legWood);
    canvas.drawLine(Offset(homeX + bedX + bedW - 4, groundY - 2), Offset(homeX + bedX + bedW - 4, groundY), legWood);

    // Cream Mattress
    final mattressPaint = Paint()
      ..color = (isDark ? const Color(0xFF475569) : Colors.white).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(homeX + bedX + 8, bedTop - 4, bedW - 8, 10),
        const Radius.circular(3),
      ),
      mattressPaint,
    );

    // Fluffy Indented Pillow
    final pillowPaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final pillowBorder = Paint()
      ..color = (isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)).withValues(alpha: alpha)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final pillowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(homeX + bedX + 10, bedTop - 12, 26, 14),
      const Radius.circular(5),
    );
    canvas.drawRRect(pillowRect, pillowPaint);
    canvas.drawRRect(pillowRect, pillowBorder);

    // ── 4. Bedside Nightstand ──
    const standX = bedX + bedW + 6;
    final standPaint = Paint()
      ..color = const Color(0xFFB45309).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(homeX + standX, groundY - 32, 26, 32),
        const Radius.circular(4),
      ),
      standPaint,
    );

    // Drawer dividers & Brass Knobs
    final drawerLine = Paint()
      ..color = const Color(0xFF78350F).withValues(alpha: alpha)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(homeX + standX, groundY - 16), Offset(homeX + standX + 26, groundY - 16), drawerLine);
    final knobPaint = Paint()..color = const Color(0xFFFBBF24).withValues(alpha: alpha);
    canvas.drawCircle(Offset(homeX + standX + 13, groundY - 24), 2.2, knobPaint);
    canvas.drawCircle(Offset(homeX + standX + 13, groundY - 8), 2.2, knobPaint);

    // Micro-Animation: Water Glass with Vibrating Surface on Nightstand
    final glassX = homeX + standX + 2;
    final glassY = groundY - 32;
    final glassPaint = Paint()..color = (isDark ? const Color(0xFF93C5FD) : const Color(0xFF60A5FA)).withValues(alpha: alpha * 0.7);
    canvas.drawRect(Rect.fromLTWH(glassX, glassY - 9, 6, 9), glassPaint);
    if (progress >= 0.06 && progress < 0.28) {
      // Surface vibration ripple
      final ripplePaint = Paint()..color = Colors.white.withValues(alpha: alpha * 0.8)..strokeWidth = 1.0;
      canvas.drawLine(Offset(glassX, glassY - 9 + math.sin(phi * 10) * 1.0), Offset(glassX + 6, glassY - 9 - math.sin(phi * 10) * 1.0), ripplePaint);
    }

    // ── 5. EXTRA PROMINENT ANIMATED RETRO ALARM CLOCK ──
    _drawProminentAlarmClock(canvas, homeX + standX + 14, groundY - 33, alpha, phi);
  }

  void _drawProminentAlarmClock(Canvas canvas, double cx, double cy, double alpha, double phi) {
    final isAlarmActive = progress >= 0.06 && progress < 0.28;

    // Intense high-frequency vibration during alarm phase
    final vibX = isAlarmActive ? math.sin(phi * 12) * 2.5 : 0.0;
    final vibY = isAlarmActive ? -math.cos(phi * 12).abs() * 2.0 : 0.0;
    final clockCenter = Offset(cx + vibX, cy - 10 + vibY);

    const clockRadius = 10.5;

    // Glowing Alarm Aura Pulse
    if (isAlarmActive) {
      final pulseRadius = 16.0 + math.sin(phi * 4).abs() * 6.0;
      final glowPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: alpha * 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(clockCenter, pulseRadius, glowPaint);
    }

    // Bold Red Clock Housing
    final clockBody = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(clockCenter, clockRadius, clockBody);

    final clockBorder = Paint()
      ..color = const Color(0xFF991B1B).withValues(alpha: alpha)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(clockCenter, clockRadius, clockBorder);

    // Clean White Clock Face
    final clockFace = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(clockCenter, clockRadius - 2.5, clockFace);

    // Twin Brass Bells on top
    final bellPaint = Paint()..color = const Color(0xFFFBBF24).withValues(alpha: alpha);
    final bellBorder = Paint()..color = const Color(0xFFB45309).withValues(alpha: alpha)..strokeWidth = 1.0..style = PaintingStyle.stroke;

    final bellLeft = clockCenter + const Offset(-7.5, -9.0);
    final bellRight = clockCenter + const Offset(7.5, -9.0);

    canvas.drawCircle(bellLeft, 4.2, bellPaint);
    canvas.drawCircle(bellLeft, 4.2, bellBorder);
    canvas.drawCircle(bellRight, 4.2, bellPaint);
    canvas.drawCircle(bellRight, 4.2, bellBorder);

    // Oscillating Hammer hitting between bells
    final hammerAngle = isAlarmActive ? math.sin(phi * 14) * 0.45 : 0.0;
    final hammerPaint = Paint()..color = const Color(0xFF475569).withValues(alpha: alpha)..strokeWidth = 1.8..strokeCap = StrokeCap.round;
    canvas.drawLine(
      clockCenter + const Offset(0, -8),
      clockCenter + Offset(math.sin(hammerAngle) * 6, -14),
      hammerPaint,
    );
    canvas.drawCircle(clockCenter + Offset(math.sin(hammerAngle) * 6, -14), 2.0, Paint()..color = const Color(0xFF1E293B).withValues(alpha: alpha));

    // Clock Hands (09:20 AM)
    final handPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: alpha)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(clockCenter, clockCenter + const Offset(-4.2, 0.5), handPaint);
    canvas.drawLine(clockCenter, clockCenter + const Offset(2.2, 4.0), handPaint);
    canvas.drawCircle(clockCenter, 1.2, handPaint);

    // Mini Clock Peg Feet
    final footPaint = Paint()..color = const Color(0xFFB45309).withValues(alpha: alpha)..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    canvas.drawLine(clockCenter + const Offset(-6, 8.5), clockCenter + const Offset(-9, 12.5), footPaint);
    canvas.drawLine(clockCenter + const Offset(6, 8.5), clockCenter + const Offset(9, 12.5), footPaint);

    // ── RADIATING DYNAMIC SOUNDWAVES & COMIC ALARM ARCS (⚡ RING! RING! ⚡) ──
    if (isAlarmActive) {
      final ringPaint = Paint()
        ..color = const Color(0xFFF59E0B).withValues(
            alpha: ((0.7 + 0.3 * math.sin(phi * 6).abs()) * alpha).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;

      // Tier 1 Shockwave Arc
      canvas.drawArc(
        Rect.fromCircle(center: clockCenter, radius: 15),
        -math.pi * 0.88,
        math.pi * 0.45,
        false,
        ringPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: clockCenter, radius: 15),
        -math.pi * 0.57,
        math.pi * 0.45,
        false,
        ringPaint,
      );

      // Tier 2 Shockwave Arc
      canvas.drawArc(
        Rect.fromCircle(center: clockCenter, radius: 23),
        -math.pi * 0.88,
        math.pi * 0.45,
        false,
        ringPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: clockCenter, radius: 23),
        -math.pi * 0.57,
        math.pi * 0.45,
        false,
        ringPaint,
      );

      // Lightning sparks from bells
      final sparkPaint = Paint()..color = const Color(0xFFFBBF24).withValues(alpha: alpha)..strokeWidth = 2.0..strokeCap = StrokeCap.round;
      canvas.drawLine(bellLeft + const Offset(-4, -4), bellLeft + const Offset(-10, -9), sparkPaint);
      canvas.drawLine(bellRight + const Offset(4, -4), bellRight + const Offset(10, -9), sparkPaint);
    }
  }

  void _drawParallaxCampusScenery(Canvas canvas, Size size, double groundY) {
    final sceneAlpha = ((progress - 0.12) / 0.15).clamp(0.0, 1.0);

    final treePaint = Paint()
      ..color = (isDark ? const Color(0xFF1E3A2F) : const Color(0xFF86EFAC))
          .withValues(alpha: (isDark ? 0.35 : 0.45) * sceneAlpha)
      ..style = PaintingStyle.fill;

    final trunkPaint = Paint()
      ..color = (isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8))
          .withValues(alpha: 0.4 * sceneAlpha)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const spacing = 110.0;
    final shift = isError ? 0.0 : (runPhase * spacing * 1.2) % spacing;

    for (double x = size.width + spacing; x >= -spacing; x -= spacing) {
      final treeX = x - shift;
      if (treeX >= -20 && treeX <= size.width + 20) {
        canvas.drawLine(Offset(treeX, groundY), Offset(treeX, groundY - 34), trunkPaint);
        canvas.drawCircle(Offset(treeX, groundY - 42), 16, treePaint);
        canvas.drawCircle(Offset(treeX - 7, groundY - 36), 11, treePaint);
        canvas.drawCircle(Offset(treeX + 7, groundY - 36), 11, treePaint);
      }
    }

    // Micro-Animation: Drifting Autumn Leaves across Road
    if (!isError && progress >= 0.20 && progress < 0.90) {
      final leafPaint = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: sceneAlpha * 0.7)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 3; i++) {
        final lx = (size.width * 1.2 - ((runPhase * 2.2 + i * 0.35) % 1.0) * (size.width + 80));
        final ly = groundY - 20 - (i * 18) + math.sin(runPhase * 4 * math.pi + i) * 8;
        canvas.save();
        canvas.translate(lx, ly);
        canvas.rotate(runPhase * 4 * math.pi + i);
        canvas.drawOval(const Rect.fromLTWH(-3, -2, 6, 4), leafPaint);
        canvas.restore();
      }
    }
  }

  void _drawSpeedStreaks(Canvas canvas, Size size, double groundY) {
    final streakPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final baseSpeed = runPhase;

    final streaks = [
      {'y': groundY * 0.20, 'len': 55.0, 'spd': 1.8, 'w': 2.0, 'alpha': 0.16},
      {'y': groundY * 0.36, 'len': 80.0, 'spd': 2.3, 'w': 2.5, 'alpha': 0.25},
      {'y': groundY * 0.50, 'len': 45.0, 'spd': 1.6, 'w': 1.5, 'alpha': 0.15},
      {'y': groundY * 0.66, 'len': 95.0, 'spd': 2.8, 'w': 2.5, 'alpha': 0.30},
      {'y': groundY * 0.82, 'len': 65.0, 'spd': 2.0, 'w': 2.0, 'alpha': 0.20},
    ];

    for (var i = 0; i < streaks.length; i++) {
      final s = streaks[i];
      final y = s['y'] as double;
      final len = s['len'] as double;
      final spd = s['spd'] as double;
      final w = s['w'] as double;
      final a = s['alpha'] as double;

      final xOffset = (size.width + len * 2) * ((baseSpeed * spd + i * 0.2) % 1.0);
      final x1 = size.width - xOffset + len;
      final x2 = x1 - len;

      streakPaint.strokeWidth = w;
      streakPaint.color = (i % 2 == 0 ? primaryColor : accentColor)
          .withValues(alpha: a * (isDark ? 0.9 : 0.6));

      canvas.drawLine(Offset(x1, y), Offset(x2, y), streakPaint);
    }
  }

  void _drawCollegeCampusBuilding(Canvas canvas, Size size, double groundY) {
    final bldgFactor = ((progress - 0.35) / 0.65).clamp(0.0, 1.0);
    final easeCurve = Curves.easeOutCubic.transform(bldgFactor);
    final bldgX = size.width + 180 - easeCurve * (size.width * 0.60 + 180);

    const buildingWidth = 155.0;
    const buildingHeight = 125.0;
    final bldgTop = groundY - buildingHeight;

    // Base Academic Block Facade
    final bldgPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;
    final bldgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bldgX, bldgTop, buildingWidth, buildingHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(bldgRect, bldgPaint);

    final bldgBorder = Paint()
      ..color = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(bldgRect, bldgBorder);

    // Clock Tower & Academic Dome
    const towerWidth = 50.0;
    const towerHeight = 38.0;
    final towerX = bldgX + (buildingWidth - towerWidth) / 2;
    final towerTop = bldgTop - towerHeight;

    final towerPaint = Paint()
      ..color = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;
    final towerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(towerX, towerTop, towerWidth, towerHeight),
      const Radius.circular(5),
    );
    canvas.drawRRect(towerRect, towerPaint);
    canvas.drawRRect(towerRect, bldgBorder);

    final domePath = Path()
      ..moveTo(towerX - 4, towerTop)
      ..quadraticBezierTo(towerX + towerWidth / 2, towerTop - 20, towerX + towerWidth + 4, towerTop)
      ..close();
    final domePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(domePath, domePaint);

    // Micro-Animation: Fluttering Sine-Wave College Flag on Dome
    final polePaint = Paint()
      ..color = isDark ? Colors.white70 : Colors.black54
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(towerX + towerWidth / 2, towerTop - 20),
      Offset(towerX + towerWidth / 2, towerTop - 36),
      polePaint,
    );

    final flagPaint = Paint()..color = const Color(0xFFF59E0B)..style = PaintingStyle.fill;
    final flagPath = Path();
    const flagW = 16.0;
    const flagH = 10.0;
    final flagOriginX = towerX + towerWidth / 2;
    final flagOriginY = towerTop - 36;

    flagPath.moveTo(flagOriginX, flagOriginY);
    for (double fx = 0; fx <= flagW; fx += 2) {
      final fy = math.sin((runPhase * 4 * math.pi) + (fx / flagW) * math.pi * 2) * 1.8;
      flagPath.lineTo(flagOriginX + fx, flagOriginY + fy);
    }
    flagPath.lineTo(flagOriginX + flagW, flagOriginY + flagH);
    for (double fx = flagW; fx >= 0; fx -= 2) {
      final fy = math.sin((runPhase * 4 * math.pi) + (fx / flagW) * math.pi * 2) * 1.8;
      flagPath.lineTo(flagOriginX + fx, flagOriginY + flagH + fy);
    }
    flagPath.close();
    canvas.drawPath(flagPath, flagPaint);

    // Clock at 09:30 AM Cutoff
    final clockCenter = Offset(towerX + towerWidth / 2, towerTop + towerHeight / 2);
    final clockFacePaint = Paint()..color = Colors.white;
    canvas.drawCircle(clockCenter, 11, clockFacePaint);

    final clockRim = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(clockCenter, 11, clockRim);

    final handPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(clockCenter, clockCenter + const Offset(-6.0, 2.0), handPaint);
    canvas.drawLine(clockCenter, clockCenter + const Offset(0, 7.5), handPaint);

    // Classroom Lit Windows with Student Silhouettes
    final windowLitPaint = Paint()
      ..color = const Color(0xFFFEF08A).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final windowDarkPaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;

    for (var row = 0; row < 2; row++) {
      final wy = bldgTop + 26 + row * 22;
      for (var col = 0; col < 4; col++) {
        final wx = bldgX + 14 + col * 33;
        final isLit = (col + row) % 2 == 0;
        final wRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(wx, wy, 21, 14),
          const Radius.circular(2),
        );
        canvas.drawRRect(wRect, isLit ? windowLitPaint : windowDarkPaint);

        // Micro silhouette head inside lit window
        if (isLit) {
          final silPaint = Paint()..color = const Color(0xFF475569).withValues(alpha: 0.35);
          canvas.drawCircle(Offset(wx + 10, wy + 8), 3.5, silPaint);
        }
      }
    }

    // Grand Entrance Archway
    const archWidth = 46.0;
    const archHeight = 48.0;
    final archX = bldgX + (buildingWidth - archWidth) / 2;
    final archY = groundY - archHeight;

    final hallwayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFEF08A).withValues(alpha: 0.95),
          const Color(0xFFF59E0B).withValues(alpha: 0.85),
        ],
      ).createShader(Rect.fromLTWH(archX, archY, archWidth, archHeight));

    final archPath = Path()
      ..moveTo(archX, groundY)
      ..lineTo(archX, archY + 16)
      ..quadraticBezierTo(archX + archWidth / 2, archY - 8, archX + archWidth, archY + 16)
      ..lineTo(archX + archWidth, groundY)
      ..close();
    canvas.drawPath(archPath, hallwayPaint);

    // Pillars
    final pillarPaint = Paint()
      ..color = isDark ? const Color(0xFFE2E8F0) : Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(archX - 2, groundY), Offset(archX - 2, archY + 14), pillarPaint);
    canvas.drawLine(Offset(archX + archWidth + 2, groundY), Offset(archX + archWidth + 2, archY + 14), pillarPaint);

    // Grand Steps
    final stepPaint = Paint()
      ..color = isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(archX - 26, groundY + 1), Offset(archX + archWidth + 26, groundY + 1), stepPaint);
    canvas.drawLine(Offset(archX - 32, groundY + 4), Offset(archX + archWidth + 32, groundY + 4), stepPaint);

    // ── 5 CHEERING FRIENDS BESIDE ENTRANCE ──
    _drawCampusFriends(canvas, archX, archWidth, groundY, bldgTop);
  }

  void _drawCampusFriends(Canvas canvas, double archX, double archWidth, double groundY, double bldgTop) {
    final phi = runPhase * 2 * math.pi;

    final skinPaint = Paint()..color = const Color(0xFFFCD34D);
    final pantsPaint = Paint()
      ..color = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // FRIEND 1: Left Step — Teal Hoodie, Double-Arm Victory Wave \o/
    final f1X = archX - 22;
    final f1Bounce = math.sin(phi * 2) * 2.0;
    final f1Y = groundY - 24 + f1Bounce;

    final f1Hoodie = Paint()
      ..color = const Color(0xFF0D9488)
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f1X, f1Y + 5), Offset(f1X, f1Y - 9), f1Hoodie);
    canvas.drawLine(Offset(f1X - 2, f1Y + 5), Offset(f1X - 3, groundY), pantsPaint);
    canvas.drawLine(Offset(f1X + 2, f1Y + 5), Offset(f1X + 3, groundY), pantsPaint);
    canvas.drawCircle(Offset(f1X, f1Y - 16), 5.5, skinPaint);
    final f1Cap = Paint()..color = const Color(0xFF0284C7);
    canvas.drawArc(Rect.fromCircle(center: Offset(f1X, f1Y - 16), radius: 6.0), math.pi, math.pi, true, f1Cap);
    final arm1 = Paint()..color = const Color(0xFF0D9488)..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f1X - 3, f1Y - 6), Offset(f1X - 8, f1Y - 17 + math.sin(phi * 3) * 3), arm1);
    canvas.drawLine(Offset(f1X + 3, f1Y - 6), Offset(f1X + 8, f1Y - 17 - math.sin(phi * 3) * 3), arm1);

    // FRIEND 2: Left Pillar — Purple Hoodie, Holding Steaming Coffee / Chai ☕
    final f2X = archX - 9;
    final f2Y = groundY - 25;
    final f2Hoodie = Paint()
      ..color = const Color(0xFF8B5CF6)
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f2X, f2Y + 5), Offset(f2X, f2Y - 9), f2Hoodie);
    canvas.drawLine(Offset(f2X - 2, f2Y + 5), Offset(f2X - 2, groundY), pantsPaint);
    canvas.drawLine(Offset(f2X + 2, f2Y + 5), Offset(f2X + 2, groundY), pantsPaint);
    canvas.drawCircle(Offset(f2X, f2Y - 16), 5.5, skinPaint);
    final f2Hair = Paint()..color = const Color(0xFF78350F);
    canvas.drawCircle(Offset(f2X, f2Y - 18), 4.5, f2Hair);
    final arm2 = Paint()..color = const Color(0xFF8B5CF6)..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f2X - 3, f2Y - 6), Offset(f2X - 7, f2Y - 2), arm2);
    final cupPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(f2X - 10, f2Y - 5, 4, 6), cupPaint);
    canvas.drawLine(Offset(f2X + 3, f2Y - 6), Offset(f2X + 7, f2Y - 16 + math.sin(phi * 2) * 2), arm2);

    // Micro-Animation: Curling Coffee Steam wisps rising ☕
    final steamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final steamX = f2X - 8 + math.sin(phi * 3) * 1.5;
    final steamY = f2Y - 7 - (runPhase * 10) % 8;
    canvas.drawLine(Offset(steamX, steamY), Offset(steamX + 1.5, steamY - 3), steamPaint);

    // FRIEND 3: Right Pillar — Rose Hoodie, Glasses with Sparkle Glint ✨ & Thumbs Up 👍
    final f3X = archX + archWidth + 9;
    final f3Y = groundY - 25;
    final f3Hoodie = Paint()
      ..color = const Color(0xFFF43F5E)
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f3X, f3Y + 5), Offset(f3X, f3Y - 9), f3Hoodie);
    canvas.drawLine(Offset(f3X - 2, f3Y + 5), Offset(f3X - 2, groundY), pantsPaint);
    canvas.drawLine(Offset(f3X + 2, f3Y + 5), Offset(f3X + 2, groundY), pantsPaint);
    canvas.drawCircle(Offset(f3X, f3Y - 16), 5.5, skinPaint);
    final glasses = Paint()..color = const Color(0xFF0F172A)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(f3X - 2, f3Y - 16), 1.8, glasses);
    canvas.drawCircle(Offset(f3X + 2, f3Y - 16), 1.8, glasses);

    // Micro-Animation: Glasses Glint sparkle ✨
    if ((runPhase * 4).toInt() % 2 == 0) {
      final glintPaint = Paint()..color = Colors.white..strokeWidth = 1.2..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(f3X - 4, f3Y - 18), Offset(f3X, f3Y - 14), glintPaint);
      canvas.drawLine(Offset(f3X - 2, f3Y - 18), Offset(f3X - 2, f3Y - 14), glintPaint);
    }

    final arm3 = Paint()..color = const Color(0xFFF43F5E)..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f3X - 3, f3Y - 6), Offset(f3X - 7, f3Y - 14), arm3);
    canvas.drawCircle(Offset(f3X - 7, f3Y - 15), 1.5, skinPaint);
    canvas.drawLine(Offset(f3X + 3, f3Y - 6), Offset(f3X + 7, f3Y + 1), arm3);

    // FRIEND 4: Right Step — Amber Hoodie, Pointing at 09:30 Clock
    final f4X = archX + archWidth + 22;
    final f4Bounce = math.sin(phi * 2 + math.pi) * 2.0;
    final f4Y = groundY - 24 + f4Bounce;
    final f4Hoodie = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f4X, f4Y + 5), Offset(f4X, f4Y - 9), f4Hoodie);
    canvas.drawLine(Offset(f4X - 2, f4Y + 5), Offset(f4X - 3, groundY), pantsPaint);
    canvas.drawLine(Offset(f4X + 2, f4Y + 5), Offset(f4X + 3, groundY), pantsPaint);
    canvas.drawCircle(Offset(f4X, f4Y - 16), 5.5, skinPaint);
    final beanie = Paint()..color = const Color(0xFF1E293B);
    canvas.drawArc(Rect.fromCircle(center: Offset(f4X, f4Y - 16), radius: 5.8), math.pi, math.pi, true, beanie);
    final arm4 = Paint()..color = const Color(0xFFF59E0B)..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f4X - 3, f4Y - 6), Offset(f4X - 8, f4Y - 18), arm4);
    canvas.drawLine(Offset(f4X + 3, f4Y - 6), Offset(f4X + 7, f4Y - 10), arm4);

    // FRIEND 5: Archway Lobby — Emerald Hoodie Waving Welcome
    final f5X = archX + archWidth / 2 + 10;
    final f5Y = groundY - 23;
    final f5Hoodie = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f5X, f5Y + 4), Offset(f5X, f5Y - 8), f5Hoodie);
    canvas.drawLine(Offset(f5X - 2, f5Y + 4), Offset(f5X - 2, groundY), pantsPaint);
    canvas.drawLine(Offset(f5X + 2, f5Y + 4), Offset(f5X + 2, groundY), pantsPaint);
    canvas.drawCircle(Offset(f5X, f5Y - 14), 5.0, skinPaint);
    final arm5 = Paint()..color = const Color(0xFF10B981)..strokeWidth = 2.8..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(f5X - 2, f5Y - 5), Offset(f5X - 6, f5Y - 14 + math.sin(phi * 3) * 2), arm5);
    canvas.drawLine(Offset(f5X + 2, f5Y - 5), Offset(f5X + 5, f5Y + 2), arm5);

    // Micro-Animation: Cheerful Comic Speech Bubble above Friends
    final bubbleCenter = Offset(archX + archWidth / 2, bldgTop + 14 + math.sin(phi) * 2.5);
    final bubbleBg = Paint()..color = isDark ? const Color(0xFF0F172A) : Colors.white;
    final bubbleBorder = Paint()..color = const Color(0xFF10B981)..strokeWidth = 1.4..style = PaintingStyle.stroke;
    final bRect = RRect.fromRectAndRadius(Rect.fromCenter(center: bubbleCenter, width: 62, height: 16), const Radius.circular(8));
    canvas.drawRRect(bRect, bubbleBg);
    canvas.drawRRect(bRect, bubbleBorder);

    final textPainter = TextPainter(
      text: TextSpan(
        text: isDone ? 'ON TIME! ⚡' : 'HURRY! 🏃',
        style: GoogleFonts.outfit(
          color: const Color(0xFF10B981),
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, bubbleCenter - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  void _drawGroundTrack(Canvas canvas, Size size, double groundY) {
    final groundPaint = Paint()
      ..color = (isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8))
          .withValues(alpha: 0.5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, groundY), Offset(size.width, groundY), groundPaint);

    final dashPaint = Paint()
      ..color = (isError ? const Color(0xFFEF4444) : (isDone ? accentColor : primaryColor))
          .withValues(alpha: isDark ? 0.45 : 0.35)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const dashWidth = 18.0;
    const dashSpace = 24.0;
    final totalSpacing = dashWidth + dashSpace;
    final shift = (isError || isDone) ? 0.0 : (runPhase * totalSpacing * 2.8) % totalSpacing;

    for (double x = size.width + totalSpacing; x >= -totalSpacing; x -= totalSpacing) {
      final startX = x - shift;
      if (startX + dashWidth >= 0 && startX <= size.width) {
        canvas.drawLine(
          Offset(startX, groundY + 7),
          Offset(startX + dashWidth, groundY + 7),
          dashPaint,
        );
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════
  //  UNIFIED FLUID KINEMATIC STUDENT (NO SHARP CUTS)
  // ═════════════════════════════════════════════════════════════════

  void _drawFluidKinematicStudent(Canvas canvas, Size size, double groundY) {
    final phi = runPhase * 2 * math.pi;

    // Room camera pan position
    double roomShift = 0.0;
    if (progress >= 0.12) {
      final t = ((progress - 0.12) / 0.18).clamp(0.0, 1.0);
      roomShift = Curves.easeInOutCubic.transform(t);
    }
    final homeX = -roomShift * (size.width * 0.85 + 120);

    // Initial bed coordinates
    final inBedX = homeX + 54.0;
    const finalSprintLaneX = 0.35; // factor of size.width
    final sprintX = size.width * finalSprintLaneX;

    // ── STAGE PROGRESSION PARAMETERS (Continuous Blend) ──
    // 0.00 -> 0.08: Deep Sleep in Bed
    // 0.08 -> 0.16: Awakening & Sitting Up in Bed (sitBlend: 0.0 -> 1.0)
    // 0.16 -> 0.28: Fluid Leap Out of Bed into Running Lane (leapBlend: 0.0 -> 1.0)
    // 0.28 -> 0.95: Full Campus Sprint (runBlend: 0.0 -> 1.0)
    // 0.95 -> 1.00: Gliding Up the Steps (arriveBlend: 0.0 -> 1.0)

    final sitT = ((progress - 0.08) / 0.08).clamp(0.0, 1.0);
    final sitBlend = Curves.easeOutBack.transform(sitT);

    final leapT = ((progress - 0.16) / 0.12).clamp(0.0, 1.0);
    final leapBlend = Curves.easeInOutCubic.transform(leapT);

    final arriveT = ((progress - 0.95) / 0.05).clamp(0.0, 1.0);
    final arriveBlend = Curves.easeOutCubic.transform(arriveT);

    // 1. Calculate Continuous Student Position X & Y
    double currentStudentX;
    double currentStudentY;

    if (progress < 0.16) {
      currentStudentX = inBedX;
      final breathing = (1.0 - sitBlend) * (math.sin(phi) * 1.5);
      currentStudentY = groundY - 32 + breathing;
    } else {
      // Smooth continuous trajectory from Bed X to Sprint Lane X
      currentStudentX = inBedX + leapBlend * (sprintX - inBedX) + arriveBlend * (size.width * 0.16);
      final leapArc = math.sin(leapBlend * math.pi) * 22.0;
      currentStudentY = (groundY - 32) - leapArc + leapBlend * (-12.0);
    }

    // 2. Draw Duvet Blanket in Bed (smoothly pulled/kicked back)
    if (progress < 0.28) {
      _drawContinuousBedBlanket(canvas, homeX, groundY, sitBlend, leapBlend);
    }

    // 3. Render Student Kinematics with Continuous Interpolation
    _drawParametricStudent(
      canvas: canvas,
      size: size,
      groundY: groundY,
      pos: Offset(currentStudentX, currentStudentY),
      sitBlend: sitBlend,
      leapBlend: leapBlend,
      runBlend: ((progress - 0.18) / 0.10).clamp(0.0, 1.0),
      phi: phi,
      homeX: homeX,
    );
  }

  void _drawContinuousBedBlanket(Canvas canvas, double homeX, double groundY, double sitBlend, double leapBlend) {
    final alpha = (1.0 - leapBlend).clamp(0.0, 1.0);
    if (alpha <= 0.01) return;

    // Blanket slides back as student sits up and jumps
    final blanketX = homeX + 58 + sitBlend * 14 + leapBlend * 22;
    final blanketY = groundY - 37 + sitBlend * 10;
    final blanketW = 50 - sitBlend * 16;
    final blanketH = 34 - sitBlend * 8;

    final blanketPaint = Paint()
      ..color = primaryColor.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final blanketRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(blanketX, blanketY, blanketW.clamp(16.0, 52.0), blanketH.clamp(14.0, 36.0)),
      const Radius.circular(6),
    );
    canvas.drawRRect(blanketRect, blanketPaint);
  }

  void _drawParametricStudent({
    required Canvas canvas,
    required Size size,
    required double groundY,
    required Offset pos,
    required double sitBlend,
    required double leapBlend,
    required double runBlend,
    required double phi,
    required double homeX,
  }) {
    // Torso spine angle from upward vertical (0 = straight up, + = forward lean into run)
    double torsoAngle;
    if (progress < 0.08) {
      // Resting horizontally in bed towards pillow
      torsoAngle = -math.pi * 0.44;
    } else if (progress < 0.16) {
      // Sitting up smoothly towards 85 degrees
      torsoAngle = -math.pi * 0.44 * (1.0 - sitBlend) + 0.06 * sitBlend;
    } else {
      // Blends into athletic forward sprint lean (~15 degrees = 0.26 rad)
      const sprintLean = 0.26;
      torsoAngle = 0.06 + leapBlend * (sprintLean - 0.06);
    }

    // Harmonic 2-phase pelvic vertical oscillation (authentic human running bounce)
    final bounce = runBlend * (math.sin(phi * 2) * 4.2);
    final hip = Offset(pos.dx, pos.dy + bounce);

    // Anatomical chest & shoulder pivot
    final chest = Offset(
      hip.dx + 22.0 * math.sin(torsoAngle),
      hip.dy - 24.0 * math.cos(torsoAngle),
    );

    // Anatomical neck & head center
    final neck = Offset(
      chest.dx + 4.5 * math.sin(torsoAngle),
      chest.dy - 4.5 * math.cos(torsoAngle),
    );
    final headCenter = Offset(
      neck.dx + 8.5 * math.sin(torsoAngle),
      neck.dy - 8.5 * math.cos(torsoAngle),
    );

    // Dynamic dust puffs kicked up behind athletic sneakers during fast sprint
    if (runBlend >= 0.75 && progress < 0.95) {
      final dustOpacity = (isDark ? 0.22 : 0.14) * runBlend;
      final dustPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: dustOpacity)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 2; i++) {
        final dPhase = (runPhase * 2.0 + i * 0.5) % 1.0;
        final dustX = hip.dx - 14.0 - dPhase * 26.0;
        final dustY = groundY - 2.0 - dPhase * 5.0;
        final dustRadius = 2.5 + dPhase * 3.5;
        canvas.drawCircle(Offset(dustX, dustY), dustRadius, dustPaint);
      }
    }

    // ── LAYER 1: BACK ARM (Swinging in opposition to front leg) ──
    if (runBlend > 0.05) {
      final backArmAngle = (0.65 * math.sin(phi) + 0.20) * runBlend;
      _drawArm(
        canvas,
        shoulder: Offset(chest.dx - 3.0, chest.dy + 1.0),
        armAngle: backArmAngle,
        isFront: false,
        runBlend: runBlend,
        phi: phi,
      );
    }

    // ── LAYER 2: BACK LEG (Human Stride with 180° phase offset) ──
    if (runBlend > 0.05) {
      _drawLeg(
        canvas,
        hip: Offset(hip.dx - 2.5, hip.dy),
        phaseAngle: phi + math.pi,
        isFront: false,
        runBlend: runBlend,
        groundY: groundY,
      );
    }

    // ── LAYER 3: ERGONOMIC COLLEGE BACKPACK ──
    if (leapBlend > 0.05) {
      final bpAlpha = leapBlend.clamp(0.0, 1.0);
      final backpackLag = runBlend * (math.sin(phi - 0.7) * 3.0);
      final backpackCenter = Offset(
        chest.dx - 13.0 * leapBlend * math.cos(torsoAngle),
        chest.dy + 2.0 + backpackLag,
      );

      final backpackPaint = Paint()
        ..color = const Color(0xFFF97316).withValues(alpha: bpAlpha)
        ..style = PaintingStyle.fill;
      final backpackBorder = Paint()
        ..color = const Color(0xFFEA580C).withValues(alpha: bpAlpha)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      final backpackRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: backpackCenter,
          width: 17.0 * leapBlend,
          height: 25.0 * leapBlend,
        ),
        Radius.circular(6.0 * leapBlend),
      );
      canvas.drawRRect(backpackRect, backpackPaint);
      canvas.drawRRect(backpackRect, backpackBorder);

      // Backpack Front Pocket & Reflector Stripe
      final pocketPaint = Paint()
        ..color = const Color(0xFFC2410C).withValues(alpha: bpAlpha)
        ..style = PaintingStyle.fill;
      final pocketRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          backpackCenter.dx - 7.0 * leapBlend,
          backpackCenter.dy + 1.0,
          11.0 * leapBlend,
          9.0 * leapBlend,
        ),
        Radius.circular(3.0 * leapBlend),
      );
      canvas.drawRRect(pocketRect, pocketPaint);

      final reflectorPaint = Paint()
        ..color = const Color(0xFFFEF08A).withValues(alpha: bpAlpha * 0.85)
        ..strokeWidth = 1.6 * leapBlend
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        backpackCenter + Offset(-6.0 * leapBlend, 3.0),
        backpackCenter + Offset(2.0 * leapBlend, 3.0),
        reflectorPaint,
      );

      // Backpack Shoulder Straps
      final strapPaint = Paint()
        ..color = const Color(0xFF9A3412).withValues(alpha: bpAlpha)
        ..strokeWidth = 3.0 * leapBlend
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(backpackCenter + Offset(4.0 * leapBlend, -7.0 * leapBlend), chest, strapPaint);
    }

    // ── LAYER 4: ATHLETIC TORSO & VARSITY HOODIE ──
    final torsoPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(hip, chest, torsoPaint);

    if (runBlend > 0.3) {
      // Athletic hoodie zipper & seamline
      final zipperPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.40 * runBlend)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(chest.dx - 1.5, chest.dy + 2.0),
        Offset(hip.dx - 1.0, hip.dy - 2.0),
        zipperPaint,
      );

      // Micro-Animation: Swinging College ID Card Lanyard
      final lanyardSwing = math.sin(phi - 0.4) * 3.5 * runBlend;
      final lanyardPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(chest, chest + Offset(2.0 + lanyardSwing, 12.0), lanyardPaint);

      final idCardPaint = Paint()..color = Colors.white;
      final idBorder = Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      final idRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(chest.dx + 2.0 + lanyardSwing - 2.5, chest.dy + 12.0, 5.0, 7.0),
        const Radius.circular(1.0),
      );
      canvas.drawRRect(idRect, idCardPaint);
      canvas.drawRRect(idRect, idBorder);
    }

    // ── LAYER 5: FRONT LEG (Human Stride) ──
    if (runBlend > 0.05) {
      _drawLeg(
        canvas,
        hip: Offset(hip.dx + 2.5, hip.dy),
        phaseAngle: phi,
        isFront: true,
        runBlend: runBlend,
        groundY: groundY,
      );
    } else {
      // In bed relaxed tucked legs
      final inBedPants = Paint()
        ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(hip, Offset(hip.dx + 18.0, hip.dy + 5.0), inBedPants);
    }

    // ── LAYER 6: ANATOMICAL NECK & HEAD ──
    final neckPaint = Paint()
      ..color = const Color(0xFFEAB308)
      ..strokeWidth = 5.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(chest, neck, neckPaint);

    final skinPaint = Paint()..color = const Color(0xFFFCD34D);
    canvas.drawCircle(headCenter, 9.8, skinPaint);

    // Ear contour
    final earPaint = Paint()..color = const Color(0xFFF59E0B);
    canvas.drawCircle(headCenter + const Offset(-4.2, 1.0), 2.2, earPaint);

    // ── LAYER 7: FACIAL EXPRESSIONS & HEADWEAR ──
    if (progress < 0.08) {
      // ── STAGE A: PEACEFUL SLEEP IN BED ──
      final eyePaint = Paint()
        ..color = const Color(0xFF0F172A)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final eyePath = Path()
        ..moveTo(headCenter.dx - 1.0, headCenter.dy)
        ..quadraticBezierTo(headCenter.dx + 2.0, headCenter.dy + 2.0, headCenter.dx + 5.0, headCenter.dy);
      canvas.drawPath(eyePath, eyePaint);

      // Cozy Bedhead Hair
      final hairPaint = Paint()..color = const Color(0xFF78350F)..style = PaintingStyle.fill;
      canvas.drawCircle(headCenter + const Offset(-4.0, -5.0), 6.5, hairPaint);
      canvas.drawCircle(headCenter + const Offset(1.0, -7.0), 5.5, hairPaint);

      // Floating Zzz's
      final zPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.85)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final z1 = Offset(headCenter.dx + 16.0 + math.sin(phi) * 3.0, headCenter.dy - 12.0 - runPhase * 12.0);
      final z2 = Offset(headCenter.dx + 26.0 + math.sin(phi + 1.0) * 3.0, headCenter.dy - 22.0 - runPhase * 14.0);
      _drawLetterZ(canvas, z1, 6.0, zPaint);
      _drawLetterZ(canvas, z2, 8.5, zPaint);
    } else if (progress < 0.18) {
      // ── STAGE B: SHOCKED WAKING UP (O_O 💦 !) ──
      final eyeWhite = Paint()..color = Colors.white;
      final eyePupil = Paint()..color = const Color(0xFF0F172A);
      canvas.drawCircle(Offset(headCenter.dx - 2.0, headCenter.dy - 1.0), 3.2, eyeWhite);
      canvas.drawCircle(Offset(headCenter.dx + 4.0, headCenter.dy - 1.0), 3.2, eyeWhite);
      canvas.drawCircle(Offset(headCenter.dx - 1.5, headCenter.dy - 1.0), 1.8, eyePupil);
      canvas.drawCircle(Offset(headCenter.dx + 4.5, headCenter.dy - 1.0), 1.8, eyePupil);

      // Shocked Open Mouth
      final mouthPaint = Paint()..color = const Color(0xFF991B1B);
      canvas.drawOval(Rect.fromCenter(center: Offset(headCenter.dx + 1.5, headCenter.dy + 5.0), width: 3.5, height: 4.8), mouthPaint);

      // Panic Sweat Droplets
      final sweatPaint = Paint()..color = const Color(0xFF60A5FA);
      canvas.drawCircle(Offset(headCenter.dx + 13.0, headCenter.dy - 8.0), 2.4, sweatPaint);
      canvas.drawCircle(Offset(headCenter.dx + 17.0, headCenter.dy - 2.0), 1.8, sweatPaint);

      // Comic Exclamation Mark Bubble (!)
      final bubblePaint = Paint()..color = const Color(0xFFEF4444);
      canvas.drawCircle(Offset(headCenter.dx + 16.0, headCenter.dy - 22.0), 5.0, bubblePaint);
      final exclPaint = Paint()..color = Colors.white..strokeWidth = 1.6..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(headCenter.dx + 16.0, headCenter.dy - 24.5), Offset(headCenter.dx + 16.0, headCenter.dy - 21.0), exclPaint);
      canvas.drawCircle(Offset(headCenter.dx + 16.0, headCenter.dy - 19.2), 0.9, Paint()..color = Colors.white);
    } else {
      // ── STAGE C: DETERMINED ATHLETIC RUNNER (FORWARD VISOR CAP & EXPRESSION) ──
      final hairPaint = Paint()..color = const Color(0xFF78350F)..style = PaintingStyle.fill;
      canvas.drawCircle(headCenter + const Offset(-4.0, -3.0), 7.0, hairPaint);

      // Hair wind tufts blowing backwards
      if (runBlend > 0.3) {
        final tuftPath = Path()
          ..moveTo(headCenter.dx - 7.0, headCenter.dy - 2.0)
          ..lineTo(headCenter.dx - 15.0 - runBlend * 3.0, headCenter.dy - 1.0 + math.sin(phi * 3) * 1.5)
          ..lineTo(headCenter.dx - 7.0, headCenter.dy + 3.0)
          ..close();
        canvas.drawPath(tuftPath, hairPaint);
      }

      final capPaint = Paint()
        ..color = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)
        ..style = PaintingStyle.fill;

      // Cap Crown (sits snugly over upper skull)
      canvas.drawArc(
        Rect.fromCircle(center: headCenter, radius: 10.3),
        math.pi * 0.82,
        math.pi * 1.08,
        true,
        capPaint,
      );

      // Cap Top Button
      canvas.drawCircle(headCenter + const Offset(0.0, -10.4), 1.8, Paint()..color = const Color(0xFF0369A1));

      // AERODYNAMIC FORWARD-FACING VISOR (Points FORWARD in +X direction towards campus!)
      final visorPath = Path()
        ..moveTo(headCenter.dx + 4.0, headCenter.dy - 4.0)
        ..quadraticBezierTo(
          headCenter.dx + 11.0,
          headCenter.dy - 3.5,
          headCenter.dx + 16.5,
          headCenter.dy + 0.5,
        )
        ..quadraticBezierTo(
          headCenter.dx + 10.0,
          headCenter.dy + 0.5,
          headCenter.dx + 4.5,
          headCenter.dy - 1.0,
        )
        ..close();
      canvas.drawPath(visorPath, capPaint);

      // Under-visor subtle aerodynamic shade
      final visorShadow = Paint()
        ..color = Colors.black26
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(headCenter.dx + 4.5, headCenter.dy - 0.5),
        Offset(headCenter.dx + 14.5, headCenter.dy + 0.8),
        visorShadow,
      );

      // Determined Focused Eye & Eyebrow
      final pupilPaint = Paint()..color = const Color(0xFF0F172A);
      canvas.drawCircle(Offset(headCenter.dx + 5.0, headCenter.dy - 0.5), 2.0, pupilPaint);
      canvas.drawCircle(Offset(headCenter.dx + 5.8, headCenter.dy - 1.2), 0.7, Paint()..color = Colors.white);

      final browPaint = Paint()
        ..color = const Color(0xFF0F172A)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(headCenter.dx + 2.5, headCenter.dy - 3.5),
        Offset(headCenter.dx + 7.5, headCenter.dy - 2.0),
        browPaint,
      );

      // Determined Grit Mouth
      final mouthPaint = Paint()
        ..color = const Color(0xFF991B1B)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(headCenter.dx + 4.0, headCenter.dy + 4.5),
        Offset(headCenter.dx + 7.0, headCenter.dy + 3.8),
        mouthPaint,
      );

      // Flying sweat beads trailing in the sprint wind
      if (runBlend > 0.4) {
        final sweatPaint = Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.85);
        final sw1 = Offset(headCenter.dx - 12.0 - (runPhase * 16 % 12), headCenter.dy - 2.0 + math.sin(phi * 2) * 1.5);
        final sw2 = Offset(headCenter.dx - 18.0 - (runPhase * 20 % 14), headCenter.dy + 3.0 + math.cos(phi * 2) * 1.5);
        canvas.drawCircle(sw1, 1.8, sweatPaint);
        canvas.drawCircle(sw2, 1.3, sweatPaint);
      }
    }

    // ── LAYER 8: FRONT ARM (Pumping with Attendance Register) ──
    if (runBlend > 0.05) {
      final frontArmAngle = (-0.65 * math.sin(phi) + 0.20) * runBlend;
      _drawArm(
        canvas,
        shoulder: Offset(chest.dx + 3.5, chest.dy - 1.0),
        armAngle: frontArmAngle,
        isFront: true,
        runBlend: runBlend,
        phi: phi,
      );
    }
  }

  void _drawLetterZ(Canvas canvas, Offset pos, double s, Paint paint) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy)
      ..lineTo(pos.dx + s, pos.dy)
      ..lineTo(pos.dx, pos.dy + s)
      ..lineTo(pos.dx + s, pos.dy + s);
    canvas.drawPath(path, paint);
  }

  // ═════════════════════════════════════════════════════════════════
  //  THE TRUCK COLLISION SCENE (PORTAL UNREACHABLE ERROR)
  // ═════════════════════════════════════════════════════════════════

  void _drawTruckHitCollision(Canvas canvas, Size size, double groundY) {
    final t = crashPhase; // 0.0 -> 1.0 (3.6s cycle)
    final studentBaseX = size.width * 0.35;
    final impactStopX = studentBaseX + 15.0;

    double truckFrontX;
    if (t < 0.25) {
      final inT = t / 0.25;
      final easeIn = Curves.easeInQuad.transform(inT);
      truckFrontX = (size.width + 80) - easeIn * (size.width + 80 - impactStopX);
    } else {
      truckFrontX = impactStopX;
    }

    // 1. Skid marks
    if (t >= 0.24) {
      final skidPaint = Paint()
        ..color = (isDark ? Colors.black54 : Colors.black38)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(impactStopX + 10, groundY - 1),
        Offset(impactStopX + 100, groundY - 1),
        skidPaint,
      );
      canvas.drawLine(
        Offset(impactStopX + 10, groundY + 4),
        Offset(impactStopX + 100, groundY + 4),
        skidPaint,
      );
    }

    // 2. Draw Truck
    _drawTruck(canvas, truckFrontX, groundY, size, t);

    // 3. Impact Starburst
    if (t >= 0.23 && t <= 0.38) {
      _drawImpactBAM(canvas, Offset(studentBaseX + 12, groundY - 42), t);
    }

    // 4. Student Action
    if (t < 0.24) {
      _drawFluidKinematicStudent(canvas, size, groundY);
    } else {
      _drawFlyingOrDazedStudent(canvas, studentBaseX, groundY, t);
    }
  }

  void _drawTruck(Canvas canvas, double truckFrontX, double groundY, Size size, double t) {
    const truckW = 145.0;
    const truckH = 92.0;
    final truckTop = groundY - truckH;
    final truckX = truckFrontX;

    // Cargo Container Box
    final cargoRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(truckX + 42, truckTop - 12, truckW - 42, truckH + 4),
      const Radius.circular(6),
    );
    final cargoPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(cargoRect, cargoPaint);

    final cargoBorder = Paint()
      ..color = const Color(0xFF991B1B)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(cargoRect, cargoBorder);

    // Stripes
    final cargoStripe = Paint()
      ..color = const Color(0xFF991B1B)
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(truckX + 46, truckTop + 14), Offset(truckX + truckW - 4, truckTop + 14), cargoStripe);
    canvas.drawLine(Offset(truckX + 46, truckTop + 42), Offset(truckX + truckW - 4, truckTop + 42), cargoStripe);

    // "PORTAL 504" Emblem Plate
    final plateBg = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(truckX + 54, truckTop + 20, 64, 16),
        const Radius.circular(3),
      ),
      plateBg,
    );

    // Front Cab
    final cabPath = Path()
      ..moveTo(truckX + 42, groundY - 6)
      ..lineTo(truckX, groundY - 6)
      ..lineTo(truckX, truckTop + 34)
      ..lineTo(truckX + 18, truckTop + 12)
      ..lineTo(truckX + 42, truckTop + 12)
      ..close();
    final cabPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawPath(cabPath, cabPaint);
    canvas.drawPath(cabPath, cargoBorder);

    // Windshield
    final windshieldPath = Path()
      ..moveTo(truckX + 38, truckTop + 15)
      ..lineTo(truckX + 20, truckTop + 15)
      ..lineTo(truckX + 8, truckTop + 32)
      ..lineTo(truckX + 38, truckTop + 32)
      ..close();
    final windPaint = Paint()..color = const Color(0xFF93C5FD);
    canvas.drawPath(windshieldPath, windPaint);

    // Headlight & High-Beam Cone
    final headlightPaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(truckX + 3, groundY - 24), 7.0, headlightPaint);

    final rayPaint = Paint()
      ..color = const Color(0xFFFEF08A).withValues(alpha: 0.40)
      ..style = PaintingStyle.fill;
    final rayPath = Path()
      ..moveTo(truckX + 3, groundY - 24)
      ..lineTo(truckX - 70, groundY - 55)
      ..lineTo(truckX - 70, groundY + 4)
      ..close();
    canvas.drawPath(rayPath, rayPaint);

    // Grill Bumper
    final grillPaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFF334155)
      ..strokeWidth = 2.2;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(truckX + 2, groundY - 19 + i * 3.8),
        Offset(truckX + 14, groundY - 19 + i * 3.8),
        grillPaint,
      );
    }

    // Heavy Wheels
    final wheelPaint = Paint()..color = const Color(0xFF1E293B);
    final rimPaint = Paint()..color = const Color(0xFF94A3B8);

    final wheelCenters = [
      Offset(truckX + 24, groundY - 3),
      Offset(truckX + truckW - 56, groundY - 3),
      Offset(truckX + truckW - 20, groundY - 3),
    ];

    for (final wc in wheelCenters) {
      canvas.drawCircle(wc, 12.0, wheelPaint);
      canvas.drawCircle(wc, 6.0, rimPaint);
    }

    // Warning Horn lines when charging in
    if (t < 0.25) {
      final hornPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(truckX - 12, truckTop + 20), radius: 10),
        -math.pi / 3,
        2 * math.pi / 3,
        false,
        hornPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(truckX - 12, truckTop + 20), radius: 18),
        -math.pi / 3,
        2 * math.pi / 3,
        false,
        hornPaint,
      );
    }

    // Smoking Exhaust & Brakes
    if (t >= 0.25) {
      final smokePaint = Paint()
        ..color = (isDark ? Colors.white24 : Colors.black12)
        ..style = PaintingStyle.fill;
      final sx = truckX + truckW + 5 + (runPhase * 20 % 15);
      canvas.drawCircle(Offset(sx, truckTop + 8), 8.0, smokePaint);
      canvas.drawCircle(Offset(sx + 10, truckTop + 2), 12.0, smokePaint);
      canvas.drawCircle(Offset(truckX + 24, groundY - 14), 7.0, smokePaint);
    }
  }

  void _drawImpactBAM(Canvas canvas, Offset impactPos, double t) {
    final starPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(impactPos.dx, impactPos.dy);
    canvas.scale(1.5 + 0.4 * math.sin(t * 22 * math.pi));

    final path = Path();
    const points = 10;
    for (int i = 0; i < points; i++) {
      final angle = i * math.pi / 5;
      final radius = (i % 2 == 0) ? 28.0 : 13.0;
      final x = math.cos(angle) * radius;
      final y = math.sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, starPaint);
    canvas.restore();
  }

  void _drawFlyingOrDazedStudent(Canvas canvas, double studentBaseX, double groundY, double t) {
    double studentX;
    double studentY;
    double rotationAngle;

    if (t < 0.65) {
      final flyT = (t - 0.24) / 0.41;
      studentX = studentBaseX - flyT * 85.0;
      final arc = math.sin(flyT * math.pi);
      studentY = (groundY - 44) - arc * 65.0;
      rotationAngle = -flyT * 4 * math.pi;
    } else {
      studentX = studentBaseX - 85.0;
      studentY = groundY - 30;
      rotationAngle = -0.2;
    }

    canvas.save();
    canvas.translate(studentX, studentY);
    canvas.rotate(rotationAngle);

    // Torso
    final torsoPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-4, 8), const Offset(6, -16), torsoPaint);

    // Head
    final skinPaint = Paint()..color = const Color(0xFFFCD34D);
    canvas.drawCircle(const Offset(10, -26), 9.5, skinPaint);

    // Shock X Eyes
    final eyePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(7, -28), const Offset(11, -24), eyePaint);
    canvas.drawLine(const Offset(11, -28), const Offset(7, -24), eyePaint);

    // Cap with bill
    final capPaint = Paint()..color = const Color(0xFF38BDF8);
    canvas.drawCircle(const Offset(8, -32), 6.5, capPaint);
    final capBill = Path()
      ..moveTo(12, -32)
      ..lineTo(19, -29)
      ..lineTo(14, -27)
      ..close();
    canvas.drawPath(capBill, capPaint);

    // Limbs
    final legPaint = Paint()
      ..color = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-4, 8), const Offset(-18, 16), legPaint);
    canvas.drawLine(const Offset(-4, 8), const Offset(14, 22), legPaint);

    // Shoes
    final shoePaint = Paint()..color = const Color(0xFFEF4444)..strokeWidth = 4.5..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-18, 16), const Offset(-24, 18), shoePaint);
    canvas.drawLine(const Offset(14, 22), const Offset(20, 24), shoePaint);

    final armPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(4, -14), const Offset(-16, -24), armPaint);
    canvas.drawLine(const Offset(4, -14), const Offset(20, -10), armPaint);

    canvas.restore();

    // Circling Stars over Head
    if (t >= 0.60) {
      final dizzyCenter = Offset(studentX, groundY - 52);
      final starAngle = runPhase * 4 * math.pi;
      final star1 = dizzyCenter + Offset(math.cos(starAngle) * 16, math.sin(starAngle) * 8);
      final star2 = dizzyCenter + Offset(math.cos(starAngle + math.pi) * 16, math.sin(starAngle + math.pi) * 8);

      final starPaint = Paint()..color = const Color(0xFFFBBF24);
      canvas.drawCircle(star1, 3.5, starPaint);
      canvas.drawCircle(star2, 3.5, starPaint);
    }

    // Flying Paper Sheets
    if (t >= 0.24) {
      final notePaint = Paint()..color = Colors.white;
      final noteOffsets = [
        Offset(studentX + 20 - t * 45, groundY - 60 - t * 25),
        Offset(studentX - 20 - t * 30, groundY - 45 - t * 40),
        Offset(studentX + 35 - t * 50, groundY - 75 - t * 15),
      ];

      for (var i = 0; i < noteOffsets.length; i++) {
        final pos = noteOffsets[i];
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate((t * 8 + i * 2) % (2 * math.pi));
        canvas.drawRect(const Rect.fromLTWH(-5, -7, 10, 14), notePaint);
        canvas.restore();
      }
    }
  }

  void _drawLeg(
    Canvas canvas, {
    required Offset hip,
    required double phaseAngle,
    required bool isFront,
    required double runBlend,
    required double groundY,
  }) {
    const thighLen = 17.5;
    const shinLen = 17.5;

    // 1. Thigh angle from vertical downward (positive = forward, negative = backward)
    // Amplitude ~0.60 rad (~34.4 deg), forward lean bias ~0.12 rad (~6.9 deg)
    final theta = phaseAngle;
    final thighAngle = (0.60 * math.sin(theta) + 0.12) * runBlend;

    // 2. Human knee flexion (knee ONLY bends backward: beta_knee >= 0)
    // Recovery swing folds heel up towards glute (peaks when sin(theta - 0.4) is negative)
    final recSwing = math.sin(theta - 0.4);
    final double kneeBend;
    if (recSwing < 0) {
      // High heel recovery fold (up to ~75 deg)
      kneeBend = (0.18 + 1.15 * math.pow(-recSwing, 1.35)) * runBlend;
    } else {
      // Ground stance / push-off shock absorption (10 deg to 24 deg)
      kneeBend = (0.18 + 0.24 * math.sin(theta).clamp(0.0, 1.0)) * runBlend;
    }

    // 3. Knee joint position
    final knee = Offset(
      hip.dx + thighLen * math.sin(thighAngle),
      hip.dy + thighLen * math.cos(thighAngle),
    );

    // 4. Shin & Ankle (Strictly posterior flexion: shinAngle = thighAngle - kneeBend)
    final shinAngle = thighAngle - kneeBend;
    final ankle = Offset(
      knee.dx + shinLen * math.sin(shinAngle),
      knee.dy + shinLen * math.cos(shinAngle),
    );

    // 5. Draw Upper Thigh & Pants
    final pantsColor = isFront
        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A))
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFF334155));

    final pantsPaint = Paint()
      ..color = pantsColor
      ..strokeWidth = isFront ? 7.0 : 5.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(hip, knee, pantsPaint);

    // Contrasting sporty side stripe on front thigh
    if (isFront && runBlend > 0.3) {
      final stripePaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.85)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(hip.dx + 1.2, hip.dy + 1.0),
        Offset(knee.dx + 1.0, knee.dy - 2.0),
        stripePaint,
      );
    }

    // 6. Draw Lower Leg / Shin
    final calfPaint = Paint()
      ..color = pantsColor
      ..strokeWidth = isFront ? 5.8 : 4.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(knee, ankle, calfPaint);

    // Athletic Sock Cuff
    final sockPaint = Paint()
      ..color = Colors.white.withValues(alpha: isFront ? 0.95 : 0.7)
      ..strokeWidth = isFront ? 4.8 : 4.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(ankle + Offset(-math.sin(shinAngle) * 3.5, -math.cos(shinAngle) * 3.5), ankle, sockPaint);

    // 7. Athletic Running Sneaker with Dynamic Foot Rotation
    final double footAngle;
    if (math.sin(theta) < -0.2) {
      footAngle = shinAngle + 0.35 * runBlend; // plantarflexed push-off
    } else {
      footAngle = 0.08 + (shinAngle * 0.3) * runBlend; // level runner foot
    }

    const toeLen = 10.0;
    const heelLen = 4.0;
    final toe = Offset(
      ankle.dx + toeLen * math.cos(footAngle),
      ankle.dy + toeLen * math.sin(footAngle),
    );
    final heel = Offset(
      ankle.dx - heelLen * math.cos(footAngle),
      ankle.dy - heelLen * math.sin(footAngle),
    );

    // Sneaker Upper Body
    final shoeUpper = Paint()
      ..color = isFront ? const Color(0xFFEF4444) : const Color(0xFFDC2626)
      ..strokeWidth = isFront ? 5.2 : 4.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(heel, toe, shoeUpper);

    // White Running Outsole / Midsole Cushion
    final soleOffset = Offset(-math.sin(footAngle) * 2.2, math.cos(footAngle) * 2.2);
    final solePaint = Paint()
      ..color = Colors.white.withValues(alpha: isFront ? 0.95 : 0.75)
      ..strokeWidth = isFront ? 2.4 : 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(heel + soleOffset, toe + soleOffset, solePaint);

    // Sneaker Laces Accent
    if (isFront) {
      final lacePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(ankle + const Offset(1.5, -1.0), ankle + const Offset(4.5, 0.5), lacePaint);
    }
  }

  void _drawArm(
    Canvas canvas, {
    required Offset shoulder,
    required double armAngle,
    required bool isFront,
    required double runBlend,
    required double phi,
  }) {
    const upperArmLen = 13.5;
    const forearmLen = 13.5;

    // Shoulder to Elbow (swinging in anti-phase with legs)
    final elbow = Offset(
      shoulder.dx + upperArmLen * math.sin(armAngle),
      shoulder.dy + upperArmLen * math.cos(armAngle),
    );

    // Human Sprinter Elbow is naturally bent at ~80 deg forward-upward
    final forearmAngle = armAngle + 1.42 * runBlend;
    final hand = Offset(
      elbow.dx + forearmLen * math.sin(forearmAngle),
      elbow.dy + forearmLen * math.cos(forearmAngle),
    );

    final sleeveColor = isFront
        ? primaryColor
        : primaryColor.withValues(alpha: 0.70);

    final bicepPaint = Paint()
      ..color = sleeveColor
      ..strokeWidth = isFront ? 5.5 : 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(shoulder, elbow, bicepPaint);

    final forearmPaint = Paint()
      ..color = sleeveColor
      ..strokeWidth = isFront ? 4.8 : 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(elbow, hand, forearmPaint);

    // Runner's Hand / Fist
    final skinHandPaint = Paint()
      ..color = const Color(0xFFFCD34D)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(hand, isFront ? 3.4 : 3.0, skinHandPaint);

    // Front Hand holds the Official Attendance Register / Folder
    if (isFront && runBlend > 0.15) {
      canvas.save();
      canvas.translate(hand.dx, hand.dy);
      canvas.rotate(0.28 + math.sin(phi) * 0.08);

      // Attendance Folder Body (Emerald / Accent)
      final folderPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;
      final folderRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5, -14, 18, 22),
        const Radius.circular(3.0),
      );
      canvas.drawRRect(folderRect, folderPaint);

      // White Paper Sheets extending slightly
      final sheetPaint = Paint()..color = Colors.white;
      canvas.drawRect(const Rect.fromLTWH(8.5, -12, 3.0, 18), sheetPaint);

      // Micro-Animation: Fluttering Corner in Wind
      final flutter = math.sin(phi * 4) * 2.2;
      final flutterCorner = Path()
        ..moveTo(11.5, -12)
        ..lineTo(11.5 + flutter, -8)
        ..lineTo(8.5, -12)
        ..close();
      canvas.drawPath(flutterCorner, Paint()..color = Colors.white70);

      // Attendance Present Checkmark (✓)
      final tickPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final tickPath = Path()
        ..moveTo(-1.5, -3)
        ..lineTo(2.0, 1.0)
        ..lineTo(7.0, -6.0);
      canvas.drawPath(tickPath, tickPaint);

      canvas.restore();
    }
  }

  // ═════════════════════════════════════════════════════════════════
  //  ARRIVAL EFFECTS: HIGH-FIVE ELECTRIC SPARKS & CLOCK BELL WAVES
  // ═════════════════════════════════════════════════════════════════

  void _drawArrivalCelebrationEffects(Canvas canvas, Size size, double groundY) {
    final phi = runPhase * 2 * math.pi;

    // 1. Clock Tower Bell Soundwaves (9:30 AM chime)
    final towerTop = groundY - 125.0 - 38.0;
    final towerX = size.width * 0.60;
    final bellCenter = Offset(towerX, towerTop - 10);

    final chimePaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.35 + 0.35 * math.sin(phi * 2).abs())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (var r = 14.0; r <= 32.0; r += 9.0) {
      final pulseRadius = r + (runPhase * 16) % 16;
      final alpha = (1.0 - (pulseRadius - 14) / 25).clamp(0.0, 1.0);
      chimePaint.color = const Color(0xFFF59E0B).withValues(alpha: alpha * 0.5);
      canvas.drawArc(
        Rect.fromCircle(center: bellCenter, radius: pulseRadius),
        -math.pi * 0.85,
        math.pi * 0.7,
        false,
        chimePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: bellCenter, radius: pulseRadius),
        -math.pi * 0.15,
        math.pi * 0.7,
        false,
        chimePaint,
      );
    }

    // 2. Volumetric Warm Light Rays expanding from the Archway
    final archCenter = Offset(size.width * 0.55, groundY - 30);
    final rayPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFEF08A).withValues(alpha: 0.40),
          const Color(0xFF10B981).withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: archCenter, radius: 55));
    canvas.drawCircle(archCenter, 55, rayPaint);

    // 3. Electric Golden High-Five Sparks (⚡)
    final sparkCenter = Offset(size.width * 0.48, groundY - 32);
    final sparkPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * math.pi + runPhase * math.pi;
      final len = 6.0 + 4.0 * math.sin(phi * 3 + i).abs();
      final p1 = sparkCenter + Offset(math.cos(angle) * 8, math.sin(angle) * 8);
      final p2 = sparkCenter + Offset(math.cos(angle) * (8 + len), math.sin(angle) * (8 + len));
      canvas.drawLine(p1, p2, sparkPaint);
    }

    // 4. Floating Neon Checkmark Orbs (✓ Marked Present)
    final checkPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    final checkGlow = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final orbs = [
      Offset(size.width * 0.44, groundY - 55 - math.sin(phi) * 6),
      Offset(size.width * 0.64, groundY - 60 - math.cos(phi) * 6),
      Offset(size.width * 0.54, groundY - 72 - math.sin(phi + 1) * 5),
    ];

    for (final orb in orbs) {
      canvas.drawCircle(orb, 7.0, checkGlow);
      canvas.drawCircle(orb, 4.0, checkPaint);

      // Mini white checkmark inside orb
      final tick = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final tp = Path()
        ..moveTo(orb.dx - 2, orb.dy)
        ..lineTo(orb.dx - 0.5, orb.dy + 1.8)
        ..lineTo(orb.dx + 2.5, orb.dy - 1.8);
      canvas.drawPath(tp, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _StudentSprintPainter oldDelegate) {
    return oldDelegate.runPhase != runPhase ||
        oldDelegate.crashPhase != crashPhase ||
        oldDelegate.progress != progress ||
        oldDelegate.isDone != isDone ||
        oldDelegate.isError != isError ||
        oldDelegate.isDark != isDark;
  }
}
