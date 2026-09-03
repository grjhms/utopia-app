import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/attendance_cache_service.dart';
import '../services/attendance_history_service.dart';
import '../services/attendance_service.dart';
import '../services/secure_storage_service.dart';
import '../widgets/utopia_snackbar.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/student_sprint_loader.dart';
import '../models/user_timetable.dart';
import '../services/user_timetable_service.dart';
import '../theme/m3_expressive_theme.dart';
import 'total_attendance_screen.dart';

enum _AttendanceViewState { initial, loading, loaded, error }

enum AttendanceFilterSort {
  defaultOrder,
  lowestFirst,
  highestFirst,
  criticalOnly,
  alphabetical,
  mostClasses,
}

typedef _AttendanceRangeMode = AttendanceRangeMode;

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  final TextEditingController _rollController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _selectedCollege = 'aus';

  late final AnimationController _glowController;
  _AttendanceViewState _state = _AttendanceViewState.loading;
  bool _obscurePassword = true;
  String? _errorMessage;
  Map<String, dynamic>? _attendanceData;
  Map<String, String>? _savedCredentials;
  UserTimetable? _userTimetable;
  bool _isFromCache = false;
  String? _cacheAgeLabel;
  int _currentTabIndex = 0;
  DateTime _selectedCalendarDate = DateTime.now();
  AttendanceFilterSort _selectedSortFilter = AttendanceFilterSort.defaultOrder;

  // ── Live sync & portal status ──
  bool _isSyncingLive = false;
  bool _portalDown = false;
  String? _portalErrorMessage;
  DateTime? _lastSyncTime;
  final Set<int> _expandedSemesters = {};
  late final AnimationController _syncMotionController;

  // ── Attendance loader progress ──
  double _fetchProgress = 0.0;
  Timer? _progressTimer;

  // ── Attendance target threshold (65% or 75%, default 75%) ──
  double _attendanceTarget = 0.75;
  int get _targetPercentage => (_attendanceTarget * 100).round();

  Future<void> _loadTargetPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble('attendance_target');
      if (saved != null && (saved == 0.65 || saved == 0.75)) {
        if (mounted) {
          setState(() {
            _attendanceTarget = saved;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _setTarget(double newTarget) async {
    setState(() {
      _attendanceTarget = newTarget;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('attendance_target', newTarget);
    } catch (_) {}
    if (mounted) {
      showUtopiaSnackBar(
        context,
        message: 'Attendance target set to $_targetPercentage%',
        tone: UtopiaSnackBarTone.success,
      );
    }
  }

  // ── Today's attendance for inline card ──
  Future<Map<String, dynamic>>? _todayAttendanceFuture;

  void _ensureTodayAttendanceLoaded({bool force = false}) {
    if ((_todayAttendanceFuture != null && !force) || _savedCredentials == null) return;
    final now = DateTime.now();
    final portalDate = _formatPortalDateForPortal(now);
    final creds = _savedCredentials!;
    _todayAttendanceFuture = AttendanceService.fetchAttendance(
      creds['rollNumber'] ?? '',
      creds['password'] ?? '',
      college: creds['college'] ?? _selectedCollege,
      fromDate: portalDate,
      toDate: portalDate,
      mode: AttendanceRangeMode.period,
    );
  }

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _syncMotionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_loadTargetPreference());
    unawaited(_loadSavedCredentials());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _syncMotionController.dispose();
    _glowController.dispose();
    _rollController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final credentials = await SecureStorageService.getCredentials();
      if (!mounted) {
        return;
      }
      if (credentials == null) {
        setState(() => _state = _AttendanceViewState.initial);
        return;
      }

      _savedCredentials = credentials;
      _rollController.text = credentials['rollNumber'] ?? '';
      _passwordController.text = credentials['password'] ?? '';
      final timetable = await UserTimetableService.getTimetable();
      final storedCollege = credentials['college'] ?? 'aus';
      final activeCollege = storedCollege == 'aec' ? 'acet' : storedCollege;
      final roll = _rollController.text.trim();

      // Check if we have cached attendance first (instant local retrieval)
      final cached = await AttendanceCacheService.load(roll);
      if (!mounted) {
        return;
      }

      if (cached != null) {
        // Cache exists! Immediately render loaded attendance dashboard without blocking loader
        setState(() {
          _selectedCollege = activeCollege;
          _userTimetable = timetable;
          _attendanceData = cached.data;
          _isFromCache = true;
          _lastSyncTime = cached.cachedAt;
          _cacheAgeLabel = cached.ageLabel;
          _state = _AttendanceViewState.loaded;
        });

        // Directly fetch fresh data from college portal in background
        unawaited(_fetchAttendanceLive(
          rollNumber: roll,
          password: _passwordController.text,
          college: activeCollege,
        ));
      } else {
        // No cache yet (first time ever connecting)
        setState(() {
          _selectedCollege = activeCollege;
          _userTimetable = timetable;
        });
        await _fetchAttendance(
          rollNumber: roll,
          password: _passwordController.text,
          college: activeCollege,
          saveCredentials: false,
          keepFormOnFailure: false,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Could not load saved attendance credentials';
        _state = _AttendanceViewState.error;
      });
    }
  }

  /// Directly fetches fresh attendance from college portal in background.
  /// Updates screen immediately on success. If failed, preserves cached data and flags portal as down.
  Future<void> _fetchAttendanceLive({
    required String rollNumber,
    required String password,
    required String college,
    _AttendanceRangeMode mode = _AttendanceRangeMode.tillNow,
  }) async {
    final trimmedRoll = rollNumber.trim();
    if (trimmedRoll.isEmpty || password.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _isSyncingLive = true;
        _portalDown = false;
        _portalErrorMessage = null;
      });
      _syncMotionController.repeat();
    }

    try {
      final isAcet = college == 'acet' || college == 'aec';
      final serviceMode = isAcet
          ? (mode == _AttendanceRangeMode.tillNow
                ? AttendanceRangeMode.tillNow
                : AttendanceRangeMode.period)
          : AttendanceRangeMode.period;

      final result = await AttendanceService.fetchAttendance(
        trimmedRoll,
        password,
        college: college,
        mode: serviceMode,
        forceLive: true,
      );

      _savedCredentials = {
        'rollNumber': trimmedRoll,
        'password': password,
        'college': college,
      };

      unawaited(AttendanceHistoryService.recordSnapshot(trimmedRoll, result));

      if (!mounted) {
        return;
      }

      _syncMotionController.stop();
      _syncMotionController.reset();

      // SUCCESS: Immediately update values on the screen!
      setState(() {
        _attendanceData = result;
        _isFromCache = false;
        _lastSyncTime = DateTime.now();
        _cacheAgeLabel = 'just now';
        _isSyncingLive = false;
        _portalDown = false;
        _portalErrorMessage = null;
        _state = _AttendanceViewState.loaded;
      });
    } catch (e) {
      debugPrint('[AttendanceScreen] live fetch failed: $e');
      if (!mounted) {
        return;
      }

      _syncMotionController.stop();
      _syncMotionController.reset();

      final message = _friendlyErrorMessage(e);
      if (_attendanceData != null) {
        // Keep previous cached attendance on screen and mark portal as down!
        // Also check if academic insights were saved in cache during the attempt!
        final cached = await AttendanceCacheService.load(trimmedRoll);
        if (!mounted) return;
        setState(() {
          _isSyncingLive = false;
          _portalDown = true;
          _portalErrorMessage = message;
          if (cached?.data['academicInsights'] != null) {
            _attendanceData!['academicInsights'] =
                cached!.data['academicInsights'];
          }
        });
      } else {
        // No previous data exists: try loading cache
        final cached = await AttendanceCacheService.load(trimmedRoll);
        if (cached != null) {
          setState(() {
            _attendanceData = cached.data;
            _isFromCache = true;
            _lastSyncTime = cached.cachedAt;
            _cacheAgeLabel = cached.ageLabel;
            _isSyncingLive = false;
            _portalDown = true;
            _portalErrorMessage = message;
            _state = _AttendanceViewState.loaded;
          });
        } else {
          setState(() {
            _errorMessage = message;
            _state = _AttendanceViewState.error;
            _isSyncingLive = false;
            _portalDown = true;
          });
        }
      }
    }
  }

  Future<void> _fetchAttendance({
    required String rollNumber,
    required String password,
    required String college,
    required bool saveCredentials,
    required bool keepFormOnFailure,
    _AttendanceRangeMode mode = _AttendanceRangeMode.tillNow,
  }) async {
    final trimmedRoll = rollNumber.trim();
    if (trimmedRoll.isEmpty || password.isEmpty) {
      showUtopiaSnackBar(
        context,
        message: 'Enter your roll number and portal password',
        tone: UtopiaSnackBarTone.error,
      );
      return;
    }

    if (saveCredentials) {
      await SecureStorageService.saveCredentials(
        trimmedRoll,
        password,
        college,
      );
      _savedCredentials = {
        'rollNumber': trimmedRoll,
        'password': password,
        'college': college,
      };
    }

    setState(() {
      _errorMessage = null;
      _state = _AttendanceViewState.loading;
      _fetchProgress = 0.0;
    });

    // ── Start simulated progress timer ──
    _progressTimer?.cancel();
    final rng = math.Random();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        final remaining = 0.92 - _fetchProgress;
        if (remaining <= 0.005) { timer.cancel(); return; }
        final step = remaining * (0.02 + rng.nextDouble() * 0.06);
        _fetchProgress = (_fetchProgress + step).clamp(0.0, 0.92);
      });
    });

    try {
      final isAcet = college == 'acet' || college == 'aec';
      final serviceMode = isAcet
          ? (mode == _AttendanceRangeMode.tillNow
                ? AttendanceRangeMode.tillNow
                : AttendanceRangeMode.period)
          : AttendanceRangeMode.period;

      final result = await AttendanceService.fetchAttendance(
        trimmedRoll,
        password,
        college: college,
        mode: serviceMode,
        forceLive: true,
      );

      _savedCredentials = {
        'rollNumber': trimmedRoll,
        'password': password,
        'college': college,
      };
      unawaited(AttendanceHistoryService.recordSnapshot(trimmedRoll, result));
      if (!mounted) {
        return;
      }
      _progressTimer?.cancel();
      // If newly fetched attendance has empty subjects, preserve existing records!
      final newSubjects = (result['subjects'] as List?) ?? [];
      final existingData = _attendanceData;
      final existingSubjects = (existingData?['subjects'] as List?) ?? [];

      Map<String, dynamic> finalData = result;
      bool isPreservedFromCache = result['fromCache'] as bool? ?? false;

      if (newSubjects.isEmpty && existingSubjects.isNotEmpty) {
        finalData = Map<String, dynamic>.from(existingData!);
        finalData['academicInsights'] = result['academicInsights'] ?? existingData['academicInsights'];
        finalData['attendanceUnavailable'] = true;
        isPreservedFromCache = true;
      } else if (newSubjects.isEmpty) {
        final cached = await AttendanceCacheService.load(trimmedRoll);
        if (cached != null && (cached.data['subjects'] as List? ?? []).isNotEmpty) {
          finalData = Map<String, dynamic>.from(cached.data);
          finalData['academicInsights'] = result['academicInsights'] ?? cached.data['academicInsights'];
          finalData['attendanceUnavailable'] = true;
          isPreservedFromCache = true;
        }
      }

      setState(() {
        _attendanceData = finalData;
        _isFromCache = isPreservedFromCache;
        _cacheAgeLabel = finalData['cacheAgeLabel'] as String? ?? 'just now';
        _lastSyncTime = DateTime.now();
        _isSyncingLive = false;
        _portalDown = false;
        _portalErrorMessage = finalData['attendanceUnavailable'] == true ? 'Attendance records unavailable' : null;
        _state = _AttendanceViewState.loaded;
      });
    } catch (e) {
      _progressTimer?.cancel();
      final message = _friendlyErrorMessage(e);
      if (!mounted) {
        return;
      }

      // Check if cache exists for this student!
      final cached = await AttendanceCacheService.load(trimmedRoll);
      if (cached != null) {
        setState(() {
          _attendanceData = cached.data;
          _isFromCache = true;
          _lastSyncTime = cached.cachedAt;
          _cacheAgeLabel = cached.ageLabel;
          _isSyncingLive = false;
          _portalDown = true;
          _portalErrorMessage = message;
          _state = _AttendanceViewState.loaded;
        });
        if (mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Portal is currently down. Showing saved attendance.',
            tone: UtopiaSnackBarTone.info,
          );
        }
        return;
      }

      if (keepFormOnFailure) {
        if (!mounted) return;
        setState(() => _state = _AttendanceViewState.initial);
        showUtopiaSnackBar(
          context,
          message: message,
          tone: UtopiaSnackBarTone.error,
        );
        return;
      }

      setState(() {
        _errorMessage = message;
        _state = _AttendanceViewState.error;
      });
    }
  }

  Future<void> _refresh() async {
    final credentials = _savedCredentials;
    if (credentials == null) {
      return;
    }
    final timetable = await UserTimetableService.getTimetable();
    if (mounted) {
      setState(() {
        _userTimetable = timetable;
        _todayAttendanceFuture = null;
      });
    }

    // If attendance data is already displayed, refresh in background without full-screen loading!
    if (_attendanceData != null) {
      await _fetchAttendanceLive(
        rollNumber: credentials['rollNumber'] ?? '',
        password: credentials['password'] ?? '',
        college: credentials['college'] ?? 'aus',
        mode: _AttendanceRangeMode.tillNow,
      );
    } else {
      await _fetchAttendance(
        rollNumber: credentials['rollNumber'] ?? '',
        password: credentials['password'] ?? '',
        college: credentials['college'] ?? 'aus',
        saveCredentials: false,
        keepFormOnFailure: false,
        mode: _AttendanceRangeMode.tillNow,
      );
    }
  }

  Future<void> _loadCachedAttendance() async {
    final roll = _savedCredentials?['rollNumber'] ?? _rollController.text.trim();
    if (roll.isEmpty) return;

    final cached = await AttendanceCacheService.load(roll);
    if (cached != null && mounted) {
      setState(() {
        _attendanceData = cached.data;
        _isFromCache = true;
        _lastSyncTime = cached.cachedAt;
        _cacheAgeLabel = cached.ageLabel;
        _state = _AttendanceViewState.loaded;
      });
    } else if (mounted) {
      showUtopiaSnackBar(
        context,
        message: 'No saved offline attendance found for $roll',
        tone: UtopiaSnackBarTone.info,
      );
    }
  }

  String _formatSyncTimeLabel() {
    final time = _lastSyncTime;
    if (time == null) {
      if (_cacheAgeLabel != null && _cacheAgeLabel!.isNotEmpty) {
        return _cacheAgeLabel!;
      }
      return 'earlier';
    }

    final now = DateTime.now();
    final diff = now.difference(time);

    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $period';

    if (diff.inMinutes < 1) {
      return 'just now';
    }

    if (diff.inMinutes < 30) {
      return '${diff.inMinutes} min ago';
    }

    final isSameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    if (isSameDay) {
      return timeStr;
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = time.year == yesterday.year && time.month == yesterday.month && time.day == yesterday.day;
    if (isYesterday) {
      return 'Yesterday, $timeStr';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[time.month - 1]} ${time.day}';
  }

  Widget _buildTopSyncBar() {
    final lastTimeLabel = _formatSyncTimeLabel();

    // ── 1. PORTAL IS DOWN / FAILED ──
    if (_portalDown) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: U.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: U.red.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: U.red.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.cloud_off_rounded, color: U.red, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'College portal is down',
                          style: GoogleFonts.outfit(
                            color: U.red,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: U.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'OFFLINE',
                          style: GoogleFonts.outfit(
                            color: U.red,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _portalErrorMessage != null && _portalErrorMessage!.isNotEmpty && !_portalErrorMessage!.contains('Exception')
                        ? '$_portalErrorMessage • Saved ($lastTimeLabel)'
                        : 'Saved data ($lastTimeLabel)',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _refresh,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: U.red.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 14, color: U.red),
                    const SizedBox(width: 4),
                    Text(
                      'Retry',
                      style: GoogleFonts.outfit(
                        color: U.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0, duration: 250.ms);
    }

    // ── 2. SYNCING LIVE IN BACKGROUND ──
    if (_isSyncingLive) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: U.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: U.primary.withValues(alpha: 0.28),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: RotationTransition(
                  turns: _syncMotionController,
                  child: Icon(
                    Icons.sync_rounded,
                    color: U.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Syncing with college portal...',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LIVE',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                            begin: const Offset(0.92, 0.92),
                            end: const Offset(1.08, 1.08),
                            duration: 700.ms,
                          ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Updating records...',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms);
    }

    // ── 3. SYNCED & UP TO DATE (IDLE STATE) ──
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 6),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: U.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: U.green.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isFromCache
                  ? 'Saved • $lastTimeLabel'
                  : 'Synced • $lastTimeLabel',
              style: GoogleFonts.outfit(
                color: U.sub,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: _refresh,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync_rounded, size: 13, color: U.sub),
                  const SizedBox(width: 3),
                  Text(
                    'Sync',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    final shouldDisconnect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: U.card,
        title: Text(
          'Disconnect portal',
          style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove your attendance credentials from this device?',
          style: GoogleFonts.outfit(color: U.sub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub)),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: U.red.withValues(alpha: 0.16),
              foregroundColor: U.red,
            ),
            child: Text(
              'Disconnect',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (shouldDisconnect != true) {
      return;
    }

    _progressTimer?.cancel();
    _isSyncingLive = false;
    await SecureStorageService.clearCredentials();
    final roll = _savedCredentials?['rollNumber'] ?? '';
    if (roll.isNotEmpty) {
      unawaited(AttendanceCacheService.clear(roll));
      unawaited(AttendanceHistoryService.clearHistory(roll));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _savedCredentials = null;
      _attendanceData = null;
      _errorMessage = null;
      _isFromCache = false;
      _cacheAgeLabel = null;
      _rollController.clear();
      _passwordController.clear();
      _selectedCollege = 'aus';
      _state = _AttendanceViewState.initial;
      _todayAttendanceFuture = null;
    });
  }

  Widget _buildThreeDotsMenu() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: U.text),
      color: U.surfaceContainerHigh,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: U.border),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'refresh_all':
            _refresh();
            break;
          case 'refresh_marks':
            _refreshMarksOnly();
            break;
          case 'today_sheet':
            _showTodaySheet();
            break;
          case 'total_summary':
            if (_attendanceData != null && _savedCredentials != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TotalAttendanceScreen(
                    attendanceData: _attendanceData!,
                    credentials: _savedCredentials!,
                  ),
                ),
              );
            } else {
              showUtopiaSnackBar(
                context,
                message: 'Connect to portal to view total summary',
                tone: UtopiaSnackBarTone.info,
              );
            }
            break;
          case 'change_target':
            _showTargetSelectionDialog();
            break;
          case 'account_info':
            _showAccountInfoDialog();
            break;
          case 'disconnect':
            _disconnect();
            break;
        }
      },
      itemBuilder: (context) {
        final hasData = _attendanceData != null;
        final hasSavedCreds = _savedCredentials != null;
        return [
          if (hasData) ...[
            _buildPopupItem(
              value: 'refresh_all',
              icon: Icons.sync_rounded,
              title: 'Sync All Data',
              subtitle: 'Live portal refresh',
            ),
            if (_selectedCollege == 'aus' || _selectedCollege == 'acet' || _selectedCollege == 'aec')
              _buildPopupItem(
                value: 'refresh_marks',
                icon: Icons.school_rounded,
                title: 'Sync Marks Only',
                subtitle: 'Fetch latest marks & SGPA',
              ),
            _buildPopupItem(
              value: 'today_sheet',
              icon: Icons.today_rounded,
              title: "Today's Attendance",
              subtitle: 'Periods held today',
            ),
            _buildPopupItem(
              value: 'total_summary',
              icon: Icons.summarize_rounded,
              title: 'Total Attendance',
              subtitle: 'Held vs Attended metrics',
            ),
            const PopupMenuDivider(),
          ],
          _buildPopupItem(
            value: 'change_target',
            icon: Icons.track_changes_rounded,
            title: 'Attendance Target',
            subtitle: 'Currently $_targetPercentage% (65% or 75%)',
          ),
          if (hasSavedCreds)
            _buildPopupItem(
              value: 'account_info',
              icon: Icons.badge_rounded,
              title: 'Connected Account',
              subtitle: _savedCredentials?['rollNumber'] ?? 'Info',
            ),
          _buildPopupItem(
            value: 'disconnect',
            icon: Icons.logout_rounded,
            title: 'Log out',
            subtitle: 'Clear credentials & reset',
            isDestructive: true,
          ),
        ];
      },
    );
  }

  PopupMenuItem<String> _buildPopupItem({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive ? U.red : U.text;
    final iconColor = isDestructive ? U.red : U.primary;

    return PopupMenuItem<String>(
      value: value,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: textColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.robotoFlex(
                      color: U.sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTargetSelectionDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = appThemeNotifier.value.isDark;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: isDark ? U.surfaceContainerHigh : U.surfaceContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: U.outlineVariant.withValues(alpha: 0.25),
                  width: 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: U.outlineVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.track_changes_rounded, color: U.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attendance Target',
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Select your minimum safe percentage threshold',
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildTargetOption(
                    percentage: 75,
                    title: '75% (Default Target)',
                    subtitle: 'Standard university requirement. Safe from condonation.',
                    isSelected: _targetPercentage == 75,
                    onTap: () {
                      _setTarget(0.75);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildTargetOption(
                    percentage: 65,
                    title: '65% (Condonation Target)',
                    subtitle: 'Minimum margin allowed with medical certificate / condonation.',
                    isSelected: _targetPercentage == 65,
                    onTap: () {
                      _setTarget(0.65);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTargetOption({
    required int percentage,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = appThemeNotifier.value.isDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? U.primary.withValues(alpha: 0.10)
              : (isDark ? U.surfaceContainerLowest.withValues(alpha: 0.5) : U.surfaceContainerLowest),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? U.primary : U.outlineVariant.withValues(alpha: 0.25),
            width: isSelected ? 1.4 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? U.primary : U.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '$percentage%',
                  style: GoogleFonts.outfit(
                    color: isSelected ? U.bg : U.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? U.primary : U.sub,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountInfoDialog() {
    final roll = _savedCredentials?['rollNumber'] ?? _rollController.text.trim();
    final college = (_selectedCollege == 'aec' ? 'ACET' : _selectedCollege).toUpperCase();
    final lastTime = _formatSyncTimeLabel();
    final overall = (_attendanceData?['overallPercentage'] as num?)?.toDouble();
    final cgpa = (_attendanceData?['academicInsights']?['cgpa'] as num?)?.toDouble();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: U.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.badge_rounded, color: U.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Connected Account',
              style: GoogleFonts.outfit(
                color: U.text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Roll Number', roll),
            const SizedBox(height: 10),
            _buildInfoRow('College', college),
            const SizedBox(height: 10),
            _buildInfoRow('Last Synced', lastTime),
            if (overall != null) ...[
              const SizedBox(height: 10),
              _buildInfoRow('Attendance', '${overall.toStringAsFixed(1)}%'),
            ],
            if (cgpa != null) ...[
              const SizedBox(height: 10),
              _buildInfoRow('CGPA', cgpa.toStringAsFixed(2)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.outfit(color: U.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.robotoFlex(
            color: U.sub,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: U.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Future<void> _refreshMarksOnly() async {
    final credentials = _savedCredentials;
    if (credentials == null) return;
    final roll = credentials['rollNumber'] ?? '';
    final pwd = credentials['password'] ?? '';
    final college = credentials['college'] ?? _selectedCollege;

    if (roll.isEmpty || pwd.isEmpty) return;

    showUtopiaSnackBar(
      context,
      message: 'Syncing academic marks from ${college.toUpperCase()} portal...',
      tone: UtopiaSnackBarTone.info,
    );

    try {
      final marks = await AttendanceService.fetchMarksOnly(roll, pwd, college: college);
      if (marks != null && mounted) {
        setState(() {
          if (_attendanceData != null) {
            _attendanceData!['academicInsights'] = marks;
          }
        });
        showUtopiaSnackBar(
          context,
          message: 'Academic marks updated successfully',
          tone: UtopiaSnackBarTone.success,
        );
      } else {
        _fetchAttendanceLive(
          rollNumber: roll,
          password: pwd,
          college: college,
        );
      }
    } catch (_) {
      _fetchAttendanceLive(
        rollNumber: roll,
        password: pwd,
        college: college,
      );
    }
  }

  // ── Academic Insights Section (AUS Portal) ──
  Widget _buildAcademicInsightsSection(Map<String, dynamic> data) {
    final academic = data['academicInsights'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, color: U.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Academic Insights',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (_isSyncingLive)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (academic == null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: U.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: U.outlineVariant.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: U.sub, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _isSyncingLive ? 'Fetching marks...' : 'Marks unavailable',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            _buildCgpaHeroCard(academic),
            const SizedBox(height: 12),
            _buildSemestersBreakdown(academic),
            const SizedBox(height: 14),
            _buildAcademicGrowthGraph(academic),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildCgpaHeroCard(Map<String, dynamic> academic) {
    final cgpa = (academic['cgpa'] as num?)?.toDouble() ?? 0.0;
    final passed = (academic['passed'] as num?)?.toInt() ?? 0;
    final failed = (academic['failed'] as num?)?.toInt() ?? 0;
    final credits = (academic['credits'] ?? '').toString().trim();

    final isDark = appThemeNotifier.value.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? U.surfaceContainerHigh : U.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'CGPA',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                cgpa.toStringAsFixed(2),
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ 10',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSimpleStatPill(
                label: 'Passed',
                value: '$passed',
                color: U.green,
              ),
              _buildSimpleStatPill(
                label: 'Backlogs',
                value: '$failed',
                color: failed == 0 ? U.green : U.red,
              ),
              if (credits.isNotEmpty && credits != '0' && credits != '0.0')
                _buildSimpleStatPill(
                  label: 'Credits',
                  value: credits,
                  color: U.primary,
                ),
              if ((academic['percentage'] ?? '').toString().trim().isNotEmpty)
                _buildSimpleStatPill(
                  label: 'Overall',
                  value: '${(academic['percentage'] ?? '').toString().trim()}%',
                  color: U.peach,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStatPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value ',
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemestersBreakdown(Map<String, dynamic> academic) {
    final semesters = (academic['semesters'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (semesters.isEmpty) return const SizedBox.shrink();

    final isDark = appThemeNotifier.value.isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: semesters.asMap().entries.map((entry) {
        final idx = entry.key;
        final sem = entry.value;
        final title = sem['title'] as String? ?? 'Semester ${idx + 1}';
        final sgpa = (sem['sgpa'] as num?)?.toDouble() ?? 0.0;
        final credits = (sem['credits'] as String? ?? '').trim();
        final courses = (sem['courses'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final isExpanded = _expandedSemesters.contains(idx);

        String displayTitle = title;
        if (title.contains('Semester')) {
          displayTitle = title.replaceAll('-', ' – ');
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark ? U.surfaceContainerHigh : U.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded
                  ? U.primary.withValues(alpha: 0.35)
                  : U.outlineVariant.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedSemesters.remove(idx);
                    } else {
                      _expandedSemesters.add(idx);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'S${idx + 1}',
                            style: GoogleFonts.outfit(
                              color: U.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${courses.length} subjects${credits.isNotEmpty ? ' • $credits cr' : ''}',
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: U.primary.withValues(alpha: 0.20),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          '${sgpa.toStringAsFixed(2)} SGPA',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: U.sub,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (isExpanded && courses.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Divider(
                    height: 1,
                    thickness: 0.6,
                    color: U.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    children: courses.map((c) => _buildCourseRow(c)).toList(),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCourseRow(Map<String, dynamic> c) {
    final code = c['courseCode'] as String? ?? '';
    final name = c['courseName'] as String? ?? '';
    final grade = (c['grade'] as String? ?? '').trim();
    final points = (c['points'] as String? ?? '').trim();
    final credits = (c['credits'] as String? ?? '').trim();
    final isFail = grade == 'F' || (c['result'] ?? '').toString().toUpperCase() == 'FAIL';

    final isDark = appThemeNotifier.value.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark
            ? U.surfaceContainerLowest.withValues(alpha: 0.5)
            : U.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.18),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isFail
                  ? U.red.withValues(alpha: 0.12)
                  : (grade == 'O' || grade == 'S' || grade == 'A'
                      ? U.primary.withValues(alpha: 0.10)
                      : (isDark ? U.surfaceContainerHigh : U.surfaceContainerHighest.withValues(alpha: 0.6))),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isFail
                    ? U.red.withValues(alpha: 0.3)
                    : (grade == 'O' || grade == 'S' || grade == 'A'
                        ? U.primary.withValues(alpha: 0.25)
                        : U.outlineVariant.withValues(alpha: 0.2)),
                width: 0.6,
              ),
            ),
            child: Center(
              child: Text(
                grade.isNotEmpty ? grade : '—',
                style: GoogleFonts.outfit(
                  color: isFail
                      ? U.red
                      : (grade == 'O' || grade == 'S' || grade == 'A' ? U.primary : U.text),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (credits.isNotEmpty && credits != '0' && credits != '0.0') '$credits credits',
                    if (code.isNotEmpty && code != name) code,
                    if (isFail) 'Backlog',
                  ].join(' • '),
                  style: GoogleFonts.outfit(
                    color: isFail ? U.red : U.sub,
                    fontSize: 11,
                    fontWeight: isFail ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isFail)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: U.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: U.red.withValues(alpha: 0.3), width: 0.7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '0',
                    style: GoogleFonts.outfit(
                      color: U.red,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'pts',
                    style: GoogleFonts.outfit(
                      color: U.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (points == '10' || points == '9')
                    ? U.primary.withValues(alpha: 0.12)
                    : (isDark
                        ? U.surfaceContainerHigh
                        : U.surfaceContainerHighest.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (points == '10' || points == '9')
                      ? U.primary.withValues(alpha: 0.25)
                      : U.outlineVariant.withValues(alpha: 0.2),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    points.isNotEmpty ? points : '—',
                    style: GoogleFonts.outfit(
                      color: (points == '10' || points == '9') ? U.primary : U.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'pts',
                    style: GoogleFonts.outfit(
                      color: (points == '10' || points == '9')
                          ? U.primary.withValues(alpha: 0.8)
                          : U.sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAcademicGrowthGraph(Map<String, dynamic> academic) {
    final semesters = (academic['semesters'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (semesters.isEmpty) return const SizedBox.shrink();

    final sgpas = <double>[];
    for (final s in semesters) {
      sgpas.add((s['sgpa'] as num?)?.toDouble() ?? 0.0);
    }

    final cgpa = (academic['cgpa'] as num?)?.toDouble() ?? 0.0;
    final isDark = appThemeNotifier.value.isDark;

    double delta = 0.0;
    if (sgpas.length >= 2) {
      delta = sgpas.last - sgpas.first;
    }

    double highestSgpa = 0.0;
    int highestSemIdx = 0;
    for (int i = 0; i < sgpas.length; i++) {
      if (sgpas[i] >= highestSgpa) {
        highestSgpa = sgpas[i];
        highestSemIdx = i + 1;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? U.surfaceContainerHigh : U.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.trending_up_rounded, color: U.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Performance & Growth',
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'SGPA progression across semesters',
                      style: GoogleFonts.outfit(
                        color: U.sub,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (sgpas.length >= 2)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: (delta >= 0 ? U.green : U.red).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (delta >= 0 ? U.green : U.red).withValues(alpha: 0.25),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        delta >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: delta >= 0 ? U.green : U.red,
                        size: 13,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          color: delta >= 0 ? U.green : U.red,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Graph Canvas
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _AcademicGrowthChartPainter(
                sgpas: sgpas,
                cgpa: cgpa,
                primaryColor: U.primary,
                textColor: U.text,
                subTextColor: U.sub,
                gridColor: U.outlineVariant.withValues(alpha: 0.25),
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Metric Insight Tiles
          Row(
            children: [
              Expanded(
                child: _buildGrowthMetricTile(
                  label: 'Highest SGPA',
                  value: highestSgpa.toStringAsFixed(2),
                  subValue: 'Sem $highestSemIdx',
                  color: U.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildGrowthMetricTile(
                  label: 'Latest SGPA',
                  value: sgpas.isNotEmpty ? sgpas.last.toStringAsFixed(2) : '—',
                  subValue: 'Sem ${sgpas.length}',
                  color: U.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildGrowthMetricTile(
                  label: 'Cumulative',
                  value: cgpa > 0 ? cgpa.toStringAsFixed(2) : '—',
                  subValue: 'CGPA',
                  color: U.peach,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthMetricTile({
    required String label,
    required String value,
    required String subValue,
    required Color color,
  }) {
    final isDark = appThemeNotifier.value.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? U.surfaceContainerLowest.withValues(alpha: 0.5) : U.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.15),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: U.sub,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  subValue,
                  style: GoogleFonts.outfit(
                    color: U.sub,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _friendlyErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Something went wrong while fetching attendance';
    }
    return message;
  }

  Color _percentageColor(double value) {
    if (value <= 0) {
      return U.primary;
    }
    if (value >= _targetPercentage) {
      return U.green;
    }
    if (value >= (_targetPercentage - 10)) {
      return U.peach;
    }
    return U.red;
  }

  IconData _subjectIcon(String subject) {
    final key = subject.toLowerCase();
    if (key.contains('devc') || key.contains('ppsuc')) {
      return Icons.code_rounded;
    }
    if (key.contains('beee') || key.contains('e.')) {
      return Icons.electrical_services_rounded;
    }
    if (key.contains('iot')) return Icons.memory_rounded;
    if (key.contains('dtai')) return Icons.auto_awesome_rounded;
    if (key.contains('env')) return Icons.eco_rounded;
    if (key.contains('emp')) return Icons.psychology_alt_rounded;
    return Icons.book_rounded;
  }

  String _headlineFor(double overall) {
    if (overall <= 0) {
      return 'Unavailable';
    }
    if (overall >= 85) {
      return 'Locked in';
    }
    if (overall >= _targetPercentage) {
      return 'On track';
    }
    if (overall >= (_targetPercentage - 10)) {
      return 'Recoverable';
    }
    return 'Needs attention';
  }

  int _missableClasses(int attended, int held) {
    if (held <= 0 || attended <= 0) {
      return 0;
    }
    return ((attended / _attendanceTarget) - held).floor().clamp(0, 9999);
  }

  int _classesNeededToRecover(int attended, int held) {
    if (held <= 0) {
      return 0;
    }
    final needed =
        ((_attendanceTarget * held) - attended) / (1 - _attendanceTarget);
    return needed.ceil().clamp(0, 9999);
  }

  String _heroStatusText(int belowTargetCount, {int totalSubjects = 1, double overall = 100}) {
    if (totalSubjects == 0 || overall <= 0) {
      return 'Attendance records unavailable';
    }
    if (belowTargetCount > 0) {
      return '$belowTargetCount subject${belowTargetCount == 1 ? '' : 's'} need attention';
    }
    return 'All subjects are on track';
  }

  String _formatPortalDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _showTodaySheet() async {
    debugPrint('[DEBUG][Attendance] _showTodaySheet called');
    final credentials = _savedCredentials;
    debugPrint(
      '[DEBUG][Attendance] credentials: ${credentials != null ? "found" : "null"}',
    );
    if (credentials == null) {
      return;
    }
    final now = DateTime.now();
    final todayLabel = _formatPortalDate(now);
    final portalDate = _formatPortalDateForPortal(now);
    debugPrint(
      '[DEBUG][Attendance] Today: label=$todayLabel, portalDate=$portalDate',
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AttendanceDateSheet(
        title: 'Today',
        dateLabel: todayLabel,
        date: now,
        credentials: credentials,
        onRefresh: _refresh,
        portalDateLabel: portalDate,
        mode: _AttendanceRangeMode.period,
      ),
    );
    debugPrint('[DEBUG][Attendance] _showTodaySheet completed');
  }



  String _formatPortalDateForPortal(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day-$month-${dt.year}';
  }

  String _formatDisplayDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLoadedActions = _state == _AttendanceViewState.loaded;
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance',
              style: GoogleFonts.outfit(
                color: U.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _isSyncingLive
                  ? 'Syncing live data...'
                  : (_portalDown
                      ? 'Portal offline • Showing cached'
                      : (_currentTabIndex == 2 ? 'Insights' : 'Overview')),
              style: GoogleFonts.outfit(
                color: _portalDown
                    ? U.red
                    : (_isSyncingLive ? U.primary : U.sub),
                fontSize: 12,
                fontWeight: (_portalDown || _isSyncingLive)
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (showLoadedActions)
            IconButton(
              onPressed: _isSyncingLive ? null : _refresh,
              tooltip: _isSyncingLive ? 'Syncing...' : 'Sync Portal Data',
              icon: _isSyncingLive
                  ? RotationTransition(
                      turns: _syncMotionController,
                      child: Icon(Icons.sync_rounded, color: U.primary, size: 22),
                    )
                  : Icon(Icons.sync_rounded, color: U.text, size: 22),
            ),
          _buildThreeDotsMenu(),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: switch (_state) {
            _AttendanceViewState.initial => _buildInitialState(),
            _AttendanceViewState.loading => _buildLoadingState(),
            _AttendanceViewState.loaded => _buildLoadedState(),
            _AttendanceViewState.error => _buildErrorState(),
          },
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      key: const ValueKey('attendance_initial'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Center(
            child: Column(
              children: [
                Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: U.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.fact_check_rounded,
                        color: U.primary,
                        size: 28,
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                      duration: 500.ms,
                      curve: Curves.easeOutBack,
                    ),
                const SizedBox(height: 12),
                Text(
                      'Connect Attendance',
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 100.ms, duration: 500.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      delay: 100.ms,
                      duration: 500.ms,
                    ),
                const SizedBox(height: 6),
                Text(
                  'Your data stays on this device only',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: U.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: U.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedCollege = 'aus'),
                            child: Container(
                              height: 44,
                              color: _selectedCollege == 'aus'
                                  ? U.primary
                                  : U.surface,
                              child: Center(
                                child: Text(
                                  'AUS',
                                  style: GoogleFonts.outfit(
                                    color: _selectedCollege == 'aus'
                                        ? U.bg
                                        : U.sub,
                                    fontSize: 14,
                                    fontWeight: _selectedCollege == 'aus'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedCollege = 'acet'),
                            child: Container(
                              height: 44,
                              color: (_selectedCollege == 'acet' || _selectedCollege == 'aec')
                                  ? U.primary
                                  : U.surface,
                              child: Center(
                                child: Text(
                                  'ACET',
                                  style: GoogleFonts.outfit(
                                    color: (_selectedCollege == 'acet' || _selectedCollege == 'aec')
                                        ? U.bg
                                        : U.sub,
                                    fontSize: 14,
                                    fontWeight: (_selectedCollege == 'acet' || _selectedCollege == 'aec')
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _rollController,
                    hintText: _selectedCollege == 'aus'
                        ? 'e.g. 25B11ME038'
                        : 'e.g. 24P31A42F2',
                    labelText: 'Roll Number',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _passwordController,
                    hintText: 'Your portal password',
                    labelText: 'Password',
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      color: U.sub,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _state == _AttendanceViewState.loading
                          ? null
                          : () => _fetchAttendance(
                              rollNumber: _rollController.text,
                              password: _passwordController.text,
                              college: _selectedCollege,
                              saveCredentials: true,
                              keepFormOnFailure: false,
                            ),
                      icon: const Icon(Icons.sync_lock_rounded, size: 18),
                      label: Text(
                        'Connect',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: U.primary,
                        foregroundColor: U.bg,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      key: const ValueKey('attendance_loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(U.primary),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Connecting to college portal...',
            style: GoogleFonts.outfit(
              color: U.sub,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _disconnect,
            icon: Icon(Icons.logout_rounded, size: 16, color: U.red),
            label: Text(
              'Log out / Cancel',
              style: GoogleFonts.outfit(
                color: U.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: U.red.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedState() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Column(
        children: [
          _buildTopSyncBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: () {
                switch (_currentTabIndex) {
                  case 2:
                    return _buildInsightsTab();
                  case 0:
                  default:
                    return _buildOverviewTab();
                }
              }(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    final isDark = appThemeNotifier.value.isDark;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: isDark
                    ? U.surface.withValues(alpha: 0.55)
                    : U.surface.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.6),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.donut_large_rounded, 'Overview'),
                  _buildNavItem(2, Icons.bar_chart_rounded, 'Insights'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentTabIndex == index;
    final color = isSelected ? U.primary : U.sub;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTabIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 12 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: U.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getProcessedSubjects(List<Map<String, dynamic>> rawSubjects) {
    List<Map<String, dynamic>> list = List.from(rawSubjects);

    switch (_selectedSortFilter) {
      case AttendanceFilterSort.defaultOrder:
        return list;
      case AttendanceFilterSort.lowestFirst:
        list.sort((a, b) {
          final aPct = (a['percentage'] as num?)?.toDouble() ?? 0.0;
          final bPct = (b['percentage'] as num?)?.toDouble() ?? 0.0;
          return aPct.compareTo(bPct);
        });
        return list;
      case AttendanceFilterSort.highestFirst:
        list.sort((a, b) {
          final aPct = (a['percentage'] as num?)?.toDouble() ?? 0.0;
          final bPct = (b['percentage'] as num?)?.toDouble() ?? 0.0;
          return bPct.compareTo(aPct);
        });
        return list;
      case AttendanceFilterSort.criticalOnly:
        return list.where((s) {
          final pct = (s['percentage'] as num?)?.toDouble() ?? 0.0;
          return pct < _targetPercentage.toDouble();
        }).toList();
      case AttendanceFilterSort.alphabetical:
        list.sort((a, b) {
          final aName = (a['subject'] ?? '').toString();
          final bName = (b['subject'] ?? '').toString();
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });
        return list;
      case AttendanceFilterSort.mostClasses:
        list.sort((a, b) {
          final aHeld = (a['totalClasses'] as num?)?.toInt() ?? 0;
          final bHeld = (b['totalClasses'] as num?)?.toInt() ?? 0;
          return bHeld.compareTo(aHeld);
        });
        return list;
    }
  }

  String _getSortFilterLabel(AttendanceFilterSort sort) {
    switch (sort) {
      case AttendanceFilterSort.defaultOrder:
        return 'Default Portal Order';
      case AttendanceFilterSort.lowestFirst:
        return 'Lowest Attendance First';
      case AttendanceFilterSort.highestFirst:
        return 'Highest Attendance First';
      case AttendanceFilterSort.criticalOnly:
        return 'Needs Attention Only (< $_targetPercentage%)';
      case AttendanceFilterSort.alphabetical:
        return 'Alphabetical (A → Z)';
      case AttendanceFilterSort.mostClasses:
        return 'Most Classes Held';
    }
  }

  String _getSortFilterShortLabel(AttendanceFilterSort sort) {
    switch (sort) {
      case AttendanceFilterSort.defaultOrder:
        return 'Default';
      case AttendanceFilterSort.lowestFirst:
        return 'Lowest %';
      case AttendanceFilterSort.highestFirst:
        return 'Highest %';
      case AttendanceFilterSort.criticalOnly:
        return '< $_targetPercentage% Only';
      case AttendanceFilterSort.alphabetical:
        return 'A → Z';
      case AttendanceFilterSort.mostClasses:
        return 'Most Held';
    }
  }

  IconData _getSortFilterIcon(AttendanceFilterSort sort) {
    switch (sort) {
      case AttendanceFilterSort.defaultOrder:
        return Icons.swap_vert_rounded;
      case AttendanceFilterSort.lowestFirst:
        return Icons.warning_amber_rounded;
      case AttendanceFilterSort.highestFirst:
        return Icons.check_circle_outline_rounded;
      case AttendanceFilterSort.criticalOnly:
        return Icons.filter_alt_rounded;
      case AttendanceFilterSort.alphabetical:
        return Icons.sort_by_alpha_rounded;
      case AttendanceFilterSort.mostClasses:
        return Icons.bar_chart_rounded;
    }
  }

  Widget _buildFilterDropdown() {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: U.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: U.outlineVariant.withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
          elevation: 8,
        ),
      ),
      child: ClipRRect(
        borderRadius: M3Shapes.fullRadius,
        child: PopupMenuButton<AttendanceFilterSort>(
          initialValue: _selectedSortFilter,
          borderRadius: M3Shapes.fullRadius,
          clipBehavior: Clip.antiAlias,
          tooltip: 'Filter subjects',
          onSelected: (sort) {
            setState(() {
              _selectedSortFilter = sort;
            });
          },
          offset: const Offset(0, 44),
          itemBuilder: (context) {
            return AttendanceFilterSort.values.map((sort) {
              final isSelected = sort == _selectedSortFilter;
              return PopupMenuItem<AttendanceFilterSort>(
                value: sort,
                child: Row(
                  children: [
                    Icon(
                      _getSortFilterIcon(sort),
                      size: 18,
                      color: isSelected ? U.primary : U.sub,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getSortFilterLabel(sort),
                        style: GoogleFonts.robotoFlex(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected ? U.primary : U.text,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: U.primary,
                      ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _selectedSortFilter != AttendanceFilterSort.defaultOrder
                  ? U.primary.withValues(alpha: 0.14)
                  : U.surfaceContainerHigh,
              borderRadius: M3Shapes.fullRadius,
              border: Border.all(
                color: _selectedSortFilter != AttendanceFilterSort.defaultOrder
                  ? U.primary.withValues(alpha: 0.5)
                  : U.outlineVariant.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getSortFilterIcon(_selectedSortFilter),
                  size: 16,
                  color: _selectedSortFilter != AttendanceFilterSort.defaultOrder
                      ? U.primary
                      : U.text,
                ),
                const SizedBox(width: 6),
                Text(
                  _getSortFilterShortLabel(_selectedSortFilter),
                  style: GoogleFonts.robotoFlex(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _selectedSortFilter != AttendanceFilterSort.defaultOrder
                        ? U.primary
                        : U.text,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _selectedSortFilter != AttendanceFilterSort.defaultOrder
                      ? U.primary
                      : U.sub,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final data = _attendanceData ?? const <String, dynamic>{};
    final subjects = (data['subjects'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final processedSubjects = _getProcessedSubjects(subjects);
    final studentName = (data['studentName'] as String? ?? '').trim();
    final overall = (data['overallPercentage'] as num?)?.toDouble() ?? 0;
    final overallColor = _percentageColor(overall);
    final belowTarget = subjects.where((subject) {
      final percentage = (subject['percentage'] as num?)?.toDouble() ?? 0;
      return percentage < _targetPercentage;
    }).length;

    return Stack(
      children: [
        RefreshIndicator(
          color: U.primary,
          backgroundColor: U.card,
          onRefresh: _refresh,
          child: CustomScrollView(
            key: const ValueKey('attendance_loaded'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GradientHero(
                        icon: Icons.timeline_rounded,
                        eyebrow: (overall <= 0 || subjects.isEmpty)
                            ? 'Unavailable'
                            : _headlineFor(overall),
                        title: (overall <= 0 && subjects.isEmpty)
                            ? '—'
                            : '${overall.toStringAsFixed(1)}%',
                        subtitle: _heroStatusText(
                          belowTarget,
                          totalSubjects: subjects.length,
                          overall: overall,
                        ),
                        detail: studentName.isEmpty ? null : studentName,
                        accent: (overall <= 0 || subjects.isEmpty)
                            ? U.primary
                            : overallColor,
                        subtitleColor: (overall <= 0 || subjects.isEmpty)
                            ? U.sub
                            : (belowTarget > 0 ? U.red : null),
                      ),
                      if (subjects.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Subjects',
                                  style: GoogleFonts.robotoFlex(
                                    color: U.text,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedSortFilter == AttendanceFilterSort.criticalOnly
                                      ? '${processedSubjects.length} of ${subjects.length} subjects in danger'
                                      : '${processedSubjects.length} subjects enrolled',
                                  style: GoogleFonts.robotoFlex(
                                    color: U.sub,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            _buildFilterDropdown(),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (subjects.isEmpty)
                const SliverToBoxAdapter(child: SizedBox(height: 8))
              else if (processedSubjects.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: U.surfaceContainer,
                        borderRadius: M3Shapes.cardRadius,
                        border: Border.all(
                          color: U.outlineVariant.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: U.green.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.verified_rounded, color: U.green, size: 26),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No subjects below $_targetPercentage%!',
                            style: GoogleFonts.robotoFlex(
                              color: U.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All your enrolled subjects are currently meeting or exceeding the attendance threshold.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.robotoFlex(
                              color: U.sub,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: EdgeInsets.only(
                          bottom: index == processedSubjects.length - 1 ? 0 : 12,
                        ),
                        child: _buildSubjectCard(processedSubjects[index]),
                      ),
                      childCount: processedSubjects.length,
                    ),
                  ),
                ),
              // ── Academic Insights Section (AUS & ACET Portal) ──
              if (_selectedCollege == 'aus' || _selectedCollege == 'acet' || _selectedCollege == 'aec')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: _buildAcademicInsightsSection(data),
                  ),
                ),
              // Footnote for server type at the end of the scrollview instead of floating overlay
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: U.sub),
                        const SizedBox(width: 6),
                        Text(
                          'Fetched via ${data['serverUsed'] ?? 'In-App'}',
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Today floating button positioned snuggly above the bottom navigation bar
        Positioned(
          right: 24,
          bottom: 20,
          child: _TodayPulseButton(
            animation: _glowController,
            onTap: _showTodaySheet,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarTab() {
    final credentials = _savedCredentials;
    if (credentials == null) {
      return Center(
        child: Text(
          'No credentials active',
          style: GoogleFonts.outfit(color: U.sub),
        ),
      );
    }

    final portalDate = _formatPortalDateForPortal(_selectedCalendarDate);
    final isAcet = credentials['college'] == 'acet' || credentials['college'] == 'aec';
    final serviceMode = isAcet
        ? AttendanceRangeMode.period
        : AttendanceRangeMode.period;

    final Future<Map<String, dynamic>> calendarFuture = AttendanceService.fetchAttendance(
      credentials['rollNumber'] ?? '',
      credentials['password'] ?? '',
      college: credentials['college'] ?? 'aus',
      fromDate: portalDate,
      toDate: portalDate,
      mode: serviceMode,
    );

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: U.border),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: U.green, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDisplayDate(_selectedCalendarDate),
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Daily class-by-class records',
                      style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  final now = DateTime.now();
                   final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedCalendarDate,
                    firstDate: DateTime(2020),
                    lastDate: now,
                    builder: (context, child) {
                      final theme = Theme.of(context);
                      return Theme(
                        data: theme.copyWith(
                          colorScheme: theme.colorScheme.copyWith(
                            primary: U.green,
                          ),
                          datePickerTheme: theme.datePickerTheme.copyWith(
                            todayForegroundColor: WidgetStateProperty.all(U.green),
                            todayBorder: BorderSide(color: U.green, width: 1.5),
                            dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return U.green;
                              }
                              return null;
                            }),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() => _selectedCalendarDate = picked);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: U.green.withValues(alpha: 0.1),
                  foregroundColor: U.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: Text(
                  'Change Date',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: calendarFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: UtopiaLoader(scale: 0.7));
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, color: U.red, size: 40),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load records',
                          style: GoogleFonts.outfit(color: U.text, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _friendlyErrorMessage(snapshot.error ?? ''),
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final dateData = snapshot.data ?? const <String, dynamic>{};
              final periods = (dateData['periods'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>();

              if (periods.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: U.green.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.event_busy_rounded, color: U.green, size: 36),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Classes Scheduled',
                        style: GoogleFonts.outfit(
                          color: U.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No class records exist for this day',
                        style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                itemCount: periods.length,
                itemBuilder: (context, index) {
                  final period = periods[index];
                  final name = period['subject'] ?? 'Unknown Subject';
                  final status = period['status'] ?? 'Absent';
                  final duration = period['duration'] ?? '';
                  final isPresent = status.toString().trim().toLowerCase() == 'present';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: U.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: U.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: U.border),
                          ),
                          child: Text(
                            'Period ${index + 1}',
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.outfit(
                                  color: U.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (duration.toString().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  duration,
                                  style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPresent ? U.green.withValues(alpha: 0.12) : U.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isPresent ? U.green.withValues(alpha: 0.3) : U.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            status,
                            style: GoogleFonts.outfit(
                              color: isPresent ? U.green : U.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _weekdayKey(DateTime date) {
    switch (date.weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
      default:
        return 'Sun';
    }
  }

  bool _isSubjectMatch(String portalSubject, String timetableSlot) {
    final p = portalSubject.trim().toLowerCase();
    final t = timetableSlot.trim().toLowerCase();
    if (p.isEmpty || t.isEmpty) return false;

    // 1. Direct match
    if (p == t) return true;

    // 2. Timetable slot is an acronym of the portal subject
    // e.g. "Discrete Mathematics" -> DM, "Digital Electronics" -> DE
    final words = p.split(RegExp(r'[\s\-]+'));
    if (words.length > 1) {
      final acronym = words.map((w) => w.isNotEmpty ? w[0] : '').join();
      if (acronym == t) return true;
    }

    // 3. Portal subject is an acronym of the timetable slot
    final tWords = t.split(RegExp(r'[\s\-]+'));
    if (tWords.length > 1) {
      final tAcronym = tWords.map((w) => w.isNotEmpty ? w[0] : '').join();
      if (tAcronym == p) return true;
    }

    // 4. Substring matching
    if (p.contains(t) || t.contains(p)) return true;

    return false;
  }

  Widget _buildTomorrowPredictor() {
    final credentials = _savedCredentials;
    if (credentials == null) return const SizedBox.shrink();

    if (_userTimetable == null) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: U.border.withValues(alpha: 0.8),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: appThemeNotifier.value.isDark ? 0.2 : 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.calendar_month_rounded, color: U.primary, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              "Tomorrow's Predictor Not Synced",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Set up your timetable in the Timetable tab to see if you can safely miss tomorrow's classes!",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: U.sub,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowDayKey = _weekdayKey(tomorrow);

    final timetableDay = _userTimetable!.week.firstWhere(
      (d) => d.day.toLowerCase().startsWith(tomorrowDayKey.toLowerCase()),
      orElse: () => const TimetableDay(day: '', slots: []),
    );

    final tomorrowSlots = timetableDay.slots
        .where((slot) => slot.trim().isNotEmpty && slot.trim().toLowerCase() != 'free')
        .toList();

    if (tomorrowSlots.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: U.border.withValues(alpha: 0.8),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: appThemeNotifier.value.isDark ? 0.2 : 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: U.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wb_sunny_outlined, color: U.green, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              "Tomorrow: No Classes!",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Tomorrow is a free day or weekend. Sleep in and relax!",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: U.sub,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    // Parse overall subjects and build predictions
    final data = _attendanceData ?? const <String, dynamic>{};
    final subjects = (data['subjects'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    final List<Map<String, dynamic>> subjectPredictions = [];
    int totalTomorrowCount = 0;
    int totalCanMissCount = 0;
    bool hasDanger = false;

    for (final subject in subjects) {
      final name = (subject['subject'] ?? 'Subject').toString();
      final totalClasses = (subject['totalClasses'] as num?)?.toInt() ?? 0;
      final attendedClasses = (subject['attendedClasses'] as num?)?.toInt() ?? 0;
      final percentage = (subject['percentage'] as num?)?.toDouble() ?? 0;

      final tomorrowCount = tomorrowSlots.where((slot) => _isSubjectMatch(name, slot)).length;
      if (tomorrowCount == 0) continue;

      totalTomorrowCount += tomorrowCount;

      // Predictions
      final newTotal = totalClasses + tomorrowCount;
      final newAttendedIfAttendAll = attendedClasses + tomorrowCount;
      final percentageIfAttendAll = newTotal == 0 ? 0.0 : (newAttendedIfAttendAll / newTotal) * 100;
      final percentageIfMissAll = newTotal == 0 ? 0.0 : (attendedClasses / newTotal) * 100;

      int maxMissableTomorrow = 0;
      for (int m = tomorrowCount; m >= 0; m--) {
        final newAttended = attendedClasses + tomorrowCount - m;
        final pct = (newAttended / newTotal) * 100;
        if (pct >= _targetPercentage.toDouble()) {
          maxMissableTomorrow = m;
          break;
        }
      }

      final isDangerTomorrow = percentageIfAttendAll < _targetPercentage.toDouble();
      if (isDangerTomorrow) {
        hasDanger = true;
      }

      totalCanMissCount += maxMissableTomorrow;

      subjectPredictions.add({
        'name': name,
        'tomorrowCount': tomorrowCount,
        'maxMissableTomorrow': maxMissableTomorrow,
        'isDangerTomorrow': isDangerTomorrow,
        'percentageIfAttendAll': percentageIfAttendAll,
        'percentageIfMissAll': percentageIfMissAll,
        'currentPercentage': percentage,
      });
    }

    // If no tomorrow subject matches, then we have classes but they aren't matched with subjects
    if (subjectPredictions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Overall verdict
    final String verdictTitle;
    final String verdictDesc;
    final Color verdictColor;
    final IconData verdictIcon;

    if (hasDanger) {
      verdictTitle = "Danger Zone!";
      verdictDesc = "You are below $_targetPercentage% in some of tomorrow's subjects. Even if you attend all tomorrow, you'll still be below $_targetPercentage%. Critical action required!";
      verdictColor = U.red;
      verdictIcon = Icons.report_problem_rounded;
    } else if (totalCanMissCount == totalTomorrowCount) {
      verdictTitle = "Safe to Skip Entire Day!";
      verdictDesc = "🎉 Incredible! You can safely miss all $totalTomorrowCount classes tomorrow without dropping below $_targetPercentage% in any subject!";
      verdictColor = U.green;
      verdictIcon = Icons.check_circle_rounded;
    } else if (totalCanMissCount > 0) {
      verdictTitle = "Safe to Miss Some Classes";
      verdictDesc = "You can safely miss up to $totalCanMissCount out of $totalTomorrowCount classes tomorrow. Check subject-wise details below.";
      verdictColor = U.peach;
      verdictIcon = Icons.info_outline_rounded;
    } else {
      verdictTitle = "Attendance Required Tomorrow";
      verdictDesc = "⚠️ You must attend all $totalTomorrowCount classes tomorrow to keep your attendance above $_targetPercentage% in all subjects.";
      verdictColor = U.primary;
      verdictIcon = Icons.event_busy_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: U.border.withValues(alpha: 0.8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: appThemeNotifier.value.isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of tomorrow section
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Icon(Icons.psychology_outlined, color: U.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  "Tomorrow's Attendance Analyzer",
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          // Verdict banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: verdictColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: verdictColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(verdictIcon, color: verdictColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        verdictTitle,
                        style: GoogleFonts.outfit(
                          color: verdictColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        verdictDesc,
                        style: GoogleFonts.outfit(
                          color: verdictColor.withValues(alpha: 0.85),
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Subject breakdown header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "SUBJECT-WISE FORECAST",
              style: GoogleFonts.outfit(
                color: U.sub,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // List of subject details
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: subjectPredictions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final pred = subjectPredictions[index];
              final name = pred['name'] as String;
              final tCount = pred['tomorrowCount'] as int;
              final maxMissable = pred['maxMissableTomorrow'] as int;
              final isDanger = pred['isDangerTomorrow'] as bool;
              final pctAll = pred['percentageIfAttendAll'] as double;
              final pctMiss = pred['percentageIfMissAll'] as double;
              final currentPct = pred['currentPercentage'] as double;

              final Color badgeColor;
              final String badgeText;

              if (isDanger) {
                badgeColor = U.red;
                badgeText = "Critical Zone";
              } else if (maxMissable == tCount) {
                badgeColor = U.green;
                badgeText = "Safe to miss all $tCount";
              } else if (maxMissable > 0) {
                badgeColor = U.peach;
                badgeText = "Can miss $maxMissable of $tCount";
              } else {
                badgeColor = U.primary;
                badgeText = "Must attend all $tCount";
              }

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: U.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: U.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.outfit(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Current: ${currentPct.toStringAsFixed(1)}%",
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                        ),
                        Text(
                          isDanger
                              ? "Attend all: ${pctAll.toStringAsFixed(1)}% (Danger)"
                              : maxMissable == tCount
                              ? "Miss all: ${pctMiss.toStringAsFixed(1)}% (Safe)"
                              : "Attend: ${pctAll.toStringAsFixed(1)}% | Miss: ${pctMiss.toStringAsFixed(1)}%",
                          style: GoogleFonts.outfit(
                            color: isDanger
                                ? U.red
                                : maxMissable == tCount
                                ? U.green
                                : U.sub,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTodayAttendanceInlineCard() {
    _ensureTodayAttendanceLoaded();

    return Container(
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.today_rounded, color: U.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Attendance",
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDisplayDate(DateTime.now()),
                      style: GoogleFonts.outfit(
                        color: U.sub,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, size: 18, color: U.sub),
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh today',
                onPressed: () {
                  setState(() {
                    _ensureTodayAttendanceLoaded(force: true);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<Map<String, dynamic>>(
            future: _todayAttendanceFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.scale(
                          scale: 0.6,
                          child: const UtopiaLoader(scale: 0.6),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Checking today\'s classes...',
                          style: GoogleFonts.outfit(
                            color: U.sub,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: U.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: U.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Could not load today\'s attendance',
                          style: GoogleFonts.outfit(
                            color: U.red,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _ensureTodayAttendanceLoaded(force: true);
                          });
                        },
                        child: Text(
                          'Retry',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final todayData = snapshot.data ?? const <String, dynamic>{};
              final totalClasses = (todayData['totalClasses'] as num?)?.toInt() ?? 0;
              final totalAttended = (todayData['totalAttended'] as num?)?.toInt() ?? 0;
              final overall = (todayData['overallPercentage'] as num?)?.toDouble() ?? 0;
              final subjects = (todayData['subjects'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>();
              final activeSubjects = subjects.where((s) {
                final held = (s['totalClasses'] as num?)?.toInt() ?? (s['held'] as num?)?.toInt() ?? 0;
                return held > 0;
              }).toList();

              if (totalClasses == 0 || activeSubjects.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: U.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: U.outlineVariant.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_rounded, color: U.green, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No periods marked today or records unavailable',
                          style: GoogleFonts.outfit(
                            color: U.sub,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final pctColor = _percentageColor(overall);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 14, color: U.primary),
                            const SizedBox(width: 6),
                            Text(
                              '$totalAttended of $totalClasses attended',
                              style: GoogleFonts.outfit(
                                color: U.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: pctColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${overall.toStringAsFixed(1)}%',
                          style: GoogleFonts.outfit(
                            color: pctColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: activeSubjects.map((sub) {
                      final name = (sub['name'] ?? sub['subject'] ?? 'Subject').toString();
                      final held = (sub['totalClasses'] as num?)?.toInt() ?? (sub['held'] as num?)?.toInt() ?? 0;
                      final att = (sub['attendedClasses'] as num?)?.toInt() ?? (sub['attended'] as num?)?.toInt() ?? 0;
                      final isPresent = att > 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: U.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isPresent
                                ? U.green.withValues(alpha: 0.3)
                                : U.red.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPresent ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
                              size: 14,
                              color: isPresent ? U.green : U.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '($att/$held)',
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: _showTodaySheet,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Full details',
                              style: GoogleFonts.outfit(
                                color: U.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded, size: 10, color: U.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsTab() {
    final data = _attendanceData ?? const <String, dynamic>{};
    final overall = (data['overallPercentage'] as num?)?.toDouble() ?? 0;
    final totalClasses = (data['totalClasses'] as num?)?.toInt() ?? 0;
    final totalAttended = (data['totalAttended'] as num?)?.toInt() ?? 0;
    final studentName = (data['studentName'] as String? ?? '').trim();
    final color = _percentageColor(overall);
    final statusLabel = _headlineFor(overall);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        // ── 0. Today's Attendance (Directly at top for ACET) ──
        if (_selectedCollege == 'acet' || _selectedCollege == 'aec') ...[
          _buildTodayAttendanceInlineCard(),
          const SizedBox(height: 16),
        ],

        // ── 1. Attendance Progress (Only for AUS where attendance is estimated) ──
        if (_selectedCollege == 'aus') ...[
          _buildAttendanceTrendCard(data),
          const SizedBox(height: 16),
        ],

        // ── 2. Tomorrow's Predictor (Positioned right after Attendance Progress) ──
        _buildTomorrowPredictor(),

        const SizedBox(height: 16),

        // ── 3. Merged Overall Attendance Hero Card (Includes Held / Attended / Missed metrics) ──
        _buildOverallHeroCard(
          overall: overall,
          totalClasses: totalClasses,
          totalAttended: totalAttended,
          studentName: studentName,
          color: color,
          statusLabel: statusLabel,
        ),

        const SizedBox(height: 24),

        // ── 4. Insight Tip Banner ──
        _buildInsightTipBanner(overall: overall, attended: totalAttended, held: totalClasses),

        // ── 5. Academic Insights (AUS & ACET Portal) ──
        if (_selectedCollege == 'aus' || _selectedCollege == 'acet' || _selectedCollege == 'aec') ...[
          const SizedBox(height: 24),
          _buildAcademicInsightsSection(data),
        ],
      ],
    );
  }

  Widget _buildOverallHeroCard({
    required double overall,
    required int totalClasses,
    required int totalAttended,
    required String studentName,
    required Color color,
    required String statusLabel,
  }) {
    final missedClasses = (totalClasses - totalAttended).clamp(0, 9999);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [U.card, color.withValues(alpha: 0.14)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: U.border.withValues(alpha: 0.8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: appThemeNotifier.value.isDark ? 0.2 : 0.03,
            ),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.bar_chart_rounded,
                  color: color,
                  size: 26,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.outfit(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Overall Attendance',
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${overall.toStringAsFixed(1)}%',
            style: GoogleFonts.outfit(
              color: U.text,
              fontSize: 48,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: U.surface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              value: (overall / 100).clamp(0.0, 1.0),
            ),
          ),
          if (studentName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  color: U.sub,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    studentName,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // ── Merged Class Totals (Classes Held, Attended, Missed inside card) ──
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: U.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: U.border.withValues(alpha: 0.5),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMergedStatCol(
                    label: 'Classes Held',
                    value: '$totalClasses',
                    icon: Icons.event_note_rounded,
                    color: U.primary,
                  ),
                ),
                Container(width: 1, height: 28, color: U.border.withValues(alpha: 0.5)),
                Expanded(
                  child: _buildMergedStatCol(
                    label: 'Attended',
                    value: '$totalAttended',
                    icon: Icons.check_circle_outline_rounded,
                    color: color,
                  ),
                ),
                Container(width: 1, height: 28, color: U.border.withValues(alpha: 0.5)),
                Expanded(
                  child: _buildMergedStatCol(
                    label: 'Missed',
                    value: '$missedClasses',
                    icon: Icons.cancel_outlined,
                    color: U.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMergedStatCol({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: U.sub,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildAttendanceTrendCard(Map<String, dynamic> data) {
    final roll = _savedCredentials?['rollNumber'] ?? '';
    if (roll.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<AttendanceComparison>(
      future: AttendanceHistoryService.getComparison(roll, data),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final comp = snapshot.data!;

        final Color badgeColor;
        final IconData trendIcon;
        final String deltaText;

        if (comp.overallDelta > 0.005) {
          badgeColor = U.green;
          trendIcon = Icons.trending_up_rounded;
          deltaText = '+${comp.overallDelta.toStringAsFixed(1)}%';
        } else if (comp.overallDelta < -0.005) {
          badgeColor = U.red;
          trendIcon = Icons.trending_down_rounded;
          deltaText = '${comp.overallDelta.toStringAsFixed(1)}%';
        } else {
          badgeColor = U.primary;
          trendIcon = Icons.trending_flat_rounded;
          deltaText = '0.0%';
        }

        final prevDateLabel = comp.hasPrevious && comp.previousTimestamp != null
            ? _formatShortTime(comp.previousTimestamp)
            : 'Baseline';

        return Container(
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: U.border.withValues(alpha: 0.7),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: appThemeNotifier.value.isDark ? 0.25 : 0.04,
                ),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Row ──
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(trendIcon, color: badgeColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attendance Progress',
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            comp.hasPrevious
                                ? 'Compared with $prevDateLabel'
                                : 'Baseline recorded',
                            style: GoogleFonts.outfit(
                              color: U.sub,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (comp.hasPrevious)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(trendIcon, color: badgeColor, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              deltaText,
                              style: GoogleFonts.outfit(
                                color: badgeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                if (comp.hasPrevious) ...[
                  const SizedBox(height: 16),

                  // ── Clean 3-Card Metrics Row ──
                  Row(
                    children: [
                      Expanded(
                        child: _buildDeltaCard(
                          label: 'Overall %',
                          currVal: '${comp.currentOverall.toStringAsFixed(1)}%',
                          prevVal: '${comp.previousOverall.toStringAsFixed(1)}%',
                          deltaVal: comp.overallDelta,
                          isPercentage: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDeltaCard(
                          label: 'Classes Held',
                          currVal: '${comp.currentHeld}',
                          prevVal: '${comp.previousHeld}',
                          deltaVal: comp.heldDelta.toDouble(),
                          unit: 'held',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDeltaCard(
                          label: 'Attended',
                          currVal: '${comp.currentAttended}',
                          prevVal: '${comp.previousAttended}',
                          deltaVal: comp.attendedDelta.toDouble(),
                          unit: 'attended',
                        ),
                      ),
                    ],
                  ),

                  // ── Every Subject Positive / Negative Breakdown ──
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PER-SUBJECT BREAKDOWN',
                        style: GoogleFonts.outfit(
                          color: U.sub,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        '${comp.subjectDeltas.length} subjects',
                        style: GoogleFonts.outfit(
                          color: U.sub,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: comp.subjectDeltas
                        .map((sub) => _buildSubjectDeltaItem(sub))
                        .toList(),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    'First snapshot recorded! Future refreshes will compare against this data to show your attendance progress over time.',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (data['subjects'] != null && (data['subjects'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'SUBJECT STATUS',
                      style: GoogleFonts.outfit(
                        color: U.sub,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: (data['subjects'] as List).map((s) {
                        final map = s as Map<String, dynamic>;
                        final name = (map['subject'] ?? '').toString();
                        final pct = (map['percentage'] as num?)?.toDouble() ?? 0;
                        final attended = (map['attendedClasses'] as num?)?.toInt() ?? 0;
                        final total = (map['totalClasses'] as num?)?.toInt() ?? 0;
                        final isOk = pct >= _targetPercentage;
                        final color = isOk ? U.green : U.red;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: U.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: U.border.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.outfit(
                                        color: U.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$attended/$total classes attended • ${pct.toStringAsFixed(1)}%',
                                      style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(isOk ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: color, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      isOk ? 'On Track' : 'Needs Attention',
                                      style: GoogleFonts.outfit(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatShortTime(DateTime? dt) {
    if (dt == null) return 'Baseline';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(targetDate).inDays;

    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final hourStr = hour12.toString().padLeft(2, '0');
    final minStr = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hourStr:$minStr $ampm';

    if (diffDays == 0) {
      return 'Today, $timeStr';
    } else if (diffDays == 1) {
      return 'Yesterday, $timeStr';
    }

    final day = dt.day.toString().padLeft(2, '0');
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = monthNames[dt.month - 1];
    return '$day $month, $timeStr';
  }

  Widget _buildDeltaCard({
    required String label,
    required String currVal,
    required String prevVal,
    required double deltaVal,
    bool isPercentage = false,
    String unit = '',
  }) {
    final bool hasChanged = deltaVal.abs() > 0.001;
    final bool isPositive = deltaVal > 0;
    final Color color = !hasChanged
        ? U.sub
        : (isPositive ? U.green : U.red);

    String changeSubtitle;
    if (!hasChanged) {
      changeSubtitle = 'No change';
    } else if (isPercentage) {
      final sign = isPositive ? '+' : '';
      changeSubtitle = '$sign${deltaVal.toStringAsFixed(1)}%';
    } else {
      final intDelta = deltaVal.toInt();
      final sign = isPositive ? '+' : '';
      changeSubtitle = '$sign$intDelta $unit';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: U.border.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: U.sub,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            currVal,
            style: GoogleFonts.outfit(
              color: U.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (hasChanged) ...[
                Icon(
                  isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 11,
                  color: color,
                ),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Text(
                  changeSubtitle,
                  style: GoogleFonts.outfit(
                    color: hasChanged ? color : U.sub.withValues(alpha: 0.65),
                    fontSize: 10,
                    fontWeight: hasChanged ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectDeltaItem(SubjectDelta sub) {
    final double delta = sub.deltaPercentage;
    final bool isPositive = delta > 0.005;
    final bool isNegative = delta < -0.005;

    final Color color = isPositive
        ? U.green
        : isNegative
            ? U.red
            : U.sub;
    final IconData icon = isPositive
        ? Icons.trending_up_rounded
        : isNegative
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

    String badgeLabel;
    if (isPositive) {
      badgeLabel = '+${delta.toStringAsFixed(1)}%';
    } else if (isNegative) {
      badgeLabel = '${delta.toStringAsFixed(1)}%';
    } else {
      badgeLabel = '0.0%';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: U.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.subjectName,
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${sub.currentAttended}/${sub.currentHeld} classes attended • ${sub.currentPercentage.toStringAsFixed(1)}%',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 4),
                Text(
                  badgeLabel,
                  style: GoogleFonts.outfit(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool wide = false,
  }) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: U.border.withValues(alpha: 0.8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: appThemeNotifier.value.isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: U.sub,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightTipBanner({
    required double overall,
    required int attended,
    required int held,
  }) {
    final double target = _attendanceTarget;
    final int missable = (held <= 0 || attended <= 0)
        ? 0
        : ((attended / target) - held).floor().clamp(0, 9999);
    final int needed = held <= 0
        ? 0
        : (((target * held) - attended) / (1 - target)).ceil().clamp(0, 9999);

    final String message;
    final Color tint;
    final IconData icon;

    if (held <= 0 || overall <= 0) {
      message = 'Attendance records unavailable.';
      tint = U.primary;
      icon = Icons.info_outline_rounded;
    } else if (overall >= _targetPercentage) {
      message = missable == 0
          ? 'You are exactly at the $_targetPercentage% threshold. Attend all upcoming classes to stay safe.'
          : 'You can miss up to $missable more class${missable == 1 ? '' : 'es'} and still stay above $_targetPercentage%.';
      tint = U.green;
      icon = Icons.verified_outlined;
    } else {
      message = needed == 0
          ? 'Your attendance needs attention. Attend classes regularly to improve.'
          : 'Attend $needed consecutive class${needed == 1 ? '' : 'es'} to reach the $_targetPercentage% target.';
      tint = overall >= (_targetPercentage - 10) ? U.peach : U.red;
      icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                color: tint,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final name = (subject['subject'] ?? 'Subject').toString();
    final totalClasses = (subject['totalClasses'] as num?)?.toInt() ?? 0;
    final attendedClasses = (subject['attendedClasses'] as num?)?.toInt() ?? 0;
    final percentage = (subject['percentage'] as num?)?.toDouble() ?? 0;
    final color = _percentageColor(percentage);
    final classesNeeded = _classesNeededToRecover(
      attendedClasses,
      totalClasses,
    );
    final missableClasses = _missableClasses(attendedClasses, totalClasses);
    final bufferLine = percentage >= _targetPercentage
        ? missableClasses == 0
              ? 'At the $_targetPercentage% line'
              : 'Can miss $missableClasses more class${missableClasses == 1 ? '' : 'es'}'
        : classesNeeded == 0
        ? 'Needs attention'
        : 'Attend $classesNeeded more class${classesNeeded == 1 ? '' : 'es'} to reach $_targetPercentage%';

    return Container(
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: M3Shapes.cardRadius,
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_subjectIcon(name), color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.robotoFlex(
                          color: U.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$attendedClasses / $totalClasses classes attended',
                        style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: M3Shapes.fullRadius,
                  ),
                  child: Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: GoogleFonts.robotoFlex(
                      color: color,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: U.surfaceContainerLowest,
                borderRadius: M3Shapes.fullRadius,
              ),
              child: ClipRRect(
                borderRadius: M3Shapes.fullRadius,
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  value: totalClasses == 0
                      ? 0
                      : (percentage / 100).clamp(0.0, 1.0),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  percentage >= _targetPercentage ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                  size: 14,
                  color: percentage >= _targetPercentage ? U.sub : color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    bufferLine,
                    style: GoogleFonts.robotoFlex(
                      color: percentage >= _targetPercentage ? U.sub : color,
                      fontSize: 12,
                      fontWeight: percentage >= _targetPercentage
                          ? FontWeight.w500
                          : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      key: const ValueKey('attendance_error'),
      child: StudentSprintLoader(
        scale: 1.0,
        isError: true,
        errorMessage: _errorMessage,
        onRetry: _savedCredentials == null
            ? () => setState(() => _state = _AttendanceViewState.initial)
            : _refresh,
        onViewSaved: _loadCachedAttendance,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hintText,
    required String labelText,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      enableInteractiveSelection: true,
      enableSuggestions: !obscureText,
      autocorrect: false,
      style: GoogleFonts.outfit(color: U.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: GoogleFonts.outfit(
          color: U.sub.withValues(alpha: 0.8),
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.outfit(color: U.sub, fontSize: 14),
        filled: true,
        fillColor: U.surface,
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: U.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: U.primary),
        ),
      ),
    );
  }
}

class _GradientHero extends StatelessWidget {
  const _GradientHero({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.accent,
    this.subtitleColor,
    this.detail,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color? accent;
  final Color? subtitleColor;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? U.primary;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [U.card, accentColor.withValues(alpha: 0.18)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: U.border.withValues(alpha: 0.8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: appThemeNotifier.value.isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            eyebrow,
            style: GoogleFonts.outfit(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: U.text,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              color: subtitleColor ?? U.sub,
              fontSize: 14,
              height: 1.45,
              fontWeight: subtitleColor == null
                  ? FontWeight.w500
                  : FontWeight.w700,
            ),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person_outline_rounded, color: U.sub, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    detail!,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: U.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tint, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
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
    );
  }
}

class _TodayPulseButton extends StatelessWidget {
  const _TodayPulseButton({required this.animation, required this.onTap});

  final AnimationController animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Container(
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: U.border,
              width: 0.8,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.today_rounded,
                      color: U.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Today',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodaySubjectRow extends StatelessWidget {
  const _TodaySubjectRow({
    required this.name,
    required this.totalClasses,
    required this.attendedClasses,
    required this.percentage,
    required this.icon,
    required this.color,
  });

  final String name;
  final int totalClasses;
  final int attendedClasses;
  final double percentage;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: U.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$attendedClasses / $totalClasses classes',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceDateSheet extends StatefulWidget {
  const _AttendanceDateSheet({
    required this.title,
    required this.dateLabel,
    required this.date,
    required this.credentials,
    required this.onRefresh,
    this.portalDateLabel,
    this.mode = _AttendanceRangeMode.period,
  });

  final String title;
  final String dateLabel;
  final DateTime date;
  final Map<String, String> credentials;
  final VoidCallback onRefresh;
  final String? portalDateLabel;
  final _AttendanceRangeMode mode;

  @override
  State<_AttendanceDateSheet> createState() => _AttendanceDateSheetState();
}

class _AttendanceDateSheetState extends State<_AttendanceDateSheet> {
  late Future<Map<String, dynamic>> _future;

  String _formatPortalDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day-$month-${dt.year}';
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[DEBUG][Sheet] initState called for: ${widget.title}');
    _loadData();
  }

  void _loadData() {
    final portalDate = widget.portalDateLabel ?? _formatPortalDate(widget.date);
    debugPrint(
      '[DEBUG][Sheet] _loadData: title=${widget.title}, portalDate=$portalDate, mode=${widget.mode}',
    );

    final isAcet = widget.credentials['college'] == 'acet' || widget.credentials['college'] == 'aec';
    final serviceMode = isAcet
        ? (widget.mode == _AttendanceRangeMode.tillNow
              ? AttendanceRangeMode.tillNow
              : AttendanceRangeMode.period)
        : AttendanceRangeMode.period;

    debugPrint(
      '[DEBUG][Sheet] serviceMode=$serviceMode, college=${widget.credentials['college']}',
    );

    if (serviceMode == AttendanceRangeMode.tillNow) {
      debugPrint('[DEBUG][Sheet] Calling fetchAttendance (tillNow mode)');
      _future = AttendanceService.fetchAttendance(
        widget.credentials['rollNumber'] ?? '',
        widget.credentials['password'] ?? '',
        college: widget.credentials['college'] ?? 'aus',
        mode: serviceMode,
      );
    } else {
      debugPrint(
        '[DEBUG][Sheet] Calling fetchAttendance (period mode): fromDate=$portalDate, toDate=$portalDate',
      );
      _future = AttendanceService.fetchAttendance(
        widget.credentials['rollNumber'] ?? '',
        widget.credentials['password'] ?? '',
        college: widget.credentials['college'] ?? 'aus',
        fromDate: portalDate,
        toDate: portalDate,
        mode: serviceMode,
      );
    }
  }

  Color _percentageColor(double value) {
    if (value >= 75) {
      return U.green;
    }
    if (value >= 65) {
      return U.peach;
    }
    return U.red;
  }

  IconData _subjectIcon(String subject) {
    final key = subject.toLowerCase();
    if (key.contains('devc') || key.contains('ppsuc')) {
      return Icons.code_rounded;
    }
    if (key.contains('beee') || key.contains('e.')) {
      return Icons.electrical_services_rounded;
    }
    if (key.contains('iot')) return Icons.memory_rounded;
    if (key.contains('dtai')) return Icons.auto_awesome_rounded;
    if (key.contains('env')) return Icons.eco_rounded;
    if (key.contains('emp')) return Icons.psychology_alt_rounded;
    return Icons.book_rounded;
  }

  String _friendlyErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Something went wrong while fetching attendance';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border.all(color: U.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Attendance for ${widget.dateLabel}',
                style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
              ),
              const SizedBox(height: 18),
              StatefulBuilder(
                builder: (context, setSheetState) {
                  return FutureBuilder<Map<String, dynamic>>(
                    future: _future,
                    builder: (context, snapshot) {
                      debugPrint(
                        '[DEBUG][Sheet] FutureBuilder state: ${snapshot.connectionState}, hasError: ${snapshot.hasError}, hasData: ${snapshot.hasData}',
                      );

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        debugPrint('[DEBUG][Sheet] Loading... showing spinner');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Transform.scale(
                              scale: 0.6,
                              child: const UtopiaLoader(scale: 0.6),
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        debugPrint('[DEBUG][Sheet] Error: ${snapshot.error}');
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TodayStatusCard(
                              icon: Icons.cloud_off_rounded,
                              title: 'Could not load attendance',
                              subtitle: _friendlyErrorMessage(
                                snapshot.error ?? 'Something went wrong',
                              ),
                              tint: U.red,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  setSheetState(() {
                                    _loadData();
                                  });
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: U.primary,
                                  foregroundColor: U.bg,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(
                                  'Try again',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      debugPrint('[DEBUG][Sheet] Data loaded successfully');
                      final dateData =
                          snapshot.data ?? const <String, dynamic>{};
                      final totalClasses =
                          (dateData['totalClasses'] as num?)?.toInt() ?? 0;
                      final totalAttended =
                          (dateData['totalAttended'] as num?)?.toInt() ?? 0;
                      final overall =
                          (dateData['overallPercentage'] as num?)?.toDouble() ??
                          0;
                      final subjects =
                          (dateData['subjects'] as List<dynamic>? ?? const [])
                              .cast<Map<String, dynamic>>();
                      final activeSubjects = subjects.where((subject) {
                        final held =
                            (subject['totalClasses'] as num?)?.toInt() ?? 0;
                        return held > 0;
                      }).toList();
                      final overallColor = _percentageColor(overall);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TodayStatusCard(
                            icon: totalClasses == 0
                                ? Icons.event_available_rounded
                                : Icons.calendar_today_rounded,
                            title: totalClasses == 0
                                ? 'No classes recorded'
                                : '$totalAttended of $totalClasses classes attended',
                            subtitle: totalClasses == 0
                                ? 'Nothing has been marked for this day.'
                                : '${overall.toStringAsFixed(1)}% attendance',
                            tint: totalClasses == 0 ? U.primary : overallColor,
                          ),
                          if (activeSubjects.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              'Subjects',
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...activeSubjects.map(
                              (subject) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _TodaySubjectRow(
                                  name: subject['subject'].toString(),
                                  totalClasses:
                                      (subject['totalClasses'] as num?)
                                          ?.toInt() ??
                                      0,
                                  attendedClasses:
                                      (subject['attendedClasses'] as num?)
                                          ?.toInt() ??
                                      0,
                                  percentage:
                                      (subject['percentage'] as num?)
                                          ?.toDouble() ??
                                      0,
                                  icon: _subjectIcon(
                                    subject['subject'].toString(),
                                  ),
                                  color: _percentageColor(
                                    (subject['percentage'] as num?)
                                            ?.toDouble() ??
                                        0,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                setSheetState(() {
                                  _loadData();
                                });
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: U.primary,
                                foregroundColor: U.bg,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                'Refresh',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademicGrowthChartPainter extends CustomPainter {
  _AcademicGrowthChartPainter({
    required this.sgpas,
    required this.cgpa,
    required this.primaryColor,
    required this.textColor,
    required this.subTextColor,
    required this.gridColor,
    required this.isDark,
  });

  final List<double> sgpas;
  final double cgpa;
  final Color primaryColor;
  final Color textColor;
  final Color subTextColor;
  final Color gridColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (sgpas.isEmpty) return;

    final n = sgpas.length;
    const padL = 24.0;
    const padR = 24.0;
    const padT = 24.0;
    const padB = 26.0;

    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;

    double minVal = sgpas.reduce(math.min);
    double maxVal = sgpas.reduce(math.max);
    if (cgpa > 0) {
      if (cgpa < minVal) minVal = cgpa;
      if (cgpa > maxVal) maxVal = cgpa;
    }

    double range = maxVal - minVal;
    if (range < 0.8) range = 0.8;
    final plotMin = math.max(0.0, minVal - range * 0.4);
    final plotMax = math.min(10.0, maxVal + range * 0.35);

    double getY(double val) {
      final norm = (val - plotMin) / (plotMax - plotMin);
      return (size.height - padB) - norm * plotH;
    }

    double getX(int idx) {
      if (n == 1) return padL + plotW / 2;
      return padL + idx * (plotW / (n - 1));
    }

    // 1. Draw Average CGPA Dashed Reference Line
    if (cgpa > 0 && cgpa >= plotMin && cgpa <= plotMax) {
      final cgpaY = getY(cgpa);
      final dashPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.3)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      const dashWidth = 4.0;
      const dashSpace = 4.0;
      double startX = padL;
      while (startX < size.width - padR) {
        canvas.drawLine(
          Offset(startX, cgpaY),
          Offset(math.min(startX + dashWidth, size.width - padR), cgpaY),
          dashPaint,
        );
        startX += dashWidth + dashSpace;
      }

      final cgpaSpan = TextSpan(
        text: 'Avg ${cgpa.toStringAsFixed(2)}',
        style: GoogleFonts.outfit(
          color: primaryColor.withValues(alpha: 0.75),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      );
      final tp = TextPainter(
        text: cgpaSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - padR - tp.width, cgpaY - tp.height - 2));
    }

    // 2. Compute Points
    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      points.add(Offset(getX(i), getY(sgpas[i])));
    }

    // 3. Draw Bezier Spline & Gradient Fill
    if (n > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 0; i < n - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final cx1 = p0.dx + (p1.dx - p0.dx) / 2;
        final cy1 = p0.dy;
        final cx2 = p0.dx + (p1.dx - p0.dx) / 2;
        final cy2 = p1.dy;
        path.cubicTo(cx1, cy1, cx2, cy2, p1.dx, p1.dy);
      }

      final fillPath = Path.from(path)
        ..lineTo(points.last.dx, size.height - padB + 6)
        ..lineTo(points.first.dx, size.height - padB + 6)
        ..close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryColor.withValues(alpha: 0.22),
            primaryColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(padL, padT, plotW, plotH + 6))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);

      final linePaint = Paint()
        ..color = primaryColor
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, linePaint);
    }

    // 4. Draw Data Points & Badges
    for (int i = 0; i < n; i++) {
      final pt = points[i];

      // Outer halo
      final haloPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 6.0, haloPaint);

      // Inner dot
      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 3.8, dotPaint);

      final ringPaint = Paint()
        ..color = isDark ? const Color(0xFF1E201E) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(pt, 3.8, ringPaint);

      // SGPA floating badge text above
      final sgpaText = sgpas[i].toStringAsFixed(2);
      final sgpaSpan = TextSpan(
        text: sgpaText,
        style: GoogleFonts.outfit(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
      final sgpaTp = TextPainter(
        text: sgpaSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      sgpaTp.paint(canvas, Offset(pt.dx - sgpaTp.width / 2, pt.dy - sgpaTp.height - 5));

      // Semester label below
      final semLabel = 'Sem ${i + 1}';
      final semSpan = TextSpan(
        text: semLabel,
        style: GoogleFonts.outfit(
          color: subTextColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      final semTp = TextPainter(
        text: semSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      semTp.paint(
        canvas,
        Offset(pt.dx - semTp.width / 2, size.height - padB + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AcademicGrowthChartPainter oldDelegate) {
    return oldDelegate.sgpas != sgpas ||
        oldDelegate.cgpa != cgpa ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.isDark != isDark;
  }
}

