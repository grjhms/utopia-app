import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/follow_service.dart';
import '../services/people_interaction_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/chat_media_picker.dart';
import '../widgets/instagram_badge.dart';
import '../widgets/superuser_badge.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import '../widgets/thought_cloud_badge.dart';
import '../widgets/utopia_wave_button.dart';
import '../widgets/wave_count_badge.dart';
import 'chat_screen.dart';
import 'friends_screen.dart';
import 'user_profile_screen.dart';
import '../theme/m3_expressive_theme.dart';

const List<String> kBTechBranches = [
  'Agri Engg',
  'CSE (AI & ML)',
  'CSE (AI & ML - Microsoft)',
  'CSE (AI & ML - Google)',
  'Civil Engg',
  'CSE',
  'CSE (Data Science)',
  'CSE (Data Science - Google)',
  'CSE (Google Cloud)',
  'CSE (SAP)',
  'EEE',
  'ECE',
  'Mechanical Engg',
  'Mining Engg',
  'Petroleum Tech',
];

enum PeopleViewMode { grid, list }

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PeopleInteractionService _interactionService = PeopleInteractionService();
  final FollowService _followService = FollowService();

  PeopleViewMode _viewMode = PeopleViewMode.grid;
  String _selectedFilter = 'All'; // 'All', 'My Branch', 'Active', or Branch name
  String _selectedBranch = 'All';
  bool _hasAutoPromptedBranch = false;
  bool _isSearchFocused = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _currentUserName => FirebaseAuth.instance.currentUser?.displayName ?? 'Student';
  String? get _currentUserPhoto => FirebaseAuth.instance.currentUser?.photoURL;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('displayName')
        .snapshots();

    _searchFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isSearchFocused = _searchFocusNode.hasFocus;
        });
      }
    });

    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openSetMyBranchModal([Map<String, int> branchCounts = const {}]) {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SetUserBranchSheet(
        currentUid: _currentUid,
        branchCounts: branchCounts,
        onBranchSaved: (branch) {
          if (mounted) {
            setState(() {
              _selectedBranch = branch;
              _selectedFilter = 'My Branch';
            });
            showUtopiaSnackBar(
              context,
              message: 'Branch set to $branch',
              tone: UtopiaSnackBarTone.success,
            );
          }
        },
      ),
    );
  }

  void _openSetStatusSheet(CampusVibe? currentVibe) {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SetStatusSheet(
        initialVibe: currentVibe,
        currentUserName: _currentUserName,
        currentUserPhoto: _currentUserPhoto,
        onStatusSaved: (emoji, text, location, durationHours, mediaUrl) async {
          await _interactionService.setUserVibe(
            emoji: emoji,
            text: text,
            location: location,
            durationHours: durationHours,
            mediaUrl: mediaUrl,
          );
          if (mounted) {
            setState(() {});
            final hoursText = durationHours >= 24 ? '24h' : '${durationHours}h';
            final hasMedia = mediaUrl != null && mediaUrl.isNotEmpty;
            showUtopiaSnackBar(
              context,
              message: hasMedia
                  ? '$emoji Media status updated ($hoursText)'
                  : '$emoji Status updated ($hoursText)',
              tone: UtopiaSnackBarTone.success,
            );
          }
        },
        onStatusCleared: () async {
          await _interactionService.clearUserVibe();
          if (mounted) {
            setState(() {});
            showUtopiaSnackBar(
              context,
              message: 'Status cleared',
              tone: UtopiaSnackBarTone.info,
            );
          }
        },
      ),
    );
  }

  void _openQuickPeekSheet(Map<String, dynamic> user, CampusVibe? vibe) {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickPeekProfileSheet(
        user: user,
        vibe: vibe,
        currentUid: _currentUid,
        interactionService: _interactionService,
        followService: _followService,
      ),
    );
  }

  void _openBranchPickerModal(Map<String, int> branchCounts, int totalCount) {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BranchPickerSheet(
        selectedBranch: _selectedBranch,
        branchCounts: branchCounts,
        totalCount: totalCount,
        onSelectBranch: (branch) {
          setState(() {
            _selectedBranch = branch;
            _selectedFilter = branch;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _usersStream,
          builder: (context, userSnap) {
            final rawDocs = userSnap.data?.docs ?? [];
            final totalCount = rawDocs.length;
            final query = _searchController.text.trim().toLowerCase();

            // All campus users
            final allUsers = rawDocs.map((d) => {...d.data(), 'uid': d.id}).toList();

            // Find current user data
            final currentUserDoc = allUsers.firstWhere(
              (u) => u['uid'] == _currentUid,
              orElse: () => {},
            );
            final myBranch = (currentUserDoc['branch'] ?? '').toString().trim();
            final hasSelectedBranch = myBranch.isNotEmpty;

            // Calculate branch member counts
            final branchCounts = <String, int>{};
            for (final u in allUsers) {
              final b = (u['branch'] ?? '').toString().trim();
              if (b.isNotEmpty) {
                branchCounts[b] = (branchCounts[b] ?? 0) + 1;
              }
            }

            // Auto-prompt branch picker once if user hasn't selected their branch
            if (!hasSelectedBranch && !_hasAutoPromptedBranch && _currentUid.isNotEmpty && rawDocs.isNotEmpty) {
              _hasAutoPromptedBranch = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _openSetMyBranchModal();
                }
              });
            }

            // Map of active vibes / statuses
            final activeVibesMap = <String, CampusVibe>{};
            for (final u in allUsers) {
              if (u['vibe'] != null) {
                try {
                  final vibe = CampusVibe.fromMap(u['uid'].toString(), u);
                  if ((vibe.text.isNotEmpty || (vibe.mediaUrl != null && vibe.mediaUrl!.isNotEmpty)) && !vibe.isExpired) {
                    activeVibesMap[vibe.uid] = vibe;
                  }
                } catch (_) {}
              }
            }

            final currentUserVibe = activeVibesMap[_currentUid];

            // Filter logic
            final filteredUsers = allUsers.where((u) {
              final uid = u['uid'].toString();
              final branch = (u['branch'] ?? '').toString().trim();
              final bio = (u['bio'] ?? '').toString().toLowerCase();
              final hasVibe = activeVibesMap.containsKey(uid);

              if (_selectedFilter == 'Active' && !hasVibe) {
                return false;
              } else if (_selectedFilter == 'My Branch') {
                if (myBranch.isEmpty || branch.toLowerCase() != myBranch.toLowerCase()) {
                  return false;
                }
              } else if (_selectedFilter != 'All' &&
                  _selectedFilter != 'Active' &&
                  _selectedFilter != 'My Branch') {
                if (branch != _selectedFilter) return false;
              }

              if (query.isEmpty) return true;
              final name = (u['displayName'] ?? '').toString().toLowerCase();
              final email = (u['email'] ?? '').toString().toLowerCase();
              final b = branch.toLowerCase();
              final insta = (u['instagramId'] ?? '').toString().toLowerCase();
              final vibeText = activeVibesMap[uid]?.text.toLowerCase() ?? '';

              return name.contains(query) ||
                  email.contains(query) ||
                  b.contains(query) ||
                  insta.contains(query) ||
                  bio.contains(query) ||
                  vibeText.contains(query);
            }).toList()
              ..sort((a, b) {
                // Priority: users with active status first, then alphabetical
                final hasVibeA = activeVibesMap.containsKey(a['uid']);
                final hasVibeB = activeVibesMap.containsKey(b['uid']);
                if (hasVibeA && !hasVibeB) return -1;
                if (!hasVibeA && hasVibeB) return 1;
                final nameA = (a['displayName'] ?? '').toString().toLowerCase();
                final nameB = (b['displayName'] ?? '').toString().toLowerCase();
                return nameA.compareTo(nameB);
              });

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _searchFocusNode.unfocus(),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  // ── 1. Hyper Material 3 Header Bar ──────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'People',
                                style: GoogleFonts.robotoFlex(
                                  color: U.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                ),
                              ).animate().fadeIn(duration: 250.ms).slideX(begin: -0.05, end: 0),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: U.surfaceContainerHighest,
                                      borderRadius: M3Shapes.fullRadius,
                                      border: Border.all(
                                        color: U.outlineVariant.withValues(alpha: 0.3),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (activeVibesMap.isNotEmpty) ...[
                                          _RadarPingDot(),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          totalCount > 0 ? '$totalCount campus members' : 'Campus directory',
                                          style: GoogleFonts.robotoFlex(
                                            color: U.sub,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ).animate().fadeIn(duration: 300.ms, delay: 50.ms).scaleXY(begin: 0.9, end: 1.0),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),

                          // Friends / Requests shortcut button
                          StreamBuilder<int>(
                            stream: _followService.pendingRequestsCountStream(_currentUid),
                            builder: (context, reqSnap) {
                              final reqCount = reqSnap.data ?? 0;
                              return M3Pressable(
                                onTap: () {
                                  _searchFocusNode.unfocus();
                                  Navigator.of(context).push(
                                    buildForwardRoute(const FriendsScreen()),
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: U.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: U.outlineVariant.withValues(alpha: 0.35),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Icon(Icons.people_alt_outlined, color: U.text, size: 20),
                                    ),
                                    if (reqCount > 0)
                                      Positioned(
                                        right: -3,
                                        top: -3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: U.red,
                                            borderRadius: M3Shapes.fullRadius,
                                            border: Border.all(color: U.surface, width: 2),
                                          ),
                                          child: Text(
                                            reqCount > 99 ? '99+' : '$reqCount',
                                            style: GoogleFonts.robotoFlex(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ).animate().scale(curve: Curves.elasticOut, duration: 400.ms),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),

                          // View Switcher (Grid vs List) with spring rotating animation
                          M3Pressable(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _searchFocusNode.unfocus();
                              setState(() {
                                _viewMode = _viewMode == PeopleViewMode.grid
                                    ? PeopleViewMode.list
                                    : PeopleViewMode.grid;
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: U.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: U.outlineVariant.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, anim) => RotationTransition(
                                  turns: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                                  child: ScaleTransition(scale: anim, child: child),
                                ),
                                child: Icon(
                                  _viewMode == PeopleViewMode.grid
                                      ? Icons.view_agenda_rounded
                                      : Icons.grid_view_rounded,
                                  key: ValueKey(_viewMode),
                                  color: U.text,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 2. Hyper Material 3 Search Bar ──────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                      child: Row(
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
                                        hintText: 'Search people, branch, bio...',
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
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.15, end: 0, curve: Curves.easeOutBack),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── 3. Campus Vibe Story Capsules (Fluid Horizontal Row) ─────────
                  SliverToBoxAdapter(
                    child: _CampusStatusRow(
                      currentUid: _currentUid,
                      currentUserName: _currentUserName,
                      currentUserPhoto: _currentUserPhoto,
                      currentUserVibe: currentUserVibe,
                      activeVibes: activeVibesMap.values.toList(),
                      onSetStatusTap: () => _openSetStatusSheet(currentUserVibe),
                      onStatusTap: (vibe) {
                        final targetUser = allUsers.firstWhere(
                          (u) => u['uid'] == vibe.uid,
                          orElse: () => {
                            'uid': vibe.uid,
                            'displayName': vibe.displayName,
                            'photoUrl': vibe.photoUrl,
                            'branch': vibe.branch,
                          },
                        );
                        _openQuickPeekSheet(targetUser, vibe);
                      },
                    ),
                  ),

                  // ── 4. Academic Branch Prompt Banner ────────────────────────────
                  if (!hasSelectedBranch && query.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: U.surfaceContainerHigh,
                            borderRadius: M3Shapes.cardRadius,
                            border: Border.all(
                              color: U.primary.withValues(alpha: 0.35),
                              width: 1.0,
                            ),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: U.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(Icons.school_rounded, color: U.primary, size: 26),
                              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.95, end: 1.05, duration: 1200.ms, curve: Curves.easeInOut),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Set your major / branch',
                                      style: GoogleFonts.robotoFlex(
                                        color: U.text,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Connect easily with peers in your program',
                                      style: GoogleFonts.robotoFlex(
                                        color: U.sub,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonal(
                                onPressed: _openSetMyBranchModal,
                                style: FilledButton.styleFrom(
                                  backgroundColor: U.primary.withValues(alpha: 0.16),
                                  foregroundColor: U.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Select',
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
                      ),
                    ),

                  // ── 5. Hyper Material 3 Filter Chips ────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                      child: SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            _buildFilterPill(
                              id: 'All',
                              label: 'All',
                              count: totalCount,
                            ),
                            const SizedBox(width: 8),
                            if (hasSelectedBranch) ...[
                              _buildFilterPill(
                                id: 'My Branch',
                                label: myBranch,
                                icon: Icons.school_rounded,
                                count: branchCounts[myBranch],
                              ),
                              const SizedBox(width: 8),
                            ],
                            _buildFilterPill(
                              id: 'Active',
                              label: 'Active Status',
                              count: activeVibesMap.length,
                              showLiveDot: true,
                            ),
                            const SizedBox(width: 8),
                            // Branch selector dropdown chip
                            M3Pressable(
                              onTap: () => _openBranchPickerModal(branchCounts, totalCount),
                              borderRadius: M3Shapes.fullRadius,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: _selectedFilter != 'All' &&
                                          _selectedFilter != 'Active' &&
                                          _selectedFilter != 'My Branch'
                                      ? U.primary.withValues(alpha: 0.16)
                                      : U.surfaceContainerHigh,
                                  borderRadius: M3Shapes.fullRadius,
                                  border: Border.all(
                                    color: _selectedFilter != 'All' &&
                                            _selectedFilter != 'Active' &&
                                            _selectedFilter != 'My Branch'
                                        ? U.primary.withValues(alpha: 0.55)
                                        : U.outlineVariant.withValues(alpha: 0.35),
                                    width: _selectedFilter != 'All' &&
                                            _selectedFilter != 'Active' &&
                                            _selectedFilter != 'My Branch'
                                        ? 1.2
                                        : 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 15,
                                      color: _selectedFilter != 'All' &&
                                              _selectedFilter != 'Active' &&
                                              _selectedFilter != 'My Branch'
                                          ? U.primary
                                          : U.sub,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _selectedBranch == 'All' ||
                                              _selectedFilter == 'All' ||
                                              _selectedFilter == 'Active' ||
                                              _selectedFilter == 'My Branch'
                                          ? 'Branches'
                                          : _selectedBranch,
                                      style: GoogleFonts.robotoFlex(
                                        color: _selectedFilter != 'All' &&
                                                _selectedFilter != 'Active' &&
                                                _selectedFilter != 'My Branch'
                                            ? U.primary
                                            : U.sub,
                                        fontSize: 12.5,
                                        fontWeight: _selectedFilter != 'All' &&
                                                _selectedFilter != 'Active' &&
                                                _selectedFilter != 'My Branch'
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    if (_selectedFilter != 'All' &&
                                        _selectedFilter != 'Active' &&
                                        _selectedFilter != 'My Branch' &&
                                        (branchCounts[_selectedBranch] ?? 0) > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: U.primary.withValues(alpha: 0.22),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${branchCounts[_selectedBranch]}',
                                          style: GoogleFonts.robotoFlex(
                                            color: U.primary,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: _selectedFilter != 'All' &&
                                              _selectedFilter != 'Active' &&
                                              _selectedFilter != 'My Branch'
                                          ? U.primary
                                          : U.sub,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── 6. Main List or Grid Content (Fluid Animated Switcher) ───────
                  if (userSnap.connectionState == ConnectionState.waiting)
                    const SliverToBoxAdapter(child: _PeopleSkeleton())
                  else if (userSnap.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load directory',
                        subtitle: 'Please check your connection and try again.',
                      ),
                    )
                  else if (filteredUsers.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'No members found',
                        subtitle: query.isNotEmpty
                            ? 'Try searching with another name, branch, or skill.'
                            : 'Try changing your branch filter or be the first to set a status!',
                      ).animate().fadeIn(duration: 250.ms).scaleXY(begin: 0.9, end: 1.0, curve: Curves.easeOutBack),
                    )
                  else if (_viewMode == PeopleViewMode.grid)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      sliver: SliverGrid(
                        key: ValueKey('grid-$_selectedFilter-${query.isNotEmpty}'),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.77,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final user = filteredUsers[index];
                            final uid = user['uid'].toString();
                            final vibe = activeVibesMap[uid];
                            final cleanName = UtopiaApp.sanitizeDisplayName(
                              (user['displayName'] ?? 'Student').toString(),
                            );

                            final card = _PeerGridCard(
                              key: ValueKey('peer-grid-$uid'),
                              user: user,
                              vibe: vibe,
                              currentUid: _currentUid,
                              interactionService: _interactionService,
                              followService: _followService,
                              onTap: () {
                                Navigator.of(context).push(
                                  buildForwardRoute(
                                    UserProfileScreen(
                                      uid: uid,
                                      displayName: cleanName,
                                      email: (user['email'] ?? '').toString(),
                                      photoUrl: user['photoUrl']?.toString(),
                                    ),
                                  ),
                                );
                              },
                              onLongPress: () => _openQuickPeekSheet(user, vibe),
                            );

                            // Staggered fast pop-in animation on filter switch
                            if (index < 12) {
                              return card
                                  .animate(key: ValueKey('anim-grid-$uid-$_selectedFilter'))
                                  .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                                  .scaleXY(
                                    begin: 0.92,
                                    end: 1.0,
                                    duration: 240.ms,
                                    delay: (index * 20).ms,
                                    curve: Curves.easeOutBack,
                                  )
                                  .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    duration: 240.ms,
                                    delay: (index * 20).ms,
                                    curve: Curves.easeOutCubic,
                                  );
                            }
                            return card;
                          },
                          childCount: filteredUsers.length,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 120),
                      sliver: SliverList(
                        key: ValueKey('list-$_selectedFilter-${query.isNotEmpty}'),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final user = filteredUsers[index];
                            final uid = user['uid'].toString();
                            final vibe = activeVibesMap[uid];
                            final cleanName = UtopiaApp.sanitizeDisplayName(
                              (user['displayName'] ?? 'Student').toString(),
                            );

                            final tile = _PeerListTile(
                              key: ValueKey('peer-list-$uid'),
                              user: user,
                              vibe: vibe,
                              currentUid: _currentUid,
                              interactionService: _interactionService,
                              followService: _followService,
                              onTap: () {
                                Navigator.of(context).push(
                                  buildForwardRoute(
                                    UserProfileScreen(
                                      uid: uid,
                                      displayName: cleanName,
                                      email: (user['email'] ?? '').toString(),
                                      photoUrl: user['photoUrl']?.toString(),
                                    ),
                                  ),
                                );
                              },
                              onLongPress: () => _openQuickPeekSheet(user, vibe),
                            );

                            if (index < 12) {
                              return tile
                                  .animate(key: ValueKey('anim-list-$uid-$_selectedFilter'))
                                  .fadeIn(duration: 200.ms, curve: Curves.easeOut)
                                  .scaleXY(
                                    begin: 0.94,
                                    end: 1.0,
                                    duration: 220.ms,
                                    delay: (index * 18).ms,
                                    curve: Curves.easeOutBack,
                                  )
                                  .slideY(
                                    begin: 0.06,
                                    end: 0,
                                    duration: 220.ms,
                                    delay: (index * 18).ms,
                                    curve: Curves.easeOutCubic,
                                  );
                            }
                            return tile;
                          },
                          childCount: filteredUsers.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String id,
    required String label,
    int? count,
    bool showLiveDot = false,
    IconData? icon,
  }) {
    final isSelected = _selectedFilter == id;
    return M3Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        _searchFocusNode.unfocus();
        setState(() {
          _selectedFilter = id;
          if (id == 'All') _selectedBranch = 'All';
        });
      },
      borderRadius: M3Shapes.fullRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? U.primary : U.surfaceContainerHigh,
          borderRadius: M3Shapes.fullRadius,
          border: Border.all(
            color: isSelected
                ? U.primary
                : U.outlineVariant.withValues(alpha: 0.35),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isSelected) ...[
              Icon(
                Icons.check_rounded,
                size: 14,
                color: U.getContrastColor(U.primary),
              ).animate().scale(curve: Curves.easeOutBack, duration: 180.ms),
              const SizedBox(width: 5),
            ] else if (showLiveDot) ...[
              _RadarPingDot(),
              const SizedBox(width: 5),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: U.sub,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.robotoFlex(
                color: isSelected ? U.getContrastColor(U.primary) : U.text,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? U.getContrastColor(U.primary).withValues(alpha: 0.22)
                      : U.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.robotoFlex(
                    color: isSelected ? U.getContrastColor(U.primary) : U.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// RADAR PING DOT (Live Animated Indicator)
// ────────────────────────────────────────────────────────────────────────────
class _RadarPingDot extends StatelessWidget {
  const _RadarPingDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF22C55E).withValues(alpha: 0.35),
            ),
          ).animate(onPlay: (c) => c.repeat()).scaleXY(begin: 0.6, end: 1.5, duration: 1100.ms, curve: Curves.easeOut).fadeOut(duration: 1100.ms),
          Container(
            width: 6.5,
            height: 6.5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CAMPUS STATUS ROW (Material 3 Expressive Story Capsules)
// ────────────────────────────────────────────────────────────────────────────
class _CampusStatusRow extends StatelessWidget {
  const _CampusStatusRow({
    required this.currentUid,
    required this.currentUserName,
    required this.currentUserPhoto,
    required this.currentUserVibe,
    required this.activeVibes,
    required this.onSetStatusTap,
    required this.onStatusTap,
  });

  final String currentUid;
  final String currentUserName;
  final String? currentUserPhoto;
  final CampusVibe? currentUserVibe;
  final List<CampusVibe> activeVibes;
  final VoidCallback onSetStatusTap;
  final ValueChanged<CampusVibe> onStatusTap;

  @override
  Widget build(BuildContext context) {
    final otherVibes = activeVibes.where((v) => v.uid != currentUid).toList();

    return Container(
      height: 106,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Current User Status Capsule
          M3Pressable(
            onTap: onSetStatusTap,
            scaleFactor: 0.93,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 76,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (currentUserVibe != null &&
                          currentUserVibe!.mediaUrl != null &&
                          currentUserVibe!.mediaUrl!.isNotEmpty) ...[
                        // Squircle status media container
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: U.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: U.primary,
                              width: 2.2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: CachedNetworkImage(
                              imageUrl: currentUserVibe!.mediaUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: U.surface,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Icon(Icons.broken_image_rounded, size: 18, color: U.sub),
                            ),
                          ),
                        ),
                        // Reduced-size profile icon overlay
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: U.surface, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: U.surfaceContainerHigh,
                              backgroundImage: currentUserPhoto != null && currentUserPhoto!.isNotEmpty
                                  ? CachedNetworkImageProvider(currentUserPhoto!)
                                  : null,
                              child: currentUserPhoto == null || currentUserPhoto!.isEmpty
                                  ? Text(
                                      currentUserName.isEmpty ? 'U' : currentUserName[0].toUpperCase(),
                                      style: GoogleFonts.robotoFlex(
                                        color: U.primary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -8,
                          child: ThoughtCloudBadge(
                            vibe: currentUserVibe,
                            avatarRadius: 30,
                            compact: true,
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: U.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: currentUserVibe != null ? U.primary : U.outlineVariant.withValues(alpha: 0.45),
                              width: currentUserVibe != null ? 2.2 : 1.2,
                            ),
                          ),
                          padding: const EdgeInsets.all(3.5),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: currentUserPhoto != null && currentUserPhoto!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: currentUserPhoto!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: U.primary.withValues(alpha: 0.14),
                                    alignment: Alignment.center,
                                    child: Text(
                                      currentUserName.isEmpty ? 'U' : currentUserName[0].toUpperCase(),
                                      style: GoogleFonts.robotoFlex(
                                        color: U.primary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        if (currentUserVibe != null)
                          Positioned(
                            top: -6,
                            right: -8,
                            child: ThoughtCloudBadge(
                              vibe: currentUserVibe,
                              avatarRadius: 30,
                              compact: true,
                            ),
                          )
                        else
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: U.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: U.surface, width: 2),
                              ),
                              child: Icon(Icons.add_rounded, size: 12, color: U.getContrastColor(U.primary)),
                            ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.95, end: 1.15, duration: 900.ms, curve: Curves.easeInOut),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    currentUserVibe != null ? 'Your Vibe' : 'Set Status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoFlex(
                      color: currentUserVibe != null ? U.primary : U.sub,
                      fontSize: 11.5,
                      fontWeight: currentUserVibe != null ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Subtle divider if others have active status
          if (otherVibes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
              child: VerticalDivider(width: 1, color: U.outlineVariant.withValues(alpha: 0.35)),
            ),

          // Other active peers with fluid spring entrance
          ...otherVibes.asMap().entries.map((entry) {
            final idx = entry.key;
            final vibe = entry.value;
            final hasVibeMedia = vibe.mediaUrl != null && vibe.mediaUrl!.isNotEmpty;

            final item = M3Pressable(
              onTap: () => onStatusTap(vibe),
              scaleFactor: 0.93,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 76,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (hasVibeMedia) ...[
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: U.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: U.primary,
                                width: 2.2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: CachedNetworkImage(
                                imageUrl: vibe.mediaUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: U.surface,
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Icon(Icons.broken_image_rounded, size: 18, color: U.sub),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: U.surface, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: U.surfaceContainerHigh,
                                backgroundImage: vibe.photoUrl != null && vibe.photoUrl!.isNotEmpty
                                    ? CachedNetworkImageProvider(vibe.photoUrl!)
                                    : null,
                                child: vibe.photoUrl == null || vibe.photoUrl!.isEmpty
                                    ? Text(
                                        vibe.displayName.isEmpty ? 'U' : vibe.displayName[0].toUpperCase(),
                                        style: GoogleFonts.robotoFlex(
                                          color: U.primary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -8,
                            child: ThoughtCloudBadge(
                              vibe: vibe,
                              avatarRadius: 30,
                              compact: true,
                            ),
                          ),
                        ] else ...[
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: U.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: U.primary,
                                width: 2.2,
                              ),
                            ),
                            padding: const EdgeInsets.all(3.5),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: vibe.photoUrl != null && vibe.photoUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: vibe.photoUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: U.primary.withValues(alpha: 0.14),
                                      alignment: Alignment.center,
                                      child: Text(
                                        vibe.displayName.isEmpty ? 'U' : vibe.displayName[0].toUpperCase(),
                                        style: GoogleFonts.robotoFlex(
                                          color: U.primary,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -8,
                            child: ThoughtCloudBadge(
                              vibe: vibe,
                              avatarRadius: 30,
                              compact: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      vibe.displayName.split(' ')[0],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.robotoFlex(
                        color: U.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (idx < 8) {
              return item
                  .animate()
                  .fadeIn(duration: 250.ms, delay: (idx * 25).ms)
                  .scaleXY(begin: 0.88, end: 1.0, duration: 260.ms, curve: Curves.easeOutBack);
            }
            return item;
          }),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// PEER GRID CARD (Material 3 Expressive)
// ────────────────────────────────────────────────────────────────────────────
class _PeerGridCard extends StatefulWidget {
  const _PeerGridCard({
    super.key,
    required this.user,
    required this.vibe,
    required this.currentUid,
    required this.interactionService,
    required this.followService,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, dynamic> user;
  final CampusVibe? vibe;
  final String currentUid;
  final PeopleInteractionService interactionService;
  final FollowService followService;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_PeerGridCard> createState() => _PeerGridCardState();
}

class _PeerGridCardState extends State<_PeerGridCard> {
  bool _hasWaved = false;

  @override
  void initState() {
    super.initState();
    widget.interactionService.hasWavedRecently(widget.user['uid'].toString()).then((waved) {
      if (mounted) setState(() => _hasWaved = waved);
    });
  }

  Future<void> _handleWave() async {
    if (_hasWaved) return;
    setState(() => _hasWaved = true);
    await widget.interactionService.sendWave(widget.user['uid'].toString());
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.user['uid'].toString();
    final displayName = UtopiaApp.sanitizeDisplayName(
      (widget.user['displayName'] ?? 'Student').toString(),
    );
    final firstName = displayName.split(' ').first;
    final photoUrl = widget.user['photoUrl']?.toString();
    final branch = (widget.user['branch'] ?? '').toString().trim();
    final isSuperuser = widget.user['role'] == 'superuser';
    final instagramId = (widget.user['instagramId'] ?? '').toString().trim();
    final isMe = uid == widget.currentUid;
    final hasActiveVibe = widget.vibe != null;

    return M3Pressable(
      onTap: widget.onTap,
      scaleFactor: 0.94,
      borderRadius: M3Shapes.cardRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: U.surfaceContainerLow,
          borderRadius: M3Shapes.cardRadius,
          border: Border.all(
            color: hasActiveVibe
                ? U.primary.withValues(alpha: 0.55)
                : U.outlineVariant.withValues(alpha: 0.35),
            width: hasActiveVibe ? 1.6 : 0.8,
          ),
          boxShadow: hasActiveVibe
              ? [
                  BoxShadow(
                    color: U.primary.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Squircle Avatar / Status Container
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.vibe != null &&
                    widget.vibe!.mediaUrl != null &&
                    widget.vibe!.mediaUrl!.isNotEmpty) ...[
                  // Squircle status media container
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: U.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: U.primary,
                        width: 2.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: widget.vibe!.mediaUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: U.surface,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Icon(Icons.broken_image_rounded, size: 22, color: U.sub),
                      ),
                    ),
                  ),
                  // Small profile icon overlay
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: U.surface, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: U.surfaceContainerHigh,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                style: GoogleFonts.robotoFlex(
                                  color: U.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -8,
                    child: ThoughtCloudBadge(
                      vibe: widget.vibe,
                      avatarRadius: 37,
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: U.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: widget.vibe != null
                            ? U.primary
                            : U.outlineVariant.withValues(alpha: 0.35),
                        width: widget.vibe != null ? 2.2 : 1.0,
                      ),
                    ),
                    padding: const EdgeInsets.all(3.5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: U.primary.withValues(alpha: 0.14),
                              alignment: Alignment.center,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'U',
                                style: GoogleFonts.robotoFlex(
                                  color: U.primary,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Vibe thought cloud top-right
                  if (widget.vibe != null)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: ThoughtCloudBadge(
                        vibe: widget.vibe,
                        avatarRadius: 37,
                      ),
                    ),
                ],
              ],
            ),

            const SizedBox(height: 10),

            // Name row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoFlex(
                      color: U.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isSuperuser) ...[
                  const SizedBox(width: 3),
                  const SuperUserBadge(size: 13),
                ],
                if (instagramId.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  InstagramBadge(handle: instagramId, iconSize: 11, showHandle: false),
                ],
              ],
            ),

            // Branch text pill
            if (branch.isNotEmpty) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: U.surfaceContainerHighest,
                  borderRadius: M3Shapes.fullRadius,
                ),
                child: Text(
                  branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoFlex(
                    color: U.sub,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            const Spacer(),

            // Wave button (or "You" container for current user)
            if (!isMe)
              UtopiaWaveButton(
                hasWaved: _hasWaved,
                onWave: _handleWave,
                variant: WaveButtonVariant.standard,
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6.5),
                decoration: BoxDecoration(
                  color: U.surfaceContainerHighest,
                  borderRadius: M3Shapes.fullRadius,
                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Center(
                  child: Text(
                    'You',
                    style: GoogleFonts.robotoFlex(
                      color: U.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// PEER LIST TILE (Material 3 Expressive Card)
// ────────────────────────────────────────────────────────────────────────────
class _PeerListTile extends StatefulWidget {
  const _PeerListTile({
    super.key,
    required this.user,
    required this.vibe,
    required this.currentUid,
    required this.interactionService,
    required this.followService,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, dynamic> user;
  final CampusVibe? vibe;
  final String currentUid;
  final PeopleInteractionService interactionService;
  final FollowService followService;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_PeerListTile> createState() => _PeerListTileState();
}

class _PeerListTileState extends State<_PeerListTile> {
  bool _loadingFollow = false;
  bool _hasWaved = false;

  @override
  void initState() {
    super.initState();
    widget.interactionService.hasWavedRecently(widget.user['uid'].toString()).then((waved) {
      if (mounted) setState(() => _hasWaved = waved);
    });
  }

  Future<void> _handleFollow(FollowStatus status) async {
    if (_loadingFollow) return;
    setState(() => _loadingFollow = true);
    try {
      await widget.followService.toggleFollow(widget.user['uid'].toString());
    } finally {
      if (mounted) setState(() => _loadingFollow = false);
    }
  }

  Future<void> _handleWave() async {
    if (_hasWaved) return;
    setState(() => _hasWaved = true);
    await widget.interactionService.sendWave(widget.user['uid'].toString());
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.user['uid'].toString();
    final displayName = UtopiaApp.sanitizeDisplayName(
      (widget.user['displayName'] ?? 'Student').toString(),
    );
    final photoUrl = widget.user['photoUrl']?.toString();
    final bio = (widget.user['bio'] ?? '').toString().trim();
    final branch = (widget.user['branch'] ?? '').toString().trim();
    final isSuperuser = widget.user['role'] == 'superuser';
    final instagramId = (widget.user['instagramId'] ?? '').toString().trim();
    final isMe = uid == widget.currentUid;
    final hasActiveVibe = widget.vibe != null;

    return M3Pressable(
      onTap: widget.onTap,
      scaleFactor: 0.965,
      borderRadius: M3Shapes.cardRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: U.surfaceContainerLow,
          borderRadius: M3Shapes.cardRadius,
          border: Border.all(
            color: hasActiveVibe
                ? U.primary.withValues(alpha: 0.55)
                : U.outlineVariant.withValues(alpha: 0.35),
            width: hasActiveVibe ? 1.4 : 0.8,
          ),
          boxShadow: hasActiveVibe
              ? [
                  BoxShadow(
                    color: U.primary.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Squircle Avatar + Status Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.vibe != null &&
                    widget.vibe!.mediaUrl != null &&
                    widget.vibe!.mediaUrl!.isNotEmpty) ...[
                  // Squircle status media container
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: U.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: U.primary,
                        width: 2.0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: widget.vibe!.mediaUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: U.surface,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Icon(Icons.broken_image_rounded, size: 18, color: U.sub),
                      ),
                    ),
                  ),
                  // Small profile icon overlay
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: U.surface, width: 1.8),
                      ),
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: U.surfaceContainerHigh,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                style: GoogleFonts.robotoFlex(
                                  color: U.primary,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -8,
                    child: ThoughtCloudBadge(
                      vibe: widget.vibe,
                      avatarRadius: 28,
                      compact: true,
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: U.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: widget.vibe != null ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
                        width: widget.vibe != null ? 2.0 : 0.8,
                      ),
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: U.primary.withValues(alpha: 0.14),
                              alignment: Alignment.center,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'U',
                                style: GoogleFonts.robotoFlex(
                                  color: U.primary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (widget.vibe != null)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: ThoughtCloudBadge(
                        vibe: widget.vibe,
                        avatarRadius: 28,
                        compact: true,
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(width: 14),

            // Info Column
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
                          style: GoogleFonts.robotoFlex(
                            color: U.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isSuperuser) ...[
                        const SizedBox(width: 4),
                        const SuperUserBadge(size: 13),
                      ],
                      if (instagramId.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        InstagramBadge(handle: instagramId, iconSize: 12, showHandle: false),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (branch.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: U.surfaceContainerHighest,
                        borderRadius: M3Shapes.fullRadius,
                      ),
                      child: Text(
                        branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.robotoFlex(
                          color: U.sub,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (widget.vibe != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${widget.vibe!.emoji} ${widget.vibe!.text}',
                      style: GoogleFonts.robotoFlex(
                        color: U.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else if (bio.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      bio,
                      style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Actions
            if (!isMe) ...[
              UtopiaWaveButton(
                hasWaved: _hasWaved,
                onWave: _handleWave,
                variant: WaveButtonVariant.iconOnly,
                width: 36,
                height: 36,
              ),
              const SizedBox(width: 8),
              StreamBuilder<FollowStatus>(
                stream: widget.followService.followStatusStream(widget.currentUid, uid),
                builder: (context, statusSnap) {
                  final status = statusSnap.data ?? FollowStatus.notFollowing;
                  return _InlineFollowButton(
                    status: status,
                    loading: _loadingFollow,
                    onTap: () => _handleFollow(status),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// INLINE FOLLOW BUTTON (Material 3 Expressive Pill)
// ────────────────────────────────────────────────────────────────────────────
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
        fg = U.getContrastColor(U.primary);
        bordered = false;
        break;
      case FollowStatus.requested:
        label = 'Requested';
        bg = U.surfaceContainerHigh;
        fg = U.sub;
        bordered = true;
        break;
      case FollowStatus.following:
        label = 'Following';
        bg = U.surfaceContainerHigh;
        fg = U.sub;
        bordered = true;
        break;
    }

    return M3Pressable(
      onTap: onTap,
      scaleFactor: 0.92,
      borderRadius: M3Shapes.fullRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: M3Shapes.fullRadius,
          border: bordered
              ? Border.all(color: U.outlineVariant.withValues(alpha: 0.4), width: 0.8)
              : null,
        ),
        child: Center(
          child: loading
              ? const UtopiaLoader(scale: 0.22)
              : Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.robotoFlex(
                    color: fg,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SET CAMPUS STATUS BOTTOM SHEET (Material 3 Expressive)
// ────────────────────────────────────────────────────────────────────────────
class _SetStatusSheet extends StatefulWidget {
  const _SetStatusSheet({
    required this.initialVibe,
    required this.currentUserName,
    required this.currentUserPhoto,
    required this.onStatusSaved,
    required this.onStatusCleared,
  });

  final CampusVibe? initialVibe;
  final String currentUserName;
  final String? currentUserPhoto;
  final void Function(
    String emoji,
    String text,
    String? location,
    int durationHours,
    String? mediaUrl,
  ) onStatusSaved;
  final VoidCallback onStatusCleared;

  @override
  State<_SetStatusSheet> createState() => _SetStatusSheetState();
}

class _SetStatusSheetState extends State<_SetStatusSheet> {
  late final TextEditingController _textController;
  late String _selectedEmoji;
  String? _selectedLocation;
  int _selectedDurationHours = 24;
  String? _selectedMediaUrl;

  static const List<String> _emojis = [
    '📚', '🏛️', '🫠', '☕', '💻', '🏃', '🔋', '✍️',
    '🎧', '📖', '🔬', '🥪', '🤝', '🏠', '💡', '✨',
  ];

  static const List<String> _spots = [
    'Library', 'Canteen', 'Lab', 'Classroom', 'Hostel', 'Campus Grounds', 'Sports Complex',
  ];

  static const List<Map<String, String>> _presets = [
    {'emoji': '📚', 'text': 'Studying (allegedly)'},
    {'emoji': '🏛️', 'text': 'Here for the attendance'},
    {'emoji': '🫠', 'text': 'Brain is buffering'},
    {'emoji': '☕', 'text': 'Fueled by caffeine'},
    {'emoji': '💻', 'text': 'Fighting runtime errors'},
    {'emoji': '🏃', 'text': 'Sprinting to lecture'},
    {'emoji': '🔋', 'text': 'Social battery at 1%'},
    {'emoji': '✍️', 'text': 'Speedrunning assignments'},
    {'emoji': '🎧', 'text': 'Focus mode'},
    {'emoji': '📖', 'text': 'In the library'},
    {'emoji': '🔬', 'text': 'In the lab'},
    {'emoji': '🥪', 'text': 'Canteen run'},
    {'emoji': '🤝', 'text': 'Group study'},
    {'emoji': '🏠', 'text': 'Hibernating at hostel'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedEmoji = widget.initialVibe?.emoji ?? '📚';
    _textController = TextEditingController(text: widget.initialVibe?.text ?? '');
    _selectedLocation = widget.initialVibe?.location;
    _selectedDurationHours = widget.initialVibe?.durationHours ?? 24;
    _selectedMediaUrl = widget.initialVibe?.mediaUrl;
    _textController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _save() {
    final text = _textController.text.trim();
    if (text.isEmpty && (_selectedMediaUrl == null || _selectedMediaUrl!.isEmpty)) return;
    HapticFeedback.selectionClick();
    final hasMedia = _selectedMediaUrl != null && _selectedMediaUrl!.isNotEmpty;
    widget.onStatusSaved(
      hasMedia ? '' : _selectedEmoji,
      text,
      _selectedLocation,
      _selectedDurationHours,
      _selectedMediaUrl,
    );
    Navigator.pop(context);
  }

  void _clear() {
    HapticFeedback.lightImpact();
    widget.onStatusCleared();
    Navigator.pop(context);
  }

  void _openMediaPicker() {
    ChatMediaPickerSheet.show(
      context,
      onSelectGif: (url) {
        setState(() => _selectedMediaUrl = url);
      },
      onSelectSticker: (url) {
        setState(() => _selectedMediaUrl = url);
      },
      onSelectEmoji: (emoji) {
        setState(() => _selectedEmoji = emoji);
      },
    );
  }

  void _openCustomEmojiDialog() {
    final emojiController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentInput = emojiController.text.trim();
          final previewEmoji = currentInput.isNotEmpty
              ? currentInput.characters.first
              : _selectedEmoji;

          return AlertDialog(
            backgroundColor: U.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: M3Shapes.extraLargeRadius),
            title: Row(
              children: [
                Icon(Icons.emoji_emotions_outlined, color: U.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Choose Emoji',
                  style: GoogleFonts.robotoFlex(color: U.text, fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pick a quick emoji or type any from your keyboard',
                    style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: U.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      border: Border.all(color: U.primary, width: 1.5),
                    ),
                    child: Text(
                      previewEmoji,
                      style: const TextStyle(fontSize: 30),
                    ),
                  ).animate().scale(curve: Curves.easeOutBack, duration: 250.ms),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: _emojis.map((e) {
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          emojiController.text = e;
                          setDialogState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: previewEmoji == e
                                ? U.primary.withValues(alpha: 0.18)
                                : U.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: previewEmoji == e
                                  ? U.primary
                                  : U.outlineVariant.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 18)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emojiController,
                    autofocus: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      hintText: 'Or type any emoji...',
                      hintStyle: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13),
                      filled: true,
                      fillColor: U.surfaceContainerLowest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: M3Shapes.mediumRadius,
                        borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: M3Shapes.mediumRadius,
                        borderSide: BorderSide(color: U.primary, width: 1.8),
                      ),
                    ),
                    onChanged: (val) {
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.robotoFlex(color: U.sub, fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: U.primary,
                  foregroundColor: U.getContrastColor(U.primary),
                  shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                  elevation: 0,
                ),
                onPressed: () {
                  final text = emojiController.text.trim();
                  if (text.isNotEmpty) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedEmoji = text.characters.first;
                    });
                  }
                  Navigator.pop(ctx);
                },
                child: Text('Apply', style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = widget.initialVibe != null;
    final currentText = _textController.text.trim();
    final hasMedia = _selectedMediaUrl != null && _selectedMediaUrl!.isNotEmpty;
    final isEmpty = currentText.isEmpty && !hasMedia;

    return Container(
      decoration: BoxDecoration(
        color: U.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // M3 Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.outlineVariant,
                    borderRadius: M3Shapes.fullRadius,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasActive ? 'Update Status' : 'Set Campus Status',
                        style: GoogleFonts.robotoFlex(
                          color: U.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Share what you\'re up to with classmates',
                        style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11.5),
                      ),
                    ],
                  ),
                  if (hasActive)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: Icon(Icons.delete_outline_rounded, size: 15, color: U.red),
                      label: Text(
                        'Clear',
                        style: GoogleFonts.robotoFlex(
                          color: U.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: U.red.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // ── 1. Unified Status Composer Card ──
              Container(
                decoration: BoxDecoration(
                  color: U.surfaceContainer,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: !isEmpty ? U.primary.withValues(alpha: 0.5) : U.outlineVariant.withValues(alpha: 0.4),
                    width: !isEmpty ? 1.4 : 0.8,
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Emoji Avatar Button
                        M3Pressable(
                          onTap: _openCustomEmojiDialog,
                          scaleFactor: 0.92,
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: U.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: U.primary.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _selectedEmoji,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: U.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: U.surfaceContainer, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.edit,
                                    size: 8,
                                    color: U.getContrastColor(U.primary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Text Field
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            autofocus: widget.initialVibe == null && !hasMedia,
                            style: GoogleFonts.robotoFlex(
                              color: U.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLength: 50,
                            decoration: InputDecoration(
                              hintText: hasMedia ? 'Add a caption (optional)...' : 'What\'s happening?',
                              hintStyle: GoogleFonts.robotoFlex(
                                color: U.sub.withValues(alpha: 0.7),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),

                        // Clear text button
                        if (_textController.text.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.cancel_rounded, size: 18, color: U.sub),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _textController.clear();
                              setState(() {});
                            },
                          ),
                      ],
                    ),

                    // Attached Media Preview
                    if (hasMedia) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: U.primary.withValues(alpha: 0.35), width: 1),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: _selectedMediaUrl!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(U.primary)),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => const Icon(Icons.broken_image_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Attached Media',
                                    style: GoogleFonts.robotoFlex(
                                      color: U.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Will show on your campus bubble',
                                    style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _openMediaPicker,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                              ),
                              child: Text('Change', style: GoogleFonts.robotoFlex(fontSize: 11.5, fontWeight: FontWeight.w700, color: U.primary)),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded, size: 16, color: U.red),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() => _selectedMediaUrl = null);
                              },
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 200.ms).scale(curve: Curves.easeOutBack),
                    ],

                    const SizedBox(height: 8),
                    Divider(height: 1, thickness: 0.5, color: U.outlineVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 8),

                    // Quick Action Badges (GIF, Location, Expiry)
                    Row(
                      children: [
                        // GIF / Sticker Trigger
                        M3Pressable(
                          onTap: _openMediaPicker,
                          scaleFactor: 0.94,
                          borderRadius: M3Shapes.fullRadius,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: hasMedia ? U.primary.withValues(alpha: 0.14) : U.surfaceContainerHigh,
                              borderRadius: M3Shapes.fullRadius,
                              border: Border.all(
                                color: hasMedia ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.gif_box_rounded, size: 14, color: hasMedia ? U.primary : U.sub),
                                const SizedBox(width: 4),
                                Text(
                                  hasMedia ? 'GIF Added' : 'GIF / Sticker',
                                  style: GoogleFonts.robotoFlex(
                                    color: hasMedia ? U.primary : U.text,
                                    fontSize: 11,
                                    fontWeight: hasMedia ? FontWeight.w700 : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Location Spot Pill
                        if (_selectedLocation != null) ...[
                          M3Pressable(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedLocation = null);
                            },
                            scaleFactor: 0.94,
                            borderRadius: M3Shapes.fullRadius,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: U.primary.withValues(alpha: 0.14),
                                borderRadius: M3Shapes.fullRadius,
                                border: Border.all(color: U.primary, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_rounded, size: 13, color: U.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    _selectedLocation!,
                                    style: GoogleFonts.robotoFlex(
                                      color: U.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(Icons.close_rounded, size: 11, color: U.primary),
                                ],
                              ),
                            ),
                          ).animate().scale(curve: Curves.easeOutBack, duration: 180.ms),
                          const SizedBox(width: 6),
                        ],

                        const Spacer(),

                        // Expiry Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: U.surfaceContainerLowest,
                            borderRadius: M3Shapes.fullRadius,
                            border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3), width: 0.7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 12, color: U.sub),
                              const SizedBox(width: 3),
                              Text(
                                _selectedDurationHours == 24 ? '24h' : '${_selectedDurationHours}h',
                                style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 10.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 2. Quick Vibes (Curated Horizontal Row) ──
              Text(
                'QUICK VIBES',
                style: GoogleFonts.robotoFlex(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _presets.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final p = _presets[index];
                    final isSelected = _selectedEmoji == p['emoji'] && _textController.text == p['text'];
                    return M3Pressable(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedEmoji = p['emoji']!;
                          _textController.text = p['text']!;
                        });
                      },
                      scaleFactor: 0.94,
                      borderRadius: M3Shapes.fullRadius,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? U.primary.withValues(alpha: 0.16) : U.surfaceContainer,
                          borderRadius: M3Shapes.fullRadius,
                          border: Border.all(
                            color: isSelected ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
                            width: isSelected ? 1.4 : 0.7,
                          ),
                        ),
                        child: Text(
                          '${p['emoji']} ${p['text']}',
                          style: GoogleFonts.robotoFlex(
                            color: isSelected ? U.primary : U.text,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Campus Location Spots (Horizontal Chips) ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CAMPUS SPOT',
                    style: GoogleFonts.robotoFlex(
                      color: U.sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (_selectedLocation != null)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedLocation = null);
                      },
                      child: Text(
                        'Clear',
                        style: GoogleFonts.robotoFlex(color: U.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _spots.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final spot = _spots[index];
                    final isSelected = _selectedLocation == spot;
                    return M3Pressable(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedLocation = isSelected ? null : spot);
                      },
                      scaleFactor: 0.94,
                      borderRadius: M3Shapes.fullRadius,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? U.primary.withValues(alpha: 0.16) : U.surfaceContainer,
                          borderRadius: M3Shapes.fullRadius,
                          border: Border.all(
                            color: isSelected ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
                            width: isSelected ? 1.4 : 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: isSelected ? U.primary : U.sub,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              spot,
                              style: GoogleFonts.robotoFlex(
                                color: isSelected ? U.primary : U.text,
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── 4. Expiry Duration (Material 3 Segmented Row) ──
              Text(
                'EXPIRES IN',
                style: GoogleFonts.robotoFlex(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final dur in [2, 4, 8, 24]) ...[
                    Expanded(
                      child: M3Pressable(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedDurationHours = dur);
                        },
                        scaleFactor: 0.94,
                        borderRadius: M3Shapes.fullRadius,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedDurationHours == dur ? U.primary.withValues(alpha: 0.16) : U.surfaceContainer,
                            borderRadius: M3Shapes.fullRadius,
                            border: Border.all(
                              color: _selectedDurationHours == dur ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
                              width: _selectedDurationHours == dur ? 1.4 : 0.7,
                            ),
                          ),
                          child: Text(
                            dur == 24 ? 'Today (24h)' : '${dur}h',
                            style: GoogleFonts.robotoFlex(
                              color: _selectedDurationHours == dur ? U.primary : U.text,
                              fontSize: 12,
                              fontWeight: _selectedDurationHours == dur ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (dur != 24) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // ── 5. Primary Save Button ──
              SizedBox(
                width: double.infinity,
                height: 48,
                child: M3Pressable(
                  onTap: isEmpty ? null : _save,
                  scaleFactor: 0.96,
                  borderRadius: M3Shapes.fullRadius,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isEmpty ? U.primary.withValues(alpha: 0.3) : U.primary,
                      borderRadius: M3Shapes.fullRadius,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      hasActive ? 'Update Status' : 'Set Status',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: isEmpty
                            ? U.getContrastColor(U.primary).withValues(alpha: 0.6)
                            : U.getContrastColor(U.primary),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// QUICK PEEK PROFILE SHEET (Material 3 Expressive)
// ────────────────────────────────────────────────────────────────────────────
class _QuickPeekProfileSheet extends StatefulWidget {
  const _QuickPeekProfileSheet({
    required this.user,
    required this.vibe,
    required this.currentUid,
    required this.interactionService,
    required this.followService,
  });

  final Map<String, dynamic> user;
  final CampusVibe? vibe;
  final String currentUid;
  final PeopleInteractionService interactionService;
  final FollowService followService;

  @override
  State<_QuickPeekProfileSheet> createState() => _QuickPeekProfileSheetState();
}

class _QuickPeekProfileSheetState extends State<_QuickPeekProfileSheet> {
  bool _loadingFollow = false;
  bool _hasWaved = false;

  @override
  void initState() {
    super.initState();
    widget.interactionService.hasWavedRecently(widget.user['uid'].toString()).then((waved) {
      if (mounted) setState(() => _hasWaved = waved);
    });
  }

  Future<void> _handleFollow(FollowStatus status) async {
    if (_loadingFollow) return;
    setState(() => _loadingFollow = true);
    try {
      await widget.followService.toggleFollow(widget.user['uid'].toString());
    } finally {
      if (mounted) setState(() => _loadingFollow = false);
    }
  }

  Future<void> _handleWave() async {
    if (_hasWaved) return;
    setState(() => _hasWaved = true);
    await widget.interactionService.sendWave(widget.user['uid'].toString());
  }

  Future<void> _openChat() async {
    final uid = widget.user['uid'].toString();
    final canChat = await widget.followService.canChat(widget.currentUid, uid);
    if (!mounted) return;
    if (!canChat) {
      showUtopiaSnackBar(
        context,
        message: 'You can message students you follow or who follow you.',
        tone: UtopiaSnackBarTone.info,
      );
      return;
    }
    Navigator.pop(context);
    final cleanName = UtopiaApp.sanitizeDisplayName(
      (widget.user['displayName'] ?? 'Student').toString(),
    );
    Navigator.of(context).push(
      buildForwardRoute(
        ChatScreen(
          otherUserId: uid,
          displayName: cleanName,
          email: widget.user['email'] ?? '',
          photoUrl: widget.user['photoUrl']?.toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.user['uid'].toString();
    final displayName = UtopiaApp.sanitizeDisplayName(
      (widget.user['displayName'] ?? 'Student').toString(),
    );
    final photoUrl = widget.user['photoUrl']?.toString();
    final bio = (widget.user['bio'] ?? '').toString().trim();
    final branch = (widget.user['branch'] ?? '').toString().trim();
    final instagramId = (widget.user['instagramId'] ?? '').toString().trim();
    final isSuperuser = widget.user['role'] == 'superuser';
    final wavesCount = (widget.user['wavesReceivedCount'] as num?)?.toInt() ?? 0;
    final isMe = uid == widget.currentUid;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: U.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: U.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Profile Header Row & Status View
            () {
              final hasMediaVibe = widget.vibe != null &&
                  widget.vibe!.mediaUrl != null &&
                  widget.vibe!.mediaUrl!.isNotEmpty;

              if (hasMediaVibe) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Compact Profile Header (Squircle)
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: U.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: photoUrl != null && photoUrl.isNotEmpty
                                ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                                : Center(
                                    child: Text(
                                      displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                                      style: GoogleFonts.robotoFlex(
                                        color: U.primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
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
                                      style: GoogleFonts.robotoFlex(
                                        color: U.text,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (isSuperuser) ...[
                                    const SizedBox(width: 4),
                                    const SuperUserBadge(size: 14),
                                  ],
                                ],
                              ),
                              if (branch.isNotEmpty)
                                Text(
                                  branch,
                                  style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                        if (instagramId.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InstagramBadge(handle: instagramId, iconSize: 13, compact: true),
                          ),
                        if (wavesCount > 0)
                          WaveCountBadge(count: wavesCount, compact: true),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Squared Status View-Mode Container
                    Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: (MediaQuery.of(context).size.width - 40).clamp(200.0, 260.0),
                          maxHeight: (MediaQuery.of(context).size.width - 40).clamp(200.0, 260.0),
                        ),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerHigh,
                          borderRadius: M3Shapes.cardRadius,
                          border: Border.all(color: U.primary.withValues(alpha: 0.4), width: 1.5),
                        ),
                        child: ClipRRect(
                          borderRadius: M3Shapes.cardRadius,
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: CachedNetworkImage(
                              imageUrl: widget.vibe!.mediaUrl!,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => Container(
                                color: U.surfaceContainerLowest,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Icon(Icons.broken_image_rounded, size: 32, color: U.sub),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Status Details / Caption
                    if (widget.vibe!.text.isNotEmpty || widget.vibe!.location != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerHigh,
                          borderRadius: M3Shapes.mediumRadius,
                          border: Border.all(color: U.primary.withValues(alpha: 0.25), width: 0.8),
                        ),
                        child: Row(
                          children: [
                            if (widget.vibe!.emoji.isNotEmpty && widget.vibe!.emoji != '✨') ...[
                              Text(widget.vibe!.emoji, style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.vibe!.text.isNotEmpty)
                                    Text(
                                      widget.vibe!.text,
                                      style: GoogleFonts.robotoFlex(
                                        color: U.primary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  if (widget.vibe!.location != null)
                                    Text(
                                      '📍 ${widget.vibe!.location!}',
                                      style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              }

              // Standard Profile Header Row
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: U.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: widget.vibe != null ? U.primary : U.outlineVariant.withValues(alpha: 0.35),
                                width: widget.vibe != null ? 2.0 : 1.0,
                              ),
                            ),
                            padding: const EdgeInsets.all(3),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: photoUrl != null && photoUrl.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                                  : Container(
                                      color: U.primary.withValues(alpha: 0.14),
                                      alignment: Alignment.center,
                                      child: Text(
                                        displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                                        style: GoogleFonts.robotoFlex(
                                          color: U.primary,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          if (widget.vibe != null)
                            Positioned(
                              top: -6,
                              right: -8,
                              child: ThoughtCloudBadge(
                                vibe: widget.vibe,
                                avatarRadius: 34,
                              ),
                            ),
                        ],
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
                                    style: GoogleFonts.robotoFlex(
                                      color: U.text,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (isSuperuser) ...[
                                  const SizedBox(width: 4),
                                  const SuperUserBadge(size: 15),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (branch.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: U.surfaceContainerLowest,
                                      borderRadius: M3Shapes.fullRadius,
                                    ),
                                    child: Text(
                                      branch,
                                      style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                if (instagramId.isNotEmpty)
                                  InstagramBadge(handle: instagramId, iconSize: 13, compact: true),
                                if (wavesCount > 0)
                                  WaveCountBadge(count: wavesCount, compact: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Active Status Card (text only)
                  if (widget.vibe != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: U.surfaceContainerHigh,
                        borderRadius: M3Shapes.largeRadius,
                        border: Border.all(color: U.primary.withValues(alpha: 0.3), width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Text(widget.vibe!.emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.vibe!.text,
                                  style: GoogleFonts.robotoFlex(
                                    color: U.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (widget.vibe!.location != null)
                                  Text(
                                    '📍 ${widget.vibe!.location!}',
                                    style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            }(),

            // Bio
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                bio,
                style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13, height: 1.35),
              ),
            ],

            const SizedBox(height: 18),

            // Actions
            if (!isMe)
              Row(
                children: [
                  Expanded(
                    child: UtopiaWaveButton(
                      hasWaved: _hasWaved,
                      onWave: _handleWave,
                      variant: WaveButtonVariant.outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: BorderSide(color: U.outlineVariant.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                      ),
                      onPressed: _openChat,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 14, color: U.text),
                          const SizedBox(width: 6),
                          Text('Message', style: GoogleFonts.robotoFlex(color: U.text, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StreamBuilder<FollowStatus>(
                      stream: widget.followService.followStatusStream(widget.currentUid, uid),
                      builder: (context, statusSnap) {
                        final status = statusSnap.data ?? FollowStatus.notFollowing;
                        final isFollowing = status == FollowStatus.following;

                        return FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: isFollowing ? U.surfaceContainerHigh : U.primary,
                            foregroundColor: isFollowing ? U.text : U.getContrastColor(U.primary),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: M3Shapes.fullRadius,
                              side: isFollowing ? BorderSide(color: U.outlineVariant.withValues(alpha: 0.4)) : BorderSide.none,
                            ),
                          ),
                          onPressed: () => _handleFollow(status),
                          child: Text(
                            status == FollowStatus.notFollowing
                                ? 'Follow'
                                : status == FollowStatus.requested
                                    ? 'Requested'
                                    : 'Following',
                            style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w800),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// BRANCH PICKER SHEET (Material 3 Expressive)
// ────────────────────────────────────────────────────────────────────────────
class _BranchPickerSheet extends StatefulWidget {
  const _BranchPickerSheet({
    required this.selectedBranch,
    this.branchCounts = const {},
    this.totalCount = 0,
    required this.onSelectBranch,
  });

  final String selectedBranch;
  final Map<String, int> branchCounts;
  final int totalCount;
  final ValueChanged<String> onSelectBranch;

  @override
  State<_BranchPickerSheet> createState() => _BranchPickerSheetState();
}

class _BranchPickerSheetState extends State<_BranchPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final filtered = kBTechBranches;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: U.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
        ),
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Filter by Academic Branch',
                style: GoogleFonts.robotoFlex(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),

              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: M3Shapes.mediumRadius),
                      tileColor: widget.selectedBranch == 'All' ? U.primary.withValues(alpha: 0.12) : null,
                      title: Text(
                        'All Branches',
                        style: GoogleFonts.robotoFlex(
                          color: widget.selectedBranch == 'All' ? U.primary : U.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.totalCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: widget.selectedBranch == 'All'
                                    ? U.primary.withValues(alpha: 0.18)
                                    : U.surfaceContainerHighest,
                                borderRadius: M3Shapes.fullRadius,
                              ),
                              child: Text(
                                '${widget.totalCount} members',
                                style: GoogleFonts.robotoFlex(
                                  color: widget.selectedBranch == 'All' ? U.primary : U.sub,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (widget.selectedBranch == 'All') ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle_rounded, color: U.primary, size: 18),
                          ],
                        ],
                      ),
                      onTap: () {
                        widget.onSelectBranch('All');
                        Navigator.pop(context);
                      },
                    ),
                    ...filtered.map((b) {
                      final count = widget.branchCounts[b] ?? 0;
                      final isSelected = widget.selectedBranch == b;
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: M3Shapes.mediumRadius),
                        tileColor: isSelected ? U.primary.withValues(alpha: 0.12) : null,
                        title: Text(
                          b,
                          style: GoogleFonts.robotoFlex(
                            color: isSelected ? U.primary : U.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? U.primary.withValues(alpha: 0.18)
                                    : count > 0
                                        ? U.surfaceContainerHighest
                                        : Colors.transparent,
                                borderRadius: M3Shapes.fullRadius,
                              ),
                              child: Text(
                                count > 0 ? '$count ${count == 1 ? 'member' : 'members'}' : '0',
                                style: GoogleFonts.robotoFlex(
                                  color: isSelected
                                      ? U.primary
                                      : count > 0
                                          ? U.text
                                          : U.sub.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle_rounded, color: U.primary, size: 18),
                            ],
                          ],
                        ),
                        onTap: () {
                          widget.onSelectBranch(b);
                          Navigator.pop(context);
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SET USER BRANCH BOTTOM SHEET (Material 3 Expressive)
// ────────────────────────────────────────────────────────────────────────────
class _SetUserBranchSheet extends StatefulWidget {
  const _SetUserBranchSheet({
    required this.currentUid,
    this.branchCounts = const {},
    required this.onBranchSaved,
  });

  final String currentUid;
  final Map<String, int> branchCounts;
  final ValueChanged<String> onBranchSaved;

  @override
  State<_SetUserBranchSheet> createState() => _SetUserBranchSheetState();
}

class _SetUserBranchSheetState extends State<_SetUserBranchSheet> {
  final TextEditingController _filterController = TextEditingController();
  String _query = '';
  bool _saving = false;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _selectBranch(String branch) async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.selectionClick();

    try {
      if (widget.currentUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(widget.currentUid).set({
          'branch': branch,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onBranchSaved(branch);
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(context, message: 'Failed to save branch: $e', tone: UtopiaSnackBarTone.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = kBTechBranches.where((b) {
      if (_query.isEmpty) return true;
      return b.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: U.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
        ),
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Academic Branch',
                style: GoogleFonts.robotoFlex(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Personalize your peer directory and campus connections.',
                style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
              ),
              const SizedBox(height: 12),

              // Search field (Stadium)
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: U.surfaceContainerHigh,
                  borderRadius: M3Shapes.fullRadius,
                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: U.sub, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _filterController,
                        style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'Search branches...',
                          hintStyle: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final branch = filtered[index];
                    final count = widget.branchCounts[branch] ?? 0;
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: M3Shapes.mediumRadius),
                      title: Text(
                        branch,
                        style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: count > 0
                          ? Text(
                              '$count ${count == 1 ? 'student' : 'students'} in this branch',
                              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: U.surfaceContainerHighest,
                                borderRadius: M3Shapes.fullRadius,
                              ),
                              child: Text(
                                '$count',
                                style: GoogleFonts.robotoFlex(color: U.primary, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, color: U.sub, size: 18),
                        ],
                      ),
                      onTap: () => _selectBranch(branch),
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
}

// ────────────────────────────────────────────────────────────────────────────
// SKELETON LOADING
// ────────────────────────────────────────────────────────────────────────────
class _PeopleSkeleton extends StatelessWidget {
  const _PeopleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.77,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: U.surfaceContainerLow,
              borderRadius: M3Shapes.cardRadius,
              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: const [
                SkeletonBox(height: 74, width: 74, radius: 22),
                SizedBox(height: 12),
                SkeletonBox(height: 14, width: 85, radius: 6),
                SizedBox(height: 6),
                SkeletonBox(height: 10, width: 60, radius: 5),
                Spacer(),
                SkeletonBox(height: 32, width: double.infinity, radius: 999),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(
                begin: 0.3,
                end: 0.8,
                duration: 800.ms,
              );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: U.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: U.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.robotoFlex(
                color: U.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
