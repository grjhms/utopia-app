import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/icebreaker_data.dart';
import '../services/follow_service.dart';
import '../services/people_interaction_service.dart';
import '../services/role_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/instagram_badge.dart';
import '../widgets/superuser_badge.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import '../widgets/wave_count_badge.dart';
import 'chat_screen.dart';
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
  final PeopleInteractionService _interactionService = PeopleInteractionService();

  bool _isSearching = false;
  bool _isSuperUser = false;
  bool _hasAutoPromptedBranch = false;
  PeopleViewMode _viewMode = PeopleViewMode.grid;
  String _selectedFilter = 'All'; // 'All', 'Active', 'Study', 'Superusers', or Branch name
  String _selectedBranch = 'All';
  bool _sparkCardDismissed = false;

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

    _searchController.addListener(() {
      if (mounted) setState(() {});
    });

    RoleService().isSuperUser().then((val) {
      if (mounted) setState(() => _isSuperUser = val);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSetMyBranchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SetUserBranchSheet(
        currentUid: _currentUid,
        onBranchSaved: (branch) {
          if (mounted) {
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

  void _openSetVibeSheet(CampusVibe? currentVibe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SetVibeSheet(
        initialVibe: currentVibe,
        currentUserName: _currentUserName,
        currentUserPhoto: _currentUserPhoto,
        onVibeSaved: (emoji, text, location, statusTag, durationHours) async {
          await _interactionService.setUserVibe(
            emoji: emoji,
            text: text,
            location: location,
            statusTag: statusTag,
            durationHours: durationHours,
          );
          if (mounted) {
            setState(() {});
            final hoursText = durationHours >= 24 ? '24h' : '${durationHours}h';
            showUtopiaSnackBar(
              context,
              message: '$emoji Vibe broadcasted ($hoursText)',
              tone: UtopiaSnackBarTone.success,
            );
          }
        },
        onVibeCleared: () async {
          await _interactionService.clearUserVibe();
          if (mounted) {
            setState(() {});
            showUtopiaSnackBar(
              context,
              message: 'Campus vibe cleared',
              tone: UtopiaSnackBarTone.info,
            );
          }
        },
      ),
    );
  }

  void _openAdminEditSparkSheet(SparkQuestion currentSpark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdminEditSparkSheet(
        initialSpark: currentSpark,
        interactionService: _interactionService,
      ),
    );
  }

  void _openStudyBuddyRoulette(List<Map<String, dynamic>> allUsers) {
    final eligible = allUsers.where((u) => u['uid'] != _currentUid).toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: U.card,
          content: Text(
            'Need more peers on campus to find a study match!',
            style: GoogleFonts.outfit(color: U.text),
          ),
        ),
      );
      return;
    }

    final randomMatch = eligible[Random().nextInt(eligible.length)];
    showDialog(
      context: context,
      builder: (ctx) => _StudyBuddyRouletteDialog(
        user: randomMatch,
        currentUid: _currentUid,
        onWave: () => _interactionService.sendWave(randomMatch['uid'].toString()),
      ),
    );
  }

  void _openQuickPeekSheet(Map<String, dynamic> user, CampusVibe? vibe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickPeekProfileSheet(
        user: user,
        vibe: vibe,
        currentUid: _currentUid,
      ),
    );
  }

  void _openBranchPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        tileColor: _selectedBranch == 'All' ? U.primary.withValues(alpha: 0.12) : null,
                        title: Text(
                          'All Branches',
                          style: GoogleFonts.outfit(
                            color: _selectedBranch == 'All' ? U.primary : U.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: _selectedBranch == 'All' ? Icon(Icons.check_circle_rounded, color: U.primary, size: 20) : null,
                        onTap: () {
                          setState(() {
                            _selectedBranch = 'All';
                            _selectedFilter = 'All';
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                      ...kBTechBranches.map((b) => ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: _selectedBranch == b ? U.primary.withValues(alpha: 0.12) : null,
                            title: Text(
                              b,
                              style: GoogleFonts.outfit(
                                color: _selectedBranch == b ? U.primary : U.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: _selectedBranch == b ? Icon(Icons.check_circle_rounded, color: U.primary, size: 20) : null,
                            onTap: () {
                              setState(() {
                                _selectedBranch = b;
                                _selectedFilter = b;
                              });
                              Navigator.pop(ctx);
                            },
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: Navigator.canPop(context) ? 0 : 20,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'People',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: U.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: U.primary.withValues(alpha: 0.25), width: 0.6),
                  ),
                  child: Text(
                    'Pulse',
                    style: GoogleFonts.outfit(
                      color: U.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Study Match / Roulette
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _usersStream,
            builder: (context, snap) {
              final rawDocs = snap.data?.docs ?? [];
              final userList = rawDocs.map((d) => {'uid': d.id, ...d.data()}).toList();
              return IconButton(
                tooltip: 'Study Match',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: U.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: U.border, width: 0.8),
                  ),
                  child: Icon(Icons.casino_outlined, color: U.text, size: 16),
                ),
                onPressed: () => _openStudyBuddyRoulette(userList),
              );
            },
          ),
          // View Switcher (Grid vs List)
          IconButton(
            tooltip: _viewMode == PeopleViewMode.grid ? 'List View' : 'Grid View',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _viewMode = _viewMode == PeopleViewMode.grid ? PeopleViewMode.list : PeopleViewMode.grid;
              });
            },
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: U.card,
                shape: BoxShape.circle,
                border: Border.all(color: U.border, width: 0.8),
              ),
              child: Icon(
                _viewMode == PeopleViewMode.grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
                color: U.text,
                size: 16,
              ),
            ),
          ),
          // Search Toggle
          IconButton(
            tooltip: 'Search',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) _searchController.clear();
            }),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _isSearching ? U.primary.withValues(alpha: 0.12) : U.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isSearching ? U.primary.withValues(alpha: 0.35) : U.border,
                  width: 0.8,
                ),
              ),
              child: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                color: _isSearching ? U.primary : U.text,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _usersStream,
          builder: (context, userSnap) {
            final rawDocs = userSnap.data?.docs ?? [];
            final totalCount = rawDocs.length;

            final query = _searchController.text.trim().toLowerCase();

            // Extract all users
            final allUsers = rawDocs.map((d) => {...d.data(), 'uid': d.id}).toList();

            // Check current user branch
            final currentUserDoc = allUsers.firstWhere(
              (u) => u['uid'] == _currentUid,
              orElse: () => {},
            );
            final myBranch = (currentUserDoc['branch'] ?? '').toString().trim();
            final hasSelectedBranch = myBranch.isNotEmpty;

            // Auto-prompt branch picker once if user hasn't selected their branch
            if (!hasSelectedBranch && !_hasAutoPromptedBranch && _currentUid.isNotEmpty && rawDocs.isNotEmpty) {
              _hasAutoPromptedBranch = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _openSetMyBranchModal();
                }
              });
            }

            // Map of active vibes
            final activeVibesMap = <String, CampusVibe>{};
            for (final u in allUsers) {
              if (u['vibe'] != null) {
                try {
                  final vibe = CampusVibe.fromMap(u['uid'].toString(), u);
                  if (vibe.text.isNotEmpty && !vibe.isExpired) {
                    activeVibesMap[vibe.uid] = vibe;
                  }
                } catch (_) {}
              }
            }

            // Current user vibe
            final currentUserVibe = activeVibesMap[_currentUid];

            // Filter logic
            final filteredUsers = allUsers.where((u) {
              final uid = u['uid'].toString();
              final branch = (u['branch'] ?? '').toString().trim();
              final bio = (u['bio'] ?? '').toString().toLowerCase();
              final hasVibe = activeVibesMap.containsKey(uid);

              if (_selectedFilter == 'Active' && !hasVibe) {
                return false;
              } else if (_selectedFilter == 'Study') {
                final isStudy = bio.contains('study') ||
                    bio.contains('dsa') ||
                    bio.contains('gate') ||
                    hasVibe ||
                    branch.isNotEmpty;
                if (!isStudy) return false;
              } else if (_selectedFilter != 'All' &&
                  _selectedFilter != 'Active' &&
                  _selectedFilter != 'Study') {
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
                // Priority: users with active vibes come first, then alphabetical
                final hasVibeA = activeVibesMap.containsKey(a['uid']);
                final hasVibeB = activeVibesMap.containsKey(b['uid']);
                if (hasVibeA && !hasVibeB) return -1;
                if (!hasVibeA && hasVibeB) return 1;
                final nameA = (a['displayName'] ?? '').toString().toLowerCase();
                final nameB = (b['displayName'] ?? '').toString().toLowerCase();
                return nameA.compareTo(nameB);
              });

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Search bar (Collapsible) ──────────────────────────────────
                if (_isSearching)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: U.border),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(Icons.search_rounded, color: U.sub, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                style: GoogleFonts.outfit(color: U.text, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Search people, skills, vibes, branches...',
                                  hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: Icon(Icons.close_rounded, color: U.sub, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.08, end: 0),
                    ),
                  ),

                // ── Campus Pulse: Live Vibes Stories Tray ────────────────────
                SliverToBoxAdapter(
                  child: _CampusPulseTray(
                    currentUid: _currentUid,
                    currentUserName: _currentUserName,
                    currentUserPhoto: _currentUserPhoto,
                    currentUserVibe: currentUserVibe,
                    activeVibes: activeVibesMap.values.toList(),
                    onSetVibeTap: () => _openSetVibeSheet(currentUserVibe),
                    onVibeTap: (vibe) {
                      final targetUser = allUsers.firstWhere(
                        (u) => u['uid'] == vibe.uid,
                        orElse: () => {'uid': vibe.uid, 'displayName': vibe.displayName, 'photoUrl': vibe.photoUrl, 'branch': vibe.branch},
                      );
                      _openQuickPeekSheet(targetUser, vibe);
                    },
                  ),
                ),

                // ── Academic Branch Prompt Banner ────────────────────────────
                if (!hasSelectedBranch && query.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: U.primary.withValues(alpha: 0.3),
                            width: 0.9,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: U.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.school_outlined, color: U.primary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Set Academic Branch',
                                    style: GoogleFonts.outfit(
                                      color: U.text,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Connect with classmates & study partners',
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
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

                // ── Daily Campus Spark: Interactive Poll ─────────────────────
                if (!_sparkCardDismissed && query.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                      child: _DailyCampusSparkCard(
                        interactionService: _interactionService,
                        isSuperUser: _isSuperUser,
                        allUsers: allUsers,
                        onDismiss: () => setState(() => _sparkCardDismissed = true),
                        onAdminEdit: (spark) => _openAdminEditSparkSheet(spark),
                        onPeerTap: (uid, name, photo) {
                          final targetUser = allUsers.firstWhere(
                            (u) => u['uid'] == uid,
                            orElse: () => {'uid': uid, 'displayName': name, 'photoUrl': photo},
                          );
                          _openQuickPeekSheet(targetUser, activeVibesMap[uid]);
                        },
                      ),
                    ),
                  ),

                // ── Refined Segmented Filter Pills ───────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          _buildFilterPill(
                            id: 'All',
                            label: 'All',
                            count: null,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                            id: 'Active',
                            label: 'Active Vibes',
                            count: activeVibesMap.length,
                            leadingEmoji: '🔥',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                            id: 'Study',
                            label: 'Study Buddies',
                            count: null,
                          ),
                          const SizedBox(width: 8),
                          // Branch selector pill
                          GestureDetector(
                            onTap: _openBranchPickerModal,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: _selectedBranch != 'All'
                                    ? U.primary.withValues(alpha: 0.14)
                                    : U.card,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _selectedBranch != 'All'
                                      ? U.primary.withValues(alpha: 0.4)
                                      : U.border,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 13,
                                    color: _selectedBranch != 'All' ? U.primary : U.sub,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedBranch == 'All' ? 'Branches' : _selectedBranch,
                                    style: GoogleFonts.outfit(
                                      color: _selectedBranch != 'All' ? U.primary : U.sub,
                                      fontSize: 12.5,
                                      fontWeight: _selectedBranch != 'All' ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 15,
                                    color: _selectedBranch != 'All' ? U.primary : U.sub,
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

                // ── Result Context Subheader ─────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _selectedFilter == 'All' && query.isEmpty
                                ? 'CAMPUS DIRECTORY (${filteredUsers.length})'
                                : 'PEERS (${filteredUsers.length} OF $totalCount)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: U.sub,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        if (activeVibesMap.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: U.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${activeVibesMap.length} active now',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Main Content: Grid vs List View ──────────────────────────
                if (userSnap.connectionState == ConnectionState.waiting)
                  const SliverToBoxAdapter(child: _MinimalPeopleSkeleton())
                else if (userSnap.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not load campus members',
                      subtitle: 'Please check your connection and try again.',
                    ),
                  )
                else if (filteredUsers.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.person_search_rounded,
                      title: 'No matching peers found',
                      subtitle: query.isNotEmpty
                          ? 'Try searching with another skill, name, or vibe.'
                          : 'Try switching your filter or be the first to broadcast a vibe!',
                    ),
                  )
                else if (_viewMode == PeopleViewMode.grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.80,
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

                          return _PeerGridCard(
                            user: user,
                            vibe: vibe,
                            currentUid: _currentUid,
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
                            onWave: () => _interactionService.sendWave(uid),
                          );
                        },
                        childCount: filteredUsers.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 140),
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
                            onWave: () => _interactionService.sendWave(uid),
                          );
                        },
                        childCount: filteredUsers.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String id,
    required String label,
    required int? count,
    String? leadingEmoji,
  }) {
    final isSelected = _selectedFilter == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedFilter = id;
          if (id == 'All') _selectedBranch = 'All';
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? U.primary : U.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? Colors.transparent : U.border,
            width: 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: U.primary.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leadingEmoji != null) ...[
              Text(
                leadingEmoji,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? U.getContrastColor(U.primary) : U.sub,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? U.getContrastColor(U.primary).withValues(alpha: 0.2)
                      : U.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.outfit(
                    color: isSelected ? U.getContrastColor(U.primary) : U.primary,
                    fontSize: 10.5,
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

// ─────────────────────────────────────────────────────────────────────────────
// CAMPUS PULSE: Refined Live Vibes Tray
// ─────────────────────────────────────────────────────────────────────────────
class _CampusPulseTray extends StatelessWidget {
  const _CampusPulseTray({
    required this.currentUid,
    required this.currentUserName,
    required this.currentUserPhoto,
    required this.currentUserVibe,
    required this.activeVibes,
    required this.onSetVibeTap,
    required this.onVibeTap,
  });

  final String currentUid;
  final String currentUserName;
  final String? currentUserPhoto;
  final CampusVibe? currentUserVibe;
  final List<CampusVibe> activeVibes;
  final VoidCallback onSetVibeTap;
  final ValueChanged<CampusVibe> onVibeTap;

  @override
  Widget build(BuildContext context) {
    final otherVibes = activeVibes.where((v) => v.uid != currentUid).toList();

    return Container(
      height: 94,
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Current User Vibe Button
          GestureDetector(
            onTap: onSetVibeTap,
            child: Container(
              width: 68,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: currentUserVibe != null ? U.primary : U.border,
                            width: currentUserVibe != null ? 1.8 : 1.0,
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
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: currentUserVibe != null ? U.surface : U.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: U.surface, width: 1.5),
                          ),
                          child: currentUserVibe != null
                              ? Text(
                                  currentUserVibe!.emoji,
                                  style: const TextStyle(fontSize: 10),
                                )
                              : Icon(Icons.add_rounded, size: 10, color: U.getContrastColor(U.primary)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    currentUserVibe != null ? 'My Vibe' : 'Set Vibe',
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

          // Subtle divider
          if (otherVibes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              child: VerticalDivider(width: 1, color: U.border.withValues(alpha: 0.5)),
            ),

          // Other active vibes
          ...otherVibes.map((vibe) {
            return GestureDetector(
              onTap: () => onVibeTap(vibe),
              child: Container(
                width: 68,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: U.primary,
                              width: 1.8,
                            ),
                          ),
                          padding: const EdgeInsets.all(2.2),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: U.surface,
                            ),
                            padding: const EdgeInsets.all(1.2),
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
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              color: U.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: U.surface, width: 1.5),
                            ),
                            child: Text(
                              vibe.emoji,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
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

// ─────────────────────────────────────────────────────────────────────────────
// DAILY CAMPUS SPARK: Refined Interactive Poll
// ─────────────────────────────────────────────────────────────────────────────
class _DailyCampusSparkCard extends StatefulWidget {
  const _DailyCampusSparkCard({
    required this.interactionService,
    required this.isSuperUser,
    required this.allUsers,
    required this.onDismiss,
    required this.onAdminEdit,
    required this.onPeerTap,
  });

  final PeopleInteractionService interactionService;
  final bool isSuperUser;
  final List<Map<String, dynamic>> allUsers;
  final VoidCallback onDismiss;
  final ValueChanged<SparkQuestion> onAdminEdit;
  final void Function(String uid, String name, String? photo) onPeerTap;

  @override
  State<_DailyCampusSparkCard> createState() => _DailyCampusSparkCardState();
}

class _DailyCampusSparkCardState extends State<_DailyCampusSparkCard> {
  int? _localVote;
  String? _loadedQuestionId;

  void _loadVoteIfNew(String questionId) {
    if (_loadedQuestionId != questionId) {
      _loadedQuestionId = questionId;
      widget.interactionService.getLocalSparkVote(questionId).then((vote) {
        if (mounted && vote != null && _localVote == null) {
          setState(() => _localVote = vote);
        }
      });
    }
  }

  Future<void> _vote(String questionId, int optionIndex) async {
    HapticFeedback.selectionClick();
    setState(() => _localVote = optionIndex);
    await widget.interactionService.voteSpark(questionId, optionIndex);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SparkQuestion>(
      stream: widget.interactionService.getActiveSparkStream(),
      builder: (context, sparkSnap) {
        final question = sparkSnap.data ?? widget.interactionService.getTodaysSparkFallback();
        if (!question.enabled) return const SizedBox.shrink();

        _loadVoteIfNew(question.id);

        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

        final Map<int, List<Map<String, dynamic>>> votesMap = {};
        for (int i = 0; i < question.options.length; i++) {
          votesMap[i] = [];
        }

        int? detectedVote = _localVote;

        for (final u in widget.allUsers) {
          final sv = u['sparkVote'];
          if (sv != null) {
            Map<String, dynamic> svMap = {};
            if (sv is Map) {
              svMap = sv.map((k, v) => MapEntry(k.toString(), v));
            }
            final svQId = svMap['questionId']?.toString().trim();
            final opt = (svMap['optionIndex'] as num?)?.toInt();
            if (opt != null && opt >= 0 && opt < question.options.length) {
              final uid = (u['uid'] ?? '').toString();
              if (svQId == question.id || svQId == 'todays_spark' || svQId == null || svQId.isEmpty) {
                votesMap[opt]!.add({
                  'uid': uid,
                  'displayName': (u['displayName'] ?? 'Student').toString(),
                  'photoUrl': (u['photoUrl'] ?? u['photoURL'])?.toString(),
                  'optionIndex': opt,
                });
                if (uid == currentUid && currentUid.isNotEmpty) {
                  detectedVote = opt;
                }
              }
            }
          }
        }

        final userAlreadyInVotes = votesMap.values.any((list) => list.any((v) => v['uid'] == currentUid));
        if (!userAlreadyInVotes && detectedVote != null && currentUid.isNotEmpty) {
          votesMap[detectedVote]!.add({
            'uid': currentUid,
            'displayName': FirebaseAuth.instance.currentUser?.displayName ?? 'You',
            'photoUrl': FirebaseAuth.instance.currentUser?.photoURL,
            'optionIndex': detectedVote,
          });
        }

        int totalVotes = 0;
        for (final list in votesMap.values) {
          totalVotes += list.length;
        }

        final hasVoted = detectedVote != null;

        return Container(
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: U.border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      question.category.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: U.primary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const Spacer(),

                  if (widget.isSuperUser) ...[
                    GestureDetector(
                      onTap: () => widget.onAdminEdit(question),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: U.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: U.border, width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_rounded, size: 10.5, color: U.sub),
                            const SizedBox(width: 3),
                            Text(
                              'Admin',
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  if (totalVotes > 0) ...[
                    Text(
                      '$totalVotes voted',
                      style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                  ],

                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close_rounded, size: 16, color: U.sub),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                question.question,
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),

              // Options
              ...List.generate(question.options.length, (idx) {
                final optionText = question.options[idx];
                final optionVotes = votesMap[idx]?.length ?? 0;
                final pct = totalVotes > 0 ? (optionVotes / totalVotes) : 0.0;
                final isMyPick = detectedVote == idx;

                return GestureDetector(
                  onTap: () => _vote(question.id, idx),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    decoration: BoxDecoration(
                      color: isMyPick ? U.primary.withValues(alpha: 0.08) : U.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMyPick ? U.primary.withValues(alpha: 0.4) : U.border,
                        width: isMyPick ? 1.2 : 0.7,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (hasVoted)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: pct.clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isMyPick
                                        ? U.primary.withValues(alpha: 0.14)
                                        : U.border.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  optionText,
                                  style: GoogleFonts.outfit(
                                    color: isMyPick ? U.primary : U.text,
                                    fontSize: 12.5,
                                    fontWeight: isMyPick ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (hasVoted) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${(pct * 100).round()}%',
                                  style: GoogleFonts.outfit(
                                    color: isMyPick ? U.primary : U.sub,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              // Matching Peers Reveal
              if (hasVoted && (votesMap[detectedVote]?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Agreed with you:',
                      style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: (votesMap[detectedVote] ?? [])
                              .where((v) => v['uid'] != currentUid)
                              .take(8)
                              .map((vote) {
                            final name = (vote['displayName'] ?? 'Student').toString();
                            final photo = vote['photoUrl']?.toString();
                            final uid = vote['uid'].toString();

                            return GestureDetector(
                              onTap: () => widget.onPeerTap(uid, name, photo),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Tooltip(
                                  message: name,
                                  child: CircleAvatar(
                                    radius: 11,
                                    backgroundColor: U.primary.withValues(alpha: 0.15),
                                    backgroundImage: photo != null && photo.isNotEmpty
                                        ? CachedNetworkImageProvider(photo)
                                        : null,
                                    child: photo == null || photo.isEmpty
                                        ? Text(
                                            name.isEmpty ? 'U' : name[0].toUpperCase(),
                                            style: GoogleFonts.outfit(color: U.primary, fontSize: 8.5, fontWeight: FontWeight.w700),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPERUSER: ADMIN EDIT SPARK MODAL SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _AdminEditSparkSheet extends StatefulWidget {
  const _AdminEditSparkSheet({
    required this.initialSpark,
    required this.interactionService,
  });

  final SparkQuestion initialSpark;
  final PeopleInteractionService interactionService;

  @override
  State<_AdminEditSparkSheet> createState() => _AdminEditSparkSheetState();
}

class _AdminEditSparkSheetState extends State<_AdminEditSparkSheet> {
  late final TextEditingController _questionController;
  late final TextEditingController _categoryController;
  late final List<TextEditingController> _optionControllers;
  bool _enabled = true;
  bool _createNewPoll = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.initialSpark.question);
    _categoryController = TextEditingController(text: widget.initialSpark.category);
    _enabled = widget.initialSpark.enabled;
    _optionControllers = widget.initialSpark.options
        .map((opt) => TextEditingController(text: opt))
        .toList();
    if (_optionControllers.length < 2) {
      _optionControllers.add(TextEditingController(text: 'Option 1'));
      _optionControllers.add(TextEditingController(text: 'Option 2'));
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _categoryController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 4) return;
    setState(() {
      _optionControllers.add(TextEditingController(text: 'Option ${_optionControllers.length + 1}'));
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      final removed = _optionControllers.removeAt(index);
      removed.dispose();
    });
  }

  void _applyTemplate(SparkQuestion template) {
    setState(() {
      _questionController.text = template.question;
      _categoryController.text = template.category;
      for (final c in _optionControllers) {
        c.dispose();
      }
      _optionControllers.clear();
      _optionControllers.addAll(
        template.options.map((opt) => TextEditingController(text: opt)),
      );
    });
  }

  Future<void> _save() async {
    final question = _questionController.text.trim();
    final category = _categoryController.text.trim();
    final options = _optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

    if (question.isEmpty || options.length < 2) {
      showUtopiaSnackBar(context, message: 'Please enter question and at least 2 options', tone: UtopiaSnackBarTone.error);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.interactionService.updateSparkConfig(
        question: question,
        options: options,
        category: category.isNotEmpty ? category : 'Campus Spark',
        enabled: _enabled,
        createNewPoll: _createNewPoll,
      );

      if (mounted) {
        Navigator.pop(context);
        showUtopiaSnackBar(context, message: 'Campus Spark broadcasted successfully', tone: UtopiaSnackBarTone.success);
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(context, message: 'Failed to update: $e', tone: UtopiaSnackBarTone.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: U.border, width: 0.8),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
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
            Row(
              children: [
                Text(
                  'Manage Campus Spark',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Switch.adaptive(
                  value: _enabled,
                  activeTrackColor: U.primary,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            Text(
              'Publish custom questions & polls for the campus network.',
              style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
            ),
            const SizedBox(height: 14),

            // Templates shortcut
            Text(
              'QUICK TEMPLATES',
              style: GoogleFonts.outfit(color: U.sub, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: PeopleInteractionService.sparkPool.map((tpl) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _applyTemplate(tpl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: U.border),
                        ),
                        child: Text(
                          tpl.question,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: U.text, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Category Input
            Text('CATEGORY', style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: U.border),
              ),
              child: TextField(
                controller: _categoryController,
                style: GoogleFonts.outfit(color: U.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Study Habit, Campus Vibe, Food',
                  hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Question Input
            Text('QUESTION', style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: U.border),
              ),
              child: TextField(
                controller: _questionController,
                maxLines: 2,
                style: GoogleFonts.outfit(color: U.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Your peak productivity hours?',
                  hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Options list
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('OPTIONS', style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w700)),
                if (_optionControllers.length < 4)
                  GestureDetector(
                    onTap: _addOption,
                    child: Text('+ Add Option', style: GoogleFonts.outfit(color: U.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...List.generate(_optionControllers.length, (idx) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: U.border),
                ),
                child: Row(
                  children: [
                    Text('${idx + 1}.', style: GoogleFonts.outfit(color: U.sub, fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[idx],
                        style: GoogleFonts.outfit(color: U.text, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Option text...',
                          hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      GestureDetector(
                        onTap: () => _removeOption(idx),
                        child: Icon(Icons.remove_circle_outline_rounded, color: U.red, size: 18),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),

            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _createNewPoll,
              title: Text(
                'Reset votes (fresh poll)',
                style: GoogleFonts.outfit(color: U.text, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              activeColor: U.primary,
              onChanged: (v) => setState(() => _createNewPoll = v ?? true),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: U.primary,
                  foregroundColor: U.getContrastColor(U.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const UtopiaLoader(scale: 0.3)
                    : Text(
                        'Broadcast to Campus',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PEER GRID CARD (Refined Utopia Aesthetic)
// ─────────────────────────────────────────────────────────────────────────────
class _PeerGridCard extends StatefulWidget {
  const _PeerGridCard({
    required this.user,
    required this.vibe,
    required this.currentUid,
    required this.onTap,
    required this.onLongPress,
    required this.onWave,
  });

  final Map<String, dynamic> user;
  final CampusVibe? vibe;
  final String currentUid;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onWave;

  @override
  State<_PeerGridCard> createState() => _PeerGridCardState();
}

class _PeerGridCardState extends State<_PeerGridCard> {
  final FollowService _followService = FollowService();
  final PeopleInteractionService _interactionService = PeopleInteractionService();

  bool _loading = false;
  bool _hasWaved = false;

  @override
  void initState() {
    super.initState();
    _interactionService.hasWavedRecently(widget.user['uid'].toString()).then((waved) {
      if (mounted) setState(() => _hasWaved = waved);
    });
  }

  Future<void> _toggleFollow(FollowStatus status) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _followService.toggleFollow(widget.user['uid'].toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleWave() async {
    if (_hasWaved) return;
    setState(() => _hasWaved = true);
    widget.onWave();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.user['uid'].toString();
    final displayName = UtopiaApp.sanitizeDisplayName(
      (widget.user['displayName'] ?? 'Student').toString(),
    );
    final photoUrl = widget.user['photoUrl']?.toString();
    final branch = (widget.user['branch'] ?? '').toString().trim();
    final bio = (widget.user['bio'] ?? '').toString().trim();
    final isSuperuser = widget.user['role'] == 'superuser';
    final instagramId = (widget.user['instagramId'] ?? '').toString().trim();
    final wavesCount = (widget.user['wavesReceivedCount'] as num?)?.toInt() ?? 0;
    final isMe = uid == widget.currentUid;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.vibe != null ? U.primary.withValues(alpha: 0.35) : U.border,
            width: widget.vibe != null ? 1.0 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.vibe != null ? U.primary : Colors.transparent,
                      width: widget.vibe != null ? 1.6 : 0,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: U.primary.withValues(alpha: 0.12),
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                            style: GoogleFonts.outfit(
                              color: U.primary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
                if (widget.vibe != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: U.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: U.card, width: 1.5),
                      ),
                      child: Text(
                        widget.vibe!.emoji,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Display Name + Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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
                if (wavesCount > 0) ...[
                  const SizedBox(width: 3),
                  WaveCountBadge(count: wavesCount, compact: true),
                ],
              ],
            ),

            // Active vibe / Branch / Bio chip
            if (widget.vibe != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.vibe!.emoji} ${widget.vibe!.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: U.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else if (branch.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: U.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: U.border, width: 0.6),
                ),
                child: Text(
                  branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: U.sub,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else if (bio.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                bio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10,
                ),
              ),
            ],

            const Spacer(),

            // Actions Row: Wave + Follow
            if (!isMe)
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: GestureDetector(
                      onTap: _handleWave,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        decoration: BoxDecoration(
                          color: _hasWaved ? U.primary.withValues(alpha: 0.1) : U.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _hasWaved ? U.primary.withValues(alpha: 0.35) : U.border,
                            width: 0.8,
                          ),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _hasWaved ? '👋 Waved' : '👋 Wave',
                              maxLines: 1,
                              style: GoogleFonts.outfit(
                                color: _hasWaved ? U.primary : U.text,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),

                  Expanded(
                    flex: 5,
                    child: StreamBuilder<FollowStatus>(
                      stream: _followService.followStatusStream(widget.currentUid, uid),
                      builder: (context, statusSnap) {
                        final status = statusSnap.data ?? FollowStatus.notFollowing;
                        return _MinimalFollowButton(
                          status: status,
                          loading: _loading,
                          onTap: () => _toggleFollow(status),
                        );
                      },
                    ),
                  ),
                ],
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
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

// ─────────────────────────────────────────────────────────────────────────────
// PEER LIST TILE (Refined Streamlined Row)
// ─────────────────────────────────────────────────────────────────────────────
class _PeerListTile extends StatefulWidget {
  const _PeerListTile({
    required this.user,
    required this.vibe,
    required this.currentUid,
    required this.onTap,
    required this.onLongPress,
    required this.onWave,
  });

  final Map<String, dynamic> user;
  final CampusVibe? vibe;
  final String currentUid;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onWave;

  @override
  State<_PeerListTile> createState() => _PeerListTileState();
}

class _PeerListTileState extends State<_PeerListTile> {
  final FollowService _followService = FollowService();
  final PeopleInteractionService _interactionService = PeopleInteractionService();

  bool _loading = false;
  bool _hasWaved = false;

  @override
  void initState() {
    super.initState();
    _interactionService.hasWavedRecently(widget.user['uid'].toString()).then((waved) {
      if (mounted) setState(() => _hasWaved = waved);
    });
  }

  Future<void> _toggleFollow(FollowStatus status) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _followService.toggleFollow(widget.user['uid'].toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleWave() async {
    if (_hasWaved) return;
    setState(() => _hasWaved = true);
    widget.onWave();
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
    final wavesCount = (widget.user['wavesReceivedCount'] as num?)?.toInt() ?? 0;
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
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: U.primary.withValues(alpha: 0.12),
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
                if (widget.vibe != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: U.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: U.card, width: 1.5),
                      ),
                      child: Text(
                        widget.vibe!.emoji,
                        style: const TextStyle(fontSize: 9.5),
                      ),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
                      if (wavesCount > 0) ...[
                        const SizedBox(width: 5),
                        WaveCountBadge(count: wavesCount, compact: true),
                      ],
                    ],
                  ),
                  if (widget.vibe != null) ...[
                    const SizedBox(height: 3),
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
                    const SizedBox(height: 3),
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
            if (!isMe) ...[
              GestureDetector(
                onTap: _handleWave,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _hasWaved
                        ? U.primary.withValues(alpha: 0.1)
                        : U.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hasWaved
                          ? U.primary.withValues(alpha: 0.35)
                          : U.border,
                      width: 0.8,
                    ),
                  ),
                  child: const Text('👋', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              StreamBuilder<FollowStatus>(
                stream: _followService.followStatusStream(widget.currentUid, uid),
                builder: (context, statusSnap) {
                  final status = statusSnap.data ?? FollowStatus.notFollowing;
                  return _MinimalFollowButton(
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINIMAL FOLLOW BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _MinimalFollowButton extends StatelessWidget {
  const _MinimalFollowButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: bordered ? Border.all(color: U.border, width: 0.8) : null,
        ),
        child: Center(
          child: loading
              ? const UtopiaLoader(scale: 0.25)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.outfit(
                      color: fg,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SET VIBE BOTTOM SHEET (Refined Modal)
// ─────────────────────────────────────────────────────────────────────────────
class _SetVibeSheet extends StatefulWidget {
  const _SetVibeSheet({
    required this.initialVibe,
    required this.currentUserName,
    required this.currentUserPhoto,
    required this.onVibeSaved,
    required this.onVibeCleared,
  });

  final CampusVibe? initialVibe;
  final String currentUserName;
  final String? currentUserPhoto;
  final void Function(
    String emoji,
    String text,
    String? location,
    String? statusTag,
    int durationHours,
  ) onVibeSaved;
  final VoidCallback onVibeCleared;

  @override
  State<_SetVibeSheet> createState() => _SetVibeSheetState();
}

class _SetVibeSheetState extends State<_SetVibeSheet> {
  late final TextEditingController _customTextController;
  late String _selectedEmoji;
  String? _selectedLocation;
  String? _selectedStatusTag;
  int _selectedDurationHours = 24;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _selectedEmoji = widget.initialVibe?.emoji ?? '🎧';
    _customTextController = TextEditingController(text: widget.initialVibe?.text ?? '');
    _selectedLocation = widget.initialVibe?.location;
    _selectedStatusTag = widget.initialVibe?.statusTag;
    _selectedDurationHours = widget.initialVibe?.durationHours ?? 24;
    _customTextController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _customTextController.dispose();
    super.dispose();
  }

  void _save() {
    final text = _customTextController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    widget.onVibeSaved(
      _selectedEmoji,
      text,
      _selectedLocation,
      _selectedStatusTag,
      _selectedDurationHours,
    );
    Navigator.pop(context);
  }

  void _clear() {
    HapticFeedback.lightImpact();
    widget.onVibeCleared();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveVibe = widget.initialVibe != null;
    final currentText = _customTextController.text.trim();
    final isTextEmpty = currentText.isEmpty;
    final activePresets = PeopleInteractionService.categorizedVibes[_selectedCategory] ??
        PeopleInteractionService.presetVibes;

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
                    'Campus Vibe',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (hasActiveVibe)
                    TextButton(
                      onPressed: _clear,
                      child: Text(
                        'Clear Vibe',
                        style: GoogleFonts.outfit(
                          color: U.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                'Broadcast what you are currently working on with peers.',
                style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
              ),
              const SizedBox(height: 16),

              // ─── 1. Live Preview Card ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: U.primary.withValues(alpha: 0.3), width: 0.9),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: U.primary.withValues(alpha: 0.15),
                              backgroundImage: widget.currentUserPhoto != null &&
                                      widget.currentUserPhoto!.isNotEmpty
                                  ? CachedNetworkImageProvider(widget.currentUserPhoto!)
                                  : null,
                              child: widget.currentUserPhoto == null ||
                                      widget.currentUserPhoto!.isEmpty
                                  ? Text(
                                      widget.currentUserName.isEmpty
                                          ? 'U'
                                          : widget.currentUserName[0].toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        color: U.primary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: U.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: U.card, width: 1),
                                ),
                                child: Text(
                                  _selectedEmoji,
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.currentUserName,
                                style: GoogleFonts.outfit(
                                  color: U.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                isTextEmpty
                                    ? 'What are you working on or doing?'
                                    : '$_selectedEmoji $currentText',
                                style: GoogleFonts.outfit(
                                  color: isTextEmpty ? U.sub : U.primary,
                                  fontSize: 12.5,
                                  fontWeight: isTextEmpty ? FontWeight.w400 : FontWeight.w600,
                                  fontStyle: isTextEmpty ? FontStyle.italic : FontStyle.normal,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: U.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'PREVIEW',
                            style: GoogleFonts.outfit(
                              color: U.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedStatusTag != null ||
                        _selectedLocation != null ||
                        _selectedDurationHours != 24) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (_selectedStatusTag != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: U.surface,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: U.border),
                              ),
                              child: Text(
                                _selectedStatusTag!,
                                style: GoogleFonts.outfit(
                                  color: U.text,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (_selectedLocation != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: U.surface,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: U.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 11,
                                    color: U.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _selectedLocation!,
                                    style: GoogleFonts.outfit(
                                      color: U.text,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: U.surface,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: U.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, size: 11, color: U.sub),
                                const SizedBox(width: 3),
                                Text(
                                  _selectedDurationHours >= 24
                                      ? '24 Hours'
                                      : '${_selectedDurationHours}h',
                                  style: GoogleFonts.outfit(
                                    color: U.text,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ─── 2. Emoji Selector ──────────────────────────────────────────
              Text(
                'SELECT EMOJI',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: PeopleInteractionService.popularEmojis.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final emoji = PeopleInteractionService.popularEmojis[index];
                    final isSelected = _selectedEmoji == emoji;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedEmoji = emoji);
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? U.primary.withValues(alpha: 0.15) : U.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? U.primary : U.border,
                            width: isSelected ? 1.4 : 0.8,
                          ),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 18)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ─── 3. Custom Text Input ───────────────────────────────────────
              Text(
                'VIBE STATUS',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: U.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: U.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _selectedEmoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _customTextController,
                        autofocus: widget.initialVibe == null,
                        style: GoogleFonts.outfit(color: U.text, fontSize: 13.5),
                        maxLength: 40,
                        decoration: InputDecoration(
                          hintText: 'e.g. Grinding DSA in Lab 2',
                          hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                          border: InputBorder.none,
                          counterText: '${_customTextController.text.length}/40',
                          counterStyle: GoogleFonts.outfit(color: U.sub, fontSize: 10),
                        ),
                      ),
                    ),
                    if (_customTextController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        color: U.sub,
                        onPressed: () {
                          _customTextController.clear();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ─── 4. Availability Tag ────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'AVAILABILITY',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedStatusTag != null)
                    GestureDetector(
                      onTap: () => setState(() => _selectedStatusTag = null),
                      child: Text(
                        'Clear',
                        style: GoogleFonts.outfit(
                          color: U.sub,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: PeopleInteractionService.statusTags.map((tag) {
                  final isSelected = _selectedStatusTag == tag;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedStatusTag = isSelected ? null : tag;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? U.primary.withValues(alpha: 0.14) : U.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? U.primary : U.border,
                          width: isSelected ? 1.2 : 0.8,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: GoogleFonts.outfit(
                          color: isSelected ? U.primary : U.text,
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // ─── 5. Campus Location ────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'LOCATION',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedLocation != null)
                    GestureDetector(
                      onTap: () => setState(() => _selectedLocation = null),
                      child: Text(
                        'Clear',
                        style: GoogleFonts.outfit(
                          color: U.sub,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: PeopleInteractionService.campusSpots.map((spot) {
                  final isSelected = _selectedLocation == spot;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedLocation = isSelected ? null : spot;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? U.primary.withValues(alpha: 0.14)
                            : U.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? U.primary : U.border,
                          width: isSelected ? 1.2 : 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
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

              // ─── 6. Expiry Duration ─────────────────────────────────────────
              Text(
                'ACTIVE DURATION',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedDurationHours == dur
                                ? U.primary.withValues(alpha: 0.14)
                                : U.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedDurationHours == dur
                                  ? U.primary
                                  : U.border,
                              width: _selectedDurationHours == dur ? 1.2 : 0.8,
                            ),
                          ),
                          child: Text(
                            dur == 24 ? '24h' : '${dur}h',
                            style: GoogleFonts.outfit(
                              color: _selectedDurationHours == dur
                                  ? U.primary
                                  : U.text,
                              fontSize: 12,
                              fontWeight: _selectedDurationHours == dur
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (dur != 24) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 18),

              // ─── 7. Presets ────────────────────────────────────────────────
              Text(
                'PRESETS',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),

              // Category Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: ['All', 'Study', 'Build', 'Social', 'Chill'].map((cat) {
                    final isCatActive = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = cat);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isCatActive ? U.primary : U.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCatActive ? Colors.transparent : U.border,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: GoogleFonts.outfit(
                              color: isCatActive ? U.getContrastColor(U.primary) : U.text,
                              fontSize: 11.5,
                              fontWeight: isCatActive ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),

              // Preset list
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: activePresets.map((preset) {
                  final isSelected = _selectedEmoji == preset['emoji'] &&
                      _customTextController.text == preset['text'];
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedEmoji = preset['emoji']!;
                        _customTextController.text = preset['text']!;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? U.primary.withValues(alpha: 0.14) : U.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? U.primary : U.border,
                          width: isSelected ? 1.2 : 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(preset['emoji']!, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 5),
                          Text(
                            preset['text']!,
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
              const SizedBox(height: 20),

              // ─── 8. Save Button ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: U.primary,
                    foregroundColor: U.getContrastColor(U.primary),
                    disabledBackgroundColor: U.primary.withValues(alpha: 0.35),
                    disabledForegroundColor: U.getContrastColor(U.primary).withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: isTextEmpty ? null : _save,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedEmoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Broadcast Vibe',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// QUICK PEEK PROFILE SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _QuickPeekProfileSheet extends StatefulWidget {
  const _QuickPeekProfileSheet({
    required this.user,
    required this.vibe,
    required this.currentUid,
  });

  final Map<String, dynamic> user;
  final CampusVibe? vibe;
  final String currentUid;

  @override
  State<_QuickPeekProfileSheet> createState() => _QuickPeekProfileSheetState();
}

class _QuickPeekProfileSheetState extends State<_QuickPeekProfileSheet> {
  final FollowService _followService = FollowService();
  final PeopleInteractionService _interactionService = PeopleInteractionService();

  bool _loading = false;
  bool _hasWaved = false;

  @override
  void initState() {
    super.initState();
    _interactionService.hasWavedRecently(widget.user['uid'].toString()).then((waved) {
      if (mounted) setState(() => _hasWaved = waved);
    });
  }

  Future<void> _toggleFollow(FollowStatus status) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _followService.toggleFollow(widget.user['uid'].toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _wave() async {
    if (_hasWaved) return;
    setState(() => _hasWaved = true);
    await _interactionService.sendWave(widget.user['uid'].toString());
  }

  Future<void> _openChat([String? icebreaker]) async {
    final uid = widget.user['uid'].toString();
    final canChat = await _followService.canChat(widget.currentUid, uid);
    if (!mounted) return;
    if (!canChat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: U.card,
          content: Text(
            'You can message people you follow or who follow you.',
            style: GoogleFonts.outfit(color: U.text, fontSize: 13),
          ),
        ),
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
          initialText: icebreaker,
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

    return Container(
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: U.border, width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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

          // Header Profile Info
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: U.primary.withValues(alpha: 0.12),
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImageProvider(photoUrl)
                    : null,
                child: photoUrl == null || photoUrl.isEmpty
                    ? Text(
                        displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                        style: GoogleFonts.outfit(
                          color: U.primary,
                          fontSize: 20,
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
                    if (branch.isNotEmpty || instagramId.isNotEmpty || wavesCount > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
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
                  ],
                ),
              ),
            ],
          ),

          // Active Vibe Banner
          if (widget.vibe != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: U.primary.withValues(alpha: 0.3), width: 0.9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(widget.vibe!.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.vibe!.text,
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.vibe!.statusTag != null ||
                      widget.vibe!.location != null ||
                      widget.vibe!.durationHours != 24) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (widget.vibe!.statusTag != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: U.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: U.border),
                            ),
                            child: Text(
                              widget.vibe!.statusTag!,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (widget.vibe!.location != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: U.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: U.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 10.5,
                                  color: U.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  widget.vibe!.location!,
                                  style: GoogleFonts.outfit(
                                    color: U.text,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],

          if (bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              bio,
              style: GoogleFonts.outfit(color: U.text, fontSize: 13, height: 1.4),
            ),
          ],

          const SizedBox(height: 20),

          // Action Buttons
          if (!isMe)
            StreamBuilder<bool>(
              stream: _followService.canChatStream(widget.currentUid, uid),
              builder: (context, chatSnap) {
                final canChat = chatSnap.data ?? false;

                return Row(
                  children: [
                    Expanded(
                      flex: canChat ? 3 : 1,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: _hasWaved ? U.primary.withValues(alpha: 0.4) : U.border,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _wave,
                        child: Text(
                          _hasWaved ? '👋 Waved' : '👋 Wave',
                          style: GoogleFonts.outfit(
                            color: _hasWaved ? U.primary : U.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    if (canChat) ...[
                      Expanded(
                        flex: 3,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: U.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _openChat,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 15, color: U.text),
                              const SizedBox(width: 6),
                              Text('Chat', style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    Expanded(
                      flex: canChat ? 4 : 1,
                      child: StreamBuilder<FollowStatus>(
                        stream: _followService.followStatusStream(widget.currentUid, uid),
                        builder: (context, statusSnap) {
                          final status = statusSnap.data ?? FollowStatus.notFollowing;
                          final isFollowing = status == FollowStatus.following;

                          return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFollowing ? U.card : U.primary,
                              foregroundColor: isFollowing ? U.text : U.getContrastColor(U.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: isFollowing ? BorderSide(color: U.border) : BorderSide.none,
                              ),
                            ),
                            onPressed: () => _toggleFollow(status),
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
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDY BUDDY ROULETTE DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _StudyBuddyRouletteDialog extends StatefulWidget {
  const _StudyBuddyRouletteDialog({
    required this.user,
    required this.currentUid,
    required this.onWave,
  });

  final Map<String, dynamic> user;
  final String currentUid;
  final VoidCallback onWave;

  @override
  State<_StudyBuddyRouletteDialog> createState() => _StudyBuddyRouletteDialogState();
}

class _StudyBuddyRouletteDialogState extends State<_StudyBuddyRouletteDialog> {
  final FollowService _followService = FollowService();
  bool _waved = false;
  int _selectedCatIndex = 0;
  late String _selectedStarter;

  @override
  void initState() {
    super.initState();
    _selectedStarter = IcebreakerData.categories.first.starters.first;
  }

  void _selectCategory(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCatIndex = index;
      _selectedStarter = IcebreakerData.categories[index].starters.first;
    });
  }

  void _shufflePrompt() {
    HapticFeedback.mediumImpact();
    final cat = IcebreakerData.categories[_selectedCatIndex];
    final starters = cat.starters;
    final otherStarters = starters.where((s) => s != _selectedStarter).toList();
    if (otherStarters.isNotEmpty) {
      setState(() {
        _selectedStarter = otherStarters[Random().nextInt(otherStarters.length)];
      });
    }
  }

  void _copyPrompt() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _selectedStarter));
    showUtopiaSnackBar(context, message: 'Icebreaker prompt copied! 📋', tone: UtopiaSnackBarTone.success);
  }

  Future<void> _startChatWithIcebreaker() async {
    final uid = widget.user['uid'].toString();
    final canChat = await _followService.canChat(widget.currentUid, uid);
    if (!mounted) return;
    if (!canChat) {
      _copyPrompt();
      if (!_waved) {
        setState(() => _waved = true);
        widget.onWave();
      }
      showUtopiaSnackBar(
        context,
        message: 'Prompt copied & wave sent! Follow each other to chat.',
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
          initialText: _selectedStarter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = UtopiaApp.sanitizeDisplayName(
      (widget.user['displayName'] ?? 'Student').toString(),
    );
    final photoUrl = widget.user['photoUrl']?.toString();
    final branch = (widget.user['branch'] ?? '').toString().trim();
    final bio = (widget.user['bio'] ?? '').toString().trim();
    final wavesCount = (widget.user['wavesReceivedCount'] as num?)?.toInt() ?? 0;
    final categories = IcebreakerData.categories;
    final currentCat = categories[_selectedCatIndex.clamp(0, categories.length - 1)];

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: U.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: U.primary.withValues(alpha: 0.3), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: U.primary.withValues(alpha: 0.12),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.casino_outlined, color: U.primary, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                'Study Match',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Serendipitous campus peer connection',
                style: GoogleFonts.outfit(color: U.sub, fontSize: 11.5),
              ),
              const SizedBox(height: 14),

              CircleAvatar(
                radius: 30,
                backgroundColor: U.primary.withValues(alpha: 0.12),
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImageProvider(photoUrl)
                    : null,
                child: photoUrl == null || photoUrl.isEmpty
                    ? Text(
                        displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                        style: GoogleFonts.outfit(color: U.primary, fontSize: 20, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                style: GoogleFonts.outfit(color: U.text, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (branch.isNotEmpty || wavesCount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (branch.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: U.border, width: 0.6),
                        ),
                        child: Text(
                          branch,
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (wavesCount > 0)
                      WaveCountBadge(count: wavesCount, compact: true),
                  ],
                ),
              ],
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 11.5),
                ),
              ],

              const SizedBox(height: 16),

              // ── Interest-Driven Icebreaker Selector ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SELECT AN ICEBREAKER 💡',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  GestureDetector(
                    onTap: _shufflePrompt,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: U.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shuffle_rounded, size: 11, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text(
                            'Shuffle',
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Horizontal Category Chips
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = index == _selectedCatIndex;
                    return GestureDetector(
                      onTap: () => _selectCategory(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? cat.color.withValues(alpha: 0.15) : U.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? cat.color : U.border,
                            width: isSelected ? 1.3 : 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cat.emoji, style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 4),
                            Text(
                              cat.title,
                              style: GoogleFonts.outfit(
                                color: isSelected ? cat.color : U.text,
                                fontSize: 10.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),

              // Active Selected Prompt Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: currentCat.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: currentCat.color.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${currentCat.emoji} ${currentCat.title}',
                          style: GoogleFonts.outfit(
                            color: currentCat.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _copyPrompt,
                          child: Icon(Icons.copy_rounded, size: 14, color: U.sub),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"$_selectedStarter"',
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Other quick sentences in this category
              ...currentCat.starters.where((s) => s != _selectedStarter).take(2).map((starter) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedStarter = starter);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: U.border.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 12, color: U.sub),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              starter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: U.border),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close', style: GoogleFonts.outfit(color: U.sub, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _waved ? const Color(0xFFF59E0B) : U.card,
                        foregroundColor: _waved ? Colors.white : U.text,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _waved ? Colors.transparent : U.border),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (!_waved) {
                          setState(() => _waved = true);
                          widget.onWave();
                        }
                      },
                      child: Text(
                        _waved ? 'Waved ✨' : 'Say Hi 👋',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Chat with prompt button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: U.primary,
                    foregroundColor: U.getContrastColor(U.primary),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _startChatWithIcebreaker,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                  label: Text(
                    'Chat with this Icebreaker 💬',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
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

// ─────────────────────────────────────────────────────────────────────────────
// SKELETON LOADING
// ─────────────────────────────────────────────────────────────────────────────
class _MinimalPeopleSkeleton extends StatelessWidget {
  const _MinimalPeopleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.80,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: U.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: U.border),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: const [
                SkeletonBox(height: 48, width: 48, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 13, width: 90, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(height: 10, width: 60, radius: 5),
                Spacer(),
                SkeletonBox(height: 28, width: double.infinity, radius: 10),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(
                begin: 0.3,
                end: 0.8,
                duration: 800.ms,
                delay: (index * 100).ms,
              );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
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
            const SizedBox(height: 14),
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
              style: GoogleFonts.outfit(color: U.sub, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SET USER BRANCH BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _SetUserBranchSheet extends StatefulWidget {
  const _SetUserBranchSheet({
    required this.currentUid,
    required this.onBranchSaved,
  });

  final String currentUid;
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
        showUtopiaSnackBar(context, message: 'Failed to update branch: $e', tone: UtopiaSnackBarTone.error);
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
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
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
              const SizedBox(height: 14),

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
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _filterController.clear();
                          setState(() => _query = '');
                        },
                        child: Icon(Icons.close_rounded, color: U.sub, size: 16),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final branch = filtered[index];
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(
                        branch,
                        style: GoogleFonts.outfit(color: U.text, fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: U.sub, size: 18),
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
