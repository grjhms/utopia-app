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
/// Collapsed by default, smoothly expands on user interaction.
class SciwordleProfileCard extends StatefulWidget {
  const SciwordleProfileCard({
    super.key,
    required this.uid,
    this.initialScore,
    this.initialStreak,
    this.initialBestStreak,
    this.initialTitle,
    this.initiallyExpanded = false,
  });

  final String uid;
  final int? initialScore;
  final int? initialStreak;
  final int? initialBestStreak;
  final String? initialTitle;
  final bool initiallyExpanded;

  @override
  State<SciwordleProfileCard> createState() => _SciwordleProfileCardState();
}

class _SciwordleProfileCardState extends State<SciwordleProfileCard> {
  final SciwordleService _service = SciwordleService();
  SciwordlePlayerScore? _score;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
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
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: M3Shapes.cardRadius,
        border: Border.all(
          color: U.border.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: M3Shapes.cardRadius,
        child: InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: M3Shapes.cardRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row (Always visible, acts as expand/collapse trigger)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 17,
                      color: U.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SCIWORDLE LEAGUE',
                      style: GoogleFonts.outfit(
                        color: U.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: U.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: U.primary.withValues(alpha: 0.28),
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
                    const Spacer(),
                    if (title != null && title.isNotEmpty)
                      SciwordleBadge(
                        title: title,
                        compact: true,
                      ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: U.sub,
                      ),
                    ),
                  ],
                ),
              ),

              // Expandable Body
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: _isExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 3-Column Metrics Row
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: U.bg.withValues(alpha: 0.7),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  gamesPlayed > 0
                                      ? '$gamesPlayed played • Resets Mon'
                                      : 'Resets weekly • Mon 00:00',
                                  style: GoogleFonts.outfit(
                                    color: U.sub,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const SciwordleScreen()),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Play SciWordle',
                                          style: GoogleFonts.outfit(
                                            color: U.primary,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 10,
                                          color: U.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
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
          style: GoogleFonts.outfit(
            color: U.sub,
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
                color: U.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              unit,
              style: GoogleFonts.outfit(
                color: U.sub,
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
