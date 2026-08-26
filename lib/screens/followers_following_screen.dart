import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../main.dart';
import '../services/follow_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/wave_count_badge.dart';
import 'user_profile_screen.dart';

class FollowersFollowingScreen extends StatefulWidget {
  const FollowersFollowingScreen({
    super.key,
    required this.uid,
    required this.displayName,
    required this.showFollowers,
  });

  final String uid;
  final String displayName;
  final bool showFollowers;

  @override
  State<FollowersFollowingScreen> createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FollowService _followService = FollowService();
  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.showFollowers ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.displayName,
          style: GoogleFonts.outfit(
            color: U.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: U.primary,
          labelColor: U.primary,
          unselectedLabelColor: U.dim,
          labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Followers'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UserList(
            uid: widget.uid,
            isFollowers: true,
            followService: _followService,
            currentUid: _currentUid,
          ),
          _UserList(
            uid: widget.uid,
            isFollowers: false,
            followService: _followService,
            currentUid: _currentUid,
          ),
        ],
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({
    required this.uid,
    required this.isFollowers,
    required this.followService,
    required this.currentUid,
  });

  final String uid;
  final bool isFollowers;
  final FollowService followService;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final stream = isFollowers
        ? followService.followersUidsStream(uid)
        : followService.followingUidsStream(uid);

    return StreamBuilder<List<String>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint("Followers/Following Stream Error: ${snap.error}");
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: U.red, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading list',
                    style: GoogleFonts.outfit(color: U.text, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snap.error.toString(),
                    style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: UtopiaLoader(scale: 0.8));
        }

        final uids = snap.data ?? [];

        if (uids.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 40, color: U.dim),
                  const SizedBox(height: 16),
                  Text(
                    isFollowers ? 'No followers yet' : 'Not following anyone yet',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: uids.length,
          separatorBuilder: (_, __) => Divider(
            color: U.border,
            height: 1,
            thickness: 0.5,
            indent: 72,
          ),
          itemBuilder: (context, index) {
            final targetUid = uids[index];
            return _UserRow(
              uid: targetUid,
              currentUid: currentUid,
              followService: followService,
            );
          },
        );
      },
    );
  }
}

class _UserRow extends StatefulWidget {
  const _UserRow({
    required this.uid,
    required this.currentUid,
    required this.followService,
  });

  final String uid;
  final String currentUid;
  final FollowService followService;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _loading = false;

  Future<void> _toggleFollow(FollowStatus status) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.followService.toggleFollow(widget.uid);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint("User Row Load Error: ${snap.error}");
          return SizedBox(
            height: 68,
            child: Center(
              child: Text(
                'Error loading user: ${snap.error}',
                style: GoogleFonts.outfit(color: U.red, fontSize: 11),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const SizedBox(
            height: 68,
            child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))),
          );
        }

        final data = snap.data?.data() ?? {};
        final displayName = UtopiaApp.sanitizeDisplayName((data['displayName'] ?? 'Student').toString());
        final email = (data['email'] ?? '').toString();
        final photoUrl = data['photoUrl']?.toString();
        final bio = (data['bio'] ?? '').toString().trim();
        final isSuper = data['role'] == 'superuser';
        final wavesCount = (data['wavesReceivedCount'] as num?)?.toInt() ?? 0;

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              buildForwardRoute(
                UserProfileScreen(
                  uid: widget.uid,
                  displayName: displayName,
                  email: email,
                  photoUrl: photoUrl,
                ),
              ),
            );
          },
          splashColor: U.primary.withValues(alpha: 0.05),
          highlightColor: U.primary.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: U.primary.withValues(alpha: 0.16),
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImageProvider(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? Text(
                          displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isSuper) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded, color: U.red, size: 14),
                          ],
                          const SizedBox(width: 6),
                          WaveCountBadge(count: wavesCount, compact: true),
                        ],
                      ),
                      if (bio.isNotEmpty)
                        Text(
                          bio,
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (widget.uid != widget.currentUid) ...[
                  const SizedBox(width: 10),
                  StreamBuilder<FollowStatus>(
                    stream: widget.followService.followStatusStream(widget.currentUid, widget.uid),
                    builder: (context, statusSnap) {
                      final status = statusSnap.data ?? FollowStatus.notFollowing;
                      return _InlineFollowButton(
                        status: status,
                        loading: _loading,
                        onTap: () => _toggleFollow(status),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineFollowButton extends StatelessWidget {
  const _InlineFollowButton({
    required this.status,
    required this.loading,
    required this.onTap,
  });

  final FollowStatus status;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;
    bool bordered;

    switch (status) {
      case FollowStatus.notFollowing:
        label = 'Follow';
        bg = U.primary;
        fg = U.bg;
        bordered = false;
        break;
      case FollowStatus.requested:
        label = 'Requested';
        bg = Colors.transparent;
        fg = U.sub;
        bordered = true;
        break;
      case FollowStatus.following:
        label = 'Following';
        bg = Colors.transparent;
        fg = U.text;
        bordered = true;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: bordered ? Border.all(color: U.border) : null,
        ),
        child: loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : Text(
                label,
                style: GoogleFonts.outfit(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
