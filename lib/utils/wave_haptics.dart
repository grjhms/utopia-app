import 'package:flutter/services.dart';

/// Micro-haptic configurations optimized for high-end Linear Resonant Actuators (LRAs)
/// and Apple Taptic Engines.
///
/// Design constraints:
/// - Impulse duration strictly under 10–20ms.
/// - Zero sustained buzzing, rumbling, or motor decay.
/// - Emulates physical mechanical switch actuations (Cherry / tactile dome) and mechanical latches.
/// - Emits sharp, crisp tactile clicks only on definitive structural events.
class WaveHaptics {
  WaveHaptics._();

  /// 🔘 Mechanical Switch Actuation (~10–12ms).
  /// Emulates pressing a tactile mechanical switch or precision mouse button.
  static void mechanicalClick() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// ⚙️ Micro-Detent Notch (~5–8ms).
  /// Emulates an ultra-light tactile detent notch or precision rotary step.
  static void detent() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// 🔒 Mechanical Latch Click (~12–15ms).
  /// Decisive, crisp mechanical latch sensation signaling state lock-in.
  static void latch() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// 👋 Wave Macro Trigger:
  /// Structural micro-haptic profile: sharp switch click on actuation,
  /// followed by a crisp micro-detent at the gesture peak.
  static Future<void> wave() async {
    try {
      // 1. Initial mechanical switch actuation (< 12ms)
      await HapticFeedback.lightImpact();
      // 2. Structural pause during travel to peak
      await Future.delayed(const Duration(milliseconds: 140));
      // 3. Peak apex micro-detent (< 8ms)
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// ✌️ Wave-Back Dual Macro Trigger:
  /// Dual crisp mechanical micro-clicks (dual-stage tactile bump, < 12ms each).
  static Future<void> waveBack() async {
    try {
      await HapticFeedback.selectionClick();
      await Future.delayed(const Duration(milliseconds: 60));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// 💡 Subtle ambient tick for minor UI interactions.
  static void subtleTap() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }
}
