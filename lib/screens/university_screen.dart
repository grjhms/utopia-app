import 'package:flutter/material.dart';
import '../widgets/utopia_loader.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../main.dart';
import '../services/university_service.dart';
import 'university_selection_screen.dart';
import 'iaa_screen.dart'; // ignore: unused_import
import 'attendance_screen.dart'; // ignore: unused_import
import 'people_screen.dart'; // ignore: unused_import
import 'friends_screen.dart'; // ignore: unused_import
import 'uni_chat_screen.dart'; // ignore: unused_import
import 'docs_screen.dart'; // ignore: unused_import
import 'drive_notebooks_screen.dart'; // ignore: unused_import
import 'events_screen.dart';
import 'event_notifications_screen.dart';
import 'projects_feed_screen.dart';
import '../services/cache_service.dart';
import '../services/event_service.dart';
import '../services/notification_service.dart';
import '../models/event_model.dart';
import 'community_notes_screen.dart';
import 'classes_screen.dart';
import 'timetable_screen.dart';
import 'assignments_screen.dart';
import 'sciwordle_screen.dart'; // ignore: unused_import
import '../theme/m3_expressive_theme.dart';
import '../widgets/app_motion.dart';

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
      final dismissedIds = await NotificationService.getDismissedNotificationIds();
      final lastClearedAt = await NotificationService.getLastNotificationsClearedAt();

      final results = await Future.wait([
        EventService.instance.getEndingSoonEvents(limit: 5),
        EventService.instance.getUpcomingEvents(limit: 5),
        EventService.instance.getMyCertificates(),
      ]);

      final endingSoon = (results[0] as List<EventModel>).where((e) => !NotificationService.isNotificationDismissed(
            e.id,
            dismissedIds: dismissedIds,
            lastClearedAt: lastClearedAt,
            createdAt: e.createdAt ?? e.date,
          )).toList();
      final newEvents = (results[1] as List<EventModel>).where((e) => !NotificationService.isNotificationDismissed(
            e.id,
            dismissedIds: dismissedIds,
            lastClearedAt: lastClearedAt,
            createdAt: e.createdAt ?? e.date,
          )).toList();
      final certificates = (results[2] as List<EventCertificate>).where((c) => !NotificationService.isNotificationDismissed(
            c.id,
            dismissedIds: dismissedIds,
            lastClearedAt: lastClearedAt,
            createdAt: c.issuedAt,
          )).toList();

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
          final uniModel = await UniversityService().getUniversityById(uniId);

          if (uniModel != null) {
            uniName = uniModel.name;
            await CacheService().saveAppSetting('cached_university_id', uniModel.id);
            await CacheService().saveAppSetting('cached_university_name', uniName);
            U.cachedUniversityId = uniModel.id;
            U.cachedUniversityName = uniName;
          } else {
            // University does not exist in any Firestore university collection -> clear and prompt selection
            await UniversityService().clearUserSelectedUniversity(user.uid);
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (route) => false,
              );
              return;
            }
          }
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
      // Attendance, People, Friends, Uni Chat, IAA, Docs, Drive Folders, SciWordle
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
      if (U.isAdityaCollege(_universityId, _universityName))
        _CardItem(
          title: 'Showcase',
          subtitle: 'Explore campus\nstudent projects',
          icon: Icons.rocket_launch_outlined,
          color: theme.primary,
          delay: 150,
          showBetaBadge: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProjectsFeedScreen()),
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
      _CardItem(
        title: 'Drive Folders',
        subtitle: 'Link & sync\nGoogle Drive',
        icon: Icons.add_to_drive_rounded,
        color: theme.teal,
        delay: 180,
        showBetaBadge: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DriveNotebooksScreen()),
        ),
      ),
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
      */
      _CardItem(
        title: 'Community Notes',
        subtitle: 'Campus notes &\nstudy materials',
        icon: Icons.menu_book_outlined,
        color: theme.blue,
        delay: 190,
        onTap: () async {
          final uniId = _universityId.isNotEmpty ? _universityId : 'support';
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CommunityNotesScreen(universityFolderName: uniId),
            ),
          );
        },
      ),
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
        title: 'Assignments',
        subtitle: 'Academic tasks\nand homework',
        icon: Icons.assignment_outlined,
        color: theme.blue,
        delay: 220,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AssignmentsScreen()),
        ),
      ),
      _CardItem(
        title: 'Timetable',
        subtitle: 'View & customize\nclass schedule',
        icon: Icons.calendar_month_rounded,
        color: theme.lavender,
        delay: 250,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TimetableScreen()),
        ),
      ),
      /*
      _CardItem(
        title: 'SciWordle',
        subtitle: 'Daily science\nword puzzle',
        icon: Icons.psychology_rounded,
        color: theme.green,
        delay: 300,
        showBetaBadge: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SciwordleScreen()),
        ),
      ),
      */
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
                    style: GoogleFonts.robotoFlex(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: theme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _displayUniversityName,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: theme.text,
                      letterSpacing: -0.4,
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
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.92,
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
                      showBetaBadge: card.showBetaBadge,
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
  final bool showBetaBadge;

  _CardItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isDisabled = false,
    required this.delay,
    required this.onTap,
    this.showBetaBadge = false,
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
    return Tooltip(
      message: tooltip,
      child: M3Pressable(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: U.surfaceContainerHighest,
                border: Border.all(
                  color: U.outlineVariant.withValues(alpha: 0.35),
                  width: 0.8,
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
                          style: GoogleFonts.robotoFlex(
                            color: Colors.white,
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
  final bool showBetaBadge;

  const _UniversityCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isDisabled = false,
    required this.onTap,
    required this.delay,
    this.showBetaBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: M3Shapes.cardRadius,
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: GoogleFonts.robotoFlex(
              color: isDisabled ? U.dim : U.text,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: GoogleFonts.robotoFlex(
                    color: isDisabled ? U.dim : U.sub,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: U.surfaceContainerLowest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    isDisabled ? Icons.lock_outline_rounded : Icons.chevron_right_rounded,
                    color: U.sub,
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final card = M3Pressable(
      onTap: onTap,
      scaleFactor: 0.95,
      borderRadius: M3Shapes.cardRadius,
      child: isDisabled
          ? Opacity(
              opacity: 0.45,
              child: cardContent,
            )
          : cardContent,
    );

    final content = showBetaBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              card,
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: U.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: U.primary.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'BETA',
                    style: GoogleFonts.robotoFlex(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: U.primary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          )
        : card;

    return content.animate().fadeIn(delay: delay.ms, duration: 400.ms).slideY(
          begin: 0.1,
          end: 0,
          delay: delay.ms,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
