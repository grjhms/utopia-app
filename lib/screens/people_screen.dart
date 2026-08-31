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
                  // ── 1. Top Header Bar ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'People',
                                style: GoogleFonts.outfit(
                                  color: U.text,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                totalCount > 0 ? '$totalCount campus members' : 'Campus directory',
                                style: GoogleFonts.outfit(
                                  color: U.sub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),

                          // Friends / Following navigation shortcut
                          StreamBuilder<int>(
                            stream: _followService.pendingRequestsCountStream(_currentUid),
                            builder: (context, reqSnap) {
                              final reqCount = reqSnap.data ?? 0;
                              return IconButton(
                                tooltip: 'Friends & Requests',
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                onPressed: () {
                                  _searchFocusNode.unfocus();
                                  Navigator.of(context).push(
                                    buildForwardRoute(const FriendsScreen()),
                                  );
                                },
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: U.card,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.people_alt_outlined, color: U.text, size: 17),
                                    ),
                                    if (reqCount > 0)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(3.5),
                                          decoration: BoxDecoration(
                                            color: U.red,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: U.surface, width: 1.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // View Switcher (Grid vs List)
                          IconButton(
                            tooltip: _viewMode == PeopleViewMode.grid ? 'List View' : 'Grid View',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _searchFocusNode.unfocus();
                              setState(() {
                                _viewMode = _viewMode == PeopleViewMode.grid
                                    ? PeopleViewMode.list
                                    : PeopleViewMode.grid;
                              });
                            },
                            icon: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: U.card,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _viewMode == PeopleViewMode.grid
                                    ? Icons.view_agenda_outlined
                                    : Icons.grid_view_rounded,
                                color: U.text,
                                size: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 2. Material 3 Plain Round Search Bar (No Strokes) ──────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: U.card,
                                borderRadius: BorderRadius.circular(28),
                                border: null,
                                boxShadow: const [],
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    color: U.sub,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      textInputAction: TextInputAction.search,
                                      onSubmitted: (_) => _searchFocusNode.unfocus(),
                                      cursorColor: U.primary,
                                      style: GoogleFonts.outfit(
                                        color: U.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Search people, branch, vibe...',
                                        hintStyle: GoogleFonts.outfit(
                                          color: U.sub.withValues(alpha: 0.8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        isDense: true,
                                        filled: false,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.close_rounded,
                                          color: U.sub,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_isSearchFocused || _searchController.text.isNotEmpty) ...[
                            const SizedBox(width: 8),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // ── 3. Campus Status Row (Clean & Lightweight) ─────────────────
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

                // ── 4. Academic Branch Prompt (if not set) ─────────────────────
                if (!hasSelectedBranch && query.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: U.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.school_outlined, color: U.primary, size: 17),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Set your branch',
                                    style: GoogleFonts.outfit(
                                      color: U.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Find classmates and study partners in your major',
                                    style: GoogleFonts.outfit(
                                      color: U.sub,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _openSetMyBranchModal,
                              style: TextButton.styleFrom(
                                backgroundColor: U.primary.withValues(alpha: 0.12),
                                foregroundColor: U.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                'Select',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── 5. Ergonomic Filter Pills ──────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                    child: SizedBox(
                      height: 34,
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
                            leadingEmoji: '🟢',
                          ),
                          const SizedBox(width: 8),
                          // Branch selector dropdown pill
                          GestureDetector(
                            onTap: () => _openBranchPickerModal(branchCounts, totalCount),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: _selectedFilter != 'All' &&
                                        _selectedFilter != 'Active' &&
                                        _selectedFilter != 'My Branch'
                                    ? U.primary.withValues(alpha: 0.14)
                                    : U.card,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 13,
                                    color: _selectedFilter != 'All' &&
                                            _selectedFilter != 'Active' &&
                                            _selectedFilter != 'My Branch'
                                        ? U.primary
                                        : U.sub,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _selectedBranch == 'All' ||
                                            _selectedFilter == 'All' ||
                                            _selectedFilter == 'Active' ||
                                            _selectedFilter == 'My Branch'
                                        ? 'Branches'
                                        : _selectedBranch,
                                    style: GoogleFonts.outfit(
                                      color: _selectedFilter != 'All' &&
                                              _selectedFilter != 'Active' &&
                                              _selectedFilter != 'My Branch'
                                          ? U.primary
                                          : U.sub,
                                      fontSize: 12,
                                      fontWeight: _selectedFilter != 'All' &&
                                              _selectedFilter != 'Active' &&
                                              _selectedFilter != 'My Branch'
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (_selectedFilter != 'All' &&
                                      _selectedFilter != 'Active' &&
                                      _selectedFilter != 'My Branch' &&
                                      (branchCounts[_selectedBranch] ?? 0) > 0) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: U.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${branchCounts[_selectedBranch]}',
                                        style: GoogleFonts.outfit(
                                          color: U.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 15,
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

                // ── 6. Main List or Grid Content ───────────────────────────────
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
                    ),
                  )
                else if (_viewMode == PeopleViewMode.grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final user = filteredUsers[index];
                          final uid = user['uid'].toString();
                          final vibe = activeVibesMap[uid];
                          final cleanName = UtopiaApp.sanitizeDisplayName(
                            (user['displayName'] ?? 'Student').toString(),
                          );

                          return _PeerGridCard(
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
                        },
                        childCount: filteredUsers.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final user = filteredUsers[index];
                          final uid = user['uid'].toString();
                          final vibe = activeVibesMap[uid];
                          final cleanName = UtopiaApp.sanitizeDisplayName(
                            (user['displayName'] ?? 'Student').toString(),
                          );

                          return _PeerListTile(
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
    String? leadingEmoji,
    IconData? icon,
  }) {
    final isSelected = _selectedFilter == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _searchFocusNode.unfocus();
        setState(() {
          _selectedFilter = id;
          if (id == 'All') _selectedBranch = 'All';
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? U.primary : U.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected ? U.getContrastColor(U.primary) : U.sub,
              ),
              const SizedBox(width: 4),
            ] else if (leadingEmoji != null) ...[
              Text(
                leadingEmoji,
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? U.getContrastColor(U.primary) : U.sub,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? U.getContrastColor(U.primary).withValues(alpha: 0.22)
                      : U.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    color: isSelected ? U.getContrastColor(U.primary) : U.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
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
// CAMPUS STATUS ROW (Clean, Lightweight & Ergonomic)
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
      height: 94,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Current User Status Bubble
          GestureDetector(
            onTap: onSetStatusTap,
            child: Container(
              width: 70,
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
                        // Squared status media container
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: U.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: U.primary,
                              width: 1.8,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
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
                              border: Border.all(color: U.surface, width: 1.5),
                            ),
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: U.card,
                              backgroundImage: currentUserPhoto != null && currentUserPhoto!.isNotEmpty
                                  ? CachedNetworkImageProvider(currentUserPhoto!)
                                  : null,
                              child: currentUserPhoto == null || currentUserPhoto!.isEmpty
                                  ? Text(
                                      currentUserName.isEmpty ? 'U' : currentUserName[0].toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        color: U.primary,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
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
                            avatarRadius: 27,
                            compact: true,
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: currentUserVibe != null ? U.primary : U.border,
                              width: currentUserVibe != null ? 1.8 : 0.9,
                            ),
                          ),
                          padding: const EdgeInsets.all(2.5),
                          child: CircleAvatar(
                            backgroundColor: U.card,
                            backgroundImage: currentUserPhoto != null && currentUserPhoto!.isNotEmpty
                                ? CachedNetworkImageProvider(currentUserPhoto!)
                                : null,
                            child: currentUserPhoto == null || currentUserPhoto!.isEmpty
                                ? Text(
                                    currentUserName.isEmpty ? 'U' : currentUserName[0].toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      color: U.primary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (currentUserVibe != null)
                          Positioned(
                            top: -6,
                            right: -8,
                            child: ThoughtCloudBadge(
                              vibe: currentUserVibe,
                              avatarRadius: 27,
                              compact: true,
                            ),
                          )
                        else
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: U.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: U.surface, width: 1.2),
                              ),
                              child: Icon(Icons.add_rounded, size: 10, color: U.getContrastColor(U.primary)),
                            ),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUserVibe != null ? 'Your Status' : 'Set Status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: currentUserVibe != null ? U.primary : U.sub,
                      fontSize: 11,
                      fontWeight: currentUserVibe != null ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Subtle divider if others have active status
          if (otherVibes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              child: VerticalDivider(width: 1, color: U.border.withValues(alpha: 0.5)),
            ),

          // Other active peers
          ...otherVibes.map((vibe) {
            final hasVibeMedia = vibe.mediaUrl != null && vibe.mediaUrl!.isNotEmpty;

            return GestureDetector(
              onTap: () => onStatusTap(vibe),
              child: Container(
                width: 70,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (hasVibeMedia) ...[
                          // Squared status media container
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: U.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: U.primary,
                                width: 1.8,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
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
                          // Reduced-size profile icon overlay
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: U.surface, width: 1.5),
                              ),
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: U.primary.withValues(alpha: 0.12),
                                backgroundImage: vibe.photoUrl != null && vibe.photoUrl!.isNotEmpty
                                    ? CachedNetworkImageProvider(vibe.photoUrl!)
                                    : null,
                                child: vibe.photoUrl == null || vibe.photoUrl!.isEmpty
                                    ? Text(
                                        vibe.displayName.isEmpty ? 'U' : vibe.displayName[0].toUpperCase(),
                                        style: GoogleFonts.outfit(
                                          color: U.primary,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
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
                              avatarRadius: 27,
                              compact: true,
                            ),
                          ),
                        ] else ...[
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: U.primary,
                                width: 1.6,
                              ),
                            ),
                            padding: const EdgeInsets.all(2.5),
                            child: CircleAvatar(
                              backgroundColor: U.primary.withValues(alpha: 0.12),
                              backgroundImage: vibe.photoUrl != null && vibe.photoUrl!.isNotEmpty
                                  ? CachedNetworkImageProvider(vibe.photoUrl!)
                                  : null,
                              child: vibe.photoUrl == null || vibe.photoUrl!.isEmpty
                                  ? Text(
                                      vibe.displayName.isEmpty ? 'U' : vibe.displayName[0].toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        color: U.primary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -8,
                            child: ThoughtCloudBadge(
                              vibe: vibe,
                              avatarRadius: 27,
                              compact: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vibe.displayName.split(' ')[0],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// PEER GRID CARD (Ergonomic & Modern)
// ────────────────────────────────────────────────────────────────────────────
class _PeerGridCard extends StatefulWidget {
  const _PeerGridCard({
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

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.vibe != null ? U.primary.withValues(alpha: 0.4) : U.border,
            width: widget.vibe != null ? 1.2 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar / Status container
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.vibe != null &&
                    widget.vibe!.mediaUrl != null &&
                    widget.vibe!.mediaUrl!.isNotEmpty) ...[
                  // Squared status media container
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: U.primary,
                        width: 2.0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
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
                  // Reduced-size profile icon overlay
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: U.surface, width: 1.8),
                      ),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: U.primary.withValues(alpha: 0.12),
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
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
                      avatarRadius: 34,
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.vibe != null
                            ? U.primary.withValues(alpha: 0.5)
                            : U.border,
                        width: widget.vibe != null ? 2.0 : 1.0,
                      ),
                    ),
                    child: ClipOval(
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              width: 68,
                              height: 68,
                            )
                          : Container(
                              color: U.primary.withValues(alpha: 0.10),
                              alignment: Alignment.center,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'U',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Vibe thought cloud top-right (30% area occupancy)
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
              ],
            ),

            const SizedBox(height: 9),

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
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isSuperuser) ...[
                  const SizedBox(width: 3),
                  const SuperUserBadge(size: 12),
                ],
                if (instagramId.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  InstagramBadge(handle: instagramId, iconSize: 10, showHandle: false),
                ],
              ],
            ),

            // Branch text
            if (branch.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Wave button (hidden for own card)
            if (!isMe)
              UtopiaWaveButton(
                hasWaved: _hasWaved,
                onWave: _handleWave,
                variant: WaveButtonVariant.standard,
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: U.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: U.border, width: 0.7),
                ),
                child: Center(
                  child: Text(
                    'You',
                    style: GoogleFonts.outfit(
                      color: U.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
// PEER LIST TILE (Ergonomic & Modern)
// ────────────────────────────────────────────────────────────────────────────
class _PeerListTile extends StatefulWidget {
  const _PeerListTile({
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

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      splashColor: U.primary.withValues(alpha: 0.04),
      highlightColor: U.primary.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Avatar + status badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.vibe != null &&
                    widget.vibe!.mediaUrl != null &&
                    widget.vibe!.mediaUrl!.isNotEmpty) ...[
                  // Squared status media container
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: U.primary,
                        width: 1.8,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
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
                  // Reduced-size profile icon overlay
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: U.surface, width: 1.4),
                      ),
                      child: CircleAvatar(
                        radius: 8.5,
                        backgroundColor: U.primary.withValues(alpha: 0.12),
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
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
                      avatarRadius: 26,
                      compact: true,
                    ),
                  ),
                ] else ...[
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: U.primary.withValues(alpha: 0.12),
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
                  if (widget.vibe != null)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: ThoughtCloudBadge(
                        vibe: widget.vibe,
                        avatarRadius: 26,
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
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
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
                      if (branch.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: U.surface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: U.border, width: 0.6),
                            ),
                            child: Text(
                              branch,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.vibe != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${widget.vibe!.emoji} ${widget.vibe!.text}',
                      style: GoogleFonts.outfit(
                        color: U.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else if (bio.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      bio,
                      style: GoogleFonts.outfit(color: U.sub, fontSize: 11.5),
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
                width: 30,
                height: 30,
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
// INLINE FOLLOW BUTTON
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
        bg = Colors.transparent;
        fg = U.sub;
        bordered = true;
        break;
      case FollowStatus.following:
        label = 'Following';
        bg = Colors.transparent;
        fg = U.sub;
        bordered = true;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: bordered ? Border.all(color: U.border, width: 0.8) : null,
        ),
        child: Center(
          child: loading
              ? const UtopiaLoader(scale: 0.22)
              : Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.outfit(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SET CAMPUS STATUS BOTTOM SHEET (Streamlined & Human)
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
            backgroundColor: U.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.emoji_emotions_outlined, color: U.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Choose Any Emoji',
                  style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pick or type any emoji from your keyboard',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: U.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: U.primary, width: 1.5),
                  ),
                  child: Text(
                    previewEmoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emojiController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22),
                  decoration: InputDecoration(
                    hintText: 'Type any emoji here...',
                    hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                    filled: true,
                    fillColor: U.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: U.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: U.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (val) {
                    setDialogState(() {});
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: U.primary,
                  foregroundColor: U.getContrastColor(U.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                child: Text('Apply', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
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

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: U.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: U.border, width: 0.8),
        ),
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title Row
              Row(
                children: [
                  Text(
                    'Campus Status',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (hasActive)
                    GestureDetector(
                      onTap: _clear,
                      child: Text(
                        'Clear Status',
                        style: GoogleFonts.outfit(
                          color: U.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Let classmates know what you are currently up to.',
                style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
              ),
              const SizedBox(height: 16),

              // Main Status Input Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isEmpty ? U.border : U.primary.withValues(alpha: 0.4),
                    width: isEmpty ? 0.8 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    if (!hasMedia) ...[
                      GestureDetector(
                        onTap: _openCustomEmojiDialog,
                        child: Stack(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: U.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: U.border, width: 0.8),
                              ),
                              child: Text(
                                _selectedEmoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: U.primary,
                                  shape: BoxShape.circle,
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
                      const SizedBox(width: 10),
                    ] else ...[
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.edit_note_rounded, size: 20, color: U.primary),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        autofocus: widget.initialVibe == null && !hasMedia,
                        style: GoogleFonts.outfit(color: U.text, fontSize: 14, fontWeight: FontWeight.w500),
                        maxLength: 50,
                        decoration: InputDecoration(
                          hintText: hasMedia ? 'Add a caption (optional)...' : 'What are you up to?',
                          hintStyle: GoogleFonts.outfit(color: U.sub.withValues(alpha: 0.7), fontSize: 13.5),
                          border: InputBorder.none,
                          isDense: true,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    if (_textController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _textController.clear();
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(Icons.cancel_rounded, size: 18, color: U.sub),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Attached GIF / Sticker Preview or Add Button
              if (hasMedia)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: U.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: U.primary.withValues(alpha: 0.4), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 58,
                          height: 58,
                          color: U.surface,
                          child: CachedNetworkImage(
                            imageUrl: _selectedMediaUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Icon(Icons.broken_image_rounded, size: 20, color: U.sub),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.auto_awesome, size: 13, color: U.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Attached Media',
                                  style: GoogleFonts.outfit(
                                    color: U.primary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Rendered squared in status view',
                              style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _openMediaPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: U.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: U.border, width: 0.8),
                          ),
                          child: Text(
                            'Change',
                            style: GoogleFonts.outfit(color: U.text, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _selectedMediaUrl = null);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: U.red.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded, size: 15, color: U.red),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                GestureDetector(
                  onTap: _openMediaPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: U.border, width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gif_box_outlined, size: 19, color: U.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Add GIF or Sticker',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• GIPHY & Packs',
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Emoji Selection Bar
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // If current selected emoji is custom (not in _emojis), show it first
                      if (!_emojis.contains(_selectedEmoji)) ...[
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: U.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: U.primary, width: 1.4),
                            ),
                            child: Text(_selectedEmoji, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      for (final emoji in _emojis) ...[
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedEmoji = emoji);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _selectedEmoji == emoji ? U.primary.withValues(alpha: 0.15) : U.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedEmoji == emoji ? U.primary : U.border,
                                width: _selectedEmoji == emoji ? 1.4 : 0.8,
                              ),
                            ),
                            child: Text(emoji, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Custom emoji / Keyboard button
                      GestureDetector(
                        onTap: _openCustomEmojiDialog,
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: U.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: U.border, width: 0.8),
                          ),
                          child: Icon(Icons.add_reaction_outlined, size: 18, color: U.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Quick presets section
                Text(
                  'PRESETS',
                  style: GoogleFonts.outfit(
                    color: U.sub,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _presets.map((p) {
                    final isSelected = _selectedEmoji == p['emoji'] && _textController.text == p['text'];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedEmoji = p['emoji']!;
                          _textController.text = p['text']!;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? U.primary.withValues(alpha: 0.14) : U.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? U.primary : U.border,
                            width: isSelected ? 1.2 : 0.7,
                          ),
                        ),
                        child: Text(
                          '${p['emoji']} ${p['text']}',
                          style: GoogleFonts.outfit(
                            color: isSelected ? U.primary : U.text,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),

              // Location Spot selector
              Row(
                children: [
                  Text(
                    'LOCATION (OPTIONAL)',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedLocation != null)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedLocation = null);
                      },
                      child: Text(
                        'Clear',
                        style: GoogleFonts.outfit(color: U.primary, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _spots.map((spot) {
                  final isSelected = _selectedLocation == spot;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedLocation = isSelected ? null : spot);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? U.primary.withValues(alpha: 0.14) : U.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? U.primary : U.border,
                          width: isSelected ? 1.2 : 0.7,
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
                            style: GoogleFonts.outfit(
                              color: isSelected ? U.primary : U.text,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Duration selector
              Text(
                'EXPIRES IN',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final dur in [2, 4, 8, 24]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedDurationHours = dur);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedDurationHours == dur ? U.primary.withValues(alpha: 0.14) : U.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedDurationHours == dur ? U.primary : U.border,
                              width: _selectedDurationHours == dur ? 1.2 : 0.7,
                            ),
                          ),
                          child: Text(
                            dur == 24 ? 'Today (24h)' : '${dur}h',
                            style: GoogleFonts.outfit(
                              color: _selectedDurationHours == dur ? U.primary : U.text,
                              fontSize: 12,
                              fontWeight: _selectedDurationHours == dur ? FontWeight.w700 : FontWeight.w500,
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

              // Save button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: U.primary,
                    foregroundColor: U.getContrastColor(U.primary),
                    disabledBackgroundColor: U.primary.withValues(alpha: 0.3),
                    disabledForegroundColor: U.getContrastColor(U.primary).withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: isEmpty ? null : _save,
                  child: Text(
                    hasActive ? 'Update Status' : 'Set Status',
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700),
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
// QUICK PEEK PROFILE SHEET
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
          color: U.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: U.border, width: 0.8),
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
                  color: U.border,
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
                    // Compact Profile Header (Reduced-size icon)
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: U.primary.withValues(alpha: 0.12),
                          backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                              ? CachedNetworkImageProvider(photoUrl)
                              : null,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(
                                  displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: U.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
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
                                      style: GoogleFonts.outfit(
                                        color: U.text,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
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
                                  style: GoogleFonts.outfit(color: U.sub, fontSize: 10.5, fontWeight: FontWeight.w500),
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
                          color: U.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: U.primary.withValues(alpha: 0.35), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: U.primary.withValues(alpha: 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: CachedNetworkImage(
                              imageUrl: widget.vibe!.mediaUrl!,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => Container(
                                color: U.surface,
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
                          color: U.card,
                          borderRadius: BorderRadius.circular(12),
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
                                      style: GoogleFonts.outfit(
                                        color: U.primary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  if (widget.vibe!.location != null)
                                    Text(
                                      '📍 ${widget.vibe!.location!}',
                                      style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
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

              // Standard Profile Header Row (when no media status is applied)
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: U.primary.withValues(alpha: 0.12),
                            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(photoUrl)
                                : null,
                            child: photoUrl == null || photoUrl.isEmpty
                                ? Text(
                                    displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      color: U.primary,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          if (widget.vibe != null)
                            Positioned(
                              top: -6,
                              right: -8,
                              child: ThoughtCloudBadge(
                                vibe: widget.vibe,
                                avatarRadius: 35,
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
                                    style: GoogleFonts.outfit(
                                      color: U.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: U.card,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: U.border, width: 0.6),
                                    ),
                                    child: Text(
                                      branch,
                                      style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w600),
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
                        color: U.card,
                        borderRadius: BorderRadius.circular(14),
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
                                  style: GoogleFonts.outfit(
                                    color: U.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (widget.vibe!.location != null)
                                  Text(
                                    '📍 ${widget.vibe!.location!}',
                                    style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
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
                style: GoogleFonts.outfit(color: U.text, fontSize: 13, height: 1.35),
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
                        side: BorderSide(color: U.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _openChat,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 14, color: U.text),
                          const SizedBox(width: 6),
                          Text('Message', style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w700)),
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

                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFollowing ? U.card : U.primary,
                            foregroundColor: isFollowing ? U.text : U.getContrastColor(U.primary),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isFollowing ? BorderSide(color: U.border) : BorderSide.none,
                            ),
                          ),
                          onPressed: () => _handleFollow(status),
                          child: Text(
                            status == FollowStatus.notFollowing
                                ? 'Follow'
                                : status == FollowStatus.requested
                                    ? 'Requested'
                                    : 'Following',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
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
// BRANCH PICKER SHEET
// ────────────────────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────────────────
// BRANCH PICKER SHEET
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
          color: U.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: U.border, width: 0.8),
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
                    color: U.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Filter by Academic Branch',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      tileColor: widget.selectedBranch == 'All' ? U.primary.withValues(alpha: 0.12) : null,
                      title: Text(
                        'All Branches',
                        style: GoogleFonts.outfit(
                          color: widget.selectedBranch == 'All' ? U.primary : U.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.totalCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.selectedBranch == 'All'
                                    ? U.primary.withValues(alpha: 0.18)
                                    : U.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: U.border, width: 0.6),
                              ),
                              child: Text(
                                '${widget.totalCount} members',
                                style: GoogleFonts.outfit(
                                  color: widget.selectedBranch == 'All' ? U.primary : U.sub,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        tileColor: isSelected ? U.primary.withValues(alpha: 0.12) : null,
                        title: Text(
                          b,
                          style: GoogleFonts.outfit(
                            color: isSelected ? U.primary : U.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? U.primary.withValues(alpha: 0.18)
                                    : count > 0
                                        ? U.card
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: count > 0 ? Border.all(color: U.border, width: 0.6) : null,
                              ),
                              child: Text(
                                count > 0 ? '$count ${count == 1 ? 'member' : 'members'}' : '0',
                                style: GoogleFonts.outfit(
                                  color: isSelected
                                      ? U.primary
                                      : count > 0
                                          ? U.text
                                          : U.sub.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  fontWeight: count > 0 ? FontWeight.w600 : FontWeight.w400,
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
// SET USER BRANCH BOTTOM SHEET
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
          color: U.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: U.border, width: 0.8),
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
                    color: U.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Academic Branch',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Personalize your peer directory and campus connections.',
                style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
              ),
              const SizedBox(height: 12),

              // Search field
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: U.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: U.sub, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _filterController,
                        style: GoogleFonts.outfit(color: U.text, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search branches...',
                          hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      title: Text(
                        branch,
                        style: GoogleFonts.outfit(color: U.text, fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                      subtitle: count > 0
                          ? Text(
                              '$count ${count == 1 ? 'student' : 'students'} in this branch',
                              style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: U.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: U.border, width: 0.6),
                              ),
                              child: Text(
                                '$count',
                                style: GoogleFonts.outfit(color: U.primary, fontSize: 11, fontWeight: FontWeight.w700),
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
          childAspectRatio: 0.70,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: U.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: U.border),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: const [
                SkeletonBox(height: 62, width: 62, radius: 31),
                SizedBox(height: 10),
                SkeletonBox(height: 14, width: 85, radius: 6),
                SizedBox(height: 6),
                SkeletonBox(height: 10, width: 60, radius: 5),
                Spacer(),
                SkeletonBox(height: 30, width: double.infinity, radius: 10),
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
            Icon(icon, size: 36, color: U.sub.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
