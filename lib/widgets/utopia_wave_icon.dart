import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom hand-drawn wave hand icons for Utopia.
///
/// Two distinct states:
/// - [WaveHandState.wave]: Open palm with fingers spread, tilted —
///   "sending a wave". Drawn with thin elegant strokes.
/// - [WaveHandState.waved]: Closed fist bump / peace sign —
///   "acknowledged / already waved". Drawn with the same linework.
enum WaveHandState { wave, waved }

class UtopiaWaveHand extends StatelessWidget {
  const UtopiaWaveHand({
    super.key,
    this.size = 18.0,
    this.color,
    this.state = WaveHandState.wave,
  });

  final double size;
  final Color? color;
  final WaveHandState state;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: state == WaveHandState.wave
            ? _WaveHandPainter(color: c)
            : _WavedHandPainter(color: c),
      ),
    );
  }
}

/// Open palm with spread fingers, slightly tilted — "wave" gesture.
/// Clean thin linework, rounded joints, elegant and minimal.
class _WaveHandPainter extends CustomPainter {
  _WaveHandPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = math.max(1.0, w * 0.065);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Slight tilt for dynamism
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.18);
    canvas.translate(-w / 2, -h / 2);

    // Palm base
    final palm = Path();
    palm.moveTo(w * 0.28, h * 0.92);
    palm.cubicTo(w * 0.18, h * 0.78, w * 0.18, h * 0.55, w * 0.25, h * 0.48);
    palm.lineTo(w * 0.72, h * 0.48);
    palm.cubicTo(w * 0.82, h * 0.55, w * 0.82, h * 0.78, w * 0.72, h * 0.92);
    palm.close();
    canvas.drawPath(palm, paint);

    // Fingers — five lines extending from palm top
    final fingerData = <List<double>>[
      // [startX, startY, endX, endY] as fractions of w,h
      [0.28, 0.48, 0.18, 0.22], // pinky
      [0.37, 0.48, 0.32, 0.12], // ring
      [0.47, 0.48, 0.47, 0.06], // middle
      [0.57, 0.48, 0.60, 0.10], // index
      [0.72, 0.48, 0.80, 0.28], // thumb (shorter, angled out)
    ];

    for (final f in fingerData) {
      canvas.drawLine(
        Offset(w * f[0], h * f[1]),
        Offset(w * f[2], h * f[3]),
        paint,
      );
    }

    // Fingertips — small round caps
    final tipPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final tipR = s * 0.7;
    for (final f in fingerData) {
      canvas.drawCircle(Offset(w * f[2], h * f[3]), tipR, tipPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaveHandPainter old) => old.color != color;
}

/// Fist bump / peace gesture — "already waved" / acknowledged.
/// Two raised fingers (peace sign) with the rest curled.
class _WavedHandPainter extends CustomPainter {
  _WavedHandPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = math.max(1.0, w * 0.065);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Palm / fist body — rounder, more compact
    final fist = Path();
    fist.moveTo(w * 0.30, h * 0.92);
    fist.cubicTo(w * 0.20, h * 0.80, w * 0.22, h * 0.52, w * 0.28, h * 0.48);
    fist.lineTo(w * 0.70, h * 0.48);
    fist.cubicTo(w * 0.78, h * 0.52, w * 0.80, h * 0.80, w * 0.70, h * 0.92);
    fist.close();
    canvas.drawPath(fist, paint);

    // Two peace fingers — index & middle
    final fingers = <List<double>>[
      [0.40, 0.48, 0.36, 0.10], // index
      [0.55, 0.48, 0.58, 0.08], // middle
    ];

    for (final f in fingers) {
      canvas.drawLine(
        Offset(w * f[0], h * f[1]),
        Offset(w * f[2], h * f[3]),
        paint,
      );
    }

    // Fingertips
    final tipPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final tipR = s * 0.7;
    for (final f in fingers) {
      canvas.drawCircle(Offset(w * f[2], h * f[3]), tipR, tipPaint);
    }

    // Curled knuckle bumps for the other fingers
    final knucklePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.8
      ..strokeCap = StrokeCap.round;

    // Pinky knuckle
    final pk = Path();
    pk.moveTo(w * 0.26, h * 0.50);
    pk.quadraticBezierTo(w * 0.22, h * 0.40, w * 0.28, h * 0.38);
    canvas.drawPath(pk, knucklePaint);

    // Ring knuckle
    final rk = Path();
    rk.moveTo(w * 0.32, h * 0.48);
    rk.quadraticBezierTo(w * 0.30, h * 0.38, w * 0.34, h * 0.35);
    canvas.drawPath(rk, knucklePaint);

    // Thumb tuck
    final thumb = Path();
    thumb.moveTo(w * 0.68, h * 0.52);
    thumb.quadraticBezierTo(w * 0.78, h * 0.44, w * 0.74, h * 0.38);
    canvas.drawPath(thumb, knucklePaint);
  }

  @override
  bool shouldRepaint(covariant _WavedHandPainter old) => old.color != color;
}
