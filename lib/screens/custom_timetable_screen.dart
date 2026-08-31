import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/user_timetable.dart';
import '../services/user_timetable_service.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';

class CustomTimetableScreen extends StatefulWidget {
  final UserTimetable? initialTimetable;

  const CustomTimetableScreen({super.key, this.initialTimetable});

  @override
  State<CustomTimetableScreen> createState() => _CustomTimetableScreenState();
}

class _CustomTimetableScreenState extends State<CustomTimetableScreen>
    with SingleTickerProviderStateMixin {
  static const _dayKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const List<TimetablePeriod> _defaultPeriods = [
    TimetablePeriod(period: 1, start: '09:30 AM', end: '10:20 AM'),
    TimetablePeriod(period: 2, start: '10:20 AM', end: '11:10 AM'),
    TimetablePeriod(period: 3, start: '11:10 AM', end: '12:00 PM'),
    TimetablePeriod(period: 4, start: '12:00 PM', end: '01:00 PM'),
    TimetablePeriod(period: 5, start: '01:00 PM', end: '01:50 PM'),
    TimetablePeriod(period: 6, start: '01:50 PM', end: '02:40 PM'),
    TimetablePeriod(period: 7, start: '02:40 PM', end: '03:30 PM'),
    TimetablePeriod(period: 8, start: '03:30 PM', end: '04:20 PM'),
  ];

  late final TabController _tabController;
  final Map<String, List<TextEditingController>> _controllers = {};
  List<TimetablePeriod> _periods = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _dayKeys.length, vsync: this);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    UserTimetable? timetable = widget.initialTimetable;
    timetable ??= await UserTimetableService.getTimetable();

    if (timetable != null && timetable.periods.isNotEmpty) {
      _periods = List.from(timetable.periods);
      for (final day in _dayKeys) {
        final dayData = timetable.week.firstWhere(
          (d) => d.day.toLowerCase().startsWith(day.toLowerCase()),
          orElse: () => TimetableDay(day: day, slots: []),
        );
        final list = <TextEditingController>[];
        for (int i = 0; i < _periods.length; i++) {
          final slotText = i < dayData.slots.length ? dayData.slots[i] : '';
          list.add(TextEditingController(text: slotText));
        }
        _controllers[day] = list;
      }
    } else {
      _periods = List.from(_defaultPeriods);
      for (final day in _dayKeys) {
        _controllers[day] = List.generate(
          _periods.length,
          (_) => TextEditingController(),
        );
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final list in _controllers.values) {
      for (final controller in list) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  TimeOfDay _parseTimeOfDay(String timeStr, TimeOfDay fallback) {
    try {
      final regex = RegExp(
        r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
        caseSensitive: false,
      );
      final match = regex.firstMatch(timeStr.trim());
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final period = match.group(3)?.toUpperCase();

        if (period == 'PM' && hour < 12) {
          hour += 12;
        } else if (period == 'AM' && hour == 12) {
          hour = 0;
        }
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return fallback;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hourOfPeriod = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final hourStr = hourOfPeriod.toString().padLeft(2, '0');
    final minuteStr = time.minute.toString().padLeft(2, '0');
    final periodStr = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hourStr:$minuteStr $periodStr';
  }

  Future<void> _editSingleTime(int periodIndex, bool isStart) async {
    final current = _periods[periodIndex];
    final defaultHour = isStart ? (9 + periodIndex) % 24 : (10 + periodIndex) % 24;
    final initial = _parseTimeOfDay(
      isStart ? current.start : current.end,
      TimeOfDay(hour: defaultHour, minute: 0),
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Select ${isStart ? "Start" : "End"} Time for P${periodIndex + 1}',
    );
    if (picked == null || !mounted) return;

    final newStr = _formatTimeOfDay(picked);
    setState(() {
      _periods[periodIndex] = TimetablePeriod(
        period: periodIndex + 1,
        start: isStart ? newStr : current.start,
        end: isStart ? current.end : newStr,
      );
    });
  }

  Future<void> _editPeriodBothTimes(int periodIndex) async {
    final current = _periods[periodIndex];
    final initialStart = _parseTimeOfDay(
      current.start,
      const TimeOfDay(hour: 9, minute: 0),
    );
    final initialEnd = _parseTimeOfDay(
      current.end,
      const TimeOfDay(hour: 10, minute: 0),
    );

    final pickedStart = await showTimePicker(
      context: context,
      initialTime: initialStart,
      helpText: 'Select Start Time for P${periodIndex + 1}',
    );
    if (pickedStart == null || !mounted) return;

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: initialEnd,
      helpText: 'Select End Time for P${periodIndex + 1}',
    );
    if (pickedEnd == null || !mounted) return;

    final newStartStr = _formatTimeOfDay(pickedStart);
    final newEndStr = _formatTimeOfDay(pickedEnd);

    setState(() {
      _periods[periodIndex] = TimetablePeriod(
        period: periodIndex + 1,
        start: newStartStr,
        end: newEndStr,
      );
    });
  }

  void _addPeriod() {
    setState(() {
      final nextNum = _periods.length + 1;
      String start = '04:20 PM';
      String end = '05:10 PM';
      if (_periods.isNotEmpty) {
        start = _periods.last.end.isNotEmpty ? _periods.last.end : '04:20 PM';
        final lastEndTime = _parseTimeOfDay(
          start,
          const TimeOfDay(hour: 16, minute: 20),
        );
        final newEndMinutes =
            (lastEndTime.hour * 60 + lastEndTime.minute + 50) % (24 * 60);
        final newEndTime = TimeOfDay(
          hour: newEndMinutes ~/ 60,
          minute: newEndMinutes % 60,
        );
        end = _formatTimeOfDay(newEndTime);
      }
      _periods.add(TimetablePeriod(period: nextNum, start: start, end: end));
      for (final day in _dayKeys) {
        _controllers[day] ??= [];
        _controllers[day]!.add(TextEditingController());
      }
    });
  }

  void _removePeriod(int index) {
    if (_periods.length <= 1) return;
    setState(() {
      _periods.removeAt(index);
      for (int i = 0; i < _periods.length; i++) {
        _periods[i] = TimetablePeriod(
          period: i + 1,
          start: _periods[i].start,
          end: _periods[i].end,
        );
      }
      for (final day in _dayKeys) {
        if (_controllers[day] != null && index < _controllers[day]!.length) {
          final ctrl = _controllers[day]!.removeAt(index);
          ctrl.dispose();
        }
      }
    });
  }

  void _copyDayToAll(String currentDay) {
    final sourceControllers = _controllers[currentDay];
    if (sourceControllers == null) return;

    setState(() {
      for (final day in _dayKeys) {
        if (day == currentDay) continue;
        final targetControllers = _controllers[day] ?? [];
        for (int i = 0; i < sourceControllers.length && i < targetControllers.length; i++) {
          targetControllers[i].text = sourceControllers[i].text;
        }
      }
    });

    showUtopiaSnackBar(
      context,
      message: 'Copied $currentDay schedule to all other days!',
      tone: UtopiaSnackBarTone.success,
    );
  }

  void _clearDay(String currentDay) {
    final controllers = _controllers[currentDay];
    if (controllers == null) return;

    setState(() {
      for (final c in controllers) {
        c.clear();
      }
    });

    showUtopiaSnackBar(
      context,
      message: 'Cleared all classes for $currentDay',
      tone: UtopiaSnackBarTone.info,
    );
  }

  void _resetPeriodsToDefault() {
    setState(() {
      _periods = List.from(_defaultPeriods);
      for (final day in _dayKeys) {
        final existing = _controllers[day] ?? [];
        while (existing.length < _periods.length) {
          existing.add(TextEditingController());
        }
        while (existing.length > _periods.length) {
          final c = existing.removeLast();
          c.dispose();
        }
        _controllers[day] = existing;
      }
    });
  }

  Set<String> _getUniqueExistingSubjects() {
    final set = <String>{};
    for (final day in _dayKeys) {
      final list = _controllers[day];
      if (list != null) {
        for (final c in list) {
          final val = c.text.trim();
          if (val.isNotEmpty && val.length > 1) {
            set.add(val);
          }
        }
      }
    }
    return set;
  }

  void _showManagePeriodsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    20,
              ),
              decoration: BoxDecoration(
                color: U.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Manage Periods & Timings',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: U.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    'Tap any start or end time to freely customize your period schedule.',
                    style: GoogleFonts.outfit(fontSize: 13, color: U.sub),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _periods.length,
                      itemBuilder: (context, idx) {
                        final p = _periods[idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: U.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: U.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: U.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'P${p.period}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: U.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        final currentStart = _parseTimeOfDay(
                                          p.start,
                                          const TimeOfDay(hour: 9, minute: 0),
                                        );
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: currentStart,
                                        );
                                        if (picked != null) {
                                          final newStr = _formatTimeOfDay(picked);
                                          setState(() {
                                            _periods[idx] = TimetablePeriod(
                                              period: p.period,
                                              start: newStr,
                                              end: p.end,
                                            );
                                          });
                                          setModalState(() {});
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: U.bg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: U.border),
                                        ),
                                        child: Text(
                                          p.start.isEmpty ? 'Start' : p.start,
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: U.text,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'to',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: U.sub,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        final currentEnd = _parseTimeOfDay(
                                          p.end,
                                          const TimeOfDay(hour: 10, minute: 0),
                                        );
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: currentEnd,
                                        );
                                        if (picked != null) {
                                          final newStr = _formatTimeOfDay(picked);
                                          setState(() {
                                            _periods[idx] = TimetablePeriod(
                                              period: p.period,
                                              start: p.start,
                                              end: newStr,
                                            );
                                          });
                                          setModalState(() {});
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: U.bg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: U.border),
                                        ),
                                        child: Text(
                                          p.end.isEmpty ? 'End' : p.end,
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: U.text,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_periods.length > 1)
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: U.red,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _removePeriod(idx);
                                    setModalState(() {});
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: U.primary,
                              side: BorderSide(
                                color: U.primary.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              _addPeriod();
                              setModalState(() {});
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                              'Add Slot',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: U.sub,
                            side: BorderSide(
                              color: U.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            _resetPeriodsToDefault();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(
                            'Reset',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveTimetable() async {
    setState(() => _saving = true);
    try {
      final List<TimetableDay> week = [];
      for (final day in _dayKeys) {
        final slots = (_controllers[day] ?? []).map((c) => c.text.trim()).toList();
        week.add(TimetableDay(day: day, slots: slots));
      }

      final customTimetable = UserTimetable(periods: _periods, week: week);

      await UserTimetableService.saveTimetable(customTimetable);

      if (!mounted) return;
      showUtopiaSnackBar(
        context,
        message: 'Timetable Saved Successfully!',
        tone: UtopiaSnackBarTone.success,
      );
      Navigator.pop(context, true);
    } catch (e) {
      showUtopiaSnackBar(
        context,
        message: 'Failed to save timetable: $e',
        tone: UtopiaSnackBarTone.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDayEditor(String day) {
    final controllers = _controllers[day] ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suggestions = _getUniqueExistingSubjects();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.copy_rounded, size: 14),
                  label: Text('Copy to all days', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
                  backgroundColor: U.primary.withValues(alpha: 0.08),
                  side: BorderSide(color: U.primary.withValues(alpha: 0.25)),
                  labelStyle: TextStyle(color: U.primary),
                  onPressed: () => _copyDayToAll(day),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: Icon(Icons.clear_all_rounded, size: 15, color: U.sub),
                  label: Text('Clear day', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500)),
                  backgroundColor: U.surface,
                  side: BorderSide(color: U.border),
                  labelStyle: TextStyle(color: U.sub),
                  onPressed: () => _clearDay(day),
                ),
                const Spacer(),
                Text(
                  '${_periods.length} Periods',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: U.sub,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (suggestions.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final subj = suggestions.elementAt(i);
                  return GestureDetector(
                    onTap: () {
                      // Autofill the first empty controller on this day
                      for (final c in controllers) {
                        if (c.text.trim().isEmpty) {
                          c.text = subj;
                          setState(() {});
                          return;
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: U.border.withValues(alpha: 0.8)),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 12, color: U.primary),
                          const SizedBox(width: 4),
                          Text(
                            subj,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: U.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final p = _periods[index];
                final controller =
                    index < controllers.length ? controllers[index] : null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? U.card : U.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: U.border.withValues(alpha: 0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'P${p.period}',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: U.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Flexible Timing Capsule: tap start or end independently
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: U.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: U.border.withValues(alpha: 0.8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _editSingleTime(index, true),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text(
                                  p.start.isEmpty ? 'Start' : p.start,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: U.text,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              '-',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: U.sub,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            InkWell(
                              onTap: () => _editSingleTime(index, false),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text(
                                  p.end.isEmpty ? 'End' : p.end,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: U.text,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _editPeriodBothTimes(index),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Icon(Icons.edit_rounded, size: 12, color: U.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            color: U.text,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Free / Subject Name',
                            hintStyle: GoogleFonts.outfit(
                              fontSize: 14,
                              color: U.sub.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: _periods.length,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        foregroundColor: U.text,
        elevation: 0,
        leadingWidth: 70,
        leading: Center(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: U.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: U.border, width: 0.5),
              ),
              child: Icon(Icons.arrow_back_rounded, color: U.primary, size: 18),
            ),
          ),
        ),
        title: Text(
          'Custom Timetable',
          style: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: U.text,
            fontStyle: FontStyle.italic,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Manage Periods & Timings',
            onPressed: _showManagePeriodsSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: U.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: U.border),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: U.bg,
                unselectedLabelColor: U.sub,
                indicator: BoxDecoration(
                  color: U.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(999),
                labelPadding: const EdgeInsets.symmetric(horizontal: 18),
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: _dayKeys.map((label) => Tab(text: label)).toList(),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: UtopiaLoader(scale: 0.7))
          : TabBarView(
              controller: _tabController,
              children: _dayKeys.map(_buildDayEditor).toList(),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: U.primary,
                foregroundColor: U.bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _saving || _loading ? null : _saveTimetable,
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: U.bg,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Save Timetable',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

