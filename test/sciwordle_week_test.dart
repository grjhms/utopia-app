import 'package:flutter_test/flutter_test.dart';
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

      // Rank 4 but has highest streak
      expect(
        SciwordleService.computeTitle(rank: 4, streak: 5, maxStreak: 5, totalScore: 80),
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

      // Rank 8
      expect(
        SciwordleService.computeTitle(rank: 8, streak: 2, maxStreak: 5, totalScore: 50),
        equals('TOP 10'),
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
  });
}
