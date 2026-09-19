import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/project_model.dart';
import '../services/project_service.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/utopia_snackbar.dart';
import 'create_project_screen.dart';
import 'projects_feed_screen.dart';
import 'user_profile_screen.dart';

/// Full-detail screen for a Project Showcase entry.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final ProjectModel? initialProject;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.initialProject,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> with SingleTickerProviderStateMixin {
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();

  late bool _isLiked;
  late int _likesCount;
  bool _isLiking = false;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnimation;

  @override
  void initState() {
    super.initState();
    final uid = ProjectService().currentUid;
    _isLiked = widget.initialProject?.isLikedBy(uid) ?? false;
    _likesCount = widget.initialProject?.likesCount ?? 0;

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
  void dispose() {
    _pageController.dispose();
    _heartAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleLikeToggle(String projectId) async {
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
      final nowLiked = await ProjectService().toggleLike(projectId);
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

  Future<void> _launchExternalUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    try {
      final uri = Uri.parse(cleanUrl.startsWith('http') ? cleanUrl : 'https://$cleanUrl');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          showUtopiaSnackBar(context, message: 'Could not open URL: $url', tone: UtopiaSnackBarTone.error);
        }
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(context, message: 'Invalid URL: $url', tone: UtopiaSnackBarTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProjectModel?>(
      stream: ProjectService().getProjectStream(widget.projectId),
      initialData: widget.initialProject,
      builder: (context, snapshot) {
        final project = snapshot.data;

        if (project == null) {
          return Scaffold(
            backgroundColor: U.bg,
            appBar: AppBar(backgroundColor: U.bg),
            body: Center(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? CircularProgressIndicator(color: U.primary)
                  : Text(
                      'Project not found or deleted.',
                      style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 14),
                    ),
            ),
          );
        }

        final uid = ProjectService().currentUid;
        final isOwner = project.isOwner(uid);
        final allImages = [
          if (project.coverImage.isNotEmpty) project.coverImage,
          ...project.galleryImages,
        ];

        return Scaffold(
          backgroundColor: U.bg,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── 1. Hero Image / Gallery Carousel App Bar ────────────
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: U.bg,
                elevation: 0,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: [
                  if (isOwner)
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CreateProjectScreen(existingProject: project),
                          ),
                        );
                      },
                    ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (allImages.isNotEmpty)
                        PageView.builder(
                          controller: _pageController,
                          itemCount: allImages.length,
                          onPageChanged: (idx) => setState(() => _currentImageIndex = idx),
                          itemBuilder: (context, index) {
                            return CachedNetworkImage(
                              imageUrl: allImages[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(child: CircularProgressIndicator(color: U.primary)),
                              errorWidget: (context, url, error) => const Center(
                                child: Icon(Icons.broken_image_rounded, size: 40),
                              ),
                            );
                          },
                        )
                      else
                        Container(
                          color: U.surfaceContainerHighest,
                          child: Icon(Icons.image_outlined, size: 48, color: U.sub),
                        ),

                      // Bottom Gradient Overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 90,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                U.bg,
                                U.bg.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Carousel Page Dot Indicator
                      if (allImages.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(allImages.length, (i) {
                              final isCurrent = i == _currentImageIndex;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: isCurrent ? 20 : 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: isCurrent ? U.primary : Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── 2. Project Details Content Body ─────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category, Status & Date Row + Like Action
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Category Chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: U.primary.withValues(alpha: 0.12),
                              borderRadius: M3Shapes.fullRadius,
                              border: Border.all(color: U.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getCategoryIcon(project.category), size: 14, color: U.primary),
                                const SizedBox(width: 5),
                                Text(
                                  project.category.label,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: U.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _getStatusColor(project.status).withValues(alpha: 0.12),
                              borderRadius: M3Shapes.fullRadius,
                              border: Border.all(color: _getStatusColor(project.status).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(project.status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  project.status.label,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _getStatusColor(project.status),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Timeline / Date Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: U.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: M3Shapes.fullRadius,
                              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 12, color: U.sub),
                                const SizedBox(width: 5),
                                Text(
                                  project.formattedTimeline,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: U.sub,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Like Button
                          GestureDetector(
                            onTap: () => _handleLikeToggle(project.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isLiked ? U.red.withValues(alpha: 0.12) : U.card,
                                borderRadius: M3Shapes.fullRadius,
                                border: Border.all(
                                  color: _isLiked ? U.red.withValues(alpha: 0.3) : U.outlineVariant.withValues(alpha: 0.4),
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
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_likesCount',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 13,
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
                      const SizedBox(height: 14),

                      // Title
                      Text(
                        project.title,
                        style: GoogleFonts.robotoFlex(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: U.text,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Tagline
                      Text(
                        project.tagline,
                        style: GoogleFonts.robotoFlex(
                          fontSize: 15,
                          color: U.sub,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── 3. Tech Stack Tags ─────────────────────────
                      if (project.techStack.isNotEmpty) ...[
                        Text(
                          'TECH STACK',
                          style: GoogleFonts.robotoFlex(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: U.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: project.techStack.map((tag) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProjectsFeedScreen(initialTechTag: tag),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: U.card,
                                  borderRadius: M3Shapes.fullRadius,
                                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  tag,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: U.text,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── 4. Interactive Links Buttons ───────────────
                      if (project.links.isNotEmpty) ...[
                        Text(
                          'PROJECT LINKS',
                          style: GoogleFonts.robotoFlex(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: U.primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (project.links.github != null && project.links.github!.isNotEmpty)
                              _buildPillAction(
                                icon: Icons.code_rounded,
                                label: 'GitHub Repo',
                                color: U.primary,
                                onTap: () => _launchExternalUrl(project.links.github!),
                              ),
                            if (project.links.liveDemo != null && project.links.liveDemo!.isNotEmpty)
                              _buildPillAction(
                                icon: Icons.launch_rounded,
                                label: 'Live Demo',
                                color: U.teal,
                                onTap: () => _launchExternalUrl(project.links.liveDemo!),
                              ),
                            if (project.links.video != null && project.links.video!.isNotEmpty)
                              _buildPillAction(
                                icon: Icons.play_circle_fill_rounded,
                                label: 'Watch Video',
                                color: U.peach,
                                onTap: () => _launchExternalUrl(project.links.video!),
                              ),
                            for (final cl in project.links.other)
                              _buildPillAction(
                                icon: Icons.link_rounded,
                                label: cl.label,
                                color: U.lavender,
                                onTap: () => _launchExternalUrl(cl.url),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── 5. Contributors Section ────────────────────
                      Text(
                        'TEAM & CONTRIBUTORS (${1 + project.contributors.length})',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: U.primary,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Lead / Creator Card
                      _buildContributorCard(
                        userId: project.ownerId,
                        name: project.ownerName,
                        photoUrl: project.ownerPhotoUrl,
                        branch: project.ownerBranch,
                        role: 'Project Creator & Lead',
                        isOwner: true,
                      ),
                      const SizedBox(height: 8),

                      // Additional Teammates
                      ...project.contributors.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildContributorCard(
                              userId: c.userId,
                              name: c.name,
                              photoUrl: c.photoUrl,
                              branch: c.branch,
                              role: c.role ?? 'Contributor',
                              isOwner: false,
                            ),
                          )),
                      const SizedBox(height: 24),

                      // ── 6. Markdown Description ───────────────────
                      Text(
                        'ABOUT THIS PROJECT',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: U.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: M3Shapes.largeRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: MarkdownBody(
                          data: project.description,
                          onTapLink: (text, href, title) {
                            if (href != null) _launchExternalUrl(href);
                          },
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5, height: 1.55),
                            h1: GoogleFonts.robotoFlex(color: U.text, fontSize: 21, fontWeight: FontWeight.w800),
                            h2: GoogleFonts.robotoFlex(color: U.text, fontSize: 18, fontWeight: FontWeight.w700),
                            h3: GoogleFonts.robotoFlex(color: U.text, fontSize: 15.5, fontWeight: FontWeight.w600),
                            code: GoogleFonts.jetBrainsMono(
                              backgroundColor: U.surfaceContainerHighest,
                              color: U.primary,
                              fontSize: 12.5,
                            ),
                            blockquote: GoogleFonts.robotoFlex(
                              color: U.sub,
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              color: U.surfaceContainerHighest.withValues(alpha: 0.5),
                              border: Border(left: BorderSide(color: U.primary, width: 3)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPillAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: M3Shapes.fullRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: M3Shapes.fullRadius,
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.robotoFlex(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContributorCard({
    required String userId,
    required String name,
    required String? photoUrl,
    required String? branch,
    required String role,
    required bool isOwner,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              uid: userId,
              displayName: name,
              photoUrl: photoUrl,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: M3Shapes.mediumRadius,
          border: Border.all(
            color: isOwner ? U.primary.withValues(alpha: 0.3) : U.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isOwner ? U.primary.withValues(alpha: 0.15) : U.peach.withValues(alpha: 0.15),
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: photoUrl == null || photoUrl.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isOwner ? U.primary : U.peach,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: U.text,
                    ),
                  ),
                  if (branch != null && branch.isNotEmpty)
                    Text(
                      branch,
                      style: GoogleFonts.robotoFlex(fontSize: 11.5, color: U.sub),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: isOwner ? U.primary.withValues(alpha: 0.12) : U.surfaceContainerHighest,
                borderRadius: M3Shapes.fullRadius,
              ),
              child: Text(
                role,
                style: GoogleFonts.robotoFlex(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isOwner ? U.primary : U.sub,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: U.dim),
          ],
        ),
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
