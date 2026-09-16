// lib/models/sciwordle_model.dart
//
// Data models for SciWordle.
// Plain Dart classes decoupled from UI.

/// Represents today's science question fetched from Firestore.
class SciwordleQuestion {
  const SciwordleQuestion({
    required this.dateKey,
    required this.question,
    required this.answer,
    required this.category,
  });

  /// The Firestore document ID, e.g. "2026-04-01-m"
  final String dateKey;

  /// The full question text, e.g. "I am the force that attracts two bodies toward each other..."
  final String question;

  /// The single-word answer in lowercase, e.g. "gravity"
  final String answer;

  /// Science category tag, e.g. "Physics", "Astronomy", "Biology", "Chemistry"
  final String category;

  factory SciwordleQuestion.fromFirestore(
    Map<String, dynamic> data,
    String dateKey,
  ) {
    return SciwordleQuestion(
      dateKey: dateKey,
      question: (data['question'] as String? ?? '').trim(),
      answer: (data['answer'] as String? ?? '').trim().toLowerCase(),
      category: (data['category'] as String? ?? 'Science').trim(),
    );
  }
}

/// Represents a player's all-time score data stored in sciwordle_scores/{uid}.
class SciwordlePlayerScore {
  const SciwordlePlayerScore({
    required this.uid,
    required this.name,
    required this.totalScore,
    required this.streak,
    required this.bestStreak,
    required this.lastScore,
    required this.lastPlayedDate,
    required this.gamesPlayed,
    required this.guessDistribution,
    this.scoreTimestamp,
    this.streakTimestamp,
  });

  final String uid;
  final String name;
  final int totalScore;
  final int streak;
  final int bestStreak;
  final int lastScore;
  final String lastPlayedDate;
  final int gamesPlayed;
  final Map<String, int> guessDistribution;

  /// Timestamp when the current totalScore was achieved (for tiebreaker)
  final int? scoreTimestamp;

  /// Timestamp when the current streak was achieved (for tiebreaker)
  final int? streakTimestamp;

  /// Returns a zeroed-out score for a brand-new player.
  factory SciwordlePlayerScore.empty(String uid) {
    return SciwordlePlayerScore(
      uid: uid,
      name: '',
      totalScore: 0,
      streak: 0,
      bestStreak: 0,
      lastScore: 0,
      lastPlayedDate: '',
      gamesPlayed: 0,
      guessDistribution: const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0},
      scoreTimestamp: null,
      streakTimestamp: null,
    );
  }

  factory SciwordlePlayerScore.fromFirestore(
    Map<String, dynamic> data,
    String uid,
  ) {
    return SciwordlePlayerScore(
      uid: uid,
      name: (data['name'] as String? ?? '').trim(),
      totalScore: (data['totalScore'] as num?)?.toInt() ?? 0,
      streak: (data['streak'] as num?)?.toInt() ?? 0,
      bestStreak: (data['bestStreak'] as num?)?.toInt() ?? 0,
      lastScore: (data['lastScore'] as num?)?.toInt() ?? 0,
      lastPlayedDate: (data['lastPlayedDate'] as String? ?? '').trim(),
      gamesPlayed: (data['gamesPlayed'] as num?)?.toInt() ?? 0,
      guessDistribution: _parseGuessDistribution(data['guessDistribution']),
      scoreTimestamp: (data['scoreTimestamp'] as num?)?.toInt(),
      streakTimestamp: (data['streakTimestamp'] as num?)?.toInt(),
    );
  }

  static Map<String, int> _parseGuessDistribution(dynamic raw) {
    final map = <String, int>{'1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0};
    if (raw is Map) {
      for (final key in map.keys) {
        if (raw.containsKey(key)) {
          map[key] = (raw[key] as num).toInt();
        }
      }
    }
    return map;
  }
}

/// Represents one row in the leaderboard — fetched from sciwordle_scores docs.
class SciwordleLeaderboardEntry {
  const SciwordleLeaderboardEntry({
    required this.uid,
    required this.name,
    required this.totalScore,
    required this.streak,
    required this.bestStreak,
    required this.gamesPlayed,
  });

  final String uid;
  final String name;
  final int totalScore;
  final int streak;
  final int bestStreak;
  final int gamesPlayed;

  factory SciwordleLeaderboardEntry.fromFirestore(
    Map<String, dynamic> data,
    String uid, {
    bool isStreakActive = true,
  }) {
    final rawStreak = (data['streak'] as num?)?.toInt() ?? 0;
    return SciwordleLeaderboardEntry(
      uid: uid,
      name: (data['name'] as String? ?? 'Student').trim(),
      totalScore: (data['totalScore'] as num?)?.toInt() ?? 0,
      streak: isStreakActive ? rawStreak : 0,
      bestStreak: (data['bestStreak'] as num?)?.toInt() ?? 0,
      gamesPlayed: (data['gamesPlayed'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The letter-by-letter result of one guess attempt.
class SciwordleGuessResult {
  const SciwordleGuessResult({required this.letters});

  /// One [LetterResult] per character in the guessed word.
  final List<LetterResult> letters;
}

/// The status of a single guessed letter.
class LetterResult {
  const LetterResult({required this.letter, required this.status});

  final String letter;
  final LetterStatus status;
}

enum LetterStatus {
  /// Correct letter, correct position — Emerald Green
  correct,

  /// Correct letter, wrong position — Amber Yellow
  present,

  /// Letter not in the answer — Slate / Dim Grey
  absent,
}
