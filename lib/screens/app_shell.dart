import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/image_overlay_colors.dart';
import 'package:flutter/services.dart';
import 'people_screen.dart';
import 'focus_screen.dart';
import 'profile_screen.dart';
import 'university_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/app_motion.dart';
import '../services/app_update_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static bool _sessionCounted = false;

  static void resetSession() {
    _sessionCounted = false;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
  int _index = 0;
  late final PageController _pageController;
  late final AnimationController _gradientController;

  final List<Widget?> _screens = [
    const FocusScreen(),
    null,
    null,
    null,
  ];

  Widget _getScreen(int index) {
    if (_screens[index] == null) {
      switch (index) {
        case 1:
          _screens[index] = const PeopleScreen();
          break;
        case 2:
          _screens[index] = const UniversityScreen();
          break;
        case 3:
          _screens[index] = const ProfileScreen();
          break;
      }
    }
    return _screens[index]!;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await AppUpdateService.checkForUpdate(context);
      }
      if (mounted) {
        _checkPopupEvent();
      }
    });
  }

  Future<void> _checkPopupEvent() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!AppShell._sessionCounted) {
        AppShell._sessionCounted = true;
        final currentCount = prefs.getInt('app_open_count') ?? 0;
        await prefs.setInt('app_open_count', currentCount + 1);
      }

      final openCount = prefs.getInt('app_open_count') ?? 0;
      if (openCount < 2) {
        return;
      }

      final doc = await FirebaseFirestore.instance.collection('config').doc('app_config').get();

      final eventId = doc.data()?['popup_event_id'] as String?;
      if (eventId != null && eventId.isNotEmpty) {
        final lastSeen = prefs.getString('last_seen_popup_event_id');
        if (lastSeen != eventId) {
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: U.surfaceContainerHigh,
                    borderRadius: M3Shapes.extraLargeRadius,
                    border: Border.all(color: U.outlineVariant.withValues(alpha: 0.5), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: appThemeNotifier.value.isDark ? 0.4 : 0.12),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: U.primaryContainer.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.auto_awesome_rounded, color: U.primary, size: 32),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Share UTOPIA',
                        style: GoogleFonts.robotoFlex(
                          color: U.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Love using UTOPIA? Help your friends elevate their university experience by inviting them to the app!',
                        style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 14, height: 1.45),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: U.text,
                                side: BorderSide(color: U.outlineVariant),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: Text('Later', style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: U.primary,
                                foregroundColor: U.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                              ),
                              onPressed: () {
                                SharePlus.instance.share(
                                  ShareParams(
                                    text: 'Join me on UTOPIA! 🚀 The productivity platform.\n\nhttps://inferalis.space/download-utopia',
                                  ),
                                );
                                Navigator.pop(context);
                              },
                              child: Text('Share App', style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
            await prefs.setString('last_seen_popup_event_id', eventId);
          }
        }
      }
    } catch (e) {
      // Ignore errors silently
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  void _setIndex(int nextIndex) {
    if (nextIndex == _index) {
      return;
    }
    setState(() => _index = nextIndex);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(nextIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, _) {
        final timeSlot = ImageOverlayColors.getTimeSlot();
        final isDarkSky = timeSlot == 'evening' || timeSlot == 'night';
        final isDarkTheme = theme.isDark;
        final useLightStatusBarIcons = isDarkSky || isDarkTheme;

        final systemUiStyle = _index != 0
            ? SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: theme.isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness: theme.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: theme.surface,
                systemNavigationBarIconBrightness: theme.isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              )
            : SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: useLightStatusBarIcons ? Brightness.light : Brightness.dark,
                statusBarBrightness: useLightStatusBarIcons ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: theme.surface,
                systemNavigationBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
                systemNavigationBarDividerColor: Colors.transparent,
              );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemUiStyle,
          child: Scaffold(
            backgroundColor: theme.bg,
            extendBody: true,
            body: Stack(
              children: [
                Positioned.fill(
                  child: _buildMeshGradient(theme),
                ),
                PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    if (_index != index) {
                      setState(() => _index = index);
                    }
                  },
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _KeepAliveWrapper(child: _getScreen(0)),
                    _KeepAliveWrapper(child: _getScreen(1)),
                    _KeepAliveWrapper(child: _getScreen(2)),
                    _KeepAliveWrapper(child: _getScreen(3)),
                  ],
                ),
                // Floating Material 3 Expressive Capsule Nav Bar
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.paddingOf(context).bottom + 14,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 280),
                    curve: M3Motion.emphasizedDecelerate,
                    offset: isKeyboardOpen ? const Offset(0, 1.5) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isKeyboardOpen ? 0.0 : 1.0,
                      child: Builder(
                        builder: (context) {
                          final isDark = appThemeNotifier.value.isDark;
                          return ClipRRect(
                            borderRadius: M3Shapes.fullRadius,
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                height: 72,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D0D0E).withValues(alpha: 0.90),
                                  borderRadius: M3Shapes.fullRadius,
                                  border: Border.all(
                                    color: const Color(0xFF27272A).withValues(alpha: 0.6),
                                    width: 0.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.40),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                      spreadRadius: -2,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Expanded(
                                      child: _NavItem(
                                        icon: Icons.home_outlined,
                                        activeIcon: Icons.home_rounded,
                                        label: 'Home',
                                        isActive: _index == 0,
                                        isDark: true,
                                        onTap: () => _setIndex(0),
                                      ),
                                    ),
                                    Expanded(
                                      child: _NavItem(
                                        icon: Icons.groups_outlined,
                                        activeIcon: Icons.groups_rounded,
                                        label: 'People',
                                        isActive: _index == 1,
                                        isDark: true,
                                        onTap: () => _setIndex(1),
                                      ),
                                    ),
                                    Expanded(
                                      child: _NavItem(
                                        icon: Icons.school_outlined,
                                        activeIcon: Icons.school_rounded,
                                        label: 'Campus',
                                        isActive: _index == 2,
                                        isDark: true,
                                        onTap: () => _setIndex(2),
                                      ),
                                    ),
                                    Expanded(
                                      child: _NavItem(
                                        icon: Icons.person_outline_rounded,
                                        activeIcon: Icons.person_rounded,
                                        label: 'Profile',
                                        isActive: _index == 3,
                                        isDark: true,
                                        onTap: () => _setIndex(3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
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
  }

  Widget _buildMeshGradient(AppTheme theme) {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, _) {
        final value = _gradientController.value;
        final dx1 = cos(value * 2 * pi);
        final dy1 = sin(value * 2 * pi);

        final alpha1 = (0.05 + 0.02 * sin(value * 2 * pi)).clamp(0.0, 1.0);

        return Container(
          decoration: BoxDecoration(
            color: theme.bg,
          ),
          child: Stack(
            children: [
              // Subtle dark ambient grayscale glow
              Positioned(
                top: -200 + dy1 * 120,
                left: -200 + dx1 * 120,
                width: 600,
                height: 600,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: alpha1),
                        Colors.transparent,
                      ],
                    ),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return M3Pressable(
      onTap: onTap,
      scaleFactor: 0.92,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Standard Material 3 Icon Indicator Pill (60 x 32 dp)
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: M3Motion.expressiveCurve,
              width: isActive ? 60 : 36,
              height: 32,
              decoration: BoxDecoration(
                color: isActive ? U.primaryContainer : Colors.transparent,
                borderRadius: M3Shapes.fullRadius,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    isActive ? activeIcon : icon,
                    key: ValueKey<bool>(isActive),
                    color: isActive
                        ? U.onPrimaryContainer
                        : const Color(0xFF71717A),
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: GoogleFonts.robotoFlex(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                color: isActive
                    ? U.text
                    : const Color(0xFF71717A),
                letterSpacing: 0.2,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
