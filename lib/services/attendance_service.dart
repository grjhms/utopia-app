import 'package:flutter/foundation.dart';
import 'aec_attendance_service.dart';
import 'attendance_cache_service.dart';
import 'aus_attendance_service.dart';

export 'attendance_cache_service.dart' show CachedAttendance;

enum AttendanceRangeMode { period, tillNow }

class AttendanceService {
  /// Fetches attendance using direct on-device scraping.
  ///
  /// On success → saves to Firestore cache.
  /// On failure → falls back to Firestore cache.
  ///
  /// Returns a map with extra keys:
  ///   'fromCache': true/false
  ///   'cachedAt': DateTime? (only when fromCache == true)
  ///   'serverUsed': 'In-App' | 'cache' (which source produced the data)
  static Future<Map<String, dynamic>> fetchAttendance(
    String rollNumber,
    String password, {
    String college = 'aus',
    String fromDate = '',
    String toDate = '',
    AttendanceRangeMode mode = AttendanceRangeMode.period,
    bool forceLive = false,
  }) async {
    debugPrint(
      '[AttendanceService] fetchAttendance: college=$college, '
      'roll=$rollNumber, fromDate=$fromDate, toDate=$toDate, mode=$mode',
    );

    try {
      Map<String, dynamic> result;

      debugPrint('[AttendanceService] Scraping via In-App service…');
      if (college == 'acet' || college == 'aec') {
        result = await AecAttendanceService.fetchAttendance(
          rollNumber,
          password,
          college: college,
          fromDate: fromDate,
          toDate: toDate,
          mode: mode,
        );
      } else {
        result = await AusAttendanceService.fetchAttendance(
          rollNumber,
          password,
          fromDate: fromDate,
          toDate: toDate,
        );
      }

      debugPrint('[AttendanceService] Success via In-App');

      // Save to cache (non-blocking)
      AttendanceCacheService.save(
        rollNumber: rollNumber,
        data: result,
        college: college,
      ).catchError((e) {
        debugPrint('AttendanceService: background cache save failed: $e');
        return null;
      });

      return {
        ...result,
        'fromCache': false,
        'cachedAt': null,
        'serverUsed': 'In-App',
      };
    } catch (liveError) {
      debugPrint(
        'AttendanceService: live fetch failed ($liveError), trying cache…',
      );

      if (forceLive) {
        rethrow;
      }

      // ── Cache fallback ──
      final cached = await AttendanceCacheService.load(rollNumber);
      if (cached != null) {
        return {
          ...cached.data,
          'fromCache': true,
          'cachedAt': cached.cachedAt,
          'cacheAgeLabel': cached.ageLabel,
          'serverUsed': 'cache',
        };
      }

      // No cache available — rethrow original error
      rethrow;
    }
  }

  /// Fetch marks only (SGPA, CGPA, semester breakdowns) for either AUS or ACET/AEC.
  static Future<Map<String, dynamic>?> fetchMarksOnly(
    String rollNumber,
    String password, {
    String college = 'aus',
  }) async {
    if (college.toLowerCase() == 'acet' || college.toLowerCase() == 'aec') {
      return AecAttendanceService.fetchMarksOnly(
        rollNumber,
        password,
        college: college,
      );
    } else {
      final res = await AusAttendanceService.fetchAttendance(
        rollNumber,
        password,
      );
      return res['academicInsights'] as Map<String, dynamic>?;
    }
  }
}
