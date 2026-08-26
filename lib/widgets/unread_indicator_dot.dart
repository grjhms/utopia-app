import 'package:flutter/material.dart';

/// An ultra-modern, fluidly pulsating unread notification beacon
/// with radiant core and expanding ambient ripple wave.
class UnreadIndicatorDot extends StatefulWidget {
  final double size;
  final Color color;
  final Color? glowColor;
  final bool animate;
  final bool showRipple;

  const UnreadIndicatorDot({
    super.key,
    this.size = 9.0,
    this.color = const Color(0xFF2DD4BF), // U.teal
    this.glowColor,
    this.animate = true,
    this.showRipple = true,
  });

  @override
  State<UnreadIndicatorDot> createState() => _UnreadIndicatorDotState();
}

class _UnreadIndicatorDotState extends State<UnreadIndicatorDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseScale;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOutSine),
      ),
    );

    _glowOpacity = Tween<double>(begin: 0.45, end: 0.95).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOutSine),
      ),
    );

    _rippleScale = Tween<double>(begin: 1.0, end: 2.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _rippleOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant UnreadIndicatorDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveGlow = widget.glowColor ?? widget.color;
    final dotSize = widget.size;

    if (!widget.animate) {
      return Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.9),
              widget.color,
              widget.color.withValues(alpha: 0.9),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: effectiveGlow.withValues(alpha: 0.6),
              blurRadius: dotSize * 0.8,
              spreadRadius: dotSize * 0.15,
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: dotSize * 2.4,
          height: dotSize * 2.4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding Ambient Ripple Wave
              if (widget.showRipple)
                Transform.scale(
                  scale: _rippleScale.value,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: effectiveGlow.withValues(
                        alpha: _rippleOpacity.value.clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),

              // Glowing Halo
              Transform.scale(
                scale: _pulseScale.value,
                child: Container(
                  width: dotSize * 1.5,
                  height: dotSize * 1.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveGlow.withValues(
                      alpha: (_glowOpacity.value * 0.35).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),

              // Radiant Core Orb
              Transform.scale(
                scale: _pulseScale.value,
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.25, -0.3),
                      radius: 0.9,
                      colors: [
                        Colors.white,
                        widget.color,
                        widget.color.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: effectiveGlow.withValues(
                          alpha: _glowOpacity.value.clamp(0.0, 1.0),
                        ),
                        blurRadius: dotSize * 0.9,
                        spreadRadius: dotSize * 0.2,
                      ),
                      BoxShadow(
                        color: effectiveGlow.withValues(alpha: 0.4),
                        blurRadius: dotSize * 1.8,
                        spreadRadius: dotSize * 0.5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
