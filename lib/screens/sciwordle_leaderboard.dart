// lib/screens/sciwordle_leaderboard.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../main.dart';
import '../models/sciwordle_model.dart';
import '../services/sciwordle_service.dart';
import '../widgets/utopia_loader.dart';

class SciwordleLeaderboardScreen extends StatefulWidget {
  const SciwordleLeaderboardScreen({super.key});

  @override
  State<SciwordleLeaderboardScreen> createState() =>
      _SciwordleLeaderboardScreenState();
}

class _SciwordleLeaderboardScreenState
    extends State<SciwordleLeaderboardScreen> {
  final SciwordleService _service = SciwordleService();
  bool _loading = true;
  String? _error;
  List<SciwordleLeaderboardEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _service.fetchLeaderboard();
      if (mounted) {
        setState(() {
          _entries = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load leaderboard';
          _loading = false;
        });
      }
    }
  }

  String? _getTitleForEntry(SciwordleLeaderboardEntry entry, int rank) {
    if (_entries.isEmpty) return null;

    final isMaxStreak = entry.streak > 0 &&
        _entries.every((e) => entry.streak >= e.streak);

    if (rank == 1 && isMaxStreak) return 'ALPHA';
    if (rank == 1) return 'PRIME';
    if (isMaxStreak) return 'FIRE';
    if (rank == 2) return 'TOP 2';
    if (rank == 3) return 'TOP 3';
    return null;
  }

  Color _getTitleColor(String title) {
    switch (title) {
      case 'ALPHA':
        return const Color(0xFFEF4444);
      case 'PRIME':
        return const Color(0xFFF59E0B);
      case 'FIRE':
        return const Color(0xFFFB923C);
      case 'TOP 2':
        return const Color(0xFF38BDF8);
      case 'TOP 3':
        return const Color(0xFFC084FC);
      default:
        return U.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isDark = appThemeNotifier.value.isDark;

    int currentUserRank = -1;
    SciwordleLeaderboardEntry? currentUserEntry;

    for (int i = 0; i < _entries.length; i++) {
      if (_entries[i].uid == currentUid) {
        currentUserRank = i + 1;
        currentUserEntry = _entries[i];
        break;
      }
    }

    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SciWordle Hall of Fame',
          style: GoogleFonts.robotoFlex(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: U.text,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: UtopiaLoader(scale: 0.8))
          : _error != null
              ? _buildErrorView()
              : _entries.isEmpty
                  ? _buildEmptyView()
                  : Stack(
                      children: [
                        RefreshIndicator(
                          color: U.primary,
                          backgroundColor: U.surface,
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              20,
                              8,
                              20,
                              currentUserEntry != null ? 120 : 40,
                            ),
                            children: [
                              // Top 3 Podium
                              if (_entries.length >= 3) ...[
                                _buildPodium(isDark),
                                const SizedBox(height: 28),
                              ],

                              // Section Header
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 12),
                                child: Text(
                                  'ALL PLAYERS',
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: U.sub,
                                  ),
                                ),
                              ),

                              // Ranked list
                              ..._entries.asMap().entries.map((item) {
                                final rank = item.key + 1;
                                final entry = item.value;
                                final isMe = entry.uid == currentUid;
                                final title = _getTitleForEntry(entry, rank);

                                return _buildLeaderboardRow(
                                  rank: rank,
                                  entry: entry,
                                  isMe: isMe,
                                  title: title,
                                  isDark: isDark,
                                );
                              }),
                            ],
                          ),
                        ),

                        // Floating Current User Sticky Bottom Card
                        if (currentUserEntry != null)
                          Positioned(
                            bottom: 16,
                            left: 20,
                            right: 20,
                            child: _buildCurrentUserCard(
                              rank: currentUserRank,
                              entry: currentUserEntry,
                              title: _getTitleForEntry(
                                currentUserEntry,
                                currentUserRank,
                              ),
                              isDark: isDark,
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _buildPodium(bool isDark) {
    final first = _entries[0];
    final second = _entries[1];
    final third = _entries[2];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events_rounded, color: const Color(0xFFFBBF24), size: 20),
              const SizedBox(width: 8),
              Text(
                'TOP SCIENTISTS',
                style: GoogleFonts.robotoFlex(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: U.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Rank 2 (Silver)
              _buildPodiumStep(
                entry: second,
                rank: 2,
                accentColor: const Color(0xFF94A3B8),
                badgeColor: const Color(0xFF64748B),
                pillarHeight: 110,
                isDark: isDark,
              ),

              // Rank 1 (Gold)
              _buildPodiumStep(
                entry: first,
                rank: 1,
                accentColor: const Color(0xFFF59E0B),
                badgeColor: const Color(0xFFD97706),
                pillarHeight: 145,
                isDark: isDark,
              ),

              // Rank 3 (Bronze)
              _buildPodiumStep(
                entry: third,
                rank: 3,
                accentColor: const Color(0xFFD97706),
                badgeColor: const Color(0xFFB45309),
                pillarHeight: 90,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildPodiumStep({
    required SciwordleLeaderboardEntry entry,
    required int rank,
    required Color accentColor,
    required Color badgeColor,
    required double pillarHeight,
    required bool isDark,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Crown / Medal Icon
          if (rank == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('👑', style: TextStyle(fontSize: 22)),
            ),

          // User Avatar Circle
          Container(
            width: rank == 1 ? 52 : 44,
            height: rank == 1 ? 52 : 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.15),
              border: Border.all(color: accentColor, width: rank == 1 ? 2.0 : 1.5),
            ),
            child: Center(
              child: Text(
                entry.name.isNotEmpty ? entry.name[0].toUpperCase() : 'S',
                style: GoogleFonts.outfit(
                  fontSize: rank == 1 ? 20 : 17,
                  fontWeight: FontWeight.w800,
                  color: U.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Name
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.robotoFlex(
              fontSize: rank == 1 ? 13 : 12,
              fontWeight: FontWeight.w700,
              color: U.text,
            ),
          ),
          const SizedBox(height: 2),

          // Score
          Text(
            '${entry.totalScore} pts',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 8),

          // Podium Pillar
          Container(
            height: pillarHeight,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: isDark ? 0.35 : 0.2),
                  accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (entry.streak > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 2),
                      Text(
                        '${entry.streak}',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFFB923C),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow({
    required int rank,
    required SciwordleLeaderboardEntry entry,
    required bool isMe,
    required String? title,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? U.primary.withValues(alpha: isDark ? 0.2 : 0.12)
            : U.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isMe
              ? U.primary.withValues(alpha: 0.5)
              : U.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
          width: isMe ? 1.4 : 0.8,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? U.primary : U.sub,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Initial Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isMe
                  ? U.primary.withValues(alpha: 0.25)
                  : U.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                entry.name.isNotEmpty ? entry.name[0].toUpperCase() : 'S',
                style: GoogleFonts.robotoFlex(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isMe ? U.primary : U.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name and Title Tag
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.robotoFlex(
                          fontSize: 14,
                          fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                          color: U.text,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: U.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'YOU',
                          style: GoogleFonts.robotoFlex(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (title != null) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: _getTitleColor(title).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _getTitleColor(title).withValues(alpha: 0.4),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      title,
                      style: GoogleFonts.robotoFlex(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: _getTitleColor(title),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Streak flame
          if (entry.streak > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFB923C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.streak}',
                    style: GoogleFonts.robotoFlex(
                      color: const Color(0xFFFB923C),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Total Score
          Text(
            '${entry.totalScore}',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: U.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentUserCard({
    required int rank,
    required SciwordleLeaderboardEntry entry,
    required String? title,
    required bool isDark,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: U.surfaceContainerHigh.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: U.primary.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: U.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your Current Standing',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: U.sub,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          entry.name,
                          style: GoogleFonts.robotoFlex(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: U.text,
                          ),
                        ),
                        if (title != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: GoogleFonts.robotoFlex(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: _getTitleColor(title),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (entry.streak > 0) ...[
                Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 3),
                    Text(
                      '${entry.streak}',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFB923C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
              ],
              Text(
                '${entry.totalScore} pts',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: U.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.leaderboard_outlined, size: 54, color: U.dim),
          const SizedBox(height: 16),
          Text(
            'No Scores Yet',
            style: GoogleFonts.robotoFlex(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: U.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to solve today\'s SciWordle puzzle!',
            style: GoogleFonts.robotoFlex(fontSize: 13.5, color: U.sub),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48, color: U.red),
          const SizedBox(height: 16),
          Text(
            'Failed to load leaderboard',
            style: GoogleFonts.robotoFlex(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: U.text,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _load,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
