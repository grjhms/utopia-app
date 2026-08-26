import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import '../services/follow_service.dart';
import '../services/people_interaction_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_screen.dart';
import 'event_certificates_screen.dart';
import 'event_details_screen.dart';
import 'notification_settings_screen.dart';
import 'user_profile_screen.dart';

class EventNotificationsScreen extends StatefulWidget {
  const EventNotificationsScreen({super.key});

  @override
  State<EventNotificationsScreen> createState() =>
      _EventNotificationsScreenState();
}

class _EventNotificationsScreenState extends State<EventNotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FollowService _followService = FollowService();
  final PeopleInteractionService _sparkService = PeopleInteractionService();

  List<EventModel> _endingSoon = [];
  List<EventModel> _newEvents = [];
  List<EventCertificate> _certificates = [];
  List<Map<String, dynamic>> _inAppNotifications = [];
  List<Map<String, dynamic>> _pendingFollowRequests = [];
  List<Map<String, dynamic>> _waves = [];

  List<String> _dismissedIds = [];
  bool _isLoading = true;
  StreamSubscription? _notifSub;
  StreamSubscription? _requestsSub;
  StreamSubscription? _wavesSub;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDismissedAndData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notifSub?.cancel();
    _requestsSub?.cancel();
    _wavesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDismissedAndData() async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds = prefs.getStringList('dismissed_notifications') ?? [];
    _setupSubscriptions();
    _sparkService.syncMyWavesCount();
    await _loadEventsAndCertificates();
  }

  void _setupSubscriptions() {
    if (_currentUid.isEmpty) return;

    // 1. Pending follow requests stream
    _requestsSub?.cancel();
    _requestsSub = _followService.pendingRequestsStream(_currentUid).listen((requests) {
      if (mounted) {
        setState(() {
          _pendingFollowRequests = requests
              .where((r) => !_dismissedIds.contains(r['requestDocId']))
              .toList();
        });
      }
    }, onError: (e) {
      debugPrint('Error listening to pending follow requests: $e');
    });

    // 2. Waves received stream
    _wavesSub?.cancel();
    _wavesSub = _sparkService.getMyWavesStream().listen((wavesList) {
      if (mounted) {
        setState(() {
          _waves = wavesList
              .where((w) => !_dismissedIds.contains(w['waveId']))
              .toList();
        });
      }
    }, onError: (e) {
      debugPrint('Error listening to waves: $e');
    });

    // 3. In-App Notifications stream from Firestore
    _notifSub?.cancel();
    _notifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: _currentUid)
        .limit(30)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        final list = snapshot.docs
            .map((d) => d.data())
            .where((n) => !_dismissedIds.contains(n['id']))
            .toList();
        list.sort((a, b) {
          final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return bTime.compareTo(aTime);
        });
        setState(() {
          _inAppNotifications = list;
        });
      }
    }, onError: (e) {
      debugPrint('Error listening to notifications: $e');
    });
  }

  Future<void> _loadEventsAndCertificates() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        EventService.instance.getEndingSoonEvents(limit: 5),
        EventService.instance.getUpcomingEvents(limit: 5),
        EventService.instance.getMyCertificates(),
      ]);
      if (mounted) {
        setState(() {
          _endingSoon = (results[0] as List<EventModel>)
              .where((e) => !_dismissedIds.contains(e.id))
              .toList();
          _newEvents = (results[1] as List<EventModel>)
              .where((e) => !_dismissedIds.contains(e.id))
              .toList();
          _certificates = (results[2] as List<EventCertificate>)
              .where((c) => !_dismissedIds.contains(c.id))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _dismissNotification(String notifId) async {
    if (notifId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds.add(notifId);
    await prefs.setStringList('dismissed_notifications', _dismissedIds);

    // Also delete from Firestore notifications if it exists
    try {
      await FirebaseFirestore.instance.collection('notifications').doc(notifId).delete();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _endingSoon.removeWhere((e) => e.id == notifId);
        _newEvents.removeWhere((e) => e.id == notifId);
        _certificates.removeWhere((c) => c.id == notifId);
        _inAppNotifications.removeWhere((n) => n['id'] == notifId);
        _pendingFollowRequests.removeWhere((r) => r['requestDocId'] == notifId);
        _waves.removeWhere((w) => w['waveId'] == notifId);
      });
    }
  }

  Future<void> _clearAllNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> allIdsToDismiss = [];

    for (final event in _endingSoon) {
      if (event.id != null) allIdsToDismiss.add(event.id!);
    }
    for (final event in _newEvents) {
      if (event.id != null) allIdsToDismiss.add(event.id!);
    }
    for (final cert in _certificates) {
      if (cert.id != null) allIdsToDismiss.add(cert.id!);
    }
    for (final n in _inAppNotifications) {
      final id = n['id']?.toString();
      if (id != null && id.isNotEmpty) allIdsToDismiss.add(id);
    }
    for (final w in _waves) {
      final id = w['waveId']?.toString();
      if (id != null && id.isNotEmpty) allIdsToDismiss.add(id);
    }

    if (allIdsToDismiss.isEmpty && _pendingFollowRequests.isEmpty) return;

    _dismissedIds.addAll(allIdsToDismiss);
    await prefs.setStringList('dismissed_notifications', _dismissedIds);

    // Delete Firestore notifications for user
    for (final n in _inAppNotifications) {
      final id = n['id']?.toString();
      if (id != null && id.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('notifications').doc(id).delete();
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _endingSoon.clear();
        _newEvents.clear();
        _certificates.clear();
        _inAppNotifications.clear();
        _waves.clear();
      });
      showUtopiaSnackBar(
        context,
        message: 'All notifications cleared',
        tone: UtopiaSnackBarTone.info,
      );
    }
  }

  List<Map<String, dynamic>> get _generalInAppNotifications {
    return _inAppNotifications.where((n) {
      final type = (n['type'] ?? '').toString();
      // Follow requests and waves already have rich dedicated cards from real-time streams.
      if (type == 'follow_request' || type == 'wave') {
        return false;
      }
      return true;
    }).toList();
  }

  int get _totalCount =>
      _pendingFollowRequests.length +
      _waves.length +
      _generalInAppNotifications.length +
      _certificates.length +
      _endingSoon.length +
      _newEvents.length;

  int get _socialCount =>
      _pendingFollowRequests.length +
      _waves.length +
      _generalInAppNotifications.where((n) {
        final type = (n['type'] ?? '').toString();
        return type == 'follow_accept' || type == 'chat' || type == 'broadcast';
      }).length;

  int get _eventsCount =>
      _certificates.length + _endingSoon.length + _newEvents.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 19),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.newsreader(
            color: U.text,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
          ),
        ),
        actions: [
          if (_totalCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                onPressed: _clearAllNotifications,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(
                  'Clear All',
                  style: GoogleFonts.plusJakartaSans(
                    color: U.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(Icons.tune_rounded, color: U.text, size: 20),
              tooltip: 'Notification Settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: U.primary,
          unselectedLabelColor: U.dim,
          indicatorColor: U.primary,
          indicatorWeight: 2.5,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: 'All ($_totalCount)'),
            Tab(text: 'Social ($_socialCount)'),
            Tab(text: 'Events ($_eventsCount)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: UtopiaLoader(scale: 0.7))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAllTab(),
                _buildSocialTab(),
                _buildEventsTab(),
              ],
            ),
    );
  }

  // ─── TAB 1: ALL NOTIFICATIONS ──────────────────────────────────────────────

  Widget _buildAllTab() {
    if (_totalCount == 0) {
      return _buildEmptyState('You\'re all caught up!', 'No new notifications right now.');
    }

    final generalNotifs = _generalInAppNotifications;

    return RefreshIndicator(
      color: U.primary,
      onRefresh: _loadEventsAndCertificates,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          // 1. Follow Requests
          if (_pendingFollowRequests.isNotEmpty) ...[
            _buildSectionHeader('Follow Requests (${_pendingFollowRequests.length})'),
            ..._pendingFollowRequests.map((r) => _buildFollowRequestCard(r)),
            const SizedBox(height: 12),
          ],

          // 2. Waves Received
          if (_waves.isNotEmpty) ...[
            _buildSectionHeader('Waves Received (${_waves.length}) 👋'),
            ..._waves.map((w) => _buildWaveCard(w)),
            const SizedBox(height: 12),
          ],

          // 3. Social & In-App Notifications
          if (generalNotifs.isNotEmpty) ...[
            _buildSectionHeader('Recent Updates'),
            ...generalNotifs.map((n) => _buildInAppNotificationCard(n)),
            const SizedBox(height: 12),
          ],

          // 4. Certificates Awarded
          if (_certificates.isNotEmpty) ...[
            _buildSectionHeader('Certificates Earned 🎓'),
            ..._certificates.map((cert) => _buildCertificateCard(cert)),
            const SizedBox(height: 12),
          ],

          // 5. Events Ending Soon
          if (_endingSoon.isNotEmpty) ...[
            _buildSectionHeader('Registrations Ending Soon ⏳'),
            ..._endingSoon.map((event) => _buildEventEndingSoonCard(event)),
            const SizedBox(height: 12),
          ],

          // 6. New Events
          if (_newEvents.isNotEmpty) ...[
            _buildSectionHeader('Upcoming Campus Events 🗓️'),
            ..._newEvents.map((event) => _buildNewEventCard(event)),
          ],
        ],
      ),
    );
  }

  // ─── TAB 2: SOCIAL NOTIFICATIONS (Follows, Waves, Chats) ───────────────────

  Widget _buildSocialTab() {
    if (_socialCount == 0) {
      return _buildEmptyState('No Social Alerts', 'Follow requests, waves, and new messages will appear here.');
    }

    final socialNotifications = _generalInAppNotifications.where((n) {
      final type = (n['type'] ?? '').toString();
      return type == 'follow_accept' || type == 'chat' || type == 'broadcast';
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      children: [
        if (_pendingFollowRequests.isNotEmpty) ...[
          _buildSectionHeader('Follow Requests (${_pendingFollowRequests.length})'),
          ..._pendingFollowRequests.map((r) => _buildFollowRequestCard(r)),
          const SizedBox(height: 12),
        ],
        if (_waves.isNotEmpty) ...[
          _buildSectionHeader('Waves Received (${_waves.length}) 👋'),
          ..._waves.map((w) => _buildWaveCard(w)),
          const SizedBox(height: 12),
        ],
        if (socialNotifications.isNotEmpty) ...[
          _buildSectionHeader('Social Activity'),
          ...socialNotifications.map((n) => _buildInAppNotificationCard(n)),
        ],
      ],
    );
  }

  // ─── TAB 3: EVENTS & CERTIFICATES ──────────────────────────────────────────

  Widget _buildEventsTab() {
    if (_eventsCount == 0) {
      return _buildEmptyState('No Event Alerts', 'Event announcements and certificates will appear here.');
    }

    return RefreshIndicator(
      color: U.primary,
      onRefresh: _loadEventsAndCertificates,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          if (_certificates.isNotEmpty) ...[
            _buildSectionHeader('Certificates Earned 🎓'),
            ..._certificates.map((cert) => _buildCertificateCard(cert)),
            const SizedBox(height: 12),
          ],
          if (_endingSoon.isNotEmpty) ...[
            _buildSectionHeader('Registrations Ending Soon ⏳'),
            ..._endingSoon.map((event) => _buildEventEndingSoonCard(event)),
            const SizedBox(height: 12),
          ],
          if (_newEvents.isNotEmpty) ...[
            _buildSectionHeader('Upcoming Events 🗓️'),
            ..._newEvents.map((event) => _buildNewEventCard(event)),
          ],
        ],
      ),
    );
  }

  // ─── CARD BUILDERS ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 6),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: U.dim,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // Follow Request Card with Accept / Decline buttons
  Widget _buildFollowRequestCard(Map<String, dynamic> request) {
    final docId = (request['requestDocId'] ?? '').toString();
    final uid = (request['uid'] ?? '').toString();
    final displayName = UtopiaApp.sanitizeDisplayName(
      (request['displayName'] ?? 'Student').toString(),
    );
    final email = (request['email'] ?? '').toString();
    final photoUrl = (request['photoUrl'] ?? request['photoURL'])?.toString();
    final branch = (request['branch'] ?? request['department'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: U.primary.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: uid.isNotEmpty
                ? () {
                    Navigator.push(
                      context,
                      buildForwardRoute(
                        UserProfileScreen(
                          uid: uid,
                          displayName: displayName,
                          email: email,
                          photoUrl: photoUrl,
                        ),
                      ),
                    );
                  }
                : null,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: U.primary.withValues(alpha: 0.15),
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: uid.isNotEmpty
                  ? () {
                      Navigator.push(
                        context,
                        buildForwardRoute(
                          UserProfileScreen(
                            uid: uid,
                            displayName: displayName,
                            email: email,
                            photoUrl: photoUrl,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: U.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    branch.isNotEmpty && branch.toLowerCase() != 'student'
                        ? 'Follow request • $branch'
                        : 'Sent you a follow request',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: U.sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accept Button
              ElevatedButton(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await _followService.acceptRequest(docId);
                  _dismissNotification(docId);
                  if (mounted) {
                    showUtopiaSnackBar(
                      context,
                      message: 'Accepted $displayName\'s follow request! ✨',
                      tone: UtopiaSnackBarTone.success,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: U.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Accept',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Decline Button
              IconButton(
                icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
                onPressed: () async {
                  await _followService.declineRequest(docId);
                  _dismissNotification(docId);
                },
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // Wave Received Card
  Widget _buildWaveCard(Map<String, dynamic> wave) {
    final waveId = (wave['waveId'] ?? '').toString();
    final senderId = (wave['senderId'] ?? '').toString();
    final senderName = UtopiaApp.sanitizeDisplayName(
      (wave['senderName'] ?? 'A student').toString(),
    );
    final photoUrl = wave['senderPhotoUrl']?.toString();
    final isReply = wave['isReply'] == true;
    final replied = wave['replied'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: U.peach.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: senderId.isNotEmpty
                ? () {
                    Navigator.push(
                      context,
                      buildForwardRoute(
                        UserProfileScreen(
                          uid: senderId,
                          displayName: senderName,
                          photoUrl: photoUrl,
                        ),
                      ),
                    );
                  }
                : null,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: U.peach.withValues(alpha: 0.15),
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? const Text('👋', style: TextStyle(fontSize: 18))
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: senderId.isNotEmpty
                  ? () {
                      Navigator.push(
                        context,
                        buildForwardRoute(
                          UserProfileScreen(
                            uid: senderId,
                            displayName: senderName,
                            photoUrl: photoUrl,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: U.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('👋', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isReply
                        ? 'Waved back at you! 👋'
                        : (replied
                            ? 'You waved back. No more waves today.'
                            : 'Waved at you! Tap to wave back.'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: U.sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isReply && !replied)
                ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await _sparkService.sendWave(
                      senderId,
                      isReply: true,
                      replyToWaveId: waveId,
                    );
                    _dismissNotification(waveId);
                    if (mounted) {
                      showUtopiaSnackBar(
                        context,
                        message: 'Waved back at $senderName! 👋',
                        tone: UtopiaSnackBarTone.success,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: U.peach.withValues(alpha: 0.2),
                    foregroundColor: U.text,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: U.peach.withValues(alpha: 0.45)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('👋', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        'Wave Back',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Waved Back ✓',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.teal,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
                onPressed: () => _dismissNotification(waveId),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // In-App Notification Card (Follow accept, messages, broadcasts)
  Widget _buildInAppNotificationCard(Map<String, dynamic> notif) {
    final id = (notif['id'] ?? '').toString();
    String rawTitle = (notif['title'] ?? 'Notification').toString().trim();
    String cleanTitle = rawTitle.replaceAll('👤', '').trim();
    if (cleanTitle.isEmpty) cleanTitle = 'Notification';

    final body = (notif['body'] ?? '').toString().trim();
    final type = (notif['type'] ?? 'general').toString();
    final senderId = (notif['senderId'] ?? '').toString();
    final senderName = UtopiaApp.sanitizeDisplayName(
      (notif['senderName'] ?? cleanTitle).toString(),
    );
    final photoUrl = notif['senderPhotoUrl']?.toString();
    final email = (notif['senderEmail'] ?? '').toString();

    IconData icon = Icons.notifications_rounded;
    Color color = U.primary;
    VoidCallback? onTap;

    if (type == 'follow_accept' || type == 'chat') {
      icon = type == 'follow_accept' ? Icons.favorite_rounded : Icons.chat_bubble_rounded;
      color = type == 'follow_accept' ? U.teal : U.blue;
      onTap = () async {
        if (senderId.isNotEmpty) {
          String userEmail = email;
          String userDisplayName = senderName;
          String? userPhoto = photoUrl;
          if (userEmail.isEmpty) {
            try {
              final doc = await FirebaseFirestore.instance.collection('users').doc(senderId).get();
              final data = doc.data();
              if (data != null) {
                userEmail = (data['email'] ?? '').toString();
                userDisplayName = UtopiaApp.sanitizeDisplayName(
                  (data['displayName'] ?? senderName).toString(),
                );
                userPhoto = data['photoUrl']?.toString();
              }
            } catch (_) {}
          }
          if (mounted) {
            Navigator.push(
              context,
              buildForwardRoute(
                ChatScreen(
                  otherUserId: senderId,
                  displayName: userDisplayName,
                  email: userEmail,
                  photoUrl: userPhoto,
                ),
              ),
            );
          }
        }
      };
    } else if (type == 'broadcast') {
      icon = Icons.campaign_rounded;
      color = U.peach;
    } else if (type == 'event' || type == 'certificate') {
      icon = Icons.workspace_premium_rounded;
      color = U.gold;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: U.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cleanTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: U.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      color: U.sub,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios_rounded, size: 13, color: U.dim),
            ],
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              onPressed: () => _dismissNotification(id),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // Certificate Earned Card
  Widget _buildCertificateCard(EventCertificate cert) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventCertificatesScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: U.gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: U.gold.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: U.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.workspace_premium_rounded, color: U.gold, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Certificate Awarded! 🎓',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: U.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Participation certificate for ${cert.eventTitle}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: U.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EventCertificatesScreen()),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: U.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'View',
                style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              onPressed: () => _dismissNotification(cert.id ?? ''),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // Event Registration Ending Soon
  Widget _buildEventEndingSoonCard(EventModel event) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EventDetailsScreen(event: event)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: U.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: U.peach.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: U.peach.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: U.peach, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Registration Ending Soon',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: U.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.title} closes on ${_formatDate(event.registrationDeadline ?? event.date)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: U.sub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              onPressed: () => _dismissNotification(event.id ?? ''),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // New Event Card
  Widget _buildNewEventCard(EventModel event) {
    final conductor = event.conductedBy.isNotEmpty ? event.conductedBy : event.organizerName;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EventDetailsScreen(event: event)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: U.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: U.border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_available_rounded, color: U.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: U.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conductor.isNotEmpty
                        ? 'By $conductor • ${_formatDate(event.date)}'
                        : _formatDate(event.date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: U.sub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              onPressed: () => _dismissNotification(event.id ?? ''),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: U.surface,
                shape: BoxShape.circle,
                border: Border.all(color: U.border),
              ),
              child: Icon(Icons.notifications_none_rounded, size: 30, color: U.dim),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: U.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: U.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
