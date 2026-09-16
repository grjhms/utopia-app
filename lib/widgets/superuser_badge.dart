import 'package:flutter/material.dart';

/// A verification badge for superusers displaying the Utopia icon.
class SuperUserBadge extends StatelessWidget {
  const SuperUserBadge({
    super.key,
    this.size = 14,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/icon_cropped.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
