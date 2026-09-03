import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../main.dart';
import '../services/chat_service.dart';
import '../services/follow_service.dart';
import '../widgets/app_motion.dart';
import 'chat_screen.dart';
import 'follow_requests_screen.dart';

/// Friends screen – shows:
///   • Tab 0: Following (people the current user follows back, i.e., mutual)
///   • Tab 1: Requests badge (navigates to [FollowRequestsScreen])
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final FollowService _followService = FollowService();

  late final TabController _tabController;

  StreamSubscription<Map<String, Map<String, dynamic>>>?
      _recentChatsSubscription;
  Map<String, Map<String, dynamic>> _recentChats = const {};

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _recentChatsSubscription =
        _chatService.recentChatsStream().listen((value) {
      if (!mounted) return;
      setState(() => _recentChats = value);
    });
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }


  @override
  void dispose() {
    _tabController.dispose();
    _recentChatsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isSearching
                    ? Row(
                        key: const ValueKey('search'),
                        children: [
                          Expanded(
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: U.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: U.border),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Icon(Icons.search, color: U.sub, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      autofocus: true,
                                      style: GoogleFonts.outfit(
                                          color: U.text, fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'Search following...',
                                        hintStyle: GoogleFonts.outfit(
                                            color: U.dim),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: Icon(Icons.close,
                                          color: U.sub, size: 16),
                                      onPressed: _searchController.clear,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () => setState(() {
                              _isSearching = false;
                              _searchController.clear();
                            }),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('title'),
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: U.text,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.pop(context),
                            ),
                          if (Navigator.canPop(context))
                            const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Friends',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: U.text,
                              ),
                            ),
                          ),
                          // Requests bell
                          StreamBuilder<int>(
                            stream: _followService
                                .pendingRequestsCountStream(_currentUid),
                            builder: (context, snap) {
                              final count = snap.data ?? 0;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        buildForwardRoute(
                                          FollowRequestsScreen(
                                              currentUid: _currentUid),
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.person_add_outlined,
                                      color: U.primary,
                                      size: 22,
                                    ),
                                    tooltip: 'Follow Requests',
                                    splashRadius: 20,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  if (count > 0)
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: U.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            count > 9 ? '9+' : '$count',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _isSearching = true),
                            icon: Icon(
                              Icons.search_rounded,
                              color: U.primary,
                              size: 20,
                            ),
                            tooltip: 'Search',
                            splashRadius: 20,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 10),
            Divider(color: U.border, height: 1, thickness: 0.5),

            // ── Following list ─────────────────────────────────────────────
            Expanded(
              child: _FollowingList(
                currentUid: _currentUid,
                chatService: _chatService,
                followService: _followService,
                recentChats: _recentChats,
                query: _searchController.text.trim().toLowerCase(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Following list ───────────────────────────────────────────────────────────

class _FollowingList extends StatelessWidget {
  const _FollowingList({
    required this.currentUid,
    required this.chatService,
    required this.followService,
    required this.recentChats,
    required this.query,
  });

  final String currentUid;
  final ChatService chatService;
  final FollowService followService;
  final Map<String, Map<String, dynamic>> recentChats;
  final String query;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: followService.followingUidsStream(currentUid),
      builder: (context, followingSnap) {
        if (followingSnap.connectionState == ConnectionState.waiting) {
          return const _FriendsSkeleton();
        }

        final followingUids = followingSnap.data ?? [];

        // Collect all participants from recent chats
        final recentChatOtherUids = <String>{};
        for (final entry in recentChats.entries) {
          final participants = (entry.value['participants'] as List<dynamic>? ?? const [])
              .map((p) => p.toString())
              .toList();
          for (final p in participants) {
            if (p != currentUid && p.isNotEmpty) {
              recentChatOtherUids.add(p);
            }
          }
        }

        final allRelevantUids = {...followingUids, ...recentChatOtherUids};

        if (allRelevantUids.isEmpty) {
          return const _FriendsEmptyState(
            icon: Icons.person_add_outlined,
            title: 'No friends or chats yet',
            subtitle: 'Go to People to find classmates and connect.',
          );
        }

        // Stream all user docs to match relevant UIDs with no artificial 10-item limit
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, usersSnap) {
            if (usersSnap.connectionState == ConnectionState.waiting) {
              return const _FriendsSkeleton();
            }

            var users = (usersSnap.data?.docs ?? [])
                .where((d) => allRelevantUids.contains(d.id))
                .map((d) => {'uid': d.id, ...d.data()})
                .where((u) {
                  if (query.isEmpty) return true;
                  final name = (u['displayName'] ?? '').toString().toLowerCase();
                  final email = (u['email'] ?? '').toString().toLowerCase();
                  final branch = (u['branch'] ?? '').toString().toLowerCase();
                  return name.contains(query) || email.contains(query) || branch.contains(query);
                })
                .toList();

            // Sort by most recent chat time first, then alphabetical
            users.sort((a, b) {
              final uidA = a['uid'].toString();
              final uidB = b['uid'].toString();
              final metaA = recentChats[chatService.chatIdFor(currentUid, uidA)];
              final metaB = recentChats[chatService.chatIdFor(currentUid, uidB)];
              final timeA = metaA?['lastMessageTime'] as Timestamp?;
              final timeB = metaB?['lastMessageTime'] as Timestamp?;
              if (timeA != null && timeB != null) return timeB.compareTo(timeA);
              if (timeA != null) return -1;
              if (timeB != null) return 1;
              final nameA = (a['displayName'] ?? '').toString().toLowerCase();
              final nameB = (b['displayName'] ?? '').toString().toLowerCase();
              return nameA.compareTo(nameB);
            });

            if (users.isEmpty) {
              return const _FriendsEmptyState(
                icon: Icons.person_search_outlined,
                title: 'No results',
                subtitle: 'Try a different search term.',
              );
            }

            return ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: users.length,
              separatorBuilder: (_, _) => Divider(
                color: U.border,
                height: 1,
                thickness: 0.5,
                indent: 76,
              ),
              itemBuilder: (context, index) {
                final user = users[index];
                final uid = user['uid'].toString();
                final chatMeta = recentChats[chatService.chatIdFor(currentUid, uid)];

                return _FriendRow(
                  user: user,
                  chatMeta: chatMeta,
                  currentUid: currentUid,
                  followService: followService,
                  onTap: () {
                    Navigator.of(context).push(
                      buildForwardRoute(
                        ChatScreen(
                          otherUserId: uid,
                          displayName: UtopiaApp.sanitizeDisplayName(
                            (user['displayName'] ?? 'Friend').toString(),
                          ),
                          email: (user['email'] ?? '').toString(),
                          photoUrl: user['photoUrl']?.toString(),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Friend row ───────────────────────────────────────────────────────────────

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.user,
    required this.chatMeta,
    required this.currentUid,
    required this.followService,
    required this.onTap,
  });

  final Map<String, dynamic> user;
  final Map<String, dynamic>? chatMeta;
  final String currentUid;
  final FollowService followService;
  final VoidCallback onTap;

  String _formatChatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && dt.day != now.day)) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = UtopiaApp.sanitizeDisplayName((user['displayName'] ?? 'Friend').toString());
    final photoUrl = user['photoUrl']?.toString();
    final lastSeen = user['lastSeen'];
    final lastMessageRaw = (chatMeta?['lastMessageRaw'] ?? '').toString();
    final lastMessagePreview = (chatMeta?['lastMessage'] ?? '').toString();
    final lastMessageTime = chatMeta?['lastMessageTime'] as Timestamp?;
    final unreadCount = (chatMeta?['unreadCount_$currentUid'] as num?)?.toInt() ?? 0;
    final bio = (user['bio'] ?? '').toString().trim();
    final isOnline = lastSeen is Timestamp &&
        DateTime.now().difference(lastSeen.toDate()) <= const Duration(minutes: 5);

    final displayMessage = lastMessageRaw.isNotEmpty
        ? lastMessageRaw
        : lastMessagePreview.isNotEmpty
            ? lastMessagePreview
            : bio;

    return InkWell(
      onTap: onTap,
      splashColor: U.primary.withValues(alpha: 0.05),
      highlightColor: U.primary.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Larger Avatar with online dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: U.primary.withValues(alpha: 0.16),
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImageProvider(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? Text(
                          displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: U.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: U.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Name + last message / bio
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 15,
                            fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (user['role'] == 'superuser') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded, color: U.red, size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    displayMessage,
                    style: GoogleFonts.outfit(
                      color: unreadCount > 0 ? U.text : U.sub,
                      fontSize: 12.5,
                      fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Right column: time + unread count badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lastMessageTime != null
                      ? _formatChatTime(lastMessageTime)
                      : isOnline
                          ? 'Online'
                          : _lastSeenLabel(lastSeen),
                  style: GoogleFonts.outfit(
                    color: unreadCount > 0
                        ? U.primary
                        : isOnline
                            ? U.green
                            : U.sub,
                    fontSize: 11,
                    fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          U.primary,
                          U.primary.withValues(alpha: 0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: U.primary.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _lastSeenLabel(dynamic raw) {
    if (raw is! Timestamp) return 'Offline';
    final diff = DateTime.now().difference(raw.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Skeleton / Empty ─────────────────────────────────────────────────────────

class _FriendsSkeleton extends StatelessWidget {
  const _FriendsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 8,
      separatorBuilder: (_, _) =>
          Divider(color: U.border, height: 1, thickness: 0.5, indent: 72),
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: const [
            SkeletonBox(height: 44, width: 44, radius: 22),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 16, width: 140, radius: 8),
                  SizedBox(height: 8),
                  SkeletonBox(height: 12, width: 180, radius: 8),
                ],
              ),
            ),
            SizedBox(width: 12),
            SkeletonBox(height: 12, width: 52, radius: 8),
          ],
        ),
      ),
    );
  }
}

class _FriendsEmptyState extends StatelessWidget {
  const _FriendsEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: U.dim),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
