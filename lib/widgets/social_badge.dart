import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// SVG ASSETS
// =============================================================================

const String _kGithubSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white">
<path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/>
</svg>
''';

const String _kDiscordSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white">
<path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994.021-.041.001-.09-.041-.106a13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.929 1.793 8.18 1.793 12.061 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.894.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.028zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"/>
</svg>
''';

// =============================================================================
// INSTAGRAM
// =============================================================================

/// Real authentic Instagram logo painter rendering the camera body, lens & flash
class RealInstagramIcon extends StatelessWidget {
  final double size;
  const RealInstagramIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF833AB4),
            Color(0xFFFD1D1D),
            Color(0xFFFCB045),
          ],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.54,
          height: size * 0.54,
          child: CustomPaint(
            painter: _InstagramCameraPainter(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _InstagramCameraPainter extends CustomPainter {
  final Color color;
  _InstagramCameraPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.12;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Outer Camera Body (Rounded Rect)
    final RRect outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(size.width * 0.28),
    );
    canvas.drawRRect(outerRect, paint);

    // Center Lens (Circle)
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.22;
    canvas.drawCircle(center, radius, paint);

    // Top-Right Flash Dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final dotCenter = Offset(size.width * 0.72, size.height * 0.28);
    final dotRadius = size.width * 0.08;
    canvas.drawCircle(dotCenter, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _InstagramCameraPainter oldDelegate) =>
      oldDelegate.color != color;
}

class InstagramBadge extends StatelessWidget {
  const InstagramBadge({
    super.key,
    required this.handle,
    this.fontSize = 11.5,
    this.iconSize = 18,
    this.compact = false,
    this.showHandle,
  });

  final String handle;
  final double fontSize;
  final double iconSize;
  final bool compact;
  final bool? showHandle;

  static Future<void> launchInstagramProfile(String handle) async {
    String clean = handle.trim();
    if (clean.startsWith('@')) clean = clean.substring(1).trim();
    if (clean.startsWith('https://instagram.com/')) {
      clean = clean.replaceFirst('https://instagram.com/', '');
    } else if (clean.startsWith('http://instagram.com/')) {
      clean = clean.replaceFirst('http://instagram.com/', '');
    } else if (clean.startsWith('instagram.com/')) {
      clean = clean.replaceFirst('instagram.com/', '');
    }
    clean = clean.replaceAll('/', '').trim();
    if (clean.isEmpty) return;

    final uri = Uri.parse('https://instagram.com/$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not open Instagram profile for $clean: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    String cleanHandle = handle.trim();
    if (cleanHandle.startsWith('@')) cleanHandle = cleanHandle.substring(1).trim();
    if (cleanHandle.startsWith('https://instagram.com/')) {
      cleanHandle = cleanHandle.replaceFirst('https://instagram.com/', '');
    } else if (cleanHandle.startsWith('http://instagram.com/')) {
      cleanHandle = cleanHandle.replaceFirst('http://instagram.com/', '');
    } else if (cleanHandle.startsWith('instagram.com/')) {
      cleanHandle = cleanHandle.replaceFirst('instagram.com/', '');
    }
    cleanHandle = cleanHandle.replaceAll('/', '').trim();
    if (cleanHandle.isEmpty) return const SizedBox.shrink();

    final bool displayHandle = showHandle ?? !compact;

    if (!displayHandle) {
      return GestureDetector(
        onTap: () => launchInstagramProfile(cleanHandle),
        child: RealInstagramIcon(size: iconSize),
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => launchInstagramProfile(cleanHandle),
        borderRadius: BorderRadius.circular(20),
        splashColor: const Color(0xFFE1306C).withValues(alpha: 0.18),
        highlightColor: const Color(0xFFE1306C).withValues(alpha: 0.08),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: displayHandle ? (compact ? 8 : 10) : 5,
            vertical: displayHandle ? (compact ? 3 : 5) : 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFE1306C).withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE1306C).withValues(alpha: 0.32),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RealInstagramIcon(size: iconSize),
              if (displayHandle) ...[
                const SizedBox(width: 5),
                Text(
                  '@$cleanHandle',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFE1306C),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.open_in_new_rounded,
                  size: fontSize * 0.9,
                  color: const Color(0xFFE1306C).withValues(alpha: 0.75),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// GITHUB
// =============================================================================

/// Authentic GitHub mark icon with dark slate gradient container and white Octocat
class RealGithubIcon extends StatelessWidget {
  final double size;
  const RealGithubIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2F363D),
            Color(0xFF181717),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.6,
        ),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.58,
          height: size * 0.58,
          child: SvgPicture.string(
            _kGithubSvg,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class GithubBadge extends StatelessWidget {
  const GithubBadge({
    super.key,
    required this.handle,
    this.fontSize = 11.5,
    this.iconSize = 18,
    this.compact = false,
    this.showHandle,
  });

  final String handle;
  final double fontSize;
  final double iconSize;
  final bool compact;
  final bool? showHandle;

  static String sanitizeHandle(String raw) {
    String clean = raw.trim();
    if (clean.startsWith('@')) clean = clean.substring(1).trim();
    if (clean.startsWith('https://github.com/')) {
      clean = clean.replaceFirst('https://github.com/', '');
    } else if (clean.startsWith('http://github.com/')) {
      clean = clean.replaceFirst('http://github.com/', '');
    } else if (clean.startsWith('github.com/')) {
      clean = clean.replaceFirst('github.com/', '');
    }
    return clean.replaceAll('/', '').trim();
  }

  static Future<void> launchGithubProfile(String handle) async {
    final clean = sanitizeHandle(handle);
    if (clean.isEmpty) return;

    final uri = Uri.parse('https://github.com/$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not open GitHub profile for $clean: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanHandle = sanitizeHandle(handle);
    if (cleanHandle.isEmpty) return const SizedBox.shrink();

    final bool displayHandle = showHandle ?? !compact;

    if (!displayHandle) {
      return GestureDetector(
        onTap: () => launchGithubProfile(cleanHandle),
        child: RealGithubIcon(size: iconSize),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color badgeColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292F);
    final Color badgeBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final Color badgeBorder = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.16);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => launchGithubProfile(cleanHandle),
        borderRadius: BorderRadius.circular(20),
        splashColor: badgeColor.withValues(alpha: 0.14),
        highlightColor: badgeColor.withValues(alpha: 0.07),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: displayHandle ? (compact ? 8 : 10) : 5,
            vertical: displayHandle ? (compact ? 3 : 5) : 4,
          ),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: badgeBorder,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RealGithubIcon(size: iconSize),
              if (displayHandle) ...[
                const SizedBox(width: 5),
                Text(
                  '@$cleanHandle',
                  style: GoogleFonts.outfit(
                    color: badgeColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.open_in_new_rounded,
                  size: fontSize * 0.9,
                  color: badgeColor.withValues(alpha: 0.75),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DISCORD
// =============================================================================

/// Authentic Discord Clyde icon with Blurple container
class RealDiscordIcon extends StatelessWidget {
  final double size;
  const RealDiscordIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF5865F2), // Discord Blurple
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.60,
          height: size * 0.60,
          child: SvgPicture.string(
            _kDiscordSvg,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class DiscordBadge extends StatelessWidget {
  const DiscordBadge({
    super.key,
    required this.handle,
    this.fontSize = 11.5,
    this.iconSize = 18,
    this.compact = false,
    this.showHandle,
  });

  final String handle;
  final double fontSize;
  final double iconSize;
  final bool compact;
  final bool? showHandle;

  static String sanitizeHandle(String raw) {
    String clean = raw.trim();
    if (clean.startsWith('@')) clean = clean.substring(1).trim();
    return clean;
  }

  static Future<void> launchDiscordProfile(String handle, [BuildContext? context]) async {
    final clean = sanitizeHandle(handle);
    if (clean.isEmpty) return;

    // Check if full URL or invite
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (_) {}
      }
    } else if (clean.startsWith('discord.gg/') || clean.startsWith('discord.com/')) {
      final uri = Uri.tryParse('https://$clean');
      if (uri != null) {
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (_) {}
      }
    } else if (RegExp(r'^\d{17,20}$').hasMatch(clean)) {
      // Snowflake user ID
      final uri = Uri.parse('https://discord.com/users/$clean');
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    // Standard username / tag -> Copy to clipboard & notify
    await Clipboard.setData(ClipboardData(text: clean));
    HapticFeedback.lightImpact();

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF5865F2),
          content: Row(
            children: [
              const RealDiscordIcon(size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copied Discord tag "$clean" to clipboard',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Also attempt to deep-link to Discord app if installed
    final appUri = Uri.parse('discord://');
    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cleanHandle = sanitizeHandle(handle);
    if (cleanHandle.isEmpty) return const SizedBox.shrink();

    final bool displayHandle = showHandle ?? !compact;

    if (!displayHandle) {
      return GestureDetector(
        onTap: () => launchDiscordProfile(cleanHandle, context),
        child: RealDiscordIcon(size: iconSize),
      );
    }

    const Color discordColor = Color(0xFF5865F2);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? const Color(0xFF7983F5) : discordColor;

    final isUrl = cleanHandle.startsWith('http://') ||
        cleanHandle.startsWith('https://') ||
        cleanHandle.startsWith('discord.gg/') ||
        cleanHandle.startsWith('discord.com/') ||
        RegExp(r'^\d{17,20}$').hasMatch(cleanHandle);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => launchDiscordProfile(cleanHandle, context),
        borderRadius: BorderRadius.circular(20),
        splashColor: discordColor.withValues(alpha: 0.18),
        highlightColor: discordColor.withValues(alpha: 0.08),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: displayHandle ? (compact ? 8 : 10) : 5,
            vertical: displayHandle ? (compact ? 3 : 5) : 4,
          ),
          decoration: BoxDecoration(
            color: discordColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: discordColor.withValues(alpha: 0.32),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RealDiscordIcon(size: iconSize),
              if (displayHandle) ...[
                const SizedBox(width: 5),
                Text(
                  cleanHandle.contains('#') || isUrl ? cleanHandle : '@$cleanHandle',
                  style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  isUrl ? Icons.open_in_new_rounded : Icons.copy_rounded,
                  size: fontSize * 0.9,
                  color: textColor.withValues(alpha: 0.75),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
