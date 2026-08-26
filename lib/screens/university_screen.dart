import 'package:flutter/material.dart';
import '../widgets/utopia_loader.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../widgets/utopia_snackbar.dart';
import 'university_selection_screen.dart';
import 'iaa_screen.dart'; // ignore: unused_import
import 'attendance_screen.dart'; // ignore: unused_import
import 'people_screen.dart'; // ignore: unused_import
import 'friends_screen.dart'; // ignore: unused_import
import 'uni_chat_screen.dart'; // ignore: unused_import
import 'docs_screen.dart';
import 'events_screen.dart';
import 'event_notifications_screen.dart';
import '../services/cache_service.dart';
import '../services/event_service.dart';
import '../models/event_model.dart';
import 'community_notes_screen.dart'; // ignore: unused_import
import 'classes_screen.dart';

class UniversityScreen extends StatefulWidget {
  const UniversityScreen({super.key});

  @override
  State<UniversityScreen> createState() => _UniversityScreenState();
}

class _UniversityScreenState extends State<UniversityScreen> {
  String _universityId = U.cachedUniversityId;
  String _universityName = U.cachedUniversityName;
  bool _isLoading = true;
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadNotificationCount();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedIds = prefs.getStringList('dismissed_notifications') ?? [];

      final results = await Future.wait([
        EventService.instance.getEndingSoonEvents(limit: 5),
        EventService.instance.getUpcomingEvents(limit: 5),
        EventService.instance.getMyCertificates(),
      ]);

      final endingSoon = (results[0] as List<EventModel>).where((e) => !dismissedIds.contains(e.id)).toList();
      final newEvents = (results[1] as List<EventModel>).where((e) => !dismissedIds.contains(e.id)).toList();
      final certificates = (results[2] as List<EventCertificate>).where((c) => !dismissedIds.contains(c.id)).toList();

      if (mounted) {
        setState(() {
          _notificationCount = endingSoon.length + newEvents.length + certificates.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading notification count: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final uniId = userDoc.data()?['selectedUniversityId'] as String?;
        
        String uniName = '';
        if (uniId != null && uniId.isNotEmpty) {
          final uniDoc = await FirebaseFirestore.instance
              .collection('universities')
              .doc(uniId)
              .get();
          if (uniDoc.exists && uniDoc.data() != null) {
            uniName = uniDoc.data()?['name'] as String? ?? '';
          }

          // Cache selected university locally
          await CacheService().saveAppSetting('cached_university_id', uniId);
          await CacheService().saveAppSetting('cached_university_name', uniName);
          U.cachedUniversityId = uniId;
          U.cachedUniversityName = uniName;
        }

        if (mounted) {
          setState(() {
            _universityId = uniId ?? '';
            _universityName = uniName;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _displayUniversityName {
    if (_universityName.isNotEmpty) return _universityName;
    if (_universityId.isNotEmpty) {
      return _universityId
          .split('-')
          .map((word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '')
          .join(' ');
    }
    return 'Utopia Campus';
  }



  @override
  Widget build(BuildContext context) {
    final theme = appThemeNotifier.value;

    final cards = [
      // ── Hidden Cards (kept for reference / future restore) ──
      // Attendance, People, Friends, Uni Chat, IAA, Community Notes
      /*
      _CardItem(
        title: 'Attendance',
        subtitle: 'Track your class\nattendance daily',
        icon: Icons.fact_check_outlined,
        color: theme.primary,
        delay: 100,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        ),
      ),
      _CardItem(
        title: 'People',
        subtitle: 'Explore the\ncampus community',
        icon: Icons.public_outlined,
        color: theme.blue,
        delay: 150,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PeopleScreen()),
        ),
      ),
      _CardItem(
        title: 'Friends',
        subtitle: 'Connect with\nyour peers',
        icon: Icons.groups_outlined,
        color: theme.peach,
        delay: 200,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        ),
      ),
      */
      _CardItem(
        title: 'Events',
        subtitle: 'Campus happenings\nand activities',
        icon: Icons.event_available_outlined,
        color: theme.green,
        delay: 100,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventsScreen()),
        ),
      ),
      /*
      _CardItem(
        title: 'Uni Chat',
        subtitle: 'Chat with students\nand groups',
        icon: Icons.forum_outlined,
        color: theme.teal,
        delay: 300,
        onTap: () async {
          if (_universityId.isNotEmpty) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UniChatScreen(universityId: _universityId),
              ),
            );
          }
        },
      ),
      */
      _CardItem(
        title: 'Docs',
        subtitle: 'Access important\nresources',
        icon: Icons.description_outlined,
        color: theme.lavender,
        delay: 150,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocsScreen()),
        ),
      ),
      /*
      _CardItem(
        title: 'IAA',
        subtitle: 'Ask your academic\nAI assistant',
        icon: Icons.auto_awesome_rounded,
        color: theme.primary,
        delay: 400,
        onTap: () => Navigator.push(
          context,
          IAAScreen.route(),
        ),
      ),
      _CardItem(
        title: 'Community Notes',
        subtitle: 'Campus notes &\nstudy materials',
        icon: Icons.menu_book_outlined,
        color: theme.blue,
        delay: 450,
        onTap: () async {
          if (_universityId.isNotEmpty) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityNotesScreen(universityFolderName: _universityId),
              ),
            );
          }
        },
      ),
      */
      _CardItem(
        title: 'My Classes',
        subtitle: 'Study groups &\nshared folders',
        icon: Icons.groups_2_outlined,
        color: theme.peach,
        delay: 200,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClassesScreen()),
        ),
      ),
      _CardItem(
        title: 'Timetable',
        subtitle: 'Feature disabled',
        icon: Icons.calendar_month_rounded,
        color: Colors.grey,
        isDisabled: true,
        delay: 250,
        onTap: () {
          showUtopiaSnackBar(
            context,
            message: 'Timetable feature is currently muted & disabled.',
            tone: UtopiaSnackBarTone.info,
          );
        },
      ),
    ];

    return Scaffold(
      backgroundColor: U.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Premium Modern Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (Navigator.canPop(context)) ...[
                        _HeaderButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Circular University Change Button (Left)
                      _HeaderButton(
                        icon: Icons.swap_horiz_rounded,
                        tooltip: 'Change University',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UniversitySelectionScreen(),
                            ),
                          );
                          _loadData(); // Reload selected university details on back
                        },
                      ),
                    ],
                  ),
                  // Circular Notification Bell Button (Right)
                  _HeaderButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    showBadge: _notificationCount > 0,
                    badgeText: _notificationCount > 0 ? _notificationCount.toString() : null,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EventNotificationsScreen(),
                        ),
                      );
                      _loadNotificationCount(); // Reload count on return
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MY CAMPUS',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: theme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _displayUniversityName,
                    style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: theme.text,
                      letterSpacing: -0.6,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: UtopiaLoader(scale: 0.7),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return _UniversityCard(
                      title: card.title,
                      subtitle: card.subtitle,
                      icon: card.icon,
                      color: card.color,
                      isDisabled: card.isDisabled,
                      delay: card.delay,
                      onTap: card.onTap,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isDisabled;
  final int delay;
  final VoidCallback onTap;

  _CardItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isDisabled = false,
    required this.delay,
    required this.onTap,
  });
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool showBadge;
  final String? badgeText;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.showBadge = false,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.08) 
                    : Colors.black.withValues(alpha: 0.05),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.1) 
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: U.text,
                size: 20,
              ),
            ),
            if (showBadge)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: U.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: U.bg,
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: badgeText != null
                      ? Text(
                          badgeText!,
                          style: GoogleFonts.plusJakartaSans(
                            color: isDark ? Colors.black : Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UniversityCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isDisabled;
  final VoidCallback onTap;
  final int delay;

  const _UniversityCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isDisabled = false,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardContent = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDisabled
              ? [
                  U.card.withValues(alpha: 0.8),
                  U.card.withValues(alpha: 0.5),
                ]
              : [
                  U.card,
                  Color.lerp(U.card, color, isDark ? 0.08 : 0.05) ?? U.card,
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDisabled
              ? U.border.withValues(alpha: 0.3)
              : (isDark
                  ? color.withValues(alpha: 0.18)
                  : color.withValues(alpha: 0.14)),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isDisabled
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.18),
                        color.withValues(alpha: 0.06),
                      ],
                    ),
              color: isDisabled ? Colors.grey.withValues(alpha: 0.1) : null,
              shape: BoxShape.circle,
              border: Border.all(
                color: (isDisabled ? Colors.grey : color).withValues(alpha: 0.15),
                width: 0.8,
              ),
            ),
            child: Icon(icon, color: isDisabled ? U.dim : color, size: 24),
          ),
          const Spacer(),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: isDisabled ? U.dim : U.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: isDisabled ? U.dim : U.sub,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                  ),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    isDisabled ? Icons.lock_outline_rounded : Icons.chevron_right_rounded,
                    color: U.dim,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: isDisabled
          ? Opacity(
              opacity: 0.45,
              child: cardContent,
            )
          : cardContent,
    ).animate().fadeIn(delay: delay.ms, duration: 400.ms).slideY(
          begin: 0.1,
          end: 0,
          delay: delay.ms,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
  }
}



