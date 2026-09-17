import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/project_model.dart';
import '../services/project_service.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/utopia_snackbar.dart';

/// Material 3 Expressive Project Card for the Showcase Feed & Profiles.
class ProjectCard extends StatefulWidget {
  final ProjectModel project;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool compact;

  const ProjectCard({
    super.key,
    required this.project,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.compact = false,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> with SingleTickerProviderStateMixin {
  late bool _isLiked;
  late int _likesCount;
  bool _isLiking = false;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnimation;

  @override
  void initState() {
    super.initState();
    final uid = ProjectService().currentUid;
    _isLiked = widget.project.isLikedBy(uid);
    _likesCount = widget.project.likesCount;

    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _heartScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.bounceOut)), weight: 50),
    ]).animate(_heartAnimController);
  }

  @override
  void didUpdateWidget(covariant ProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.project.likesCount != widget.project.likesCount ||
        oldWidget.project.likedByUserIds != widget.project.likedByUserIds) {
      final uid = ProjectService().currentUid;
      _isLiked = widget.project.isLikedBy(uid);
      _likesCount = widget.project.likesCount;
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleLikeToggle() async {
    if (_isLiking) return;
    _isLiking = true;
    HapticFeedback.selectionClick();

    final prevLiked = _isLiked;
    final prevCount = _likesCount;

    setState(() {
      _isLiked = !_isLiked;
      _likesCount = _isLiked ? _likesCount + 1 : (_likesCount > 0 ? _likesCount - 1 : 0);
    });

    if (_isLiked) {
      _heartAnimController.forward(from: 0.0);
    }

    try {
      final nowLiked = await ProjectService().toggleLike(widget.project.id);
      if (mounted) {
        setState(() => _isLiked = nowLiked);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLiked = prevLiked;
          _likesCount = prevCount;
        });
      }
    } finally {
      _isLiking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = appThemeNotifier.value;
    final isDark = theme.isDark;
    final p = widget.project;
    final uid = ProjectService().currentUid;
    final isOwner = p.isOwner(uid);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: M3Shapes.cardRadius,
          border: Border.all(
            color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Hero Cover Visual ──────────────────────────────────
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: widget.compact ? 2.2 : 1.85,
                  child: Container(
                    color: U.surfaceContainerHighest,
                    child: p.coverImage.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: p.coverImage,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: U.primary),
                              ),
                            ),
                            errorWidget: (context, url, error) => Center(
                              child: Icon(Icons.code_rounded, size: 40, color: U.sub),
                            ),
                          )
                        : Center(
                            child: Icon(Icons.palette_outlined, size: 40, color: U.sub),
                          ),
                  ),
                ),

                // Top Gradient for badge contrast
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 60,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Top Left: Category Badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: M3Shapes.fullRadius,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getCategoryIcon(p.category),
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          p.category.label,
                          style: GoogleFonts.robotoFlex(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Right: Status Badge or More Options
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: _getStatusColor(p.status).withValues(alpha: 0.95),
                          borderRadius: M3Shapes.fullRadius,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: U.getContrastColor(_getStatusColor(p.status)),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              p.status.label,
                              style: GoogleFonts.robotoFlex(
                                color: U.getContrastColor(_getStatusColor(p.status)),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showOwnerActions(context),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
                            ),
                            child: const Icon(Icons.more_vert_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // ── 2. Card Content & Details ─────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: U.text,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Tagline
                  Text(
                    p.tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 13,
                      color: U.sub,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tech Stack Chips
                  if (p.techStack.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...p.techStack.take(3).map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: U.surfaceContainerHighest,
                                borderRadius: M3Shapes.smallRadius,
                                border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                tag,
                                style: GoogleFonts.robotoFlex(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: U.text,
                                ),
                              ),
                            )),
                        if (p.techStack.length > 3)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: U.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: M3Shapes.smallRadius,
                            ),
                            child: Text(
                              '+${p.techStack.length - 3}',
                              style: GoogleFonts.robotoFlex(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: U.sub,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Divider
                  Container(
                    height: 0.8,
                    color: U.outlineVariant.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),

                  // ── 3. Bottom Row: Stacked Avatars, Date & Like Button ────
                  Row(
                    children: [
                      // Stacked / Overlapping Avatars
                      Expanded(
                        child: _buildAvatarStack(p),
                      ),

                      // Date / Relative Time Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: M3Shapes.fullRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 12, color: U.sub),
                            const SizedBox(width: 4),
                            Text(
                              p.relativeTime,
                              style: GoogleFonts.robotoFlex(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: U.sub,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Like Button with Heart scale animation
                      GestureDetector(
                        onTap: _handleLikeToggle,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isLiked
                                ? U.red.withValues(alpha: 0.12)
                                : U.surfaceContainerHighest.withValues(alpha: 0.6),
                            borderRadius: M3Shapes.fullRadius,
                            border: Border.all(
                              color: _isLiked
                                  ? U.red.withValues(alpha: 0.3)
                                  : U.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ScaleTransition(
                                scale: _heartScaleAnimation,
                                child: Icon(
                                  _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  size: 16,
                                  color: _isLiked ? U.red : U.sub,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$_likesCount',
                                style: GoogleFonts.robotoFlex(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _isLiked ? U.red : U.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Overlapping Contributor Avatars ──

  Widget _buildAvatarStack(ProjectModel p) {
    // Build list of unique avatars starting with owner
    final avatarList = <_AvatarItem>[
      _AvatarItem(
        name: p.ownerName,
        photoUrl: p.ownerPhotoUrl,
        isOwner: true,
      ),
    ];

    for (final c in p.contributors) {
      if (avatarList.any((a) => a.name == c.name && a.photoUrl == c.photoUrl)) continue;
      avatarList.add(_AvatarItem(
        name: c.name,
        photoUrl: c.photoUrl,
        isOwner: false,
      ));
    }

    final displayAvatars = avatarList.take(4).toList();
    final remainingCount = avatarList.length - displayAvatars.length;

    return Row(
      children: [
        SizedBox(
          height: 28,
          width: (displayAvatars.length * 20.0) + (remainingCount > 0 ? 28 : 8),
          child: Stack(
            children: [
              for (int i = 0; i < displayAvatars.length; i++)
                Positioned(
                  left: i * 18.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: U.card, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: displayAvatars[i].isOwner ? U.primary : U.peach,
                      backgroundImage: displayAvatars[i].photoUrl != null && displayAvatars[i].photoUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(displayAvatars[i].photoUrl!)
                          : null,
                      child: displayAvatars[i].photoUrl == null || displayAvatars[i].photoUrl!.isEmpty
                          ? Text(
                              displayAvatars[i].name.isNotEmpty
                                  ? displayAvatars[i].name[0].toUpperCase()
                                  : 'U',
                              style: GoogleFonts.robotoFlex(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: U.getContrastColor(displayAvatars[i].isOwner ? U.primary : U.peach),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              if (remainingCount > 0)
                Positioned(
                  left: displayAvatars.length * 18.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: U.card, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: U.surfaceContainerHighest,
                      child: Text(
                        '+$remainingCount',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: U.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            p.ownerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.robotoFlex(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: U.sub,
            ),
          ),
        ),
      ],
    );
  }

  void _showOwnerActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: U.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: U.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.project.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.robotoFlex(fontSize: 16, fontWeight: FontWeight.w700, color: U.text),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: U.primary),
              title: Text('Edit Project', style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w600, color: U.text)),
              onTap: () {
                Navigator.of(ctx).pop();
                widget.onEdit?.call();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: U.red),
              title: Text('Delete Project', style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w600, color: U.red)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: M3Shapes.extraLargeRadius),
        title: Text(
          'Delete Project?',
          style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w800, color: U.text),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.project.title}" from Showcase? This action cannot be undone.',
          style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.robotoFlex(color: U.sub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: U.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ProjectService().deleteProject(widget.project.id);
                if (context.mounted) {
                  showUtopiaSnackBar(context, message: 'Project deleted', tone: UtopiaSnackBarTone.info);
                  widget.onDelete?.call();
                }
              } catch (e) {
                if (context.mounted) {
                  showUtopiaSnackBar(context, message: 'Error deleting: $e', tone: UtopiaSnackBarTone.error);
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(ProjectCategory cat) {
    switch (cat) {
      case ProjectCategory.app: return Icons.phone_android_rounded;
      case ProjectCategory.hardware: return Icons.memory_rounded;
      case ProjectCategory.research: return Icons.science_outlined;
      case ProjectCategory.design: return Icons.palette_outlined;
      case ProjectCategory.hackathon: return Icons.emoji_events_outlined;
      case ProjectCategory.other: return Icons.auto_awesome_outlined;
    }
  }

  Color _getStatusColor(ProjectStatus st) {
    switch (st) {
      case ProjectStatus.inProgress: return U.peach;
      case ProjectStatus.completed: return U.green;
      case ProjectStatus.lookingForTeammates: return U.teal;
    }
  }
}

class _AvatarItem {
  final String name;
  final String? photoUrl;
  final bool isOwner;

  _AvatarItem({required this.name, this.photoUrl, required this.isOwner});
}
