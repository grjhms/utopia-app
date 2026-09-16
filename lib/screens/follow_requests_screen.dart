import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../main.dart';
import '../services/follow_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/superuser_badge.dart';
import 'user_profile_screen.dart';

class FollowRequestsScreen extends StatelessWidget {
  const FollowRequestsScreen({super.key, required this.currentUid});
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final followService = FollowService();

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
          'Link Requests',
          style: GoogleFonts.outfit(
            color: U.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: followService.pendingRequestsStream(currentUid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _RequestsSkeleton();
          }

          final requests = snap.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_off_rounded, size: 40, color: U.dim),
                    const SizedBox(height: 16),
                    Text(
                      'No link requests',
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'When someone sends you a link request, it will appear here.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: requests.length,
            separatorBuilder: (_, _) =>
                Divider(color: U.border, height: 1, thickness: 0.5, indent: 72),
            itemBuilder: (context, index) {
              final req = requests[index];
              return _RequestRow(request: req, followService: followService);
            },
          );
        },
      ),
    );
  }
}

class _RequestRow extends StatefulWidget {
  const _RequestRow({required this.request, required this.followService});
  final Map<String, dynamic> request;
  final FollowService followService;

  @override
  State<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends State<_RequestRow> {
  bool _accepting = false;
  bool _declining = false;

  @override
  Widget build(BuildContext context) {
    final uid = (widget.request['uid'] ?? '').toString();
    final displayName =
        UtopiaApp.sanitizeDisplayName((widget.request['displayName'] ?? 'Student').toString());
    final email = (widget.request['email'] ?? '').toString();
    final photoUrl = widget.request['photoUrl']?.toString();
    final bio = (widget.request['bio'] ?? '').toString().trim();
    final requestDocId = (widget.request['requestDocId'] ?? '').toString();

    return InkWell(
      onTap: () {
        Navigator.of(context).push(buildForwardRoute(
          UserProfileScreen(
            uid: uid,
            displayName: displayName,
            email: email,
            photoUrl: photoUrl,
          ),
        ));
      },
      splashColor: U.primary.withValues(alpha: 0.05),
      highlightColor: U.primary.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Avatar
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

            // Name + bio
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((widget.request['role'] ?? '') == 'superuser') ...[
                        const SizedBox(width: 4),
                        const SuperUserBadge(size: 14),
                      ],
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
            const SizedBox(width: 10),

            // Accept / Link Up
            _ActionButton(
              label: 'Link Up',
              color: U.primary,
              fg: U.bg,
              loading: _accepting,
              onTap: () async {
                if (_accepting || _declining || requestDocId.isEmpty) return;
                setState(() => _accepting = true);
                try {
                  await widget.followService.acceptRequest(requestDocId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: U.card,
                      content: Text('Linked up with $displayName! 🔗', style: GoogleFonts.outfit(color: U.text)),
                    ));
                  }
                } finally {
                  if (mounted) setState(() => _accepting = false);
                }
              },
            ),
            const SizedBox(width: 8),

            // Decline
            _ActionButton(
              label: 'Decline',
              color: U.card,
              fg: U.text,
              bordered: true,
              loading: _declining,
              onTap: () async {
                if (_accepting || _declining || requestDocId.isEmpty) return;
                setState(() => _declining = true);
                try {
                  await widget.followService.declineRequest(requestDocId);
                } finally {
                  if (mounted) setState(() => _declining = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.fg,
    this.bordered = false,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color fg;
  final bool bordered;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: bordered ? Border.all(color: U.border) : null,
        ),
        child: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: U.primary),
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

class _RequestsSkeleton extends StatelessWidget {
  const _RequestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 6,
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
                  SkeletonBox(height: 14, width: 130, radius: 7),
                  SizedBox(height: 8),
                  SkeletonBox(height: 11, width: 180, radius: 6),
                ],
              ),
            ),
            SizedBox(width: 10),
            SkeletonBox(height: 30, width: 68, radius: 8),
            SizedBox(width: 8),
            SkeletonBox(height: 30, width: 56, radius: 8),
          ],
        ),
      ),
    );
  }
}

/// LinkRequestsScreen alias
typedef LinkRequestsScreen = FollowRequestsScreen;
