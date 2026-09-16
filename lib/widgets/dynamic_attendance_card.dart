import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../main.dart';
import '../theme/m3_expressive_theme.dart';
import 'app_motion.dart';
import '../utils/responsive_scale.dart';

/// Material 3 Expressive Dynamic Motion Attendance Card
///
/// Inspired by Android 15 Material You Expressive widgets (Weather pebble, Media player).
/// Features:
/// - Giant expressive typography (like the 65° M3 weather widget)
/// - Continuous organic liquid sine wave that ripples and rolls smoothly
/// - Dynamic physical fluid simulation stimulated by gyroscope and accelerometer sensors
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _waveController;

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  // Fluid physics simulation state variables
  double _currentTilt = 0.0;
  double _tiltVelocity = 0.0;
  double _targetTilt = 0.0;
  double _sloshEnergy = 0.0;
  int _lastTickMicros = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _waveController.addListener(_onFrame);
    _startSensors();
  }

  void _onFrame() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_lastTickMicros != 0) {
      final dt = ((now - _lastTickMicros) / 1000000.0).clamp(0.001, 0.050);
      _stepPhysics(dt);
    }
    _lastTickMicros = now;
  }

  void _stepPhysics(double dt) {
    // Damped spring-mass oscillator model for liquid surface tilt:
    // F_spring = -k * displacement
    // F_damping = -c * velocity
    final displacement = _targetTilt - _currentTilt;
    final springAcc = displacement * 36.0;
    final dampingAcc = -_tiltVelocity * 5.2;
    final totalAcc = springAcc + dampingAcc;

    _tiltVelocity += totalAcc * dt;
    _currentTilt += _tiltVelocity * dt;

    // Agitation / slosh turbulence builds with motion and decays back to calm
    final motionIntensity = (_tiltVelocity.abs() * 0.8 + displacement.abs() * 0.6);
    _sloshEnergy = (_sloshEnergy * math.exp(-3.2 * dt) + motionIntensity * 0.18).clamp(0.0, 1.0);
  }

  void _startSensors() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();

    try {
      _accelSubscription = accelerometerEventStream().listen(
        (event) {
          final ax = event.x;
          final ay = event.y;
          final az = event.z;

          // Normal portrait phone orientation:
          if (ay > 1.2) {
            // Reduced to 40% intensity for a subtler, more refined fluid motion
            final rawAngle = -math.atan2(ax, ay) * 0.40;
            _targetTilt = rawAngle.clamp(-0.18, 0.18);
          } else if (ay < -2.0) {
            // Upside down: keep level to avoid jarring inversion
            _targetTilt = 0.0;
          } else {
            // Flat on desk or tilted towards horizontal: roll relative to screen normal
            final rollAngle = -math.atan2(ax, az.abs() + 0.1) * 0.40;
            _targetTilt = rollAngle.clamp(-0.18, 0.18);
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}

    try {
      _gyroSubscription = gyroscopeEventStream().listen(
        (event) {
          // Gyroscope z-axis gives angular velocity around screen normal in rad/s.
          // Rapid rotation imparts an inertial slosh impulse to fluid velocity (scaled to 40%)
          final impulse = event.z * (0.32 * 0.40);
          if (impulse.abs() > 0.015) {
            _tiltVelocity = (_tiltVelocity + impulse).clamp(-2.0, 2.0);
            _sloshEnergy = (_sloshEnergy + impulse.abs() * 0.45).clamp(0.0, 1.0);
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _pauseSensors() {
    _accelSubscription?.pause();
    _gyroSubscription?.pause();
  }

  void _resumeSensors() {
    _accelSubscription?.resume();
    _gyroSubscription?.resume();
  }

  void _stopSensors() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _gyroSubscription?.cancel();
    _gyroSubscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pauseSensors();
    } else if (state == AppLifecycleState.resumed) {
      _resumeSensors();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSensors();
    _waveController.removeListener(_onFrame);
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
    final rs = ResponsiveScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAvailable = widget.isConnected &&
        widget.attendancePct != null &&
        widget.attendancePct! > 0;
    final accentColor = _getThemeColor(widget.attendancePct);
    final pct = isAvailable ? (widget.attendancePct! / 100).clamp(0.0, 1.0) : 0.20;
    final pctString = isAvailable ? widget.attendancePct!.toStringAsFixed(0) : '—';

    return M3Pressable(
      onTap: () {
        // Subtle tactile fluid disturbance on tap (subtle 40% intensity)
        _tiltVelocity = (_tiltVelocity + 0.15).clamp(-2.0, 2.0);
        _sloshEnergy = (_sloshEnergy + 0.15).clamp(0.0, 1.0);
        widget.onTap();
      },
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
                // ── LAYER 1: Dynamic Rolling Liquid Wave Canvas (Sensor & Gyro Stimulated) ──
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LiquidWavePainter(
                      color: accentColor,
                      progress: waveProgress,
                      fillPercent: pct,
                      isDark: isDark,
                      tiltAngle: _currentTilt,
                      sloshEnergy: _sloshEnergy,
                    ),
                  ),
                ),

                // ── LAYER 2: Foreground Minimal Expressive Content ──
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
                          // Live Indicator Pill
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
                                SizedBox(
                                  width: rs.s(8, min: 6, max: 10),
                                  height: rs.s(8, min: 6, max: 10),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: rs.s(8, min: 6, max: 10),
                                        height: rs.s(8, min: 6, max: 10),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accentColor.withValues(
                                            alpha: (0.3 + 0.5 * math.sin(waveProgress * 2 * math.pi)).clamp(0.1, 0.8),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: rs.s(5, min: 3.5, max: 6),
                                        height: rs.s(5, min: 3.5, max: 6),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accentColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: rs.s(7, min: 5, max: 9)),
                                Text(
                                  _pillLabel,
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
                                    fontSize: rs.font(28, min: 22, max: 34),
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
                                      fontSize: rs.font(13, min: 11, max: 15),
                                      color: U.sub,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                else if (widget.attendancePct == null)
                                  Text(
                                    'Fetching latest data...',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: rs.font(13, min: 11, max: 15),
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
                                      fontSize: rs.font(13, min: 11, max: 15),
                                      color: U.sub,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Right: Giant M3 Expressive Number Display or Unavailable Dash
                          if (widget.isConnected && isAvailable)
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      pctString,
                                      style: GoogleFonts.robotoFlex(
                                        fontSize: rs.font(52, min: 40, max: 64),
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
                                          fontSize: rs.font(22, min: 18, max: 26),
                                          fontWeight: FontWeight.w800,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (widget.isConnected && !isAvailable)
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '—',
                                      style: GoogleFonts.robotoFlex(
                                        fontSize: rs.font(44, min: 36, max: 52),
                                        fontWeight: FontWeight.w900,
                                        height: 0.9,
                                        letterSpacing: -1,
                                        color: U.text,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: rs.s(8, min: 6, max: 12),
                                        vertical: rs.s(3, min: 2, max: 5),
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
                                          fontSize: rs.font(11, min: 9.5, max: 13),
                                          fontWeight: FontWeight.w700,
                                          color: U.sub,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Container(
                              width: rs.s(52, min: 42, max: 60),
                              height: rs.s(52, min: 42, max: 60),
                              decoration: BoxDecoration(
                                color: U.surfaceContainerLowest.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.sync_lock_rounded,
                                color: U.sub,
                                size: rs.s(24, min: 20, max: 28),
                              ),
                            ),
                        ],
                      ),

                      SizedBox(height: rs.vs(16, min: 10, max: 20)),

                      // Bottom Chunky Stadium Wave Track
                      Container(
                        height: rs.vs(12, min: 9, max: 15),
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

/// Custom painter rendering an organic fluid liquid wave tank synced with the attendance percentage
/// and animated with physical fluid dynamics stimulated by phone gyro and accelerometer sensors.
class _LiquidWavePainter extends CustomPainter {
  _LiquidWavePainter({
    required this.color,
    required this.progress,
    required this.fillPercent,
    required this.isDark,
    required this.tiltAngle,
    required this.sloshEnergy,
  });

  final Color color;
  final double progress;
  final double fillPercent;
  final bool isDark;
  final double tiltAngle;
  final double sloshEnergy;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Direct liquid tank fill synced with attendance percentage (50% = half tank, 100% = full tank)
    final clampedFill = fillPercent.clamp(0.0, 1.0);
    if (clampedFill <= 0.0) return;

    final baseHeight = h * clampedFill;
    // Base wave amplitude gently undulating, boosted dynamically when fluid is sloshing
    final baseAmplitude = clampedFill >= 0.98 ? 2.5 : (clampedFill <= 0.04 ? 2.0 : 4.5);
    final waveAmplitude = baseAmplitude + (sloshEnergy * 5.5);
    final phase = progress * 2 * math.pi;

    // Fluid surface slope: tan(tiltAngle)
    // When phone tilts right (tiltAngle > 0), liquid rushes to the right side of the card.
    // In canvas coordinates, higher liquid level corresponds to a smaller y.
    // Therefore at x = w (right edge), y should be smaller than at x = 0 (left edge).
    final frontSlope = math.tan(tiltAngle);
    final backSlope = math.tan(tiltAngle * 0.82); // Subtle parallax depth for 3D liquid tank effect

    // ── WAVE 1 (Back wave - softer opacity with parallax lag) ──
    final backPath = Path();
    backPath.moveTo(0, h);
    final yBack0 = (h - baseHeight - (-w / 2) * backSlope + math.sin(phase + 1.2) * waveAmplitude * 0.75).clamp(-20.0, h);
    backPath.lineTo(0, yBack0);

    for (double x = 0; x <= w; x += 3) {
      final dx = x - w / 2;
      final waveOffset = math.sin((x / w * 2 * math.pi) + phase + 1.2) * waveAmplitude * 0.75;
      final y = (h - baseHeight - dx * backSlope + waveOffset).clamp(-20.0, h);
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
        Rect.fromLTWH(0, 0, w, h),
      );

    canvas.drawPath(backPath, backPaint);

    // ── WAVE 2 (Front wave - crisper opacity) ──
    final frontPath = Path();
    frontPath.moveTo(0, h);
    final yFront0 = (h - baseHeight - (-w / 2) * frontSlope + math.sin(phase) * waveAmplitude).clamp(-20.0, h);
    frontPath.lineTo(0, yFront0);

    for (double x = 0; x <= w; x += 3) {
      final dx = x - w / 2;
      final waveOffset = math.sin((x / w * 2 * math.pi) + phase) * waveAmplitude;
      final y = (h - baseHeight - dx * frontSlope + waveOffset).clamp(-20.0, h);
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
        Rect.fromLTWH(0, 0, w, h),
      );

    canvas.drawPath(frontPath, frontPaint);

    // ── WAVE 3: Subtle Luminous Surface Meniscus Shimmer ──
    final surfacePath = Path();
    surfacePath.moveTo(0, yFront0);
    for (double x = 3; x <= w; x += 3) {
      final dx = x - w / 2;
      final waveOffset = math.sin((x / w * 2 * math.pi) + phase) * waveAmplitude;
      final y = (h - baseHeight - dx * frontSlope + waveOffset).clamp(-20.0, h);
      surfacePath.lineTo(x, y);
    }

    final surfacePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          color.withValues(alpha: isDark ? 0.12 : 0.08),
          color.withValues(alpha: isDark ? 0.28 : 0.20),
          color.withValues(alpha: isDark ? 0.12 : 0.08),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, w, h),
      );

    canvas.drawPath(surfacePath, surfacePaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.fillPercent != fillPercent ||
        oldDelegate.tiltAngle != tiltAngle ||
        oldDelegate.sloshEnergy != sloshEnergy;
  }
}
