import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/notification_service.dart';
import '../services/people_interaction_service.dart';
import '../services/writer_firestore_service.dart';
import '../widgets/utopia_snackbar.dart';
import 'broadcast_screen.dart';

class DeveloperPanelScreen extends StatefulWidget {
  const DeveloperPanelScreen({super.key});

  @override
  State<DeveloperPanelScreen> createState() => _DeveloperPanelScreenState();
}

class _DeveloperPanelScreenState extends State<DeveloperPanelScreen> {
  // ── Analytics stats ──
  bool _statsLoading = true;
  int _totalAccounts = 0;
  int _dailyActiveUsers = 0;

  // ── News Card controls ──
  bool _newsEnabled = false;
  bool _savingNews = false;
  final _newsTitleController = TextEditingController();
  final _newsDescController = TextEditingController();

  // ── Campus Spark controls ──
  final PeopleInteractionService _sparkService = PeopleInteractionService();
  bool _sparkEnabled = true;
  bool _savingSpark = false;
  final _sparkQuestionController = TextEditingController();
  final _sparkCategoryController = TextEditingController();
  final List<TextEditingController> _sparkOptionControllers = [
    TextEditingController(text: 'Late-night owl 🦉'),
    TextEditingController(text: 'Early-morning grinder 🌅'),
    TextEditingController(text: 'Panic 2h before deadline ⏳'),
  ];
  bool _sparkResetVotes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
      _loadNewsConfig();
      _loadSparkConfig();
    });
  }

  @override
  void dispose() {
    _newsTitleController.dispose();
    _newsDescController.dispose();
    _sparkQuestionController.dispose();
    _sparkCategoryController.dispose();
    for (final c in _sparkOptionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNewsConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('app_config').get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        if (mounted) {
          setState(() {
            _newsEnabled = data['news_enabled'] as bool? ?? false;
            _newsTitleController.text = data['news_title'] as String? ?? '';
            _newsDescController.text = data['news_description'] as String? ?? '';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSparkConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('campus_spark').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final q = SparkQuestion.fromMap(data);
        if (mounted) {
          setState(() {
            _sparkEnabled = q.enabled;
            _sparkQuestionController.text = q.question;
            _sparkCategoryController.text = q.category;
            for (final c in _sparkOptionControllers) {
              c.dispose();
            }
            _sparkOptionControllers.clear();
            _sparkOptionControllers.addAll(
              q.options.map((opt) => TextEditingController(text: opt)),
            );
          });
        }
      } else {
        final fallback = _sparkService.getTodaysSparkFallback();
        if (mounted) {
          setState(() {
            _sparkQuestionController.text = fallback.question;
            _sparkCategoryController.text = fallback.category;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveNewsConfig() async {
    setState(() => _savingNews = true);
    try {
      final currentDoc = await FirebaseFirestore.instance.collection('config').doc('app_config').get();
      final data = currentDoc.exists ? (currentDoc.data() ?? {}) : <String, dynamic>{};
      data['news_enabled'] = _newsEnabled;
      data['news_title'] = _newsTitleController.text.trim();
      data['news_description'] = _newsDescController.text.trim();
      data['news_updated_at'] = FieldValue.serverTimestamp();

      await WriterFirestoreService.updateConfig('app_config', data);

      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'News Card updated successfully!',
          tone: UtopiaSnackBarTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Failed to update News Card',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingNews = false);
    }
  }

  Future<void> _saveSparkConfig() async {
    final question = _sparkQuestionController.text.trim();
    final category = _sparkCategoryController.text.trim();
    final options = _sparkOptionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

    if (question.isEmpty || options.length < 2) {
      showUtopiaSnackBar(context, message: 'Please enter question and at least 2 options', tone: UtopiaSnackBarTone.error);
      return;
    }

    setState(() => _savingSpark = true);
    try {
      await _sparkService.updateSparkConfig(
        question: question,
        options: options,
        category: category.isNotEmpty ? category : 'Campus Spark',
        enabled: _sparkEnabled,
        createNewPoll: _sparkResetVotes,
      );

      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Campus Spark updated & broadcasted! ✨',
          tone: UtopiaSnackBarTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Failed to update Campus Spark: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingSpark = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final usersRef = FirebaseFirestore.instance.collection('users');

      // Total registered accounts
      final allUsersSnap = await usersRef.count().get();
      final totalCount = allUsersSnap.count ?? 0;

      // Daily active users — lastSeen within last 24 hours
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 24)),
      );
      final dauSnap = await usersRef
          .where('lastSeen', isGreaterThan: cutoff)
          .count()
          .get();
      final dauCount = dauSnap.count ?? 0;

      if (mounted) {
        setState(() {
          _totalAccounts = totalCount;
          _dailyActiveUsers = dauCount;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _statsLoading = false);
      }
    }
  }

  Future<void> _triggerPopupEvent() async {
    try {
      final newEventId = DateTime.now().millisecondsSinceEpoch.toString();
      final data = await WriterFirestoreService.fetchConfig('app_config');
      final currentData = data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      currentData['popup_event_id'] = newEventId;
      await WriterFirestoreService.updateConfig('app_config', currentData);
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Pop-up event triggered',
          tone: UtopiaSnackBarTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Could not trigger pop-up event',
          tone: UtopiaSnackBarTone.error,
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // UI Helpers
  // ──────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String text, {bool isFirst = false}) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 24, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.outfit(
          color: U.sub,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Analytics', isFirst: true),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.people_alt_rounded,
                label: 'Total Accounts',
                value: _statsLoading ? '—' : _totalAccounts.toString(),
                color: U.blue,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.trending_up_rounded,
                label: 'Active Today',
                value: _statsLoading ? '—' : _dailyActiveUsers.toString(),
                color: U.green,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: U.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: U.sub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? iconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = iconColor ?? U.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.12 : 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: U.dim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: U.dim, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, child) {
        return Scaffold(
          backgroundColor: U.bg,
          appBar: AppBar(
            backgroundColor: U.bg,
            foregroundColor: U.text,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'Super Controls',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _buildStatsSection(),
              _buildCampusSparkSection(),
              _buildNewsCardSection(),
              _sectionHeader('Announcements'),
              _actionTile(
                icon: Icons.campaign_outlined,
                title: 'Broadcast Message',
                subtitle: 'Send notification to all students',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BroadcastScreen()),
                ),
              ),
              _actionTile(
                icon: Icons.notifications_active_outlined,
                title: 'Test Live Push Notification',
                subtitle: 'Send test high-priority push to this device',
                onTap: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    showUtopiaSnackBar(context, message: 'Please sign in to test push', tone: UtopiaSnackBarTone.error);
                    return;
                  }
                  showUtopiaSnackBar(context, message: 'Sending test push...', tone: UtopiaSnackBarTone.info);
                  await NotificationService.dispatchPushNotification(
                    recipientId: user.uid,
                    title: 'UTOPIA Live Test 👋',
                    message: 'Live push notification is working on this device!',
                    type: 'general',
                  );
                  if (context.mounted) {
                    showUtopiaSnackBar(context, message: 'Push dispatched! Check your notification tray.', tone: UtopiaSnackBarTone.success);
                  }
                },
              ),
              _actionTile(
                icon: Icons.celebration_outlined,
                title: 'Trigger Share Pop-up',
                subtitle: 'Show share pop-up on next launch',
                onTap: _triggerPopupEvent,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCampusSparkSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Campus Spark (QOTD & Polls) ⚡'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: U.primary,
                title: Text(
                  'Enable Campus Spark Card',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Shows the interactive icebreaker poll on top of People screen',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                ),
                value: _sparkEnabled,
                onChanged: (val) => setState(() => _sparkEnabled = val),
              ),
              const SizedBox(height: 12),

              // Quick Templates
              Text(
                'QUICK TEMPLATES',
                style: GoogleFonts.outfit(color: U.sub, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: PeopleInteractionService.sparkPool.map((tpl) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _sparkQuestionController.text = tpl.question;
                            _sparkCategoryController.text = tpl.category;
                            for (final c in _sparkOptionControllers) {
                              c.dispose();
                            }
                            _sparkOptionControllers.clear();
                            _sparkOptionControllers.addAll(
                              tpl.options.map((opt) => TextEditingController(text: opt)),
                            );
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: U.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: U.border),
                          ),
                          child: Text(
                            tpl.question,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(color: U.text, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Category
              TextField(
                controller: _sparkCategoryController,
                style: GoogleFonts.outfit(color: U.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Category / Badge',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText: 'e.g. Study Habit, Campus Vibe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Question
              TextField(
                controller: _sparkQuestionController,
                maxLines: 2,
                style: GoogleFonts.outfit(color: U.text, fontSize: 13.5),
                decoration: InputDecoration(
                  labelText: 'Question of the Day',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText: 'e.g. Your peak productivity hours? ⚡',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Poll Options', style: GoogleFonts.outfit(color: U.sub, fontSize: 12, fontWeight: FontWeight.w700)),
                  if (_sparkOptionControllers.length < 4)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _sparkOptionControllers.add(TextEditingController(text: 'Option ${_sparkOptionControllers.length + 1}'));
                        });
                      },
                      child: Text('+ Add Option', style: GoogleFonts.outfit(color: U.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ...List.generate(_sparkOptionControllers.length, (idx) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sparkOptionControllers[idx],
                          style: GoogleFonts.outfit(color: U.text, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Option ${idx + 1}',
                            labelStyle: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_sparkOptionControllers.length > 2) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline_rounded, color: U.red, size: 20),
                          onPressed: () {
                            setState(() {
                              final removed = _sparkOptionControllers.removeAt(idx);
                              removed.dispose();
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                );
              }),

              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _sparkResetVotes,
                title: Text(
                  'Reset poll votes (create new poll ID)',
                  style: GoogleFonts.outfit(color: U.text, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                activeColor: U.primary,
                onChanged: (v) => setState(() => _sparkResetVotes = v ?? false),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _savingSpark ? null : _saveSparkConfig,
                  icon: _savingSpark
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(
                    _savingSpark ? 'Publishing...' : 'Save & Broadcast Spark',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: U.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewsCardSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Main Screen News Card'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: U.primary,
                title: Text(
                  'Show News Card',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Displays news widget on main screen when enabled (online only)',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                ),
                value: _newsEnabled,
                onChanged: (val) {
                  setState(() => _newsEnabled = val);
                  _saveNewsConfig();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newsTitleController,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'News Title',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText: 'e.g. Midterm Exam Schedule',
                  hintStyle: GoogleFonts.outfit(color: U.dim),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newsDescController,
                maxLines: 3,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'News Description',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText: 'Enter announcement details here...',
                  hintStyle: GoogleFonts.outfit(color: U.dim),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _savingNews ? null : _saveNewsConfig,
                  icon: _savingNews
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _savingNews ? 'Saving...' : 'Save News Content',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: U.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
