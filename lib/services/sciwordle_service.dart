// lib/services/sciwordle_service.dart
//
// Handles all Firestore reads and writes for SciWordle.
// Isolated backend service ensuring screens never directly touch Firestore raw queries.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sciwordle_model.dart';

class SciwordleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _dailyCol = 'sciwordle_daily';
  static const String _scoresCol = 'sciwordle_scores';
  static const String _progressCol = 'sciwordle_progress';
  static const int _playedGameStreakBonus = 2;

  String getTodayDateIST() {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String getYesterdayDateIST() {
    final yesterday = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 1))
        .add(const Duration(hours: 5, minutes: 30));
    final y = yesterday.year.toString().padLeft(4, '0');
    final m = yesterday.month.toString().padLeft(2, '0');
    final d = yesterday.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Today's Firestore document key, e.g. "2026-04-01-m"
  String get todayKey {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final hour = now.hour;

    // From 00:00 to 00:59, the 1 AM game hasn't generated yet.
    // They are still playing the previous day's evening game.
    if (hour < 1) {
      final yDay = now.subtract(const Duration(days: 1));
      final yDate =
          '${yDay.year.toString().padLeft(4, '0')}-${yDay.month.toString().padLeft(2, '0')}-${yDay.day.toString().padLeft(2, '0')}';
      return '$yDate-e';
    }

    final date = getTodayDateIST();
    if (hour < 11) return '$date-m'; // 1:00 AM to 10:59 AM
    if (hour < 16) return '$date-a'; // 11:00 AM to 3:59 PM
    return '$date-e'; // 4:00 PM to 11:59 PM
  }

  /// Calculates the duration remaining until the next puzzle slot opens.
  Duration get durationUntilNextSlot {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final hour = now.hour;
    DateTime nextTarget;

    if (hour < 1) {
      nextTarget = DateTime.utc(now.year, now.month, now.day, 1, 0, 0);
    } else if (hour < 11) {
      nextTarget = DateTime.utc(now.year, now.month, now.day, 11, 0, 0);
    } else if (hour < 16) {
      nextTarget = DateTime.utc(now.year, now.month, now.day, 16, 0, 0);
    } else {
      final tomorrow = now.add(const Duration(days: 1));
      nextTarget = DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, 1, 0, 0);
    }

    final nowUtcLike = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);
    final diff = nextTarget.difference(nowUtcLike);
    return diff.isNegative ? Duration.zero : diff;
  }

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User is not logged in.');
    return user.uid;
  }

  String get _displayName {
    return _auth.currentUser?.displayName ?? 'Student';
  }

  int _nextStreakForPlayedGame(SciwordlePlayerScore existing) {
    if (existing.gamesPlayed == 0) return 1;
    // Only continue the streak if they played yesterday or today
    if (existing.lastPlayedDate.startsWith(getYesterdayDateIST())) {
      return existing.streak + 1;
    }
    if (existing.lastPlayedDate.startsWith(getTodayDateIST())) {
      return existing.streak;
    }
    // Missed a day or more → reset
    return 1;
  }

  /// Returns true if the user's streak is still active (played today or yesterday).
  bool isStreakActive(String? lastPlayedDate) {
    if (lastPlayedDate == null || lastPlayedDate.isEmpty) return false;
    return lastPlayedDate.startsWith(getTodayDateIST()) ||
        lastPlayedDate.startsWith(getYesterdayDateIST());
  }

  // ─── Fetch today's question ───────────────────────────────────────────────

  /// Returns today's [SciwordleQuestion], or null if not yet generated.
  Future<SciwordleQuestion?> fetchTodaysQuestion() async {
    try {
      final doc = await _db.collection(_dailyCol).doc(todayKey).get();
      if (!doc.exists || doc.data() == null) return null;
      return SciwordleQuestion.fromFirestore(doc.data()!, todayKey);
    } on FirebaseException catch (e) {
      throw Exception("Couldn't load today's question: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong loading the question. Try again.");
    }
  }

  // ─── Fetch current player's score ─────────────────────────────────────────

  /// Returns the player's score doc, or a clean slate if first time.
  Future<SciwordlePlayerScore> fetchPlayerScore() async {
    try {
      final doc = await _db.collection(_scoresCol).doc(_uid).get();
      if (!doc.exists || doc.data() == null) {
        return SciwordlePlayerScore.empty(_uid);
      }
      return SciwordlePlayerScore.fromFirestore(doc.data()!, _uid);
    } on FirebaseException catch (e) {
      throw Exception("Couldn't load your score: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong loading your score. Try again.");
    }
  }

  // ─── Save result after a game ─────────────────────────────────────────────

  /// Called exactly once when a game ends.
  /// [attemptNumber] = 1–6 if they won, null if they lost all 6.
  /// Returns the points earned this round (word score + streak bonus).
  Future<int> saveGameResult({required int? attemptNumber}) async {
    try {
      final uid = _uid;
      final today = todayKey;

      // Load existing score
      final doc = await _db.collection(_scoresCol).doc(uid).get();
      final existing = (doc.exists && doc.data() != null)
          ? SciwordlePlayerScore.fromFirestore(doc.data()!, uid)
          : SciwordlePlayerScore.empty(uid);

      // Guard: don't save twice for the same game slot
      if (existing.lastPlayedDate == today) return 0;

      // Word score: 1st try = 18 pts, 2nd = 15 ... 6th = 3, failed = 0 (3x scoring)
      final wordScore = attemptNumber != null ? (7 - attemptNumber) * 3 : 0;
      final newStreak = _nextStreakForPlayedGame(existing);
      final newBestStreak = newStreak > existing.bestStreak ? newStreak : existing.bestStreak;
      final streakBonus = _playedGameStreakBonus;

      final roundPoints = wordScore + streakBonus;
      final newTotal = existing.totalScore + roundPoints;

      final updatedDist = Map<String, int>.from(existing.guessDistribution);
      if (attemptNumber != null) {
        final key = attemptNumber.toString();
        updatedDist[key] = (updatedDist[key] ?? 0) + 1;
      }

      await _db.collection(_scoresCol).doc(uid).set({
        'name': _displayName,
        'totalScore': newTotal,
        'streak': newStreak,
        'bestStreak': newBestStreak,
        'lastScore': roundPoints,
        'lastPlayedDate': today,
        'gamesPlayed': existing.gamesPlayed + 1,
        'guessDistribution': updatedDist,
        'scoreTimestamp': newTotal > existing.totalScore
            ? DateTime.now().millisecondsSinceEpoch
            : existing.scoreTimestamp,
        'streakTimestamp': newStreak > existing.streak
            ? DateTime.now().millisecondsSinceEpoch
            : existing.streakTimestamp,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return roundPoints;
    } on FirebaseException catch (e) {
      throw Exception("Couldn't save your score: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong saving your score. Try again.");
    }
  }

  // ─── Check if already played today ───────────────────────────────────────

  /// Returns true if the current player has already played today's active slot.
  Future<bool> hasPlayedToday() async {
    try {
      final doc = await _db.collection(_scoresCol).doc(_uid).get();
      if (!doc.exists || doc.data() == null) return false;
      final lastPlayed = doc.data()!['lastPlayedDate'] as String? ?? '';
      return lastPlayed == todayKey;
    } catch (_) {
      return false;
    }
  }

  // ─── In-progress guess persistence ────────────────────────────────────────

  /// Saves current guesses to prevent cheating by backing out.
  Future<void> saveGuessProgress({
    required List<String> guesses,
    required String answer,
  }) async {
    try {
      await _db.collection(_progressCol).doc(_uid).set({
        'dateKey': todayKey,
        'guesses': guesses,
        'answer': answer,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-critical, ignore
    }
  }

  /// Fetches saved in-progress guesses for today.
  Future<SciwordleProgressData?> fetchGuessProgress() async {
    try {
      final doc = await _db.collection(_progressCol).doc(_uid).get();
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      final dateKey = data['dateKey'] as String? ?? '';
      if (dateKey != todayKey) return null;
      final guesses = (data['guesses'] as List<dynamic>? ?? [])
          .map((e) => (e as String).toLowerCase())
          .toList();
      final answer = (data['answer'] as String? ?? '').toLowerCase();
      if (guesses.isEmpty || answer.isEmpty) return null;
      return SciwordleProgressData(guesses: guesses, answer: answer);
    } catch (_) {
      return null;
    }
  }

  /// Clears in-progress data upon game completion.
  Future<void> clearGuessProgress() async {
    try {
      await _db.collection(_progressCol).doc(_uid).delete();
    } catch (_) {}
  }

  // ─── Leaderboard ──────────────────────────────────────────────────────────

  /// Fetches top player scores sorted by totalScore descending.
  Future<List<SciwordleLeaderboardEntry>> fetchLeaderboard() async {
    try {
      final snapshot = await _db.collection(_scoresCol).limit(100).get();
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final scoreA = (a.data()['totalScore'] as num?)?.toInt() ?? 0;
          final scoreB = (b.data()['totalScore'] as num?)?.toInt() ?? 0;
          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA);
          }

          final tsA =
              (a.data()['scoreTimestamp'] as num?)?.toInt() ?? 9223372036854775807;
          final tsB =
              (b.data()['scoreTimestamp'] as num?)?.toInt() ?? 9223372036854775807;
          if (tsA != tsB) {
            return tsA.compareTo(tsB);
          }

          final updatedA = a.data()['updatedAt'];
          final updatedB = b.data()['updatedAt'];
          if (updatedA is Timestamp && updatedB is Timestamp) {
            final cmp = updatedA.compareTo(updatedB);
            if (cmp != 0) {
              return cmp;
            }
          }

          return a.id.compareTo(b.id);
        });

      return docs
          .map((doc) => SciwordleLeaderboardEntry.fromFirestore(
                doc.data(),
                doc.id,
                isStreakActive: isStreakActive(
                  doc.data()['lastPlayedDate'] as String?,
                ),
              ))
          .take(50)
          .toList();
    } on FirebaseException catch (e) {
      throw Exception("Couldn't load the leaderboard: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong loading the leaderboard.");
    }
  }

  /// Fetches streaks for multiple users.
  Future<Map<String, int>> fetchStreaksForUsers(List<String> uids) async {
    final result = <String, int>{};
    try {
      final snapshot = await _db.collection(_scoresCol).get();
      for (final doc in snapshot.docs) {
        if (uids.contains(doc.id)) {
          final lastPlayed = doc.data()['lastPlayedDate'] as String?;
          if (isStreakActive(lastPlayed)) {
            result[doc.id] = (doc.data()['streak'] as num?)?.toInt() ?? 0;
          } else {
            result[doc.id] = 0;
          }
        }
      }
    } catch (_) {}
    return result;
  }

  // ─── Wordle Letter Checking Logic ─────────────────────────────────────────

  /// Checks a [guess] against the [answer] and returns letter-by-letter results.
  /// Both are checked in lowercase.
  SciwordleGuessResult checkGuess({
    required String guess,
    required String answer,
  }) {
    final guessChars = guess.split('');
    final answerChars = answer.split('');
    final statuses = List<LetterStatus>.filled(
      guess.length,
      LetterStatus.absent,
    );
    final remaining = List<String?>.from(answerChars);

    // Pass 1: greens (exact position match)
    for (int i = 0; i < guessChars.length; i++) {
      if (i < answerChars.length && guessChars[i] == answerChars[i]) {
        statuses[i] = LetterStatus.correct;
        remaining[i] = null;
      }
    }

    // Pass 2: yellows (letter exists elsewhere)
    for (int i = 0; i < guessChars.length; i++) {
      if (statuses[i] == LetterStatus.correct) continue;
      final idx = remaining.indexOf(guessChars[i]);
      if (idx != -1) {
        statuses[i] = LetterStatus.present;
        remaining[idx] = null;
      }
    }

    return SciwordleGuessResult(
      letters: List.generate(
        guessChars.length,
        (i) => LetterResult(letter: guessChars[i], status: statuses[i]),
      ),
    );
  }
}

/// Represents saved in-progress guesses for the current day.
class SciwordleProgressData {
  const SciwordleProgressData({
    required this.guesses,
    required this.answer,
  });

  final List<String> guesses;
  final String answer;
}
