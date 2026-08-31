import 'package:flutter/material.dart';
import '../widgets/utopia_loader.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/user_timetable.dart';
import '../services/gas_timetable_service.dart';
import '../services/secure_storage_service.dart';
import '../services/user_timetable_service.dart';
import '../services/notification_service.dart';
import '../widgets/utopia_snackbar.dart';
import 'custom_timetable_screen.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with SingleTickerProviderStateMixin {
  static const _dayKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  late final TabController _tabController;
  UserTimetable? _userTimetable;
  bool _loading = true;
  bool _refreshing = false;

  bool _notifEnabled = false;
  TimeOfDay _notifTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _dayKeys.length,
      vsync: this,
      initialIndex: _initialDayIndex(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _initialDayIndex() {
    final weekday = DateTime.now().weekday;
    if (weekday >= DateTime.monday && weekday <= DateTime.saturday) {
      return weekday - 1;
    }
    return 0; // default to Monday if Sunday
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (refresh) setState(() => _refreshing = true);

    try {
      _userTimetable = await UserTimetableService.getTimetable();

      final prefs = await SharedPreferences.getInstance();
      _notifEnabled = prefs.getBool('timetable_notif_enabled') ?? false;
      final h = prefs.getInt('timetable_notif_hour') ?? 7;
      final m = prefs.getInt('timetable_notif_minute') ?? 0;
      _notifTime = TimeOfDay(hour: h, minute: m);

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      showUtopiaSnackBar(
        context,
        message: 'Could not load timetable',
        tone: UtopiaSnackBarTone.error,
      );
    } finally {
      if (mounted && refresh) setState(() => _refreshing = false);
    }
  }

  Future<void> _fetchFromCollege() async {
    setState(() => _loading = true);
    try {
      final creds = await SecureStorageService.getCredentials();
      if (creds == null) {
        showUtopiaSnackBar(
          context,
          message: 'Please login to attendance first to fetch timetable.',
          tone: UtopiaSnackBarTone.error,
        );
        setState(() => _loading = false);
        return;
      }
      final rawData = await GasTimetableService.fetchTimetable(
        creds['rollNumber'] ?? '',
        creds['password'] ?? '',
        creds['college'] ?? 'aus',
      );
      final newTimetable = UserTimetable.fromJson(rawData);
      await UserTimetableService.saveTimetable(newTimetable);

      showUtopiaSnackBar(
        context,
        message: 'Timetable fetched successfully!',
        tone: UtopiaSnackBarTone.success,
      );
      _loadData();
    } catch (e) {
      setState(() => _loading = false);
      showUtopiaSnackBar(
        context,
        message: 'Failed to fetch timetable: $e',
        tone: UtopiaSnackBarTone.error,
      );
    }
  }

  Future<void> _toggleNotif(bool val) async {
    if (val) {
      final success =
          await NotificationService.scheduleDailyTimetableNotification(
            hour: _notifTime.hour,
            minute: _notifTime.minute,
          );
      if (!success && mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Failed to schedule notification. Please try again.',
          tone: UtopiaSnackBarTone.error,
        );
        return;
      }
    } else {
      await NotificationService.cancelTimetableNotification();
    }
    setState(() => _notifEnabled = val);
  }

  Future<void> _pickNotifTime() async {
    final t = await showTimePicker(context: context, initialTime: _notifTime);
    if (t != null && mounted) {
      setState(() => _notifTime = t);
      if (_notifEnabled) {
        final success =
            await NotificationService.scheduleDailyTimetableNotification(
              hour: t.hour,
              minute: t.minute,
            );
        if (!success && mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Failed to schedule notification. Please try again.',
            tone: UtopiaSnackBarTone.error,
          );
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timetable_notif_hour', t.hour);
      await prefs.setInt('timetable_notif_minute', t.minute);
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child:
            Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: U.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_calendar_rounded,
                        size: 48,
                        color: U.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Timetable Found',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: U.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You can fetch your personal timetable directly from your college portal, or create a custom one.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: U.sub,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: U.primary,
                          foregroundColor: U.bg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _fetchFromCollege,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text(
                          'Fetch from College',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: U.primary,
                          side: BorderSide(
                            color: U.primary.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CustomTimetableScreen(),
                            ),
                          );
                          if (result == true) {
                            _loadData();
                          }
                        },
                        icon: const Icon(Icons.dashboard_customize_outlined),
                        label: Text(
                          'Create Custom',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, duration: 400.ms, curve: Curves.easeOut),
      ),
    );
  }

  Future<void> _openEditTimetable() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomTimetableScreen(initialTimetable: _userTimetable),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  Widget _buildSettingsSheet() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Timetable Settings',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: U.text,
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.edit_outlined,
              color: U.primary,
            ),
            title: Text(
              'Edit Timetable & Timings',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: U.text,
              ),
            ),
            subtitle: Text(
              'Modify classes and period times',
              style: GoogleFonts.outfit(fontSize: 13, color: U.sub),
            ),
            onTap: () {
              Navigator.pop(context);
              _openEditTimetable();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.notifications_active_outlined,
              color: U.primary,
            ),
            title: Text(
              'Daily Notification',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: U.text,
              ),
            ),
            subtitle: Text(
              'Get alerted about your classes',
              style: GoogleFonts.outfit(fontSize: 13, color: U.sub),
            ),
            trailing: Switch(
              value: _notifEnabled,
              activeThumbColor: U.primary,
              onChanged: _toggleNotif,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.access_time_rounded,
              color: _notifEnabled ? U.primary : U.dim,
            ),
            title: Text(
              'Notification Time',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _notifEnabled ? U.text : U.dim,
              ),
            ),
            subtitle: Text(
              _notifTime.format(context),
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: _notifEnabled ? U.sub : U.dim,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: _notifEnabled ? U.primary : U.dim,
            ),
            enabled: _notifEnabled,
            onTap: _pickNotifTime,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: U.red),
            title: Text(
              'Delete Timetable',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: U.text,
              ),
            ),
            subtitle: Text(
              'Remove your saved timetable',
              style: GoogleFonts.outfit(fontSize: 13, color: U.sub),
            ),
            onTap: () async {
              Navigator.pop(context);
              await UserTimetableService.deleteTimetable();
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayView(String dayLabel) {
    if (_userTimetable == null) return const SizedBox.shrink();

    final dayData = _userTimetable!.week.firstWhere(
      (d) => d.day.toLowerCase().startsWith(dayLabel.toLowerCase()),
      orElse: () => const TimetableDay(day: '', slots: []),
    );

    if (dayData.slots.isEmpty || dayData.slots.every((s) => s.trim().isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: U.teal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.celebration_rounded,
                size: 40,
                color: U.teal,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No classes today!',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: U.text,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enjoy your free time or catch up on studies.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: U.sub,
              ),
            ),
          ],
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, duration: 400.ms, curve: Curves.easeOut),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: dayData.slots.length,
      itemBuilder: (context, index) {
        final subject = dayData.slots[index].trim();
        if (subject.isEmpty) {
          return const SizedBox.shrink(); // skip free periods
        }

        TimetablePeriod? period;
        if (index < _userTimetable!.periods.length) {
          period = _userTimetable!.periods[index];
        }

        return GestureDetector(
          onTap: _openEditTimetable,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: U.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: U.border.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Beautiful timeline period capsule
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: U.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: U.primary.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    'P${period?.period ?? index + 1}',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: U.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Subtle colored vertical divider
                Container(
                  width: 1.5,
                  height: 38,
                  decoration: BoxDecoration(
                    color: U.border.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                const SizedBox(width: 16),
                // Subject Details and Timings
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: U.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: U.sub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            period != null
                                ? '${period.start} - ${period.end}'
                                : 'Duration --',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: U.sub,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: U.sub.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(delay: (index * 50).ms, duration: 400.ms)
        .slideX(begin: 0.05, duration: 400.ms, curve: Curves.easeOut);
      },
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
          'Timetable',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: U.text,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          if (_userTimetable != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Timetable & Timings',
              onPressed: _openEditTimetable,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Timetable Settings',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (context) => _buildSettingsSheet(),
                );
              },
            ),
          ],
        ],
        bottom: _userTimetable == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(74),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: U.border.withValues(alpha: 0.5)),
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
                      tabs: _dayLabels
                          .map((label) => Tab(text: label))
                          .toList(),
                    ),
                  ),
                ),
              ),
      ),
      body: _loading
          ? const Center(child: UtopiaLoader(scale: 0.7))
          : _userTimetable == null
              ? _buildEmptyState()
              : TabBarView(
                  controller: _tabController,
                  children: _dayLabels.map(_buildDayView).toList(),
                ),
    );
  }
}
