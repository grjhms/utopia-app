import 'package:flutter_test/flutter_test.dart';
import 'package:utopia_app/models/sciwordle_model.dart';
import 'package:utopia_app/services/sciwordle_service.dart';

void main() {
  group('Sciwordle Weekly Reset & WeekKey Tests', () {
    test('getCurrentWeekKeyIST format is YYYY-W-MM-DD', () {
      final weekKey = SciwordleService.getCurrentWeekKeyIST();
      expect(weekKey, matches(r'^\d{4}-W-\d{2}-\d{2}$'));
    });

    test('getCurrentWeekKeyIST calculates Monday correctly', () {
      final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final daysFromMonday = (now.weekday - 1) % 7;
      final monday = now.subtract(Duration(days: daysFromMonday));

      final expectedY = monday.year.toString().padLeft(4, '0');
      final expectedM = monday.month.toString().padLeft(2, '0');
      final expectedD = monday.day.toString().padLeft(2, '0');
      final expected = '$expectedY-W-$expectedM-$expectedD';

      expect(SciwordleService.getCurrentWeekKeyIST(), equals(expected));
    });

    test('computeTitle assigns correct titles based on rank and streak', () {
      // Rank 1 and max streak
      expect(
        SciwordleService.computeTitle(rank: 1, streak: 5, maxStreak: 5, totalScore: 100),
        equals('ALPHA'),
      );

      // Rank 1 but not max streak
      expect(
        SciwordleService.computeTitle(rank: 1, streak: 3, maxStreak: 5, totalScore: 100),
        equals('PRIME'),
      );

      // Rank 4 but is highest streak user
      expect(
        SciwordleService.computeTitle(
          rank: 4,
          streak: 5,
          maxStreak: 5,
          totalScore: 80,
          isHighestStreakUser: true,
          rank1Streak: 2,
        ),
        equals('FIRE'),
      );

      // Rank 2
      expect(
        SciwordleService.computeTitle(rank: 2, streak: 2, maxStreak: 5, totalScore: 90),
        equals('TOP 2'),
      );

      // Rank 3
      expect(
        SciwordleService.computeTitle(rank: 3, streak: 2, maxStreak: 5, totalScore: 85),
        equals('TOP 3'),
      );

      // Rank 8 - should be null (no generic multi-user badge)
      expect(
        SciwordleService.computeTitle(rank: 8, streak: 2, maxStreak: 5, totalScore: 50),
        isNull,
      );

      // Rank 15
      expect(
        SciwordleService.computeTitle(rank: 15, streak: 2, maxStreak: 5, totalScore: 30),
        isNull,
      );

      // Score 0 has no title even if rank 1
      expect(
        SciwordleService.computeTitle(rank: 1, streak: 5, maxStreak: 5, totalScore: 0),
        isNull,
      );
    });

    test('computeLeaderboardTitles ensures every badge is unique to at most 1 user (everyone on streak 1)', () {
      final entries = [
        const SciwordleLeaderboardEntry(uid: 'u1', name: 'Ram Vinay', totalScore: 40, streak: 1, bestStreak: 1, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u2', name: 'Abhi Ram', totalScore: 40, streak: 1, bestStreak: 1, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u3', name: 'John Moses', totalScore: 28, streak: 1, bestStreak: 1, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u4', name: 'Sivan Devara', totalScore: 20, streak: 1, bestStreak: 1, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u5', name: 'crusader', totalScore: 14, streak: 1, bestStreak: 1, gamesPlayed: 1),
      ];

      final titles = SciwordleService.computeLeaderboardTitles(entries);

      expect(titles['u1'], equals('ALPHA'));
      expect(titles['u2'], equals('TOP 2'));
      expect(titles['u3'], equals('TOP 3'));
      expect(titles['u4'], isNull);
      expect(titles['u5'], isNull);

      // Verify all assigned titles are completely unique
      final assigned = titles.values.toList();
      expect(assigned.toSet().length, equals(assigned.length));
    });

    test('computeLeaderboardTitles awards FIRE to strictly 1 player when streak leader is not Rank 1', () {
      final entries = [
        const SciwordleLeaderboardEntry(uid: 'u1', name: 'Player 1', totalScore: 100, streak: 2, bestStreak: 2, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u2', name: 'Player 2', totalScore: 90, streak: 2, bestStreak: 2, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u3', name: 'Player 3', totalScore: 80, streak: 2, bestStreak: 2, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u4', name: 'Streak Master', totalScore: 70, streak: 6, bestStreak: 6, gamesPlayed: 1),
        const SciwordleLeaderboardEntry(uid: 'u5', name: 'Streak Equal', totalScore: 50, streak: 6, bestStreak: 6, gamesPlayed: 1),
      ];

      final titles = SciwordleService.computeLeaderboardTitles(entries);

      expect(titles['u1'], equals('PRIME'));
      expect(titles['u2'], equals('TOP 2'));
      expect(titles['u3'], equals('TOP 3'));
      expect(titles['u4'], equals('FIRE'));
      expect(titles['u5'], isNull); // Tied for streak with u4, but only 1 person gets FIRE

      // Verify all assigned titles are completely unique
      final assigned = titles.values.toList();
      expect(assigned.toSet().length, equals(assigned.length));
    });
  });
}
