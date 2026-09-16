// lib/screens/sciwordle_stats_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/sciwordle_model.dart';
import '../services/sciwordle_service.dart';
import '../widgets/utopia_loader.dart';

class SciwordleStatsScreen extends StatefulWidget {
  const SciwordleStatsScreen({super.key});

  @override
  State<SciwordleStatsScreen> createState() => _SciwordleStatsScreenState();
}

class _SciwordleStatsScreenState extends State<SciwordleStatsScreen> {
  final SciwordleService _service = SciwordleService();
  bool _loading = true;
  SciwordlePlayerScore? _playerScore;
  Timer? _countdownTimer;
  Duration _timeUntilNext = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _timeUntilNext = _service.durationUntilNextSlot;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _timeUntilNext = _service.durationUntilNextSlot;
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final score = await _service.fetchPlayerScore();
      if (mounted) {
        setState(() {
          _playerScore = score;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;

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
          'SciWordle Stats',
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
          : RefreshIndicator(
              color: U.primary,
              backgroundColor: U.surface,
              onRefresh: _loadStats,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // Total Score Banner
                  _buildTotalScoreBanner(isDark),

                  const SizedBox(height: 18),

                  // 4-Card Performance Grid
                  _buildKeyMetricsGrid(isDark),

                  const SizedBox(height: 24),

                  // Guess Distribution Card
                  _buildGuessDistributionCard(isDark),

                  const SizedBox(height: 24),

                  // Next Puzzle Countdown Card
                  _buildCountdownCard(isDark),

                  const SizedBox(height: 36),
                ],
              ),
            ),
    );
  }

  Widget _buildTotalScoreBanner(bool isDark) {
    final score = _playerScore?.totalScore ?? 0;
    final lastScore = _playerScore?.lastScore ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            U.primary.withValues(alpha: isDark ? 0.28 : 0.16),
            U.teal.withValues(alpha: isDark ? 0.14 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: U.primary.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: U.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(Icons.military_tech_rounded, color: U.primary, size: 34),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL POINTS',
                  style: GoogleFonts.robotoFlex(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: U.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$score pts',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: U.text,
                    letterSpacing: -0.5,
                  ),
                ),
                if (lastScore > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+$lastScore from last puzzle',
                    style: GoogleFonts.robotoFlex(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: U.sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _buildKeyMetricsGrid(bool isDark) {
    final played = _playerScore?.gamesPlayed ?? 0;
    final dist = _playerScore?.guessDistribution ?? {};
    final wins = dist.values.fold<int>(0, (sum, val) => sum + val);
    final winPercent = played > 0 ? ((wins / played) * 100).round() : 0;
    final streak = _playerScore?.streak ?? 0;
    final bestStreak = _playerScore?.bestStreak ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.45,
      children: [
        _buildMetricTile(
          label: 'Played',
          value: '$played',
          icon: Icons.sports_esports_outlined,
          color: U.blue,
          isDark: isDark,
        ),
        _buildMetricTile(
          label: 'Win Rate',
          value: '$winPercent%',
          icon: Icons.trending_up_rounded,
          color: const Color(0xFF10B981),
          isDark: isDark,
        ),
        _buildMetricTile(
          label: 'Current Streak',
          value: '$streak',
          icon: Icons.local_fire_department_rounded,
          color: const Color(0xFFFB923C),
          isDark: isDark,
        ),
        _buildMetricTile(
          label: 'Best Streak',
          value: '$bestStreak',
          icon: Icons.emoji_events_outlined,
          color: const Color(0xFFFBBF24),
          isDark: isDark,
        ),
      ],
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.robotoFlex(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: U.sub,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: U.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuessDistributionCard(bool isDark) {
    final dist = _playerScore?.guessDistribution ?? {
      '1': 0,
      '2': 0,
      '3': 0,
      '4': 0,
      '5': 0,
      '6': 0,
    };
    final maxCount = dist.values.isEmpty ? 1 : max(1, dist.values.reduce(max));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Guess Distribution',
                style: GoogleFonts.robotoFlex(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: U.text,
                ),
              ),
              Icon(Icons.bar_chart_rounded, color: U.primary, size: 20),
            ],
          ),
          const SizedBox(height: 18),
          ...List.generate(6, (index) {
            final attempt = '${index + 1}';
            final count = dist[attempt] ?? 0;
            final isMax = count > 0 && count == maxCount;
            final fraction = (count / maxCount).clamp(0.08, 1.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      attempt,
                      style: GoogleFonts.robotoFlex(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: U.sub,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final barWidth = count == 0 ? 32.0 : constraints.maxWidth * fraction;

                        return Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            width: barWidth,
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              gradient: isMax
                                  ? LinearGradient(
                                      colors: [
                                        U.primary,
                                        U.primary.withValues(alpha: 0.85),
                                      ],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        U.surfaceContainerHighest,
                                        U.surfaceContainerHighest.withValues(alpha: 0.7),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$count',
                              style: GoogleFonts.robotoFlex(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isMax ? Colors.white : U.text,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildCountdownCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: U.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: U.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.timer_outlined, color: U.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXT PUZZLE IN',
                  style: GoogleFonts.robotoFlex(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: U.sub,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(_timeUntilNext),
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: U.text,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}
