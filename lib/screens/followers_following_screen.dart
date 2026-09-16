import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../main.dart';
import '../services/follow_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/superuser_badge.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/wave_count_badge.dart';
import 'user_profile_screen.dart';

/// Screen displaying all mutually linked users for a given [uid].
class LinksScreen extends StatefulWidget {
  const LinksScreen({
    super.key,
    required this.uid,
    required this.displayName,
  });

  final String uid;
  final String displayName;

  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  final FollowService _followService = FollowService();
  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = widget.uid == _currentUid;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOwnProfile ? 'Your Links' : 'Links',
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!isOwnProfile)
              Text(
                widget.displayName,
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: _UserList(
        uid: widget.uid,
        followService: _followService,
        currentUid: _currentUid,
        displayName: widget.displayName,
      ),
    );
  }
}

/// Backward compatibility adapter
class FollowersFollowingScreen extends StatelessWidget {
  const FollowersFollowingScreen({
    super.key,
    required this.uid,
    required this.displayName,
    this.showFollowers = true,
  });

  final String uid;
  final String displayName;
  final bool showFollowers;

  @override
  Widget build(BuildContext context) {
    return LinksScreen(
      uid: uid,
      displayName: displayName,
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({
    required this.uid,
    required this.followService,
    required this.currentUid,
    required this.displayName,
  });

  final String uid;
  final FollowService followService;
  final String currentUid;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: followService.linkedUidsStream(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint("Links Stream Error: ${snap.error}");
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: U.red, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading links',
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
          final isOwn = uid == currentUid;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_off_rounded, size: 44, color: U.dim),
                  const SizedBox(height: 16),
                  Text(
                    'No links yet',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isOwn
                        ? 'Head to People to discover classmates and link up!'
                        : '$displayName hasn\'t linked with anyone yet.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: uids.length,
          separatorBuilder: (_, _) => Divider(
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

  Future<void> _handleLinkTap(LinkStatus status, String name) async {
    if (_loading) return;

    if (status == LinkStatus.linked) {
      final confirm = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: U.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Unlink with $name?',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Both of you will be unlinked and won\'t be able to direct message each other until linked again.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: U.text,
                          side: BorderSide(color: U.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: U.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          'Unlink',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _loading = true);
    try {
      if (status == LinkStatus.linked) {
        await widget.followService.unlink(widget.uid);
      } else if (status == LinkStatus.requested) {
        await widget.followService.cancelRequest(widget.uid);
      } else if (status == LinkStatus.hasIncomingRequest) {
        await widget.followService.acceptIncomingFrom(widget.uid);
      } else {
        await widget.followService.sendLinkRequest(widget.uid);
      }
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
          return const SizedBox.shrink();
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
                            const SuperUserBadge(size: 14),
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
                  StreamBuilder<LinkStatus>(
                    stream: widget.followService.linkStatusStream(widget.currentUid, widget.uid),
                    builder: (context, statusSnap) {
                      final status = statusSnap.data ?? LinkStatus.notLinked;
                      return _InlineLinkButton(
                        status: status,
                        loading: _loading,
                        onTap: () => _handleLinkTap(status, displayName),
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

class _InlineLinkButton extends StatelessWidget {
  const _InlineLinkButton({
    required this.status,
    required this.loading,
    required this.onTap,
  });

  final LinkStatus status;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String label;
    IconData icon;
    Color bg;
    Color fg;
    bool bordered;

    switch (status) {
      case LinkStatus.notLinked:
        label = 'Link Up';
        icon = Icons.link_rounded;
        bg = U.primary;
        fg = U.getContrastColor(U.primary);
        bordered = false;
        break;
      case LinkStatus.requested:
        label = 'Requested';
        icon = Icons.schedule_rounded;
        bg = Colors.transparent;
        fg = U.sub;
        bordered = true;
        break;
      case LinkStatus.hasIncomingRequest:
        label = 'Accept';
        icon = Icons.check_rounded;
        bg = U.primary;
        fg = U.getContrastColor(U.primary);
        bordered = false;
        break;
      case LinkStatus.linked:
        label = 'Linked';
        icon = Icons.link_rounded;
        bg = Colors.transparent;
        fg = U.text;
        bordered = true;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
