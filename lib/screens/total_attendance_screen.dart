import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/utopia_loader.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/attendance_service.dart';
import '../widgets/utopia_snackbar.dart';

/// A dedicated page that shows the student's overall / total attendance summary.
class TotalAttendanceScreen extends StatefulWidget {
  const TotalAttendanceScreen({
    super.key,
    required this.attendanceData,
    required this.credentials,
  });

  /// The last fetched attendance data map (same structure returned by
  /// [AttendanceService.fetchAttendance]).
  final Map<String, dynamic> attendanceData;

  /// Saved credentials used to refresh data on demand.
  final Map<String, String> credentials;

  @override
  State<TotalAttendanceScreen> createState() => _TotalAttendanceScreenState();
}

class _TotalAttendanceScreenState extends State<TotalAttendanceScreen> {
  late Map<String, dynamic> _data;
  bool _refreshing = false;
  bool _isColoredMode = true;

  @override
  void initState() {
    super.initState();
    _data = widget.attendanceData;
    _loadPreference();
    debugPrint(
      '[TotalAttendance] initState — overall=${_data['overallPercentage']}, '
      'totalClasses=${_data['totalClasses']}, '
      'totalAttended=${_data['totalAttended']}',
    );
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('attendance_colored_mode');
      if (mounted) {
        setState(() {
          _isColoredMode = saved ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    debugPrint('[TotalAttendance] _refresh called');
    setState(() => _refreshing = true);
    try {
      final result = await AttendanceService.fetchAttendance(
        widget.credentials['rollNumber'] ?? '',
        widget.credentials['password'] ?? '',
        college: widget.credentials['college'] ?? 'aus',
        mode: AttendanceRangeMode.tillNow,
      );
      debugPrint(
        '[TotalAttendance] refresh success — overall=${result['overallPercentage']}',
      );
      if (!mounted) return;
      setState(() => _data = result);
    } catch (e) {
      debugPrint('[TotalAttendance] refresh error: $e');
      if (!mounted) return;
      showUtopiaSnackBar(
        context,
        message: e.toString().replaceFirst('Exception: ', '').trim(),
        tone: UtopiaSnackBarTone.error,
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Color _percentageColor(double value) {
    if (_isColoredMode) {
      if (value < 65) return const Color(0xFFEF4444); // Red (<65%)
      if (value <= 75) return const Color(0xFFF59E0B); // Yellow (65-75%)
      return const Color(0xFF10B981); // Green (>75%)
    }
    // Coloured Mode OFF: Return default theme primary accent
    return U.primary;
  }

  String _statusLabel(double value) {
    if (value >= 85) return 'Locked in';
    if (value >= 75) return 'On track';
    if (value >= 65) return 'Recoverable';
    return 'Needs attention';
  }

  @override
  Widget build(BuildContext context) {
    final overall = (_data['overallPercentage'] as num?)?.toDouble() ?? 0;
    final totalClasses = (_data['totalClasses'] as num?)?.toInt() ?? 0;
    final totalAttended = (_data['totalAttended'] as num?)?.toInt() ?? 0;
    final studentName = (_data['studentName'] as String? ?? '').trim();
    final rawCollege = widget.credentials['college'] ?? 'aus';
    final college =
        (rawCollege.toLowerCase() == 'aec' ? 'ACET' : rawCollege).toUpperCase();
    final color = _percentageColor(overall);
    final statusLabel = _statusLabel(overall);

    debugPrint(
      '[TotalAttendance] build — overall=$overall, held=$totalClasses, '
      'attended=$totalAttended, name=$studentName',
    );

    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: U.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Attendance',
              style: GoogleFonts.outfit(
                color: U.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              college,
              style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: SizedBox(
                width: 20,
                height: 20,
                child: const UtopiaLoader(scale: 0.6),
              ),
            )
          else
            IconButton(
              onPressed: _refresh,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: U.primary,
          backgroundColor: U.card,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // ── Hero card ──────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    colors: [U.card, color.withValues(alpha: 0.18)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: U.border),
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
                            color: color.withValues(alpha: 0.16),
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
                            color: color.withValues(alpha: 0.16),
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
                      const SizedBox(height: 16),
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
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Stats row ──────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Classes Held',
                      value: totalClasses.toString(),
                      icon: Icons.event_note_rounded,
                      color: U.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Classes Attended',
                      value: totalAttended.toString(),
                      icon: Icons.check_circle_outline_rounded,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Absent count ───────────────────────────────────────────────
              _StatCard(
                label: 'Classes Missed',
                value: (totalClasses - totalAttended).clamp(0, 9999).toString(),
                icon: Icons.cancel_outlined,
                color: U.red,
                wide: true,
              ),
              const SizedBox(height: 24),

              // ── Tip section ────────────────────────────────────────────────
              _TipBanner(overall: overall, attended: totalAttended, held: totalClasses),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: U.border),
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
}

class _TipBanner extends StatelessWidget {
  const _TipBanner({
    required this.overall,
    required this.attended,
    required this.held,
  });

  final double overall;
  final int attended;
  final int held;

  static const double _target = 0.75;

  int get _missable {
    if (held <= 0 || attended <= 0) return 0;
    return ((attended / _target) - held).floor().clamp(0, 9999);
  }

  int get _needed {
    if (held <= 0) return 0;
    // Solve (attended + n) / (held + n) = 0.75 for n:
    //   attended + n = 0.75 * (held + n)
    //   n - 0.75n = 0.75 * held - attended
    //   n * (1 - 0.75) = 0.75 * held - attended
    //   n = (0.75 * held - attended) / (1 - 0.75)
    final n = ((_target * held) - attended) / (1 - _target);
    return n.ceil().clamp(0, 9999);
  }

  @override
  Widget build(BuildContext context) {
    final String message;
    final Color tint;
    final IconData icon;

    if (overall >= 75) {
      final m = _missable;
      message = m == 0
          ? 'You are exactly at the 75% threshold. Attend all upcoming classes to stay safe.'
          : 'You can miss up to $m more class${m == 1 ? '' : 'es'} and still stay above 75%.';
      tint = const Color(0xFFA6E3A1);
      icon = Icons.verified_outlined;
    } else {
      final n = _needed;
      message = n == 0
          ? 'Your attendance needs attention. Attend classes regularly to improve.'
          : 'Attend $n consecutive class${n == 1 ? '' : 'es'} to reach the 75% target.';
      tint = overall >= 65
          ? const Color(0xFFF9E2AF)
          : const Color(0xFFF38BA8);
      icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
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
}
