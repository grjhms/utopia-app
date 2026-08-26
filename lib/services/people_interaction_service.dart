import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CampusVibe {
  const CampusVibe({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.branch,
    required this.emoji,
    required this.text,
    required this.updatedAt,
    this.isSuperuser = false,
    this.location,
    this.statusTag,
    this.durationHours = 24,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String branch;
  final String emoji;
  final String text;
  final DateTime updatedAt;
  final bool isSuperuser;
  final String? location;
  final String? statusTag;
  final int durationHours;

  factory CampusVibe.fromMap(String uid, Map<String, dynamic> data) {
    Map<String, dynamic> vibeMap = {};
    final rawVibe = data['vibe'];
    if (rawVibe is Map) {
      vibeMap = rawVibe.map((k, v) => MapEntry(k.toString(), v));
    }

    DateTime updatedAt = DateTime.now();
    final rawUpdatedAt = vibeMap['updatedAt'];
    if (rawUpdatedAt is Timestamp) {
      updatedAt = rawUpdatedAt.toDate();
    } else if (rawUpdatedAt is int) {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(rawUpdatedAt);
    } else if (rawUpdatedAt is String) {
      updatedAt = DateTime.tryParse(rawUpdatedAt) ?? DateTime.now();
    } else if (rawUpdatedAt is DateTime) {
      updatedAt = rawUpdatedAt;
    }

    final rawDuration = vibeMap['durationHours'];
    final durationHours = (rawDuration is int)
        ? rawDuration
        : int.tryParse(rawDuration?.toString() ?? '24') ?? 24;

    final loc = vibeMap['location']?.toString().trim();
    final tag = vibeMap['statusTag']?.toString().trim();

    return CampusVibe(
      uid: uid,
      displayName: (data['displayName'] ?? 'Student').toString().trim(),
      photoUrl: (data['photoUrl'] ?? data['photoURL'])?.toString(),
      branch: (data['branch'] ?? '').toString().trim(),
      emoji: (vibeMap['emoji'] ?? '✨').toString(),
      text: (vibeMap['text'] ?? '').toString().trim(),
      updatedAt: updatedAt,
      isSuperuser: (data['role'] ?? '').toString().toLowerCase() == 'superuser',
      location: (loc != null && loc.isNotEmpty) ? loc : null,
      statusTag: (tag != null && tag.isNotEmpty) ? tag : null,
      durationHours: durationHours > 0 ? durationHours : 24,
    );
  }

  bool get isExpired {
    final now = DateTime.now();
    if (updatedAt.isAfter(now)) return false;
    return now.difference(updatedAt).inHours >= durationHours;
  }
}

class SparkQuestion {
  const SparkQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.category,
    this.enabled = true,
  });

  final String id;
  final String question;
  final List<String> options;
  final String category;
  final bool enabled;

  factory SparkQuestion.fromMap(Map<String, dynamic> data, {String fallbackId = 'spark_default'}) {
    final rawOptions = data['options'] as List? ?? [];
    final options = rawOptions.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();

    return SparkQuestion(
      id: (data['id'] ?? fallbackId).toString(),
      question: (data['question'] ?? '').toString(),
      options: options.isNotEmpty ? options : ['Option A', 'Option B'],
      category: (data['category'] ?? 'Campus Life').toString(),
      enabled: data['enabled'] as bool? ?? true,
    );
  }
}

class PeopleInteractionService {
  static final PeopleInteractionService _instance = PeopleInteractionService._internal();
  factory PeopleInteractionService() => _instance;
  PeopleInteractionService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _currentName => FirebaseAuth.instance.currentUser?.displayName ?? 'Student';
  String? get _currentPhotoUrl => FirebaseAuth.instance.currentUser?.photoURL;

  // Rich Gen-Z Popular Emoji Selector
  static const List<String> popularEmojis = [
    '🎧', '💻', '☕', '📚', '⚡', '😴', '🎮', '🍕', '🚀', '🔥',
    '🎯', '💡', '🎨', '🎵', '🏃‍♂️', '🏖️', '🥳', '💭', '🧪', '🏀',
    '🍿', '🌙', '✨', '🧠',
  ];

  // Campus Locations for Vibe Tagging
  static const List<String> campusSpots = [
    'Central Library',
    'Canteen / Cafeteria',
    'Lab 1 / Lab 2',
    'Tech Park / Innovation Hub',
    'Seminar Hall',
    'Sports Ground',
    'Hostel',
    'Classroom',
    'Off Campus',
  ];

  // Availability / Collaboration Badges
  static const List<String> statusTags = [
    '🟢 Open to Join',
    '🟡 Deep Focus',
    '☕ Break Time',
    '🧠 Study Session',
    '🔴 DND / Exam Prep',
  ];

  // Categorized Presets for Campus Vibes
  static const Map<String, List<Map<String, String>>> categorizedVibes = {
    'All': [
      {'emoji': '🎧', 'text': 'In the zone / Grinding DSA'},
      {'emoji': '☕', 'text': 'Canteen run / Need coffee'},
      {'emoji': '💻', 'text': 'Building projects / Coding'},
      {'emoji': '📚', 'text': 'Library 2nd floor'},
      {'emoji': '😴', 'text': 'Running on 3h of sleep'},
      {'emoji': '🎮', 'text': 'Chilling / Game on'},
      {'emoji': '🍕', 'text': 'Hungry / Food hunt'},
      {'emoji': '🚀', 'text': 'Cooking something big'},
      {'emoji': '🔥', 'text': 'Final sprint before deadline'},
      {'emoji': '🎯', 'text': 'Target locked / Deep focus'},
      {'emoji': '🧠', 'text': 'Solving hard leetcode / bugs'},
      {'emoji': '🎨', 'text': 'UI/UX design sprint'},
      {'emoji': '🧋', 'text': 'Need a quick chai break'},
      {'emoji': '🎵', 'text': 'Blasting favorite playlist'},
    ],
    'Study': [
      {'emoji': '🎧', 'text': 'In the zone / Grinding DSA'},
      {'emoji': '📚', 'text': 'Library 2nd floor'},
      {'emoji': '🎯', 'text': 'Target locked / Deep focus'},
      {'emoji': '🧠', 'text': 'Solving hard leetcode / bugs'},
      {'emoji': '📝', 'text': 'Prepping for midterms / GATE'},
      {'emoji': '📖', 'text': 'Assignment rush mode'},
    ],
    'Build': [
      {'emoji': '💻', 'text': 'Building projects / Coding'},
      {'emoji': '🚀', 'text': 'Cooking something big'},
      {'emoji': '🎨', 'text': 'UI/UX design sprint'},
      {'emoji': '🤖', 'text': 'Experimenting with AI / Agents'},
      {'emoji': '⚡', 'text': 'Debugging mysterious bugs'},
      {'emoji': '🛠️', 'text': 'Refactoring the backend'},
    ],
    'Social': [
      {'emoji': '☕', 'text': 'Canteen run / Need coffee'},
      {'emoji': '🍕', 'text': 'Hungry / Food hunt'},
      {'emoji': '🧋', 'text': 'Need a quick chai break'},
      {'emoji': '🗣️', 'text': 'Free hour / Chilling at lawn'},
      {'emoji': '🍿', 'text': 'Post-lecture hangout'},
    ],
    'Chill': [
      {'emoji': '🎮', 'text': 'Chilling / Game on'},
      {'emoji': '😴', 'text': 'Running on 3h of sleep'},
      {'emoji': '🎵', 'text': 'Blasting favorite playlist'},
      {'emoji': '🏃‍♂️', 'text': 'Gym grind / Playing sports'},
      {'emoji': '🌙', 'text': 'Late night recharge vibes'},
      {'emoji': '🏖️', 'text': 'Weekend mode initiated'},
    ],
  };

  // Preset Gen-Z Campus Vibes (flat list)
  static const List<Map<String, String>> presetVibes = [
    {'emoji': '🎧', 'text': 'In the zone / Grinding DSA'},
    {'emoji': '☕', 'text': 'Canteen run / Need coffee'},
    {'emoji': '💻', 'text': 'Building projects / Coding'},
    {'emoji': '📚', 'text': 'Library 2nd floor'},
    {'emoji': '😴', 'text': 'Running on 3h of sleep'},
    {'emoji': '🎮', 'text': 'Chilling / Game on'},
    {'emoji': '🍕', 'text': 'Hungry / Food hunt'},
    {'emoji': '🚀', 'text': 'Cooking something big'},
    {'emoji': '🔥', 'text': 'Final sprint before deadline'},
    {'emoji': '🎯', 'text': 'Target locked / Deep focus'},
    {'emoji': '🧠', 'text': 'Solving hard leetcode / bugs'},
    {'emoji': '🎨', 'text': 'UI/UX design sprint'},
    {'emoji': '🧋', 'text': 'Need a quick chai break'},
    {'emoji': '🎵', 'text': 'Blasting favorite playlist'},
  ];

  // Daily Rotating Gen-Z Campus Sparks (Templates for superusers & default pool)
  static final List<SparkQuestion> sparkPool = [
    const SparkQuestion(
      id: 'spark_grind_time',
      question: 'Your peak productivity hours? ⚡',
      options: ['Late-night owl 🦉', 'Early-morning grinder 🌅', 'Panic 2h before deadline ⏳'],
      category: 'Study Habit',
    ),
    const SparkQuestion(
      id: 'spark_tech_pref',
      question: 'If building a project right now, you choose... 💻',
      options: ['Mobile app with Flutter 📱', 'AI / LLM Powered Agent 🤖', 'Full-stack Web app 🌐'],
      category: 'Tech & Dev',
    ),
    const SparkQuestion(
      id: 'spark_ai_future',
      question: 'How do you mostly use AI right now? 🤖',
      options: ['Coding & Debugging 💻', 'Summarizing notes & research 📚', 'Writing & Brainstorming 💡'],
      category: 'AI & Agents',
    ),
    const SparkQuestion(
      id: 'spark_study_audio',
      question: 'What is playing in your headphones while studying? 🎧',
      options: ['Lofi & Synthwave 🎶', 'Energetic Hip-Hop / Rock 🎸', 'Complete absolute silence 🤫'],
      category: 'Campus Vibe',
    ),
    const SparkQuestion(
      id: 'spark_gaming_vibe',
      question: 'Favorite way to decompress after lectures? 🎮',
      options: ['Competitive FPS / Esports 🎯', 'Cozy / Story-driven games 🕹️', 'Streaming anime & shows 🍿'],
      category: 'Gaming',
    ),
    const SparkQuestion(
      id: 'spark_canteen_pick',
      question: 'Go-to campus refuel order? ☕',
      options: ['Cold coffee + samosa ☕', 'Maggi & Chai 🍜', 'Energy drink & chips ⚡'],
      category: 'Campus Food',
    ),
    const SparkQuestion(
      id: 'spark_design_aesthetic',
      question: 'Your UI/UX design philosophy? 🎨',
      options: ['Ultra Dark Minimalist 🖤', 'Clean Apple-like Glassmorphism 🪟', 'Vibrant Neo-Brutalist 🌈'],
      category: 'Design',
    ),
    const SparkQuestion(
      id: 'spark_group_study',
      question: 'Group study sessions usually turn into... 🗣️',
      options: ['10% study, 90% gossip & reels 🍿', 'High focus & joint problem solving 🧠', 'Existential crisis together 💀'],
      category: 'College Life',
    ),
    const SparkQuestion(
      id: 'spark_startup_vibe',
      question: 'If you founded a startup tomorrow, it would be in... 🚀',
      options: ['AI Developer Tools 🤖', 'EdTech / Student Life 🎓', 'Gaming & Social Media 👾'],
      category: 'Startups',
    ),
    const SparkQuestion(
      id: 'spark_exam_prep',
      question: 'How do you prepare for midterms? 📝',
      options: ['One-shot YouTube video at 2x ⏩', 'Studying Utopia community notes 📖', 'Praying to RNG gods 🙏'],
      category: 'Academics',
    ),
    const SparkQuestion(
      id: 'spark_music_genre',
      question: 'Top playlist on your daily commute? 🎵',
      options: ['Indie & Acoustic 🎸', 'EDM & House 🔊', 'Hip-Hop & R&B 🎤'],
      category: 'Music',
    ),
    const SparkQuestion(
      id: 'spark_fitness_grind',
      question: 'Your campus fitness routine? 🏃‍♂️',
      options: ['Gym weightlifting 💪', 'Sports (Football / Badminton) 🏸', 'Walking between campus blocks 🚶'],
      category: 'Fitness',
    ),
  ];

  /// Get fallback spark question deterministically based on day of year
  SparkQuestion getTodaysSparkFallback() {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final index = dayOfYear % sparkPool.length;
    return sparkPool[index];
  }

  /// Real-time stream of the active campus spark question from Firestore config
  Stream<SparkQuestion> getActiveSparkStream() {
    return _db.collection('config').doc('campus_spark').snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final questionText = (data['question'] ?? '').toString().trim();
        if (questionText.isNotEmpty) {
          return SparkQuestion.fromMap(data);
        }
      }
      return getTodaysSparkFallback();
    });
  }

  /// Superuser method: Update or publish a new Campus Spark question
  Future<void> updateSparkConfig({
    required String question,
    required List<String> options,
    required String category,
    required bool enabled,
    bool createNewPoll = false,
  }) async {
    final sparkDoc = _db.collection('config').doc('campus_spark');
    final currentSnap = await sparkDoc.get();
    String pollId;

    if (createNewPoll || !currentSnap.exists) {
      pollId = 'spark_${DateTime.now().millisecondsSinceEpoch}';
    } else {
      pollId = (currentSnap.data()?['id'] ?? 'spark_${DateTime.now().millisecondsSinceEpoch}').toString();
    }

    await sparkDoc.set({
      'id': pollId,
      'question': question.trim(),
      'options': options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'category': category.trim(),
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _currentUid,
      'updatedByName': _currentName,
    }, SetOptions(merge: true));
  }

  // ─── Campus Vibe Management ───────────────────────────────────────────────

  /// Set the current user's campus vibe with rich customization options
  Future<void> setUserVibe({
    required String emoji,
    required String text,
    String? location,
    String? statusTag,
    int durationHours = 24,
  }) async {
    if (_currentUid.isEmpty) return;

    final Map<String, dynamic> vibeData = {
      'emoji': emoji,
      'text': text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'durationHours': durationHours > 0 ? durationHours : 24,
    };
    if (location != null && location.isNotEmpty) {
      vibeData['location'] = location;
    }
    if (statusTag != null && statusTag.isNotEmpty) {
      vibeData['statusTag'] = statusTag;
    }

    await _db.collection('users').doc(_currentUid).set({
      'vibe': vibeData,
    }, SetOptions(merge: true));
  }

  /// Clear the current user's active campus vibe
  Future<void> clearUserVibe() async {
    if (_currentUid.isEmpty) return;
    try {
      await _db.collection('users').doc(_currentUid).set({
        'vibe': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Stream of active campus vibes (filtered to not expired)
  Stream<List<CampusVibe>> getActiveVibesStream() {
    return _db.collection('users').snapshots().map((snap) {
      final List<CampusVibe> vibes = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['vibe'] != null && data['vibe'] is Map) {
          final vibe = CampusVibe.fromMap(doc.id, data);
          if (vibe.text.isNotEmpty && !vibe.isExpired) {
            vibes.add(vibe);
          }
        }
      }
      // Sort with current user first if they have one, then newest
      vibes.sort((a, b) {
        if (a.uid == _currentUid) return -1;
        if (b.uid == _currentUid) return 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return vibes;
    });
  }

  /// Send a friendly wave (👋) to another student
  /// [isReply]: true if this is a response wave (Wave Back).
  /// [replyToWaveId]: if replying, the original waveDoc ID to mark as replied.
  Future<bool> sendWave(
    String targetUid, {
    bool isReply = false,
    String? replyToWaveId,
  }) async {
    if (_currentUid.isEmpty || _currentUid == targetUid) return false;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Record locally in preferences for instant UI response
    final prefs = await SharedPreferences.getInstance();
    final key = 'waved_${_currentUid}_$targetUid';
    await prefs.setString(key, now.toIso8601String());

    try {
      // 1. If replying, mark original wave as replied so it cannot be waved back again
      if (replyToWaveId != null && replyToWaveId.isNotEmpty) {
        try {
          await _db.collection('waves').doc(replyToWaveId).update({
            'replied': true,
            'repliedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      // 2. Create the wave document
      final waveDoc = _db.collection('waves').doc();
      await waveDoc.set({
        'waveId': waveDoc.id,
        'senderId': _currentUid,
        'senderName': _currentName,
        'senderPhotoUrl': _currentPhotoUrl,
        'receiverId': targetUid,
        'isReply': isReply,
        'replied': false,
        'dateKey': todayStr,
        'createdAt': FieldValue.serverTimestamp(),
        'seen': false,
      });

      try {
        await _db.collection('users').doc(targetUid).update({
          'wavesReceivedCount': FieldValue.increment(1),
        });
      } catch (_) {
        await _db.collection('users').doc(targetUid).set({
          'wavesReceivedCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }

      return true;
    } catch (e) {
      debugPrint('Error sending wave: $e');
      return true; // Still allow local wave state
    }
  }

  /// Sync and backfill the current user's wavesReceivedCount from the waves collection.
  Future<int> syncMyWavesCount() async {
    if (_currentUid.isEmpty) return 0;
    try {
      final snap = await _db
          .collection('waves')
          .where('receiverId', isEqualTo: _currentUid)
          .count()
          .get();
      final actualCount = snap.count ?? 0;

      final userDoc = await _db.collection('users').doc(_currentUid).get();
      final storedCount =
          (userDoc.data()?['wavesReceivedCount'] as num?)?.toInt() ?? 0;

      if (actualCount > storedCount) {
        await _db.collection('users').doc(_currentUid).set({
          'wavesReceivedCount': actualCount,
        }, SetOptions(merge: true));
        return actualCount;
      }
      return storedCount;
    } catch (e) {
      debugPrint('Error syncing waves count: $e');
      return 0;
    }
  }

  /// Check if current user has waved at target within the last 18 hours
  Future<bool> hasWavedRecently(String targetUid) async {
    if (_currentUid.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = 'waved_${_currentUid}_$targetUid';
    final val = prefs.getString(key);
    if (val == null) return false;

    final wavedAt = DateTime.tryParse(val);
    if (wavedAt == null) return false;
    return DateTime.now().difference(wavedAt).inHours < 18;
  }

  /// Stream of waves received by current user
  Stream<List<Map<String, dynamic>>> getMyWavesStream() {
    if (_currentUid.isEmpty) return Stream.value([]);
    try {
      return _db
          .collection('waves')
          .where('receiverId', isEqualTo: _currentUid)
          .limit(20)
          .snapshots()
          .map((snap) {
            final list = snap.docs.map((d) => d.data()).toList();
            list.sort((a, b) {
              final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              return bTime.compareTo(aTime);
            });
            return list;
          })
          .handleError((e) {
            debugPrint('getMyWavesStream error: $e');
            return <Map<String, dynamic>>[];
          });
    } catch (e) {
      return Stream.value([]);
    }
  }

  // ─── Daily Campus Spark (Icebreaker Polls) ─────────────────────────────────

  /// Vote on the spark question (updates user doc and local cache)
  Future<void> voteSpark(String questionId, int optionIndex) async {
    if (_currentUid.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('spark_vote_$questionId', optionIndex);

    try {
      // Update in users collection (authenticated user has guaranteed write permission)
      await _db.collection('users').doc(_currentUid).set({
        'sparkVote': {
          'questionId': questionId,
          'optionIndex': optionIndex,
          'votedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // Local vote recorded
    }
  }

  /// Get local user's selected vote for a question
  Future<int?> getLocalSparkVote(String questionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('spark_vote_$questionId');
  }

  /// Stream votes for a question to compute percentages & show matching peers
  Stream<Map<int, List<Map<String, dynamic>>>> getSparkVotesStream(String questionId) {
    return _db.collection('users').snapshots().map((snap) {
      final Map<int, List<Map<String, dynamic>>> map = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final sv = data['sparkVote'];
        if (sv is Map && sv['questionId'] == questionId) {
          final opt = (sv['optionIndex'] as num?)?.toInt() ?? 0;
          map.putIfAbsent(opt, () => []).add({
            'uid': doc.id,
            'displayName': (data['displayName'] ?? 'Student').toString(),
            'photoUrl': (data['photoUrl'] ?? data['photoURL'])?.toString(),
            'optionIndex': opt,
          });
        }
      }
      return map;
    });
  }
}
