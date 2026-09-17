// lib/services/sciwordle_service.dart
//
// Handles all Firestore reads and writes for SciWordle.
// Isolated backend service ensuring screens never directly touch Firestore raw queries.

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Current week key anchored on Monday 00:00 IST (e.g. "2026-W-09-14")
  static String getCurrentWeekKeyIST() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final daysFromMonday = (now.weekday - 1) % 7;
    final monday = now.subtract(Duration(days: daysFromMonday));
    final y = monday.year.toString().padLeft(4, '0');
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');
    return '$y-W-$m-$d';
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

  /// Returns slot letter ('m', 'a', or 'e') for a dateKey
  static String slotForDateKey(String dateKey) {
    if (dateKey.endsWith('-m')) return 'm';
    if (dateKey.endsWith('-a')) return 'a';
    if (dateKey.endsWith('-e')) return 'e';
    return 'm';
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
  Future<SciwordleQuestion?> fetchTodaysQuestion([String? specificKey]) async {
    final key = specificKey ?? todayKey;
    try {
      final doc = await _db.collection(_dailyCol).doc(key).get();
      if (!doc.exists || doc.data() == null) return null;
      return SciwordleQuestion.fromFirestore(doc.data()!, key);
    } on FirebaseException catch (e) {
      throw Exception("Couldn't load today's question: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong loading the question. Try again.");
    }
  }

  // ─── Fetch current player's score ─────────────────────────────────────────

  /// Returns the player's score doc, checking weekly reset automatically.
  Future<SciwordlePlayerScore> fetchPlayerScore() async {
    try {
      final uid = _uid;
      final currentWeek = getCurrentWeekKeyIST();
      final doc = await _db.collection(_scoresCol).doc(uid).get();

      if (!doc.exists || doc.data() == null) {
        final initial = SciwordlePlayerScore.empty(uid, currentWeek);
        return initial;
      }

      final score = SciwordlePlayerScore.fromFirestore(doc.data()!, uid);

      // Check if a new week has started: reset streak and scores for the week
      if (score.weekKey != currentWeek) {
        final resetScore = SciwordlePlayerScore(
          uid: uid,
          name: score.name.isNotEmpty ? score.name : _displayName,
          totalScore: 0,
          streak: 0,
          bestStreak: score.bestStreak,
          lastScore: 0,
          lastPlayedDate: score.lastPlayedDate,
          gamesPlayed: score.gamesPlayed,
          guessDistribution: const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0},
          weekKey: currentWeek,
          scoreTimestamp: null,
          streakTimestamp: null,
        );

        // Persist the weekly reset to Firestore
        await _db.collection(_scoresCol).doc(uid).set({
          'totalScore': 0,
          'streak': 0,
          'lastScore': 0,
          'weekKey': currentWeek,
          'guessDistribution': resetScore.guessDistribution,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Update user document
        await _updateUserSciwordleFields(
          uid: uid,
          totalScore: 0,
          streak: 0,
          bestStreak: score.bestStreak,
        );

        return resetScore;
      }

      return score;
    } on FirebaseException catch (e) {
      throw Exception("Couldn't load your score: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong loading your score. Try again.");
    }
  }

  // ─── Fetch score for any user ─────────────────────────────────────────────
  Future<SciwordlePlayerScore?> fetchUserScore(String uid) async {
    try {
      final doc = await _db.collection(_scoresCol).doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      final currentWeek = getCurrentWeekKeyIST();
      final score = SciwordlePlayerScore.fromFirestore(doc.data()!, uid);
      if (score.weekKey != currentWeek) {
        return SciwordlePlayerScore(
          uid: uid,
          name: score.name,
          totalScore: 0,
          streak: 0,
          bestStreak: score.bestStreak,
          lastScore: 0,
          lastPlayedDate: score.lastPlayedDate,
          gamesPlayed: score.gamesPlayed,
          guessDistribution: const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0},
          weekKey: currentWeek,
        );
      }
      return score;
    } catch (_) {
      return null;
    }
  }

  // ─── Save result after a game ─────────────────────────────────────────────

  /// Called exactly once when a game ends.
  /// [attemptNumber] = 1–6 if they won, null if they lost all 6.
  /// Returns the points earned this round (word score + streak bonus).
  Future<int> saveGameResult({
    required int? attemptNumber,
    required List<String> guesses,
    required String answer,
    String? question,
    String? category,
    String? dateKey,
  }) async {
    try {
      final uid = _uid;
      final today = dateKey ?? todayKey;
      final currentWeek = getCurrentWeekKeyIST();

      // Load existing score
      final doc = await _db.collection(_scoresCol).doc(uid).get();
      var existing = (doc.exists && doc.data() != null)
          ? SciwordlePlayerScore.fromFirestore(doc.data()!, uid)
          : SciwordlePlayerScore.empty(uid, currentWeek);

      // Handle weekly reset if weekKey differs
      if (existing.weekKey != currentWeek) {
        existing = SciwordlePlayerScore(
          uid: uid,
          name: existing.name,
          totalScore: 0,
          streak: 0,
          bestStreak: existing.bestStreak,
          lastScore: 0,
          lastPlayedDate: existing.lastPlayedDate,
          gamesPlayed: existing.gamesPlayed,
          guessDistribution: const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0},
          weekKey: currentWeek,
        );
      }

      // Guard: don't save twice for the same game slot
      if (await hasPlayedToday(today)) return 0;

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
        'weekKey': currentWeek,
        'scoreTimestamp': newTotal > existing.totalScore
            ? DateTime.now().millisecondsSinceEpoch
            : existing.scoreTimestamp,
        'streakTimestamp': newStreak > existing.streak
            ? DateTime.now().millisecondsSinceEpoch
            : existing.streakTimestamp,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Save completed guesses to history
      await saveCompletedGameGuesses(
        dateKey: today,
        guesses: guesses,
        answer: answer,
        won: attemptNumber != null,
        question: question,
        category: category,
      );

      // Sync user profile fields
      await _updateUserSciwordleFields(
        uid: uid,
        totalScore: newTotal,
        streak: newStreak,
        bestStreak: newBestStreak,
      );

      // Refresh leaderboards & update user's title
      unawaited(_refreshUserTitleAfterGame(uid, newTotal, newStreak));

      return roundPoints;
    } on FirebaseException catch (e) {
      throw Exception("Couldn't save your score: ${e.message}");
    } catch (_) {
      throw Exception("Something went wrong saving your score. Try again.");
    }
  }

  // ─── Update User Profile Fields ──────────────────────────────────────────
  Future<void> _updateUserSciwordleFields({
    required String uid,
    required int totalScore,
    required int streak,
    required int bestStreak,
    String? title,
  }) async {
    try {
      final updates = <String, dynamic>{
        'sciwordleScore': totalScore,
        'sciwordleStreak': streak,
        'sciwordleBestStreak': bestStreak,
        'sciwordleWeekKey': getCurrentWeekKeyIST(),
      };
      if (title != null) {
        updates['sciwordleTitle'] = title;
      }
      await _db.collection('users').doc(uid).set(updates, SetOptions(merge: true));
    } catch (_) {}
  }

  // ─── Refresh User Title After Game ──────────────────────────────────────
  Future<void> _refreshUserTitleAfterGame(String uid, int totalScore, int streak) async {
    try {
      final leaderboard = await fetchLeaderboard();
      int rank = -1;
      int maxStreak = 0;
      for (int i = 0; i < leaderboard.length; i++) {
        if (leaderboard[i].streak > maxStreak) {
          maxStreak = leaderboard[i].streak;
        }
        if (leaderboard[i].uid == uid) {
          rank = i + 1;
        }
      }
      final title = computeTitle(
        rank: rank,
        streak: streak,
        maxStreak: maxStreak,
        totalScore: totalScore,
      );
      await _db.collection('users').doc(uid).set({
        'sciwordleTitle': title ?? '',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Deterministic title calculation based on rank, streak, and score
  static String? computeTitle({
    required int rank,
    required int streak,
    required int maxStreak,
    required int totalScore,
  }) {
    if (totalScore <= 0 || rank <= 0) return null;
    final isMaxStreak = streak > 0 && streak >= maxStreak;
    if (rank == 1 && isMaxStreak) return 'ALPHA';
    if (rank == 1) return 'PRIME';
    if (isMaxStreak) return 'FIRE';
    if (rank == 2) return 'TOP 2';
    if (rank == 3) return 'TOP 3';
    if (rank <= 10) return 'TOP 10';
    return null;
  }

  // ─── Check if already played today ───────────────────────────────────────

  /// Returns true if the current player has already played the specified slot.
  Future<bool> hasPlayedToday([String? specificKey]) async {
    final key = specificKey ?? todayKey;

    // 1. Check local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('sciwordle_history_$key');
      if (local != null && local.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    // 2. Check Firestore scores document
    try {
      final doc = await _db.collection(_scoresCol).doc(_uid).get();
      if (!doc.exists || doc.data() == null) return false;
      final data = doc.data()!;
      final lastPlayed = data['lastPlayedDate'] as String? ?? '';
      if (lastPlayed == key) return true;

      final historyMap = data['completedHistory'] as Map<String, dynamic>?;
      if (historyMap != null && historyMap.containsKey(key)) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  // ─── Completed session history persistence ────────────────────────────────

  /// Saves finished puzzle guesses so the user never sees empty boxes upon completion.
  Future<void> saveCompletedGameGuesses({
    required String dateKey,
    required List<String> guesses,
    required String answer,
    required bool won,
    String? question,
    String? category,
  }) async {
    try {
      final uid = _uid;
      final historyItem = SciwordleSessionHistory(
        dateKey: dateKey,
        guesses: guesses,
        answer: answer,
        won: won,
        question: question,
        category: category,
      );

      // 1. Save in Firestore under sciwordle_scores doc history map
      await _db.collection(_scoresCol).doc(uid).set({
        'completedHistory': {
          dateKey: historyItem.toMap(),
        },
      }, SetOptions(merge: true));

      // 2. Also cache in SharedPreferences for instant retrieval
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sciwordle_history_$dateKey', jsonEncode(historyItem.toMap()));
    } catch (_) {}
  }

  /// Fetches saved completed game history for a specific dateKey.
  Future<SciwordleSessionHistory?> fetchCompletedGameHistory(String dateKey) async {
    // Check SharedPreferences first
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('sciwordle_history_$dateKey');
      if (local != null && local.isNotEmpty) {
        final decoded = jsonDecode(local);
        if (decoded is Map<String, dynamic>) {
          return SciwordleSessionHistory.fromMap(decoded);
        }
      }
    } catch (_) {}

    // Fallback to Firestore
    try {
      final uid = _uid;
      final doc = await _db.collection(_scoresCol).doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final historyMap = doc.data()!['completedHistory'] as Map<String, dynamic>?;
        if (historyMap != null && historyMap.containsKey(dateKey)) {
          final data = historyMap[dateKey] as Map<String, dynamic>;
          return SciwordleSessionHistory.fromMap(data);
        }
      }
    } catch (_) {}

    return null;
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

  /// Fetches top player scores sorted by totalScore descending for the current week.
  Future<List<SciwordleLeaderboardEntry>> fetchLeaderboard() async {
    try {
      final currentWeek = getCurrentWeekKeyIST();
      final snapshot = await _db.collection(_scoresCol).limit(100).get();
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final isWeekA = (a.data()['weekKey'] as String?) == currentWeek;
          final isWeekB = (b.data()['weekKey'] as String?) == currentWeek;

          final scoreA = isWeekA ? ((a.data()['totalScore'] as num?)?.toInt() ?? 0) : 0;
          final scoreB = isWeekB ? ((b.data()['totalScore'] as num?)?.toInt() ?? 0) : 0;
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
          .map((doc) {
            final data = doc.data();
            final isCurrentWeek = (data['weekKey'] as String?) == currentWeek;
            final weeklyData = Map<String, dynamic>.from(data);
            if (!isCurrentWeek) {
              weeklyData['totalScore'] = 0;
              weeklyData['streak'] = 0;
            }
            return SciwordleLeaderboardEntry.fromFirestore(
              weeklyData,
              doc.id,
              isStreakActive: isCurrentWeek && isStreakActive(
                data['lastPlayedDate'] as String?,
              ),
            );
          })
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
