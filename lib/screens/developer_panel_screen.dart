import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../main.dart';
import '../services/app_update_service.dart';
import '../services/luna_ai_service.dart';
import '../services/notification_service.dart';
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

  // ── App Update controls ──
  bool _updateEnabled = true;
  bool _forceUpdate = false;
  bool _savingUpdate = false;
  String _currentAppVersion = '';
  final _latestVersionController = TextEditingController();
  final _minVersionController = TextEditingController();
  final _updateTitleController = TextEditingController();
  final _updateMsgController = TextEditingController();
  final _updateUrlController = TextEditingController();

  // ── Luna AI Test controls ──
  final _lunaTestController =
      TextEditingController(text: 'Luna, roast people who skip morning class!');
  bool _lunaTesting = false;
  String? _lunaTestOutput;
  int? _lunaTestLatencyMs;
  bool _lunaPostToChat = false;
  Map<String, dynamic>? _lunaTestMetrics;
  bool _lunaShowSystemPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
      _loadNewsConfig();
      _loadUpdateConfig();
    });
  }

  @override
  void dispose() {
    _newsTitleController.dispose();
    _newsDescController.dispose();
    _latestVersionController.dispose();
    _minVersionController.dispose();
    _updateTitleController.dispose();
    _updateMsgController.dispose();
    _updateUrlController.dispose();
    _lunaTestController.dispose();
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

  Future<void> _loadUpdateConfig() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentAppVersion = packageInfo.version;
          if (packageInfo.buildNumber.isNotEmpty) {
            _currentAppVersion += '+${packageInfo.buildNumber}';
          }
        });
      }

      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        if (mounted) {
          setState(() {
            _updateEnabled = data['update_enabled'] as bool? ?? true;
            _forceUpdate = data['force_update'] as bool? ?? false;
            _latestVersionController.text =
                data['latest_version'] as String? ?? _currentAppVersion;
            _minVersionController.text =
                data['min_supported_version'] as String? ?? '0.0.0';
            _updateTitleController.text =
                data['update_title'] as String? ?? 'Update available';
            _updateMsgController.text = data['update_message'] as String? ??
                'A new version of UTOPIA is available on Google Play with new features and performance improvements.';
            _updateUrlController.text = data['update_url'] as String? ??
                AppUpdateService.defaultStoreUrl;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _latestVersionController.text = _currentAppVersion;
            _minVersionController.text = '0.0.0';
            _updateTitleController.text = 'Update available';
            _updateMsgController.text =
                'A new version of UTOPIA is available on Google Play with new features and performance improvements.';
            _updateUrlController.text = AppUpdateService.defaultStoreUrl;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveUpdateConfig() async {
    setState(() => _savingUpdate = true);
    try {
      final currentDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get();
      final data = currentDoc.exists
          ? (currentDoc.data() ?? {})
          : <String, dynamic>{};

      data['update_enabled'] = _updateEnabled;
      data['force_update'] = _forceUpdate;
      data['latest_version'] = _latestVersionController.text.trim();
      data['min_supported_version'] = _minVersionController.text.trim();
      data['update_title'] = _updateTitleController.text.trim();
      data['update_message'] = _updateMsgController.text.trim();
      data['update_url'] = _updateUrlController.text.trim();
      data['update_updated_at'] = FieldValue.serverTimestamp();

      await WriterFirestoreService.updateConfig('app_config', data);

      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Update settings saved successfully!',
          tone: UtopiaSnackBarTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Failed to save update settings: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingUpdate = false);
    }
  }

  void _previewUpdateDialog() {
    final info = UtopiaUpdateInfo(
      currentVersion: _currentAppVersion.isNotEmpty ? _currentAppVersion : '4.2.0',
      latestVersion: _latestVersionController.text.trim().isNotEmpty
          ? _latestVersionController.text.trim()
          : '4.3.0',
      minSupportedVersion: _minVersionController.text.trim().isNotEmpty
          ? _minVersionController.text.trim()
          : '0.0.0',
      title: _updateTitleController.text.trim().isNotEmpty
          ? _updateTitleController.text.trim()
          : 'Update available',
      message: _updateMsgController.text.trim().isNotEmpty
          ? _updateMsgController.text.trim()
          : 'A new version of UTOPIA is available on Google Play with new features and performance improvements.',
      storeUrl: _updateUrlController.text.trim().isNotEmpty
          ? _updateUrlController.text.trim()
          : AppUpdateService.defaultStoreUrl,
      isForced: _forceUpdate,
      hasUpdate: true,
      enabled: _updateEnabled,
    );

    AppUpdateService.showUpdateDialog(context, info);
  }

  Future<void> _checkPlayCoreStatus() async {
    showUtopiaSnackBar(
      context,
      message: 'Checking Google Play In-App Update API status...',
      tone: UtopiaSnackBarTone.info,
    );
    final status = await AppUpdateService.checkGooglePlayUpdateStatus();
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: U.card,
          title: Text(
            'Google Play API Status',
            style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.bold),
          ),
          content: Text(
            status,
            style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: TextStyle(color: U.primary)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _runLunaDeveloperTest() async {
    final prompt = _lunaTestController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _lunaTesting = true;
      _lunaTestOutput = null;
      _lunaTestLatencyMs = null;
      _lunaTestMetrics = null;
    });

    try {
      if (_lunaPostToChat) {
        final stopwatch = Stopwatch()..start();
        final uniId =
            U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'support';
        await LunaAiService().respondToChat(
          universityId: uniId,
          userPrompt: prompt,
          userName:
              FirebaseAuth.instance.currentUser?.displayName ?? 'Developer',
          userId: FirebaseAuth.instance.currentUser?.uid,
        );
        stopwatch.stop();
        if (mounted) {
          setState(() {
            _lunaTesting = false;
            _lunaTestLatencyMs = stopwatch.elapsedMilliseconds;
            _lunaTestOutput = 'Published successfully to Chat to Utopia! 🚀';
            _lunaTestMetrics = {
              'target': 'Live Campus Chat',
              'universityId': uniId,
              'latencyMs': stopwatch.elapsedMilliseconds,
              'statusCode': 200,
            };
          });
        }
      } else {
        final result = await LunaAiService().testDetailedResponse(
          userPrompt: prompt,
          userName:
              FirebaseAuth.instance.currentUser?.displayName ?? 'Developer',
        );
        if (mounted) {
          setState(() {
            _lunaTesting = false;
            _lunaTestLatencyMs = result['latencyMs'] as int?;
            _lunaTestOutput = result['output'] as String?;
            _lunaTestMetrics = result;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lunaTesting = false;
          _lunaTestOutput = 'Error: $e';
        });
      }
    }
  }

  Widget _lunaQuickChip(String label, {String? promptText}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      label: Text(label,
          style: GoogleFonts.outfit(
              fontSize: 11.5, color: U.text, fontWeight: FontWeight.w500)),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
      side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : U.border.withValues(alpha: 0.6),
          width: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      onPressed: () {
        _lunaTestController.text =
            promptText ?? 'Luna, roast people about $label';
      },
    );
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
              _buildUpdateSection(),
              _buildLunaAiTestingSection(),
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
                  await NotificationService.sendPersonalTestNotification(
                    message: 'Live push & system notifications are working on this device!',
                  );
                  await NotificationService.dispatchPushNotification(
                    recipientId: user.uid,
                    title: 'UTOPIA Live Test 👋',
                    message: 'Live push notification is working on this device!',
                    type: 'general',
                    allowSelf: true,
                  );
                  if (context.mounted) {
                    showUtopiaSnackBar(context, message: 'Test notification triggered! Check your notification tray.', tone: UtopiaSnackBarTone.success);
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

  Widget _buildUpdateSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('App Update Management'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.04),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Running Version Banner
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      U.primaryContainer.withValues(alpha: isDark ? 0.3 : 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: U.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: U.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentAppVersion.isNotEmpty
                            ? 'Currently Installed: v$_currentAppVersion'
                            : 'Detecting installed version...',
                        style: GoogleFonts.outfit(
                          color: U.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Switch: Enable Update Prompt
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: U.primary,
                title: Text(
                  'Enable Update Prompts',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Checks versions on launch and displays update dialog if available',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                ),
                value: _updateEnabled,
                onChanged: (val) => setState(() => _updateEnabled = val),
              ),

              // Switch: Force Update
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: U.red,
                title: Text(
                  'Force Update (Mandatory)',
                  style: GoogleFonts.outfit(
                    color: _forceUpdate ? U.red : U.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Prevents users from bypassing the update (disables "Later" button)',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                ),
                value: _forceUpdate,
                onChanged: (val) => setState(() => _forceUpdate = val),
              ),
              const SizedBox(height: 12),

              // Latest Version & Minimum Version Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latestVersionController,
                      style: GoogleFonts.plusJakartaSans(
                          color: U.text, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Latest Version',
                        labelStyle: GoogleFonts.outfit(color: U.sub),
                        hintText: 'e.g. 4.2.1',
                        hintStyle: GoogleFonts.outfit(color: U.dim),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: U.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _minVersionController,
                      style: GoogleFonts.plusJakartaSans(
                          color: U.text, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Min Supported Version',
                        labelStyle: GoogleFonts.outfit(color: U.sub),
                        hintText: 'e.g. 4.0.0',
                        hintStyle: GoogleFonts.outfit(color: U.dim),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: U.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Update Title
              TextField(
                controller: _updateTitleController,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Update Title',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText: 'e.g. Update available',
                  hintStyle: GoogleFonts.outfit(color: U.dim),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Update Message / Release Notes
              TextField(
                controller: _updateMsgController,
                maxLines: 3,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Release Notes / Message',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText: 'Describe new features or bug fixes...',
                  hintStyle: GoogleFonts.outfit(color: U.dim),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Update Store URL
              TextField(
                controller: _updateUrlController,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Store / Download URL',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  hintText:
                      'https://play.google.com/store/apps/details?id=com.superwave.utopia',
                  hintStyle: GoogleFonts.outfit(color: U.dim),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons: Preview & Save
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _previewUpdateDialog,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(
                        'Preview Dialog',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: U.text,
                        side: BorderSide(color: U.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _savingUpdate ? null : _saveUpdateConfig,
                      icon: _savingUpdate
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _savingUpdate ? 'Saving...' : 'Save Config',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: U.primary,
                        foregroundColor: U.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _checkPlayCoreStatus,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    'Check Google Play In-App API Status',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLunaAiTestingSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final luna = LunaAiService();
    final keysMasked = luna.loadedKeysMasked;
    final availableModels = luna.availableModels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Luna AI Developer Studio (Super Controls)'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.auto_awesome_rounded,
                            color: U.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Luna AI Console',
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Engine: Groq Cloud • ${luna.totalKeysCount} Keys Connected',
                            style: GoogleFonts.outfit(
                              color: U.dim,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Toggle System Prompt',
                        icon: Icon(
                          _lunaShowSystemPrompt
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: U.sub,
                        ),
                        onPressed: () {
                          setState(() =>
                              _lunaShowSystemPrompt = !_lunaShowSystemPrompt);
                        },
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await luna.reloadKeys();
                          if (mounted) {
                            setState(() {});
                            showUtopiaSnackBar(
                              context,
                              message:
                                  'Reloaded ${luna.totalKeysCount} Groq keys from config/Luna!',
                              tone: UtopiaSnackBarTone.info,
                            );
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: Text(
                          'Reload',
                          style: GoogleFonts.outfit(fontSize: 11),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: U.sub,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // System Prompt Viewer (Accordion)
              if (_lunaShowSystemPrompt) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: U.border.withValues(alpha: 0.4),
                      width: 0.7,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SYSTEM PROMPT & TELUGU RULES',
                            style: GoogleFonts.outfit(
                              color: U.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                  text: LunaAiService.systemPrompt));
                              showUtopiaSnackBar(context,
                                  message: 'Prompt copied to clipboard!',
                                  tone: UtopiaSnackBarTone.success);
                            },
                            child: Icon(Icons.copy_rounded,
                                size: 14, color: U.sub),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        LunaAiService.systemPrompt,
                        style: GoogleFonts.sourceCodePro(
                          color: U.sub,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ── Key Access Selector ──
              Text(
                'TARGET API KEY',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Auto-Cycle All (${luna.totalKeysCount})',
                          style: GoogleFonts.outfit(fontSize: 11)),
                      selected: luna.selectedKeyIndexOverride == null,
                      onSelected: (sel) {
                        setState(() => luna.selectedKeyIndexOverride = null);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                    ...keysMasked.entries.map((entry) {
                      final keyNum = int.tryParse(
                              entry.key.replaceFirst('API-', '')) ??
                          1;
                      final keyIdx = keyNum - 1;
                      final isSelected =
                          luna.selectedKeyIndexOverride == keyIdx;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${entry.key} (${entry.value})',
                              style: GoogleFonts.outfit(fontSize: 11)),
                          selected: isSelected,
                          onSelected: (sel) {
                            setState(() => luna.selectedKeyIndexOverride =
                                sel ? keyIdx : null);
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Model Selector ──
              Text(
                'GROQ MODEL',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: availableModels.map((model) {
                    final isSelected = luna.activeModelName == model;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(model,
                            style: GoogleFonts.outfit(fontSize: 11)),
                        selected: isSelected,
                        onSelected: (sel) {
                          setState(() => luna.selectedModelOverride =
                              sel ? model : null);
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 14),

              // ── Test Prompt Field ──
              Text(
                'CUSTOM TEST PROMPT',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _lunaTestController,
                style: GoogleFonts.outfit(color: U.text, fontSize: 13.5),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'e.g. Luna, roast people who never attend 8am lecture',
                  hintStyle: GoogleFonts.outfit(color: U.dim, fontSize: 12),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.black.withValues(alpha: 0.02),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.border.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.primary),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),

              // ── Full Quick Test Categories (Visible Wrap Layout) ──
              Text(
                'ONE-TAP TEST SCENARIOS (FULL ACCESS)',
                style: GoogleFonts.outfit(
                  color: U.sub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),

              // Group 1: Friendly & Casual Convo (Tests natural human chats)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('💬 Casual:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: U.dim, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _lunaQuickChip('heyy luna',
                              promptText: 'heyy luna what are you doing rn?'),
                          _lunaQuickChip('how was your day',
                              promptText: 'luna how was your day today?'),
                          _lunaQuickChip('canteen food',
                              promptText: 'canteen lo samosa tintunna luna, want some?'),
                          _lunaQuickChip('movie rec',
                              promptText: 'luna recommend me a fun movie to watch tonight'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Group 2: College Life & Misery (Relatable / empathetic)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('🎓 Campus:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: U.dim, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _lunaQuickChip('attendance 45%',
                              promptText: 'attendance is 45% what should I do luna'),
                          _lunaQuickChip('exhausted by exams',
                              promptText: 'so tired today, semester exams are killing me'),
                          _lunaQuickChip('skipped 8am class',
                              promptText: 'slept through the 8am class again today lol'),
                          _lunaQuickChip('proxy caught',
                              promptText: 'faculty caught me giving proxy for my friend'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Group 3: Teasing & Sassy Roasts (When students flex)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('💅 Teasing:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: U.dim, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _lunaQuickChip('college topper flex',
                              promptText: 'nenu college topper bro, 9.8 CGPA easy ga vastadi'),
                          _lunaQuickChip('sleeping 14 hours',
                              promptText: 'woke up at 3pm today, life is good'),
                          _lunaQuickChip('gym mirror selfie',
                              promptText: 'look at my gym gains, rate my mirror selfie luna'),
                          _lunaQuickChip('single life flex',
                              promptText: 'everyone is in relationships, but single life is best'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Group 4: Telugu Banter
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('🇮🇳 Telugu:',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: U.dim, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _lunaQuickChip('enti bro idhi',
                              promptText: 'Enti bro idhi, ma college gurinchi cheppu konchem'),
                          _lunaQuickChip('pedda thopu',
                              promptText: 'pedda thopu laga buildup istunnav enti luna'),
                          _lunaQuickChip('sarle kani',
                              promptText: 'Sarle kani, 8am class ki vellava leda?'),
                          _lunaQuickChip('chalu overaction',
                              promptText: 'chalu le overaction cheyyaku konchem'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Option: Post directly to campus chat
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.black.withValues(alpha: 0.015),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: U.border.withValues(alpha: 0.35),
                    width: 0.7,
                  ),
                ),
                child: SwitchListTile(
                  value: _lunaPostToChat,
                  onChanged: (val) => setState(() => _lunaPostToChat = val),
                  title: Text(
                    'Post reply to Chat to Utopia',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _lunaPostToChat
                        ? 'Live: Message will be posted in student campus chat'
                        : 'Preview only: Safe on-screen test without posting',
                    style: GoogleFonts.outfit(color: U.dim, fontSize: 11),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  dense: true,
                ),
              ),
              const SizedBox(height: 12),

              // Trigger Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _lunaTesting ? null : _runLunaDeveloperTest,
                  icon: _lunaTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(
                    _lunaTesting
                        ? 'Generating via ${luna.activeModelName}...'
                        : 'Run Test with Luna AI',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: U.primary,
                    foregroundColor: U.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              // Output Preview & Metrics Inspector
              if (_lunaTestOutput != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: U.primary.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with Badges
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Luna',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: U.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'AI',
                                  style: GoogleFonts.outfit(
                                    color: U.primary,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_lunaTestMetrics?['keyLabel'] != null)
                            _metricBadge(
                                '🔑 ${_lunaTestMetrics!['keyLabel']}', U.blue),
                          if (_lunaTestMetrics?['model'] != null)
                            _metricBadge(
                                '🤖 ${_lunaTestMetrics!['model']}', U.primary),
                          if (_lunaTestLatencyMs != null)
                            _metricBadge(
                                '⚡ ${_lunaTestLatencyMs}ms', U.green),
                          if (_lunaTestMetrics?['statusCode'] != null)
                            _metricBadge(
                                '📡 ${_lunaTestMetrics!['statusCode']}',
                                _lunaTestMetrics!['statusCode'] == 200
                                    ? U.green
                                    : Colors.orange),
                        ],
                      ),
                      Builder(builder: (context) {
                        final blocks = (_lunaTestMetrics?['blocks'] as List?)
                            ?.cast<String>();
                        if (blocks != null && blocks.length > 1) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'HUMAN-LIKE MULTI-BUBBLE DELIVERY (${blocks.length} MESSAGES):',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (int i = 0; i < blocks.length; i++) ...[
                                if (i > 0) const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : Colors.black.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: U.primary.withValues(alpha: 0.2),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color:
                                              U.primary.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Bubble ${i + 1}',
                                          style: GoogleFonts.outfit(
                                            color: U.primary,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: SelectableText(
                                          blocks[i],
                                          style: GoogleFonts.outfit(
                                            color: U.text,
                                            fontSize: 13.5,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          );
                        }
                        return SelectableText(
                          _lunaTestOutput!,
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _lunaTestOutput!));
                              showUtopiaSnackBar(context,
                                  message: 'Response copied to clipboard!',
                                  tone: UtopiaSnackBarTone.success);
                            },
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: Text('Copy Response',
                                style: GoogleFonts.outfit(fontSize: 11)),
                            style: TextButton.styleFrom(
                              foregroundColor: U.sub,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
