import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../utils/wave_haptics.dart';

enum WaveButtonVariant {
  standard,
  iconOnly,
  pill,
  outlined,
}

enum _WaveAnimationPhase {
  idle,
  centering,
  waving,
  returning,
}

/// Tactile, soft-creamy Wave button with realistic depth,
/// matching the signature Utopia bottom nav and home card material.
class UtopiaWaveButton extends StatefulWidget {
  const UtopiaWaveButton({
    super.key,
    required this.hasWaved,
    required this.onWave,
    this.variant = WaveButtonVariant.standard,
    this.label = 'Wave',
    this.wavedLabel = 'Waved',
    this.height,
    this.width,
    this.isReply = false,
  });

  final bool hasWaved;
  final Future<void> Function() onWave;
  final WaveButtonVariant variant;
  final String label;
  final String wavedLabel;
  final double? height;
  final double? width;
  final bool isReply;

  @override
  State<UtopiaWaveButton> createState() => _UtopiaWaveButtonState();
}

class _UtopiaWaveButtonState extends State<UtopiaWaveButton>
    with TickerProviderStateMixin {
  bool _pressed = false;
  bool _isProcessing = false;
  bool _displayAsWaved = false;
  _WaveAnimationPhase _phase = _WaveAnimationPhase.idle;

  late AnimationController _collapseController;
  late Animation<double> _collapseAnimation;

  late AnimationController _wiggleController;
  late Animation<double> _wiggleAnimation;

  @override
  void initState() {
    super.initState();
    _displayAsWaved = widget.hasWaved;

    // Controls text collapse (width & opacity) and emoji centering
    // 0.0 = resting (text visible), 1.0 = collapsed (emoji centered, text faded out)
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 0.0,
    );
    _collapseAnimation = CurvedAnimation(
      parent: _collapseController,
      curve: Curves.easeInOutCubic,
    );

    // Controls waving wiggle and scale pulse in the center
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _wiggleAnimation = CurvedAnimation(
      parent: _wiggleController,
      curve: Curves.linear,
    );
  }

  @override
  void didUpdateWidget(covariant UtopiaWaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasWaved != oldWidget.hasWaved &&
        _phase == _WaveAnimationPhase.idle) {
      setState(() {
        _displayAsWaved = widget.hasWaved;
      });
    }
  }

  @override
  void dispose() {
    _collapseController.dispose();
    _wiggleController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    final isWaved = widget.hasWaved || _displayAsWaved;
    if (isWaved || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _phase = _WaveAnimationPhase.centering;
    });

    // Step 1: Center the wave emoji and fade out the "Wave" text
    await _collapseController.forward();

    if (!mounted) return;
    setState(() {
      _phase = _WaveAnimationPhase.waving;
    });

    // Fire crisp LRA micro-haptic macro trigger (switch click + peak detent)
    if (widget.isReply) {
      WaveHaptics.waveBack();
    } else {
      WaveHaptics.wave();
    }

    // Trigger background wave action concurrently
    final waveFuture = widget.onWave();

    // Step 2: Play lively waving animation in center (oscillation + scale pulse)
    await _wiggleController.forward(from: 0.0);

    if (!mounted) return;
    setState(() {
      _phase = _WaveAnimationPhase.returning;
      _displayAsWaved = true;
    });

    // Step 3: Reverse back to left, switch to peace/waved emoji, and fade in "Waved" text
    await _collapseController.reverse();

    // Fire mechanical latch click upon locking into Waved state
    WaveHaptics.latch();

    try {
      await waveFuture;
    } catch (e) {
      debugPrint('UtopiaWaveButton onWave error: $e');
    }

    if (mounted) {
      setState(() {
        _phase = _WaveAnimationPhase.idle;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveWaved = widget.hasWaved || _displayAsWaved;

    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, _) {
        final isDark = theme.isDark;

        return GestureDetector(
          onTapDown: (_) {
            if (!effectiveWaved && !_isProcessing) {
              WaveHaptics.detent();
              setState(() => _pressed = true);
            }
          },
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
            child: _buildVariant(isDark),
          ),
        );
      },
    );
  }

  BoxDecoration _buildContainerDecoration({
    required bool hasWaved,
    required bool isDark,
    required double borderRadius,
    bool isCircle = false,
  }) {
    if (hasWaved) {
      return BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  U.surface.withValues(alpha: 0.60),
                  U.surface.withValues(alpha: 0.40),
                ]
              : [
                  U.surface.withValues(alpha: 0.90),
                  U.surface.withValues(alpha: 0.70),
                ],
        ),
        border: Border.all(
          color: isDark
              ? U.border.withValues(alpha: 0.35)
              : U.border.withValues(alpha: 0.65),
          width: 0.8,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
      );
    }

    return BoxDecoration(
      shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                U.card.withValues(alpha: 0.95),
                U.card.withValues(alpha: 0.80),
              ]
            : [
                Colors.white,
                U.card.withValues(alpha: 0.95),
              ],
      ),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.75),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.09),
          blurRadius: 16,
          offset: const Offset(0, 6),
          spreadRadius: -2,
        ),
        BoxShadow(
          color: isDark
              ? Colors.white.withValues(alpha: 0.025)
              : Colors.black.withValues(alpha: 0.035),
          blurRadius: 5,
          offset: const Offset(0, 2),
          spreadRadius: 0,
        ),
        if (!isDark)
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.8),
            blurRadius: 1,
            offset: const Offset(0, -0.5),
          ),
      ],
    );
  }

  Widget _buildGlossSheen({
    required double borderRadius,
    required bool isDark,
    required double height,
    bool isCircle = false,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: isCircle
              ? null
              : BorderRadius.vertical(top: Radius.circular(borderRadius)),
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: isDark ? 0.06 : 0.28),
              Colors.white.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTactileIconPod({
    required String emoji,
    required bool hasWaved,
    required bool isDark,
    required double size,
    required double fontSize,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasWaved
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        U.card,
                        U.card.withValues(alpha: 0.70),
                      ]
                    : [
                        Colors.white,
                        U.card.withValues(alpha: 0.90),
                      ],
              ),
        color: hasWaved
            ? (isDark
                ? U.border.withValues(alpha: 0.30)
                : U.border.withValues(alpha: 0.45))
            : null,
        border: hasWaved
            ? Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.50),
                width: 0.6,
              )
            : null,
        boxShadow: hasWaved
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                  blurRadius: 5,
                  offset: const Offset(1.5, 2),
                ),
                BoxShadow(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.white,
                  blurRadius: 4,
                  offset: const Offset(-1.5, -1.5),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Text(
          emoji,
          key: ValueKey(emoji),
          style: TextStyle(
            fontSize: fontSize,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildTextVariant({
    required bool isWavedStyle,
    required bool isDark,
    required String emoji,
    required String label,
    required double height,
    required double radius,
    required double iconPodSize,
    required double iconFontSize,
    required double spacing,
    required TextStyle labelStyle,
    required EdgeInsetsGeometry padding,
    required double sheenHeight,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([_collapseAnimation, _wiggleAnimation]),
      builder: (context, _) {
        final collapseVal = _collapseAnimation.value;
        final textFactor = (1.0 - collapseVal).clamp(0.0, 1.0);

        double rotationAngle = 0.0;
        double scaleFactor = 1.0;
        if (_phase == _WaveAnimationPhase.waving) {
          final t = _wiggleAnimation.value;
          // Natural expressive wave oscillation (3.5 cycles with sine envelope)
          rotationAngle =
              math.sin(t * 3.5 * 2 * math.pi) * 0.28 * math.sin(t * math.pi);
          // Scale pulse peaking around the middle of the wave
          scaleFactor = 1.0 + 0.20 * math.sin(t * math.pi);
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: height,
          width: widget.width,
          decoration: _buildContainerDecoration(
            hasWaved: isWavedStyle,
            isDark: isDark,
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isWavedStyle)
                  _buildGlossSheen(
                    borderRadius: radius,
                    isDark: isDark,
                    height: sheenHeight,
                  ),
                Padding(
                  padding: padding,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.rotate(
                        angle: rotationAngle,
                        alignment: Alignment.bottomCenter,
                        child: Transform.scale(
                          scale: scaleFactor,
                          alignment: Alignment.bottomCenter,
                          child: _buildTactileIconPod(
                            emoji: emoji,
                            hasWaved: isWavedStyle,
                            isDark: isDark,
                            size: iconPodSize,
                            fontSize: iconFontSize,
                          ),
                        ),
                      ),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: textFactor,
                          child: Opacity(
                            opacity: textFactor,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: spacing),
                                Text(
                                  label,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.clip,
                                  style: labelStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVariant(bool isDark) {
    // Determine visual waved state
    final isWavedVisual = _displayAsWaved &&
        _phase != _WaveAnimationPhase.centering &&
        _phase != _WaveAnimationPhase.waving;

    final label = isWavedVisual ? widget.wavedLabel : widget.label;
    final emoji = isWavedVisual ? '✌️' : '👋';

    switch (widget.variant) {
      case WaveButtonVariant.iconOnly:
        final size = widget.width ?? widget.height ?? 34.0;
        return AnimatedBuilder(
          animation: _wiggleAnimation,
          builder: (context, _) {
            double rotationAngle = 0.0;
            double scaleFactor = 1.0;
            if (_phase == _WaveAnimationPhase.waving) {
              final t = _wiggleAnimation.value;
              rotationAngle =
                  math.sin(t * 3.5 * 2 * math.pi) * 0.28 * math.sin(t * math.pi);
              scaleFactor = 1.0 + 0.20 * math.sin(t * math.pi);
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: size,
              height: size,
              decoration: _buildContainerDecoration(
                hasWaved: isWavedVisual,
                isDark: isDark,
                borderRadius: size / 2,
                isCircle: true,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(size / 2),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isWavedVisual)
                      _buildGlossSheen(
                        borderRadius: size / 2,
                        isDark: isDark,
                        height: size * 0.45,
                        isCircle: true,
                      ),
                    Center(
                      child: Transform.rotate(
                        angle: rotationAngle,
                        alignment: Alignment.bottomCenter,
                        child: Transform.scale(
                          scale: scaleFactor,
                          alignment: Alignment.bottomCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                              scale: animation,
                              child:
                                  FadeTransition(opacity: animation, child: child),
                            ),
                            child: Text(
                              emoji,
                              key: ValueKey(emoji),
                              style: TextStyle(
                                fontSize: size * 0.45,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

      case WaveButtonVariant.pill:
        return _buildTextVariant(
          isWavedStyle: isWavedVisual,
          isDark: isDark,
          emoji: emoji,
          label: label,
          height: widget.height ?? 34,
          radius: 20.0,
          iconPodSize: 22.0,
          iconFontSize: 12.0,
          spacing: 6.0,
          sheenHeight: 16.0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          labelStyle: GoogleFonts.plusJakartaSans(
            color: isWavedVisual ? U.sub : U.text,
            fontSize: 11.5,
            fontWeight: isWavedVisual ? FontWeight.w600 : FontWeight.w700,
            letterSpacing: -0.2,
          ),
        );

      case WaveButtonVariant.outlined:
        return _buildTextVariant(
          isWavedStyle: isWavedVisual,
          isDark: isDark,
          emoji: emoji,
          label: label,
          height: widget.height ?? 46,
          radius: 14.0,
          iconPodSize: 28.0,
          iconFontSize: 15.0,
          spacing: 8.0,
          sheenHeight: 22.0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          labelStyle: GoogleFonts.outfit(
            color: isWavedVisual ? U.sub : U.text,
            fontWeight: isWavedVisual ? FontWeight.w600 : FontWeight.w700,
            fontSize: 13.5,
            letterSpacing: -0.2,
          ),
        );

      case WaveButtonVariant.standard:
        return _buildTextVariant(
          isWavedStyle: isWavedVisual,
          isDark: isDark,
          emoji: emoji,
          label: label,
          height: widget.height ?? 38,
          radius: 14.0,
          iconPodSize: 26.0,
          iconFontSize: 14.0,
          spacing: 8.0,
          sheenHeight: 18.0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          labelStyle: GoogleFonts.outfit(
            color: isWavedVisual ? U.sub : U.text,
            fontSize: 12,
            fontWeight: isWavedVisual ? FontWeight.w600 : FontWeight.w700,
            letterSpacing: -0.2,
          ),
        );
    }
  }
}
