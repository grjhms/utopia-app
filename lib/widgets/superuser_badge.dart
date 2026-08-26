import 'package:flutter/material.dart';
import '../main.dart';

/// A theme-reactive red / crimson verification badge for superusers.
/// Dynamically adapts to the active theme palette via [U.red].
class SuperUserBadge extends StatelessWidget {
  const SuperUserBadge({
    super.key,
    this.size = 14,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.verified_rounded,
      color: U.red,
      size: size,
    );
  }
}
