// lib/widgets/sciwordle_profile_card.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/sciwordle_model.dart';
import '../screens/sciwordle_screen.dart';
import '../services/sciwordle_service.dart';
import '../theme/m3_expressive_theme.dart';
import 'sciwordle_badge.dart';

/// A card displaying a student's SciWordle weekly league score, streak, and rank title.
/// Permanently visible in profile details (cannot be hidden).
class SciwordleProfileCard extends StatefulWidget {
  const SciwordleProfileCard({
    super.key,
    required this.uid,
    this.initialScore,
    this.initialStreak,
    this.initialBestStreak,
    this.initialTitle,
  });

  final String uid;
  final int? initialScore;
  final int? initialStreak;
  final int? initialBestStreak;
  final String? initialTitle;

  @override
  State<SciwordleProfileCard> createState() => _SciwordleProfileCardState();
}

class _SciwordleProfileCardState extends State<SciwordleProfileCard> {
  final SciwordleService _service = SciwordleService();
  SciwordlePlayerScore? _score;

  @override
  void initState() {
    super.initState();
    _fetchScore();
  }

  Future<void> _fetchScore() async {
    try {
      final score = await _service.fetchUserScore(widget.uid);
      if (mounted) {
        setState(() {
          _score = score;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;

    final totalScore = _score?.totalScore ?? widget.initialScore ?? 0;
    final streak = _score?.streak ?? widget.initialStreak ?? 0;
    final bestStreak = _score?.bestStreak ?? widget.initialBestStreak ?? 0;
    final gamesPlayed = _score?.gamesPlayed ?? 0;

    String? title = widget.initialTitle;
    if (title == null || title.isEmpty) {
      if (totalScore > 0) {
        title = 'SOLVER';
      }
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: M3Shapes.cardRadius,
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.25),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.08 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      size: 16,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SCIWORDLE LEAGUE',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF6366F1),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              if (title != null && title.isNotEmpty)
                SciwordleBadge(title: title),
            ],
          ),

          const SizedBox(height: 14),

          // 3-Column Metrics Grid
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: U.surfaceContainerLowest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: U.outlineVariant.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricColumn(
                  label: 'WEEKLY SCORE',
                  value: '$totalScore',
                  unit: 'pts',
                  color: U.primary,
                ),
                Container(
                  height: 32,
                  width: 1,
                  color: U.outlineVariant.withValues(alpha: 0.35),
                ),
                _buildMetricColumn(
                  label: 'STREAK',
                  value: '$streak',
                  unit: 'days 🔥',
                  color: const Color(0xFFFB923C),
                ),
                Container(
                  height: 32,
                  width: 1,
                  color: U.outlineVariant.withValues(alpha: 0.35),
                ),
                _buildMetricColumn(
                  label: 'BEST STREAK',
                  value: '$bestStreak',
                  unit: 'days 🏆',
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Footer note with tap to play
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SciwordleScreen()),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    gamesPlayed > 0
                        ? '$gamesPlayed played • Resets Mon 00:00'
                        : 'Resets weekly • Mon 00:00 IST',
                    style: GoogleFonts.robotoFlex(
                      color: U.sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Play SciWordle',
                        style: GoogleFonts.robotoFlex(
                          color: const Color(0xFF6366F1),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: Color(0xFF6366F1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.robotoFlex(
            color: U.sub,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.outfit(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              unit,
              style: GoogleFonts.robotoFlex(
                color: U.text,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
