import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/follow_service.dart';
import '../services/people_interaction_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/instagram_badge.dart';
import '../widgets/thought_cloud_badge.dart';
import 'chat_screen.dart';
import 'followers_following_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.uid,
    required this.displayName,
    this.email = '',
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final FollowService _followService = FollowService();
  bool _actionLoading = false;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isOwnProfile => _currentUid == widget.uid;

  Future<void> _handleFollowToggle(FollowStatus status) async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await _followService.toggleFollow(widget.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: U.red,
          content: Text('Action failed', style: GoogleFonts.outfit(color: U.bg)),
        ));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _openChat(Map<String, dynamic> userData) async {
    // verify mutual follow
    final canChat = await _followService.canChat(_currentUid, widget.uid);
    if (!mounted) return;
    if (!canChat) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: U.card,
        content: Text(
          'You can only message people you follow or who follow you.',
          style: GoogleFonts.outfit(color: U.text, fontSize: 13),
        ),
      ));
      return;
    }
    Navigator.of(context).push(buildForwardRoute(ChatScreen(
      otherUserId: widget.uid,
      displayName: widget.displayName,
      email: widget.email,
      photoUrl: widget.photoUrl,
    )));
  }

  void _navigateToFollows(bool showFollowers, String name) {
    Navigator.of(context).push(
      buildForwardRoute(
        FollowersFollowingScreen(
          uid: widget.uid,
          displayName: name,
          showFollowers: showFollowers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() ?? {};
          final displayName =
              UtopiaApp.sanitizeDisplayName((userData['displayName'] ?? widget.displayName).toString());
          final photoUrl =
              (userData['photoUrl'] ?? widget.photoUrl)?.toString();
          final bio = (userData['bio'] ?? '').toString().trim();
          final university =
              (userData['selectedUniversityId'] ?? '').toString();
          final branch = (userData['branch'] ?? '').toString().trim();
          final instagramId = (userData['instagramId'] ?? '').toString().trim();

          CampusVibe? vibe;
          if (userData['vibe'] != null) {
            final parsed = CampusVibe.fromMap(widget.uid, userData);
            if ((parsed.text.isNotEmpty || (parsed.mediaUrl != null && parsed.mediaUrl!.isNotEmpty)) && !parsed.isExpired) {
              vibe = parsed;
            }
          }

          return CustomScrollView(
            slivers: [
                      // ── App bar ──────────────────────────────────────────
                      SliverAppBar(
                        backgroundColor: U.bg,
                        elevation: 0,
                        surfaceTintColor: Colors.transparent,
                        pinned: true,
                        leading: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: U.text,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        title: Text(
                          displayName,
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header ──────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Avatar
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          if (photoUrl != null && photoUrl.isNotEmpty) {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => Scaffold(
                                                  backgroundColor: Colors.black,
                                                  appBar: AppBar(
                                                    backgroundColor: Colors.black,
                                                    iconTheme: const IconThemeData(color: Colors.white),
                                                  ),
                                                  body: Center(
                                                    child: InteractiveViewer(
                                                      child: CachedNetworkImage(imageUrl: photoUrl),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: CircleAvatar(
                                          radius: 44,
                                          backgroundColor:
                                              U.primary.withValues(alpha: 0.15),
                                          backgroundImage:
                                              photoUrl != null && photoUrl.isNotEmpty
                                                  ? CachedNetworkImageProvider(photoUrl)
                                                  : null,
                                          child: photoUrl == null || photoUrl.isEmpty
                                              ? Text(
                                                  displayName.isEmpty
                                                      ? 'U'
                                                      : displayName[0].toUpperCase(),
                                                  style: GoogleFonts.outfit(
                                                    color: U.primary,
                                                    fontSize: 32,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                      if (vibe != null)
                                        Positioned(
                                          top: -6,
                                          right: -8,
                                          child: ThoughtCloudBadge(
                                            vibe: vibe,
                                            avatarRadius: 44,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 24),

                                  // Stats row
                                  Expanded(
                                    child: StreamBuilder<int>(
                                      stream: _followService
                                          .followersCountStream(widget.uid),
                                      builder: (context, followersSnap) {
                                        return StreamBuilder<int>(
                                          stream: _followService
                                              .followingCountStream(widget.uid),
                                          builder: (context, followingSnap) {
                                            final wavesCount = (userData['wavesReceivedCount'] as num?)?.toInt() ?? 0;
                                            return StreamBuilder<FollowStatus>(
                                              stream: _followService.followStatusStream(_currentUid, widget.uid),
                                              builder: (context, statusSnap) {
                                                return Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.spaceAround,
                                                  children: [
                                                    _StatPill(
                                                      count: followersSnap.data ?? 0,
                                                      label: 'Followers',
                                                      onTap: () => _navigateToFollows(true, displayName),
                                                    ),
                                                    _StatPill(
                                                      count: followingSnap.data ?? 0,
                                                      label: 'Following',
                                                      onTap: () => _navigateToFollows(false, displayName),
                                                    ),
                                                    _StatPill(
                                                      count: wavesCount,
                                                      label: 'Waves',
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── Name + bio ──────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                       if (userData['role'] == 'superuser') ...[
                                         const SizedBox(width: 4),
                                         Icon(Icons.verified_rounded, color: U.red, size: 14),
                                       ],
                                    ],
                                  ),
                                  if (university.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      university,
                                      style: GoogleFonts.outfit(
                                        color: U.sub,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                   if (bio.isNotEmpty) ...[
                                     const SizedBox(height: 8),
                                     Text(
                                       bio,
                                       style: GoogleFonts.outfit(
                                         color: U.text,
                                         fontSize: 13,
                                         height: 1.5,
                                       ),
                                     ),
                                   ],
                                   if (branch.isNotEmpty || instagramId.isNotEmpty) ...[
                                     const SizedBox(height: 10),
                                     Wrap(
                                       spacing: 8,
                                       runSpacing: 6,
                                       crossAxisAlignment: WrapCrossAlignment.center,
                                       children: [
                                         if (branch.isNotEmpty)
                                           Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                             decoration: BoxDecoration(
                                               color: U.primary.withValues(alpha: 0.12),
                                               borderRadius: BorderRadius.circular(16),
                                               border: Border.all(
                                                 color: U.primary.withValues(alpha: 0.25),
                                                 width: 0.8,
                                               ),
                                             ),
                                             child: Row(
                                               mainAxisSize: MainAxisSize.min,
                                               children: [
                                                 Icon(Icons.school_rounded, size: 12, color: U.primary),
                                                 const SizedBox(width: 4),
                                                 Text(
                                                   branch,
                                                   style: GoogleFonts.outfit(
                                                     color: U.primary,
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.w600,
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           ),
                                         if (instagramId.isNotEmpty)
                                           InstagramBadge(handle: instagramId),
                                       ],
                                     ),
                                   ],

                                   // ── Theme badge ──────────────────────────────
                                   () {
                                     final showTheme = (userData['showThemeOnProfile'] as bool?) ?? true;
                                     final themeKey = (userData['themeAccent'] ?? '').toString().trim();
                                     if (!showTheme || themeKey.isEmpty) return const SizedBox.shrink();
                                     final userTheme = U.themeForKey(themeKey);
                                     return Padding(
                                       padding: const EdgeInsets.only(top: 10),
                                       child: Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                         decoration: BoxDecoration(
                                           color: userTheme.primary.withValues(alpha: 0.10),
                                           borderRadius: BorderRadius.circular(16),
                                           border: Border.all(
                                             color: userTheme.primary.withValues(alpha: 0.30),
                                             width: 0.8,
                                           ),
                                         ),
                                         child: Row(
                                           mainAxisSize: MainAxisSize.min,
                                           children: [
                                             // Dual-tone swatch
                                             Container(
                                               width: 16,
                                               height: 16,
                                               decoration: BoxDecoration(
                                                 shape: BoxShape.circle,
                                                 color: userTheme.bg,
                                                 border: Border.all(
                                                   color: userTheme.primary.withValues(alpha: 0.5),
                                                   width: 1,
                                                 ),
                                               ),
                                               child: Center(
                                                 child: Container(
                                                   width: 8,
                                                   height: 8,
                                                   decoration: BoxDecoration(
                                                     shape: BoxShape.circle,
                                                     color: userTheme.primary,
                                                   ),
                                                 ),
                                               ),
                                             ),
                                             const SizedBox(width: 6),
                                             Text(
                                               userTheme.label,
                                               style: GoogleFonts.outfit(
                                                 color: userTheme.primary,
                                                 fontSize: 11,
                                                 fontWeight: FontWeight.w600,
                                               ),
                                             ),
                                             const SizedBox(width: 4),
                                             Icon(
                                               userTheme.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                               size: 11,
                                               color: userTheme.primary.withValues(alpha: 0.7),
                                             ),
                                           ],
                                         ),
                                       ),
                                     );
                                   }(),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ── Action buttons ──────────────────────────────
                            if (!_isOwnProfile)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                                child: StreamBuilder<FollowStatus>(
                                  stream: _followService.followStatusStream(
                                      _currentUid, widget.uid),
                                  builder: (context, statusSnap) {
                                    final status = statusSnap.data ??
                                        FollowStatus.notFollowing;

                                    return StreamBuilder<bool>(
                                      stream: _followService.canChatStream(
                                          _currentUid, widget.uid),
                                      builder: (context, chatSnap) {
                                        final canChat =
                                            chatSnap.data ?? false;

                                        return Row(
                                          children: [
                                            Expanded(
                                              child: _FollowButton(
                                                status: status,
                                                loading: _actionLoading,
                                                onPressed: () =>
                                                    _handleFollowToggle(
                                                        status),
                                              ),
                                            ),
                                            if (canChat) ...[
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () =>
                                                      _openChat(userData),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: U.text,
                                                    side: BorderSide(
                                                        color: U.border),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            vertical: 10),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  child: Text(
                                                    'Message',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),

                            const SizedBox(height: 24),



                            Divider(
                              color: U.border,
                              height: 1,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ],
                  );
        },
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({required this.count, required this.label, this.onTap});
  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatCount(count),
            style: GoogleFonts.outfit(
              color: U.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: U.sub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.status,
    required this.loading,
    required this.onPressed,
  });

  final FollowStatus status;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;
    bool outlined = false;

    switch (status) {
      case FollowStatus.notFollowing:
        label = 'Follow';
        bg = U.primary;
        fg = U.bg;
        break;
      case FollowStatus.requested:
        label = 'Requested';
        bg = U.card;
        fg = U.text;
        outlined = true;
        break;
      case FollowStatus.following:
        label = 'Following';
        bg = U.card;
        fg = U.text;
        outlined = true;
        break;
    }

    if (loading) {
      return Container(
        height: 38,
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: U.border),
        ),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: U.primary,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: outlined ? U.border : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: outlined ? fg : fg,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}


