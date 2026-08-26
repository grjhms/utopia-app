import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/image_overlay_colors.dart';
import 'package:flutter/services.dart';
import 'people_screen.dart';
import 'focus_screen.dart';
import 'profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';

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
  ];

  Widget _getScreen(int index) {
    if (_screens[index] == null) {
      switch (index) {
        case 1:
          _screens[index] = const PeopleScreen();
          break;
        case 2:
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPopupEvent();
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
                    color: U.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: U.primary.withValues(alpha: 0.3), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: U.primary.withValues(alpha: 0.2),
                        blurRadius: 32,
                        spreadRadius: 4,
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
                          color: U.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.auto_awesome, color: U.primary, size: 36),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Share UTOPIA',
                        style: GoogleFonts.playfairDisplay(
                          color: U.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Love using UTOPIA? Help your friends elevate their university experience by inviting them to the app!',
                        style: GoogleFonts.outfit(color: U.sub, fontSize: 15, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: U.text,
                                side: BorderSide(color: U.border),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: Text('Later', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: U.primary,
                                foregroundColor: U.bg,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () {
                                Share.share('Join me on UTOPIA! 🚀 The productivity platform.\n\nhttps://inferalis.space/download-utopia');
                                Navigator.pop(context);
                              },
                              child: Text('Share App', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
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
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
            backgroundColor: U.bg,
            extendBody: true,
            body: Stack(
              children: [
                Positioned.fill(
                  child: _buildMeshGradient(theme),
                ),
                PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _index = index);
                  },
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _KeepAliveWrapper(child: _getScreen(0)),
                    _KeepAliveWrapper(child: _getScreen(1)),
                    _KeepAliveWrapper(child: _getScreen(2)),
                  ],
              ),
              // Floating glassmorphic nav bar
              Positioned(
                left: 40,
                right: 40,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  offset: isKeyboardOpen ? const Offset(0, 1.5) : Offset.zero,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isKeyboardOpen ? 0.0 : 1.0,
                    child: Builder(
                      builder: (context) {
                        final isDark = appThemeNotifier.value.isDark;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                            child: Container(
                              height: 64,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? U.surface.withValues(alpha: 0.55)
                                    : U.surface.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.white.withValues(alpha: 0.6),
                                  width: 0.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.16),
                                    blurRadius: 28,
                                    offset: const Offset(0, 10),
                                    spreadRadius: -2,
                                  ),
                                  if (!isDark) ...[
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      blurRadius: 1,
                                      offset: const Offset(0, -0.5),
                                    ),
                                  ],
                                ],
                              ),
                              child: Stack(
                                children: [
                                  // Inner gloss highlight
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 28,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(32),
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.white.withValues(alpha: isDark ? 0.06 : 0.25),
                                            Colors.white.withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Nav items row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _NavItem(
                                        icon: Icons.dashboard_outlined,
                                        activeIcon: Icons.dashboard_rounded,
                                        isActive: _index == 0,
                                        accent: U.primary,
                                        isDark: isDark,
                                        onTap: () => _setIndex(0),
                                      ),
                                      _NavItem(
                                        icon: Icons.groups_outlined,
                                        activeIcon: Icons.groups_rounded,
                                        isActive: _index == 1,
                                        accent: U.primary,
                                        isDark: isDark,
                                        onTap: () => _setIndex(1),
                                      ),
                                      _NavItem(
                                        icon: Icons.person_outline_rounded,
                                        activeIcon: Icons.person_rounded,
                                        isActive: _index == 2,
                                        accent: U.primary,
                                        isDark: isDark,
                                        onTap: () => _setIndex(2),
                                      ),
                                    ],
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
    final isDark = theme.isDark;
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, _) {
        final value = _gradientController.value;
        final dx1 = cos(value * 2 * pi);
        final dy1 = sin(value * 2 * pi);
        final dx2 = sin(value * 2 * pi);
        final dy2 = cos(value * 2 * pi);

        final alpha1 = isDark
            ? (0.16 + 0.05 * sin(value * 2 * pi)).clamp(0.0, 1.0)
            : (0.15 + 0.03 * sin(value * 2 * pi)).clamp(0.0, 1.0);
            
        final alpha2 = isDark
            ? (0.14 + 0.04 * cos(value * 2 * pi)).clamp(0.0, 1.0)
            : (0.12 + 0.02 * cos(value * 2 * pi)).clamp(0.0, 1.0);
            
        final alpha3 = isDark
            ? (0.08 + 0.03 * sin(value * 2 * pi + pi)).clamp(0.0, 1.0)
            : (0.09 + 0.02 * sin(value * 2 * pi + pi)).clamp(0.0, 1.0);

        return Container(
          decoration: BoxDecoration(
            color: theme.bg,
          ),
          child: Stack(
            children: [
              // Top Left moving glow
              Positioned(
                top: -200 + dy1 * 150,
                left: -200 + dx1 * 150,
                width: 600,
                height: 600,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        theme.primary.withValues(alpha: alpha1),
                        theme.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom Right moving glow
              Positioned(
                bottom: -200 + dy2 * 130,
                right: -200 + dx2 * 130,
                width: 600,
                height: 600,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (theme.key == 'gruvbox' 
                            ? theme.peach 
                            : theme.teal).withValues(alpha: alpha2),
                        theme.teal.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Center subtle moving ambient light
              Positioned(
                top: 250 - dy1 * 80,
                right: 0 - dx2 * 80,
                width: 400,
                height: 400,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        theme.blue.withValues(alpha: alpha3),
                        theme.blue.withValues(alpha: 0.0),
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
  final bool isActive;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey(isActive),
                color: isActive
                    ? accent
                    : isDark
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.3),
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            // Active indicator dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: isActive ? 4 : 0,
              height: isActive ? 4 : 0,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
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
