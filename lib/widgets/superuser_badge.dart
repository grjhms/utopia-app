import 'package:flutter/material.dart';
import '../main.dart';

/// A theme-reactive green teal verification star badge for superusers.
class SuperUserBadge extends StatelessWidget {
  const SuperUserBadge({
    super.key,
    this.size = 14,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.verified_rounded,
      color: color ?? const Color(0xFF00A896), // Vibrant Green Teal
      size: size,
    );
  }
}









