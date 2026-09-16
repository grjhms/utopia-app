// lib/screens/how_to_play_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

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
          'How to Play',
          style: GoogleFonts.robotoFlex(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: U.text,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Hero Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    U.primary.withValues(alpha: isDark ? 0.25 : 0.15),
                    U.teal.withValues(alpha: isDark ? 0.12 : 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: U.primary.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Icon(Icons.psychology_rounded, color: U.primary, size: 30),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guess the Science Word',
                          style: GoogleFonts.robotoFlex(
                            color: U.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Each day features an exciting scientific riddle. You get 6 attempts to uncover the mystery word. Each guess must be a valid English word matching the required length.',
                          style: GoogleFonts.robotoFlex(
                            color: U.sub,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),

            const SizedBox(height: 20),

            // Visual Example Section
            _SectionCard(
              title: 'Color Clues',
              icon: Icons.palette_outlined,
              iconColor: U.blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'After each guess, the color of the tiles will change to show how close your guess was to the word.',
                    style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  _buildExampleRow(
                    letters: ['P', 'L', 'A', 'N', 'T'],
                    highlightIndex: 0,
                    statusColor: const Color(0xFF10B981),
                    description: 'P is in the word and in the correct spot.',
                    badge: 'CORRECT',
                  ),
                  const SizedBox(height: 14),
                  _buildExampleRow(
                    letters: ['S', 'O', 'L', 'A', 'R'],
                    highlightIndex: 2,
                    statusColor: const Color(0xFFF59E0B),
                    description: 'L is in the word but in the wrong spot.',
                    badge: 'PRESENT',
                  ),
                  const SizedBox(height: 14),
                  _buildExampleRow(
                    letters: ['O', 'R', 'B', 'I', 'T'],
                    highlightIndex: 3,
                    statusColor: const Color(0xFF64748B),
                    description: 'I is not in the word in any spot.',
                    badge: 'ABSENT',
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Scoring Breakdown
            _SectionCard(
              title: 'Scoring System (3x Multiplier)',
              icon: Icons.stars_rounded,
              iconColor: const Color(0xFFFBBF24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Higher points are awarded the earlier you solve the puzzle:',
                    style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ScorePill(attempt: '1st', points: '18 pts', color: const Color(0xFF10B981)),
                      _ScorePill(attempt: '2nd', points: '15 pts', color: const Color(0xFF34D399)),
                      _ScorePill(attempt: '3rd', points: '12 pts', color: const Color(0xFF60A5FA)),
                      _ScorePill(attempt: '4th', points: '9 pts', color: const Color(0xFF818CF8)),
                      _ScorePill(attempt: '5th', points: '6 pts', color: const Color(0xFFA78BFA)),
                      _ScorePill(attempt: '6th', points: '3 pts', color: const Color(0xFFF472B6)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: U.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.local_fire_department_rounded, color: const Color(0xFFFB923C), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '+2 Streak Bonus points added for every game completed, even if you run out of guesses!',
                            style: GoogleFonts.robotoFlex(
                              color: U.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Streak System
            _SectionCard(
              title: 'Streak Retention',
              icon: Icons.flash_on_rounded,
              iconColor: const Color(0xFFF97316),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BulletItem(text: 'Every game you finish increases your daily streak by 1.'),
                  _BulletItem(text: 'Failing all 6 tries still counts as participating and keeps your streak moving.'),
                  _BulletItem(text: 'Missed days pause your streak instead of resetting to zero.'),
                ],
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Titles System
            _SectionCard(
              title: 'Elite Titles',
              icon: Icons.military_tech_rounded,
              iconColor: const Color(0xFFA855F7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compete on the leaderboard to earn prestigious titles displayed next to your name:',
                    style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
                  ),
                  const SizedBox(height: 12),
                  _TitleRow(tag: 'ALPHA', desc: 'Rank #1 in score AND Rank #1 in streak simultaneously', color: const Color(0xFFEF4444)),
                  _TitleRow(tag: 'PRIME', desc: 'Rank #1 on the all-time Total Score leaderboard', color: const Color(0xFFF59E0B)),
                  _TitleRow(tag: 'FIRE', desc: 'Rank #1 in active consecutive streak', color: const Color(0xFFFB923C)),
                  _TitleRow(tag: 'TOP 2', desc: 'Rank #2 in total score', color: const Color(0xFF38BDF8)),
                  _TitleRow(tag: 'TOP 3', desc: 'Rank #3 in total score', color: const Color(0xFFC084FC)),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

            const SizedBox(height: 24),

            // Footer note
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: U.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: U.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, color: U.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Puzzles update dynamically throughout the day',
                      style: GoogleFonts.robotoFlex(
                        color: U.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleRow({
    required List<String> letters,
    required int highlightIndex,
    required Color statusColor,
    required String description,
    required String badge,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ...letters.asMap().entries.map((entry) {
              final idx = entry.key;
              final letter = entry.value;
              final isHighlighted = idx == highlightIndex;

              return Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: isHighlighted ? statusColor : U.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isHighlighted ? statusColor : U.outlineVariant.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isHighlighted ? Colors.white : U.text,
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: GoogleFonts.robotoFlex(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.robotoFlex(
                  color: U.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final String attempt;
  final String points;
  final Color color;

  const _ScorePill({
    required this.attempt,
    required this.points,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            attempt,
            style: GoogleFonts.robotoFlex(
              color: U.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Container(width: 3, height: 3, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            points,
            style: GoogleFonts.robotoFlex(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;

  const _BulletItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: U.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.robotoFlex(
                color: U.sub,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String tag;
  final String desc;
  final Color color;

  const _TitleRow({
    required this.tag,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
            ),
            child: Text(
              tag,
              style: GoogleFonts.robotoFlex(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              desc,
              style: GoogleFonts.robotoFlex(
                color: U.sub,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
