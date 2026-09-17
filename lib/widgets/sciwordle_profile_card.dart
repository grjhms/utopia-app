// lib/widgets/sciwordle_profile_card.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/sciwordle_model.dart';
import '../screens/sciwordle_screen.dart';
import '../services/sciwordle_service.dart';
import '../theme/m3_expressive_theme.dart';
import 'sciwordle_badge.dart';

/// Minimalist, clean SciWordle performance card for user profiles.
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: M3Shapes.largeRadius,
        border: Border.all(
          color: U.border.withValues(alpha: 0.6),
          width: 0.8,
        ),
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
                  const Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: Color(0xFFA1A1AA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SCIWORDLE LEAGUE',
                    style: GoogleFonts.robotoFlex(
                      color: const Color(0xFFA1A1AA),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              if (title != null && title.isNotEmpty)
                SciwordleBadge(title: title),
            ],
          ),

          const SizedBox(height: 12),

          // 3-Column Metrics Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: U.bg,
              borderRadius: M3Shapes.mediumRadius,
              border: Border.all(
                color: U.border.withValues(alpha: 0.4),
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
                ),
                Container(
                  height: 28,
                  width: 0.8,
                  color: U.border.withValues(alpha: 0.4),
                ),
                _buildMetricColumn(
                  label: 'STREAK',
                  value: '$streak',
                  unit: 'days',
                ),
                Container(
                  height: 28,
                  width: 0.8,
                  color: U.border.withValues(alpha: 0.4),
                ),
                _buildMetricColumn(
                  label: 'BEST STREAK',
                  value: '$bestStreak',
                  unit: 'days',
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

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
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    gamesPlayed > 0
                        ? '$gamesPlayed played • Resets Mon'
                        : 'Resets weekly • Mon 00:00',
                    style: GoogleFonts.robotoFlex(
                      color: const Color(0xFF71717A),
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
                          color: const Color(0xFFFFFFFF),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: Color(0xFFFFFFFF),
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
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.robotoFlex(
            color: const Color(0xFFA1A1AA),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.outfit(
                color: const Color(0xFFFFFFFF),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              unit,
              style: GoogleFonts.robotoFlex(
                color: const Color(0xFF71717A),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
