import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists attendance data locally to SharedPreferences (for instant 0ms offline loads)
/// and to Firestore (for cloud backup across devices).
class AttendanceCacheService {
  static final _firestore = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static String _localKey(String roll) =>
      'attendance_cache_local_${roll.trim().toUpperCase()}';

  static DocumentReference<Map<String, dynamic>>? _ref(String rollNumber) {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore
        .collection('attendance_cache')
        .doc(uid)
        .collection('records')
        .doc(rollNumber.toUpperCase().trim());
  }

  /// Save a successful attendance fetch to both local SharedPreferences and Firestore.
  static Future<void> save({
    required String rollNumber,
    required Map<String, dynamic> data,
    required String college,
  }) async {
    final roll = rollNumber.trim().toUpperCase();
    if (roll.isEmpty) return;

    final now = DateTime.now();

    // Subjects list must be JSON-safe
    final subjects = (data['subjects'] as List<dynamic>? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();

    // If incoming subjects is empty, NEVER overwrite existing cache with 0!
    if (subjects.isEmpty) {
      final existing = await load(roll);
      if (existing != null && (existing.data['subjects'] as List? ?? []).isNotEmpty) {
        if (data['academicInsights'] != null) {
          await saveAcademicInsights(
            rollNumber: rollNumber,
            academicInsights: data['academicInsights'] as Map<String, dynamic>,
          );
        }
        return;
      }
    }

    final cleanData = {
      'overallPercentage': (data['overallPercentage'] as num?)?.toDouble() ?? 0.0,
      'totalClasses': (data['totalClasses'] as num?)?.toInt() ?? 0,
      'totalAttended': (data['totalAttended'] as num?)?.toInt() ?? 0,
      'studentName': (data['studentName'] as String? ?? '').trim(),
      'hasReport': data['hasReport'] ?? false,
      'subjects': subjects,
      'academicInsights': data['academicInsights'],
    };

    // 1. Instant local persistence
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _localKey(roll),
        jsonEncode({
          'rollNumber': roll,
          'college': college,
          'cachedAt': now.toIso8601String(),
          'data': cleanData,
        }),
      );
    } catch (e) {
      debugPrint('AttendanceCacheService: local save failed: $e');
    }

    // 2. Cloud Firestore persistence (non-blocking)
    final ref = _ref(roll);
    if (ref == null) return;
    try {
      final firestorePayload = {
        'rollNumber': roll,
        'college': college,
        'cachedAt': FieldValue.serverTimestamp(),
        'overallPercentage': cleanData['overallPercentage'],
        'totalClasses': cleanData['totalClasses'],
        'totalAttended': cleanData['totalAttended'],
        'studentName': cleanData['studentName'],
        'hasReport': cleanData['hasReport'],
        'subjectsJson': jsonEncode(subjects),
      };
      if (cleanData['academicInsights'] != null) {
        firestorePayload['academicInsightsJson'] =
            jsonEncode(cleanData['academicInsights']);
      }
      await ref.set(firestorePayload);
    } catch (e) {
      debugPrint('AttendanceCacheService: firestore save failed: $e');
    }
  }

  /// Save academic insights to local cache and Firestore.
  static Future<void> saveAcademicInsights({
    required String rollNumber,
    required Map<String, dynamic> academicInsights,
  }) async {
    final roll = rollNumber.trim().toUpperCase();
    if (roll.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final localStr = prefs.getString(_localKey(roll));
      if (localStr != null) {
        final map = jsonDecode(localStr) as Map<String, dynamic>;
        final rawData = map['data'];
        if (rawData is Map) {
          final data = Map<String, dynamic>.from(rawData);
          data['academicInsights'] = academicInsights;
          map['data'] = data;
          await prefs.setString(_localKey(roll), jsonEncode(map));
        }
      }
    } catch (e) {
      debugPrint('AttendanceCacheService: saveAcademicInsights local failed: $e');
    }

    final ref = _ref(roll);
    if (ref == null) return;
    try {
      await ref.set({
        'academicInsightsJson': jsonEncode(academicInsights),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('AttendanceCacheService: saveAcademicInsights firestore failed: $e');
    }
  }

  /// Load cached attendance.
  /// First checks local SharedPreferences for zero-latency instant retrieval.
  /// Falls back to Firestore if no local cache exists.
  static Future<CachedAttendance?> load(String rollNumber) async {
    final roll = rollNumber.trim().toUpperCase();
    if (roll.isEmpty) return null;

    // 1. Check local SharedPreferences (0ms synchronous disk read)
    try {
      final prefs = await SharedPreferences.getInstance();
      final localStr = prefs.getString(_localKey(roll));
      if (localStr != null) {
        final map = jsonDecode(localStr) as Map<String, dynamic>;
        final tsStr = map['cachedAt'] as String?;
        final ts = tsStr != null ? DateTime.tryParse(tsStr) : null;
        final rawData = map['data'];
        if (ts != null && rawData is Map) {
          final data = Map<String, dynamic>.from(rawData);
          return CachedAttendance(cachedAt: ts, data: data);
        }
      }
    } catch (e) {
      debugPrint('AttendanceCacheService: local load failed: $e');
    }

    // 2. Fallback to Firestore
    final ref = _ref(roll);
    if (ref == null) return null;
    try {
      final doc = await ref.get();
      if (!doc.exists || doc.data() == null) return null;

      final d = doc.data()!;
      final cachedAt = (d['cachedAt'] as Timestamp?)?.toDate();
      if (cachedAt == null) return null;

      final subjectsJson = d['subjectsJson'] as String? ?? '[]';
      final subjects = (jsonDecode(subjectsJson) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      Map<String, dynamic>? academicInsights;
      final academicJson = d['academicInsightsJson'] as String?;
      if (academicJson != null && academicJson.isNotEmpty) {
        try {
          academicInsights =
              jsonDecode(academicJson) as Map<String, dynamic>?;
        } catch (_) {}
      }

      final attendanceData = {
        'overallPercentage': (d['overallPercentage'] as num?)?.toDouble() ?? 0.0,
        'totalClasses': d['totalClasses'] ?? 0,
        'totalAttended': d['totalAttended'] ?? 0,
        'studentName': d['studentName'] ?? '',
        'hasReport': d['hasReport'] ?? false,
        'subjects': subjects,
        if (academicInsights != null) 'academicInsights': academicInsights,
      };

      // Populate local cache for next time
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _localKey(roll),
          jsonEncode({
            'rollNumber': roll,
            'college': d['college'] ?? '',
            'cachedAt': cachedAt.toIso8601String(),
            'data': attendanceData,
          }),
        );
      } catch (_) {}

      return CachedAttendance(
        cachedAt: cachedAt,
        data: attendanceData,
      );
    } catch (e) {
      debugPrint('AttendanceCacheService: firestore load failed: $e');
      return null;
    }
  }

  /// Delete cached attendance locally and in Firestore (called on disconnect).
  static Future<void> clear(String rollNumber) async {
    final roll = rollNumber.trim().toUpperCase();
    if (roll.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localKey(roll));
    } catch (e) {
      debugPrint('AttendanceCacheService: local clear failed: $e');
    }

    final ref = _ref(roll);
    if (ref == null) return;
    try {
      await ref.delete();
    } catch (e) {
      debugPrint('AttendanceCacheService: firestore clear failed: $e');
    }
  }
}

class CachedAttendance {
  const CachedAttendance({required this.cachedAt, required this.data});
  final DateTime cachedAt;
  final Map<String, dynamic> data;

  String get ageLabel {
    final diff = DateTime.now().difference(cachedAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 30) return '${diff.inMinutes} min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get formattedTimeLabel {
    final now = DateTime.now();
    final diff = now.difference(cachedAt);

    final hour = cachedAt.hour > 12 ? cachedAt.hour - 12 : (cachedAt.hour == 0 ? 12 : cachedAt.hour);
    final minute = cachedAt.minute.toString().padLeft(2, '0');
    final period = cachedAt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $period';

    if (diff.inMinutes < 1) {
      return 'just now';
    }

    if (diff.inMinutes < 30) {
      return '${diff.inMinutes} min ago';
    }

    final isSameDay = cachedAt.year == now.year && cachedAt.month == now.month && cachedAt.day == now.day;
    if (isSameDay) {
      return 'Today at $timeStr';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = cachedAt.year == yesterday.year && cachedAt.month == yesterday.month && cachedAt.day == yesterday.day;
    if (isYesterday) {
      return 'Yesterday at $timeStr';
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[cachedAt.month - 1]} ${cachedAt.day} at $timeStr';
  }
}
