import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/wave_haptics.dart';

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
    this.mediaUrl,
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
  final String? mediaUrl;

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
    final media = (vibeMap['mediaUrl'] ?? vibeMap['gifUrl'] ?? vibeMap['stickerUrl'])?.toString().trim();

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
      mediaUrl: (media != null && media.isNotEmpty) ? media : null,
    );
  }

  bool get isExpired {
    final now = DateTime.now();
    if (updatedAt.isAfter(now)) return false;
    return now.difference(updatedAt).inHours >= durationHours;
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
    '🟢 Open to collaborate',
    '🟡 In focus mode',
    '☕ Taking a break',
    '📚 Studying together',
    '🔴 Do not disturb',
  ];

  // Categorized Presets for Campus Vibes
  static const Map<String, List<Map<String, String>>> categorizedVibes = {
    'All': [
      {'emoji': '📚', 'text': 'Studying (allegedly)'},
      {'emoji': '🏛️', 'text': 'Here for the attendance'},
      {'emoji': '🫠', 'text': 'Brain is buffering'},
      {'emoji': '☕', 'text': 'Fueled by caffeine'},
      {'emoji': '💻', 'text': 'Fighting runtime errors'},
      {'emoji': '🏃', 'text': 'Sprinting to lecture'},
      {'emoji': '🔋', 'text': 'Social battery at 1%'},
      {'emoji': '✍️', 'text': 'Speedrunning assignments'},
      {'emoji': '🎧', 'text': 'Focus mode'},
      {'emoji': '📖', 'text': 'In the library'},
      {'emoji': '🔬', 'text': 'In the lab'},
      {'emoji': '🥪', 'text': 'Canteen run'},
      {'emoji': '🤝', 'text': 'Group study'},
      {'emoji': '🏠', 'text': 'Hibernating at hostel'},
    ],
    'Study': [
      {'emoji': '📚', 'text': 'Studying (allegedly)'},
      {'emoji': '✍️', 'text': 'Speedrunning assignments'},
      {'emoji': '📖', 'text': 'In the library'},
      {'emoji': '🎧', 'text': 'Focus mode'},
      {'emoji': '🤝', 'text': 'Group study'},
      {'emoji': '🏛️', 'text': 'Here for the attendance'},
    ],
    'Work': [
      {'emoji': '💻', 'text': 'Fighting runtime errors'},
      {'emoji': '🔬', 'text': 'In the lab'},
      {'emoji': '🫠', 'text': 'Brain is buffering'},
      {'emoji': '💡', 'text': 'Brainstorming'},
      {'emoji': '🛠️', 'text': 'Lab practical'},
    ],
    'Break': [
      {'emoji': '☕', 'text': 'Fueled by caffeine'},
      {'emoji': '🥪', 'text': 'Canteen run'},
      {'emoji': '🔋', 'text': 'Social battery at 1%'},
      {'emoji': '🏃', 'text': 'Sprinting to lecture'},
      {'emoji': '🏠', 'text': 'Hibernating at hostel'},
      {'emoji': '🎮', 'text': 'Relaxing'},
    ],
  };

  // Preset Campus Vibes (flat list)
  static const List<Map<String, String>> presetVibes = [
    {'emoji': '📚', 'text': 'Studying (allegedly)'},
    {'emoji': '🏛️', 'text': 'Here for the attendance'},
    {'emoji': '🫠', 'text': 'Brain is buffering'},
    {'emoji': '☕', 'text': 'Fueled by caffeine'},
    {'emoji': '💻', 'text': 'Fighting runtime errors'},
    {'emoji': '🏃', 'text': 'Sprinting to lecture'},
    {'emoji': '🔋', 'text': 'Social battery at 1%'},
    {'emoji': '✍️', 'text': 'Speedrunning assignments'},
    {'emoji': '🎧', 'text': 'Focus mode'},
    {'emoji': '📖', 'text': 'In the library'},
    {'emoji': '🔬', 'text': 'In the lab'},
    {'emoji': '🥪', 'text': 'Canteen run'},
    {'emoji': '🤝', 'text': 'Group study'},
    {'emoji': '🏠', 'text': 'Hibernating at hostel'},
  ];

  // ─── Campus Vibe Management ───────────────────────────────────────────────

  /// Set the current user's campus vibe with rich customization options
  Future<void> setUserVibe({
    required String emoji,
    required String text,
    String? location,
    String? statusTag,
    int durationHours = 24,
    String? mediaUrl,
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
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      vibeData['mediaUrl'] = mediaUrl;
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
          if ((vibe.text.isNotEmpty || (vibe.mediaUrl != null && vibe.mediaUrl!.isNotEmpty)) && !vibe.isExpired) {
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

    if (isReply) {
      WaveHaptics.waveBack();
    } else {
      WaveHaptics.wave();
    }

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

}
