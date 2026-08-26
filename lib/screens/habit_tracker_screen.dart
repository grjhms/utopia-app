import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../models/focus_models.dart';
import '../services/focus_supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/habit_calculators.dart';
import 'habit_editor_screen.dart';
import 'habit_detail_screen.dart';
import '../widgets/utopia_snackbar.dart';
import '../widgets/utopia_loader.dart';

class HabitTrackerScreen extends StatefulWidget {
  const HabitTrackerScreen({super.key});

  @override
  State<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class _HabitTrackerScreenState extends State<HabitTrackerScreen> with WidgetsBindingObserver {
  final _service = FocusSupabaseService();
  bool _loading = true;
  bool _syncing = false;
  bool _showArchived = false;
  List<FocusHabit> _habits = [];
  Map<String, List<HabitRecord>> _records = {}; // habitId -> records
  late List<DateTime> _last7Days;
  String _syncTimeLabel = 'Never synced';
  bool _showFab = true;

  bool _hasAlarmPermission = true;
  bool _hasNotificationPermission = true;
  bool _checkingPermissionState = true;

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generate7Days();
    _initData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final alarmEnabled = await NotificationService.canScheduleExactNotifications();
    final notifEnabled = await NotificationService.areNotificationPermissionsEnabled();
    if (mounted) {
      setState(() {
        _hasAlarmPermission = alarmEnabled;
        _hasNotificationPermission = notifEnabled;
        _checkingPermissionState = false;
      });
    }
  }

  void _generate7Days() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    _last7Days = List.generate(7, (i) => todayStart.subtract(Duration(days: 6 - i)));
  }

  Future<void> _initData() async {
    await _service.initialize();
    
    // 1. Run the background weekly auto-sync check!
    await _service.checkAndWeeklyAutoSync();

    await _checkPermissions();
    await _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final habits = await _service.getHabits(includeArchived: _showArchived);
      final recordsMap = <String, List<HabitRecord>>{};

      for (final h in habits) {
        final records = await _service.getRecordsForHabit(h.id);
        recordsMap[h.id] = records;
      }

      final prefs = await SharedPreferences.getInstance();
      final showFab = prefs.getBool('habits_show_fab') ?? true;
      final lastSyncStr = prefs.getString('focus_last_sync_time');
      String syncLabel = 'Never synced';
      if (lastSyncStr != null) {
        try {
          final lastSync = DateTime.parse(lastSyncStr);
          final diff = DateTime.now().difference(lastSync);
          if (diff.inMinutes < 1) {
            syncLabel = 'Synced just now';
          } else if (diff.inHours < 1) {
            syncLabel = 'Synced ${diff.inMinutes}m ago';
          } else if (diff.inDays < 1) {
            syncLabel = 'Synced ${diff.inHours}h ago';
          } else {
            syncLabel = 'Synced ${diff.inDays}d ago';
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _habits = habits;
          _records = recordsMap;
          _syncTimeLabel = syncLabel;
          _showFab = showFab;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Load local habits data failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerManualSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      showUtopiaSnackBar(
        context,
        message: 'Syncing habits with cloud...',
        tone: UtopiaSnackBarTone.info,
      );

      await _service.performManualSync();
      await _loadLocalData();

      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Cloud sync complete!',
          tone: UtopiaSnackBarTone.success,
        );
      }
    } catch (e) {
      debugPrint('Manual sync triggered error: $e');
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Sync failed: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _triggerExportBackup() async {
    try {
      showUtopiaSnackBar(
        context,
        message: 'Preparing habit backup file...',
        tone: UtopiaSnackBarTone.info,
      );

      final result = await _service.exportHabitsBackupData();
      final bool savedDirectly = result['savedDirectlyToDownloads'] == true;
      final String filePath = result['path'] as String;
      final Uint8List bytes = result['bytes'] as Uint8List;

      if (savedDirectly) {
        if (context.mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Backup saved directly to Downloads folder!',
            tone: UtopiaSnackBarTone.success,
          );
        }
      } else {
        // Fallback: Use FilePicker to let the user save to Downloads
        if (context.mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Saving backup file...',
            tone: UtopiaSnackBarTone.info,
          );
        }

        final String? selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Habits Backup',
          fileName: 'utopia_habits_backup.json',
          bytes: bytes,
        );

        if (selectedPath != null) {
          if (context.mounted) {
            showUtopiaSnackBar(
              context,
              message: 'Backup saved successfully!',
              tone: UtopiaSnackBarTone.success,
            );
          }
        } else {
          // If saveFile is cancelled or not supported, use Share as ultimate fallback
          final file = XFile(filePath);
          await Share.shareXFiles(
            [file],
            text: 'My Utopia Habits Backup',
            subject: 'Utopia Habits Backup',
          );
        }
      }
    } catch (e) {
      debugPrint('Export backup failed: $e');
      if (context.mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Export failed: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    }
  }

  Future<void> _triggerImportBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        return; // User cancelled
      }

      showUtopiaSnackBar(
        context,
        message: 'Importing habits backup...',
        tone: UtopiaSnackBarTone.info,
      );

      final file = File(result.files.single.path!);
      final jsonContent = await file.readAsString();

      final success = await _service.importHabitsFromJson(jsonContent);

      if (success) {
        await _loadLocalData();
        if (context.mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Backup imported successfully!',
            tone: UtopiaSnackBarTone.success,
          );
        }
      }
    } catch (e) {
      debugPrint('Import backup failed: $e');
      if (context.mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Import failed: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _toggleBinaryRecord(FocusHabit habit, DateTime date) async {
    final dateStr = _dateStr(date);
    final existingRecords = _records[habit.id] ?? [];
    final existing = existingRecords.firstWhere(
      (r) => r.date == dateStr,
      orElse: () => HabitRecord(id: '', habitId: '', userId: '', date: '', updatedAt: DateTime.now()),
    );

    final bool currentlyCompleted = existing.id.isNotEmpty && existing.completed;
    final double newValue = currentlyCompleted ? 0.0 : 1.0;
    
    final updatedRecord = HabitRecord(
      id: existing.id.isEmpty ? '' : existing.id,
      habitId: habit.id,
      userId: _userId,
      date: dateStr,
      value: newValue,
      targetValue: 1.0,
      completed: !currentlyCompleted,
      note: existing.id.isEmpty ? null : existing.note,
      syncStatus: 'pending',
      updatedAt: DateTime.now(),
    );

    await _service.saveRecord(updatedRecord);
    
    // Quick reload local records for this habit
    final freshRecords = await _service.getRecordsForHabit(habit.id);
    setState(() {
      _records[habit.id] = freshRecords;
    });

    // Subtle haptic response
    HapticFeedback.lightImpact();
  }

  void _showNumericalRecordSheet(FocusHabit habit, DateTime date) async {
    final dateStr = _dateStr(date);
    final existingRecords = _records[habit.id] ?? [];
    final existing = existingRecords.firstWhere(
      (r) => r.date == dateStr,
      orElse: () => HabitRecord(id: '', habitId: '', userId: '', date: '', updatedAt: DateTime.now()),
    );

    final valueController = TextEditingController(
      text: existing.id.isNotEmpty ? existing.value.toStringAsFixed(0) : '0',
    );
    final noteController = TextEditingController(text: existing.note ?? '');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                decoration: BoxDecoration(
                  color: U.bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: U.border.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: U.dim.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            habit.name,
                            style: GoogleFonts.newsreader(
                              fontSize: 24,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              color: U.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDisplayDate(date),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: U.sub,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Log Progress (${habit.unit ?? 'units'})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: U.dim,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline_rounded, color: _colorFromHex(habit.color), size: 28),
                          onPressed: () {
                            final val = double.tryParse(valueController.text) ?? 0.0;
                            if (val > 0) {
                              valueController.text = (val - 1).clamp(0.0, 99999.0).toStringAsFixed(0);
                            }
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: valueController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: U.text,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              fillColor: U.surface,
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.add_circle_outline_rounded, color: _colorFromHex(habit.color), size: 28),
                          onPressed: () {
                            final val = double.tryParse(valueController.text) ?? 0.0;
                            valueController.text = (val + 1).toStringAsFixed(0);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'DAILY LOG NOTE (COMMENTS)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: U.dim,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Record a daily note for this habit check...',
                        fillColor: U.surface,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _colorFromHex(habit.color),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () async {
                          final value = double.tryParse(valueController.text) ?? 0.0;
                          final completed = value >= habit.targetValue;
                          final noteText = noteController.text.trim();

                          final updatedRecord = HabitRecord(
                            id: existing.id.isEmpty ? '' : existing.id,
                            habitId: habit.id,
                            userId: _userId,
                            date: dateStr,
                            value: value,
                            targetValue: habit.targetValue,
                            completed: completed,
                            note: noteText.isEmpty ? null : noteText,
                            syncStatus: 'pending',
                            updatedAt: DateTime.now(),
                          );

                          await _service.saveRecord(updatedRecord);
                          final freshRecords = await _service.getRecordsForHabit(habit.id);
                          
                          if (context.mounted) {
                            setState(() {
                              _records[habit.id] = freshRecords;
                            });
                            Navigator.pop(context);
                          }
                        },
                        child: Text(
                          'Save Log Record',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDisplayDate(DateTime d) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  Color _colorFromHex(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return U.primary;
    }
  }

  Widget _buildPermissionsWarning() {
    if (_checkingPermissionState) return const SizedBox.shrink();
    if (_hasAlarmPermission && _hasNotificationPermission) {
      return const SizedBox.shrink();
    }

    final isDark = appThemeNotifier.value.isDark;

    String title = 'Enable Notifications';
    String message = 'Allow notifications so habit reminders appear on time.';
    IconData icon = Icons.notifications_active_rounded;
    Future<void> Function() onFix = () async {
      await NotificationService.requestNotificationPermissionOnly();
      await _checkPermissions();
    };

    if (_hasNotificationPermission && !_hasAlarmPermission) {
      title = 'Alarms & Reminders';
      message = 'Exact alarms are restricted. Tap to enable exact alarm timing.';
      icon = Icons.alarm_rounded;
      onFix = () async {
        await NotificationService.openExactAlarmSettings();
        await _checkPermissions();
      };
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: U.gold.withValues(alpha: isDark ? 0.08 : 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: U.gold.withValues(alpha: isDark ? 0.25 : 0.45),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: U.gold.withValues(alpha: isDark ? 0.02 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ]
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: U.gold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: U.gold, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: U.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: GoogleFonts.plusJakartaSans(
                      color: U.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () async {
                await onFix();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                backgroundColor: U.gold,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'Enable',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0, duration: 400.ms);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;
    
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: U.surface,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: U.bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildPermissionsWarning(),
              Expanded(
                child: _loading
                    ? const Center(child: UtopiaLoader(scale: 0.7))
                    : _habits.isEmpty
                        ? _buildEmptyState()
                        : _buildHabitList(),
              ),
            ],
          ),
        ),
        floatingActionButton: _showFab
            ? FloatingActionButton(
                backgroundColor: U.primary,
                foregroundColor: isDark ? U.bg : Colors.white,
                elevation: 4,
                shape: const CircleBorder(),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HabitEditorScreen()),
                ).then((_) => _loadLocalData()),
                child: const Icon(Icons.add_rounded, size: 28),
              )
            : null,
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          GestureDetector(
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Habits',
                  style: GoogleFonts.newsreader(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    color: U.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _syncTimeLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: U.sub,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (_syncing)
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(9),
              child: CircularProgressIndicator(strokeWidth: 2, color: U.primary),
            )
          else
            IconButton(
              icon: Icon(Icons.sync_rounded, color: U.primary, size: 22),
              onPressed: _triggerManualSync,
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: U.primary),
            color: U.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'add_habit') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HabitEditorScreen()),
                ).then((_) => _loadLocalData());
              } else if (val == 'toggle_fab') {
                setState(() {
                  _showFab = !_showFab;
                });
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setBool('habits_show_fab', _showFab);
                });
              } else if (val == 'archive') {
                setState(() {
                  _showArchived = !_showArchived;
                  _loadLocalData();
                });
              } else if (val == 'sync') {
                _triggerManualSync();
              } else if (val == 'export') {
                _triggerExportBackup();
              } else if (val == 'import') {
                _triggerImportBackup();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'add_habit',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 18, color: U.text),
                    const SizedBox(width: 8),
                    Text(
                      'Add Habit',
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_fab',
                child: Row(
                  children: [
                    Icon(
                      _showFab ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: U.text,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showFab ? 'Hide + Button' : 'Show + Button',
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(
                      _showArchived ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: U.text,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showArchived ? 'Hide Archived' : 'Show Archived',
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sync',
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 18, color: U.text),
                    const SizedBox(width: 8),
                    Text(
                      'Manual Backup',
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 18, color: U.text),
                    const SizedBox(width: 8),
                    Text(
                      'Download Backup',
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.upload_file_rounded, size: 18, color: U.text),
                    const SizedBox(width: 8),
                    Text(
                      'Import Backup',
                      style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: U.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: U.border, width: 0.5),
              ),
              child: Icon(Icons.checklist_rounded, size: 36, color: U.sub),
            ),
            const SizedBox(height: 16),
            Text(
              'No habits tracked yet',
              style: GoogleFonts.plusJakartaSans(
                color: U.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the add (+) button below to create your very first custom YES/NO or Measurable habit!',
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 13,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildHabitList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      itemCount: _habits.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          // Column Headers Row for 7 Days Matrix
          return _buildMatrixHeader();
        }

        final habit = _habits[i - 1];
        final records = _records[habit.id] ?? [];
        final strength = HabitCalculators.calculateStrength(habit, records);
        final streak = HabitCalculators.calculateCurrentStreak(habit, records);

        return _buildHabitCard(habit, records, strength, streak)
            .animate()
            .fadeIn(delay: (i * 30).ms, duration: 350.ms)
            .slideY(begin: 0.05, end: 0, delay: (i * 30).ms, duration: 350.ms, curve: Curves.easeOutCubic);
      },
    );
  }

  Widget _buildMatrixHeader() {
    final daysOfWeekShort = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          // 7 columns for 7 days bubbles
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _last7Days.map((date) {
              final letter = daysOfWeekShort[date.weekday % 7];
              final isToday = _isSameDay(date, DateTime.now());
              return Container(
                width: 32,
                margin: const EdgeInsets.only(left: 6),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Text(
                      letter,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isToday ? U.primary : U.dim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${date.day}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? U.primary : U.sub,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitCard(FocusHabit habit, List<HabitRecord> records, double strength, int streak) {
    final habitColor = _colorFromHex(habit.color);
    final isDark = appThemeNotifier.value.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: U.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HabitDetailScreen(habit: habit),
              ),
            ).then((_) => _loadLocalData()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Habit Name & Streak Badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          habit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: U.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (streak > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: habitColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: habitColor.withValues(alpha: 0.25), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_fire_department_rounded, color: habitColor, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                '$streak day streak',
                                style: GoogleFonts.plusJakartaSans(
                                  color: habitColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Middle Row: Color indicator dot & detailed goal/strength subtitle
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: habitColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          habit.type == 'binary'
                              ? '${(strength * 100).toStringAsFixed(0)}% strength'
                              : 'Goal: ${habit.targetValue.toStringAsFixed(0)} ${habit.unit ?? ''} · ${(strength * 100).toStringAsFixed(0)}% strength',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: U.sub,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Bottom Row: Aligned 7-day grid bubbles
                  Row(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _last7Days.map((date) {
                          final dateStr = _dateStr(date);
                          final rec = records.firstWhere(
                            (r) => r.date == dateStr,
                            orElse: () => HabitRecord(id: '', habitId: '', userId: '', date: '', updatedAt: DateTime.now()),
                          );

                          final isCompleted = rec.id.isNotEmpty && rec.completed;
                          final isMeasurable = habit.type == 'measurable';
                          
                          // Progress fraction
                          double fraction = 0.0;
                          if (rec.id.isNotEmpty && rec.targetValue > 0) {
                            fraction = (rec.value / rec.targetValue).clamp(0.0, 1.0);
                          }

                          return GestureDetector(
                            onTap: () {
                              if (isMeasurable) {
                                _showNumericalRecordSheet(habit, date);
                              } else {
                                _toggleBinaryRecord(habit, date);
                              }
                            },
                            onLongPress: () {
                              _showNumericalRecordSheet(habit, date);
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCompleted
                                    ? habitColor
                                    : U.surface.withValues(alpha: 0.7),
                                border: isCompleted
                                    ? Border.all(color: habitColor, width: 0.8)
                                    : isMeasurable && fraction > 0
                                        ? null // Unified progress border drawn by custom painter!
                                        : Border.all(color: U.border.withValues(alpha: 0.4), width: 0.8),
                              ),
                              child: isCompleted
                                  ? const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 16))
                                  : isMeasurable && fraction > 0
                                      ? CustomPaint(
                                          size: const Size(32, 32),
                                          painter: _PremiumCircleProgressPainter(
                                            progress: fraction,
                                            color: habitColor,
                                            isDark: isDark,
                                          ),
                                        )
                                      : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _PremiumCircleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isDark;

  _PremiumCircleProgressPainter({
    required this.progress,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = 3.0;
    final double radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Draw the background track
    final trackPaint = Paint()
      ..color = color.withValues(alpha: isDark ? 0.15 : 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    // 2. Draw the active progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5708, // Start at top (-90 degrees)
        6.28318 * progress, // Sweep angle
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumCircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isDark != isDark;
  }
}
