import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../theme/m3_expressive_theme.dart';

/// Material 3 Expressive Spring Motion Tokens
class M3Motion {
  const M3Motion._();

  /// Spatial navigation & bottom sheets spring
  static const SpringDescription spatialSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 26.0,
  );

  /// Micro-interaction & touch feedback effects spring
  static const SpringDescription effectSpring = SpringDescription(
    mass: 1.0,
    stiffness: 520.0,
    damping: 30.0,
  );

  /// Gentle ambient motion spring
  static const SpringDescription gentleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 260.0,
    damping: 24.0,
  );

  /// Expressive spring-like curve with natural physical overshoot
  static const Curve expressiveCurve = M3ExpressiveSpringCurve();

  /// Snappy deceleration curve
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Emphasized acceleration curve
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
}

/// Custom spring physics curve for Material 3 Expressive motions
class M3ExpressiveSpringCurve extends Curve {
  const M3ExpressiveSpringCurve({this.damping = 0.82, this.frequency = 1.15});

  final double damping;
  final double frequency;

  @override
  double transformInternal(double t) {
    if (t == 0.0 || t == 1.0) return t;
    // Damped harmonic oscillation curve
    final double decay = exp(-damping * 6.0 * t);
    final double oscillation = cos(frequency * 2.0 * pi * t * (1.0 - t * 0.3));
    return 1.0 - decay * oscillation;
  }
}

/// Material 3 Expressive Pressable Card / Surface with spring physics
class M3Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleFactor;
  final BorderRadius? borderRadius;
  final bool enableHaptics;
  final ShapeBorder? shape;

  const M3Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 0.965,
    this.borderRadius,
    this.enableHaptics = true,
    this.shape,
  });

  @override
  State<M3Pressable> createState() => _M3PressableState();
}

class _M3PressableState extends State<M3Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 280),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: M3Motion.expressiveCurve,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _controller.forward();
    if (widget.enableHaptics) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Forward route transition with Material 3 Expressive spring physics
Route<T> buildForwardRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: M3Motion.emphasizedDecelerate,
        reverseCurve: M3Motion.emphasizedAccelerate,
      );

      final slide = Tween<Offset>(
        begin: const Offset(0.04, 0.03),
        end: Offset.zero,
      ).animate(curve);

      final scale = Tween<double>(
        begin: 0.96,
        end: 1.0,
      ).animate(curve);

      final fade = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ));

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Container transform route with M3 spring expansion
Route<T> buildContainerRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 440),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: M3Motion.emphasizedDecelerate,
        reverseCurve: M3Motion.emphasizedAccelerate,
      );

      final scale = Tween<double>(begin: 0.88, end: 1.0).animate(curved);
      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
      final slide = Tween<Offset>(
        begin: const Offset(0.06, 0.04),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(
            alignment: Alignment.bottomRight,
            scale: scale,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Shimmer skeleton loader with Material 3 shape support
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = M3Shapes.large,
    this.margin,
  });

  final double height;
  final double? width;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = U.surfaceContainer;
    final highlight = U.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: [
                Color.lerp(base, highlight, t * 0.6)!,
                Color.lerp(highlight, base, t * 0.6)!,
                Color.lerp(base, highlight, t * 0.6)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      },
    );
  }
}
