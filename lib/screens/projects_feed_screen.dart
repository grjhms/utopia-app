import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/project_model.dart';
import '../services/project_service.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/app_motion.dart';
import '../widgets/project_card.dart';
import 'create_project_screen.dart';
import 'project_detail_screen.dart';

/// Main Showcase Feed Screen where campus projects are discovered, filtered, and liked.
class ProjectsFeedScreen extends StatefulWidget {
  final ProjectCategory? initialCategory;
  final String? initialTechTag;

  const ProjectsFeedScreen({
    super.key,
    this.initialCategory,
    this.initialTechTag,
  });

  @override
  State<ProjectsFeedScreen> createState() => _ProjectsFeedScreenState();
}

class _ProjectsFeedScreenState extends State<ProjectsFeedScreen> {
  ProjectCategory? _selectedCategory;
  ProjectStatus? _selectedStatus;
  String? _selectedTechTag;
  bool _sortByMostLiked = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _selectedTechTag = widget.initialTechTag;

    _searchFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isSearchFocused = _searchFocusNode.hasFocus;
        });
      }
    });

    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedStatus = null;
      _selectedTechTag = null;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  bool get _hasActiveFilters =>
      _selectedCategory != null ||
      _selectedStatus != null ||
      _selectedTechTag != null ||
      _searchQuery.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: Navigator.canPop(context) ? 0 : 16,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Project Showcase',
              style: GoogleFonts.robotoFlex(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: U.text,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: U.primary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Sort Toggle (Recent vs Most Liked)
          IconButton(
            tooltip: _sortByMostLiked ? 'Sorted by Most Liked' : 'Sorted by Recent',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _sortByMostLiked ? Icons.favorite_rounded : Icons.schedule_rounded,
              color: _sortByMostLiked ? U.red : U.text,
              size: 20,
            ),
            onPressed: () {
              setState(() => _sortByMostLiked = !_sortByMostLiked);
            },
          ),
          const SizedBox(width: 4),
          // Post Project Action
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
                );
              },
              icon: Icon(Icons.add_rounded, size: 16, color: U.getContrastColor(U.primary)),
              label: Text(
                'Post',
                style: GoogleFonts.robotoFlex(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: U.getContrastColor(U.primary),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: U.primary,
                foregroundColor: U.getContrastColor(U.primary),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _searchFocusNode.unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              // Search & Filter Header
              _buildSearchAndFilterHeader(),

              // Stream of Projects
              Expanded(
                child: StreamBuilder<List<ProjectModel>>(
                  stream: ProjectService().getProjectsStream(
                    category: _selectedCategory,
                    status: _selectedStatus,
                    techStackTag: _selectedTechTag,
                    sortByMostLiked: _sortByMostLiked,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(color: U.primary),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Error loading projects: ${snapshot.error}',
                            style: GoogleFonts.robotoFlex(color: U.red, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final projects = snapshot.data ?? [];

                    // Apply client-side text search
                    final filtered = projects.where((p) {
                      if (_searchQuery.isEmpty) return true;
                      final t = p.title.toLowerCase();
                      final tag = p.tagline.toLowerCase();
                      final d = p.description.toLowerCase();
                      final owner = p.ownerName.toLowerCase();
                      final tech = p.techStack.map((s) => s.toLowerCase()).join(' ');

                      return t.contains(_searchQuery) ||
                          tag.contains(_searchQuery) ||
                          d.contains(_searchQuery) ||
                          owner.contains(_searchQuery) ||
                          tech.contains(_searchQuery);
                    }).toList();

                    if (filtered.isEmpty) {
                      return _buildEmptyState();
                    }

                    return ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final project = filtered[index];
                        return ProjectCard(
                          project: project,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProjectDetailScreen(projectId: project.id, initialProject: project),
                              ),
                            );
                          },
                          onEdit: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CreateProjectScreen(existingProject: project),
                              ),
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
      ),
    );
  }

  // ── Search & Filter Strip ──

  Widget _buildSearchAndFilterHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: Column(
        children: [
          // Hyper Material 3 Search Bar matching People Screen
          Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _isSearchFocused
                        ? U.surfaceContainerHighest
                        : U.surfaceContainerHigh,
                    borderRadius: M3Shapes.fullRadius,
                    border: Border.all(
                      color: _isSearchFocused
                          ? U.primary
                          : U.outlineVariant.withValues(alpha: 0.35),
                      width: _isSearchFocused ? 1.6 : 0.8,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      AnimatedScale(
                        scale: _isSearchFocused ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          Icons.search_rounded,
                          color: _isSearchFocused ? U.primary : U.sub,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchFocusNode.unfocus(),
                          cursorColor: U.primary,
                          style: GoogleFonts.robotoFlex(
                            color: U.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search projects, tech tags, authors...',
                            hintStyle: GoogleFonts.robotoFlex(
                              color: U.sub.withValues(alpha: 0.75),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        M3Pressable(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _searchController.clear();
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: U.surfaceContainerLowest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: U.sub,
                              size: 16,
                            ),
                          ),
                        ).animate().scale(curve: Curves.easeOutBack, duration: 180.ms),
                    ],
                  ),
                ),
              ),
              if (_isSearchFocused || _searchController.text.isNotEmpty) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _searchFocusNode.unfocus();
                    if (_searchController.text.isNotEmpty) {
                      _searchController.clear();
                    }
                    setState(() {});
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: U.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.robotoFlex(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Horizontal Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                // All Category Chip
                _buildCategoryFilterChip(label: 'All Categories', category: null),
                const SizedBox(width: 8),

                // Categories
                ...ProjectCategory.values.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildCategoryFilterChip(label: c.label, category: c),
                    )),

                // Status Filter Pill
                _buildStatusDropdownChip(),
                const SizedBox(width: 8),

                // Clear Filters (if active)
                if (_hasActiveFilters)
                  ActionChip(
                    avatar: Icon(Icons.filter_alt_off_rounded, size: 14, color: U.red),
                    label: Text('Reset', style: GoogleFonts.robotoFlex(color: U.red, fontSize: 12, fontWeight: FontWeight.w700)),
                    backgroundColor: U.red.withValues(alpha: 0.1),
                    side: BorderSide(color: U.red.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                    onPressed: _clearFilters,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip({required String label, required ProjectCategory? category}) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      showCheckmark: false,
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          _selectedCategory = val ? category : null;
        });
      },
      selectedColor: U.primary,
      backgroundColor: U.card,
      labelStyle: GoogleFonts.robotoFlex(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? U.getContrastColor(U.primary) : U.text,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: M3Shapes.fullRadius,
        side: BorderSide(
          color: isSelected ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
    );
  }

  Widget _buildStatusDropdownChip() {
    final isStatusActive = _selectedStatus != null;
    return PopupMenuButton<ProjectStatus?>(
      initialValue: _selectedStatus,
      onSelected: (st) => setState(() => _selectedStatus = st),
      shape: RoundedRectangleBorder(borderRadius: M3Shapes.largeRadius),
      color: U.surfaceContainerHigh,
      itemBuilder: (ctx) => [
        PopupMenuItem<ProjectStatus?>(
          value: null,
          child: Text('All Statuses', style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13)),
        ),
        ...ProjectStatus.values.map((st) => PopupMenuItem<ProjectStatus?>(
              value: st,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getStatusColor(st),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(st.label, style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13)),
                ],
              ),
            )),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isStatusActive ? U.peach.withValues(alpha: 0.15) : U.card,
          borderRadius: M3Shapes.fullRadius,
          border: Border.all(
            color: isStatusActive ? U.peach : U.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: isStatusActive ? U.peach : U.sub,
            ),
            const SizedBox(width: 5),
            Text(
              _selectedStatus == null ? 'Status' : _selectedStatus!.label,
              style: GoogleFonts.robotoFlex(
                fontSize: 12,
                fontWeight: isStatusActive ? FontWeight.w700 : FontWeight.w500,
                color: isStatusActive ? U.peach : U.text,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: isStatusActive ? U.peach : U.sub,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.rocket_launch_outlined, size: 36, color: U.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _hasActiveFilters ? 'No Matching Projects' : 'No Projects Showcased Yet',
              style: GoogleFonts.robotoFlex(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: U.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hasActiveFilters
                  ? 'Try clearing active filters or searching with different terms.'
                  : 'Be the first student to publish your app, hardware build, design, or research!',
              style: GoogleFonts.robotoFlex(
                fontSize: 13,
                color: U.sub,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_hasActiveFilters)
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('Clear Filters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: U.primary,
                  side: BorderSide(color: U.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
                  );
                },
                icon: Icon(Icons.add_rounded, size: 18, color: U.getContrastColor(U.primary)),
                label: Text(
                  'Post Your Project',
                  style: GoogleFonts.robotoFlex(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: U.getContrastColor(U.primary),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: U.primary,
                  foregroundColor: U.getContrastColor(U.primary),
                  shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ProjectStatus st) {
    switch (st) {
      case ProjectStatus.inProgress: return U.peach;
      case ProjectStatus.completed: return U.green;
      case ProjectStatus.lookingForTeammates: return U.teal;
    }
  }
}
