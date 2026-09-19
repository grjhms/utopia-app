import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../main.dart';
import '../services/app_update_service.dart';
import '../services/notification_service.dart';
import '../services/writer_firestore_service.dart';
import '../widgets/utopia_snackbar.dart';
import 'broadcast_screen.dart';
import 'review_moderation_queue_screen.dart';
import '../models/university_model.dart';
import '../services/university_service.dart';

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

  // ── Honest Reviews controls ──
  bool _honestReviewsGlobalEnabled = true;
  Set<String> _disabledReviewUniIds = {};
  List<UniversityModel> _allUniversities = [];
  bool _savingReviewConfig = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
      _loadUpdateConfig();
    });
  }

  @override
  void dispose() {
    _latestVersionController.dispose();
    _minVersionController.dispose();
    _updateTitleController.dispose();
    _updateMsgController.dispose();
    _updateUrlController.dispose();
    super.dispose();
  }



  Future<void> _loadUpdateConfig() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final unis = await UniversityService().fetchAllUniversities();

      if (mounted) {
        setState(() {
          _currentAppVersion = packageInfo.version;
          if (packageInfo.buildNumber.isNotEmpty) {
            _currentAppVersion += '+${packageInfo.buildNumber}';
          }
          _allUniversities = unis;
        });
      }

      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        final globalEnabled = data['honest_reviews_enabled'] as bool? ?? true;
        final disabledList = List<String>.from(data['disabled_honest_review_unis'] ?? []);

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
            _honestReviewsGlobalEnabled = globalEnabled;
            _disabledReviewUniIds = Set.from(disabledList.map((e) => e.toLowerCase().trim()));
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

  Future<void> _saveHonestReviewsConfig() async {
    setState(() => _savingReviewConfig = true);
    try {
      final currentDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get();
      final data = currentDoc.exists
          ? (currentDoc.data() ?? {})
          : <String, dynamic>{};

      data['honest_reviews_enabled'] = _honestReviewsGlobalEnabled;
      data['disabled_honest_review_unis'] = _disabledReviewUniIds.toList();

      await WriterFirestoreService.updateConfig('app_config', data);

      if (mounted) {
        setState(() => _savingReviewConfig = false);
        showUtopiaSnackBar(
          context,
          message: 'Honest Reviews visibility settings saved!',
          tone: UtopiaSnackBarTone.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingReviewConfig = false);
        showUtopiaSnackBar(
          context,
          message: 'Failed to save review settings: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    }
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

  Widget _buildHonestReviewsVisibilitySection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
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
          Row(
            children: [
              Icon(Icons.rate_review_rounded, color: U.peach, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Honest Reviews Card Visibility',
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Global switch
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Global Honest Reviews Feature',
              style: GoogleFonts.outfit(color: U.text, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              _honestReviewsGlobalEnabled
                  ? 'Feature is ENABLED app-wide'
                  : 'Feature is DISABLED globally across all colleges',
              style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
            ),
            value: _honestReviewsGlobalEnabled,
            activeTrackColor: U.peach,
            onChanged: (val) {
              setState(() => _honestReviewsGlobalEnabled = val);
            },
          ),
          const Divider(height: 20),
          Text(
            'Per-University Review Visibility (${_allUniversities.length} Colleges):',
            style: GoogleFonts.outfit(color: U.text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_allUniversities.isEmpty)
            Text('Loading universities...', style: GoogleFonts.outfit(color: U.sub, fontSize: 12))
          else
            Column(
              children: _allUniversities.map((uni) {
                final cleanId = uni.id.trim().toLowerCase();
                final bool isVisibleForUni = _honestReviewsGlobalEnabled && !_disabledReviewUniIds.contains(cleanId);

                return SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  dense: true,
                  title: Text(
                    uni.name,
                    style: GoogleFonts.outfit(color: U.text, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isVisibleForUni ? 'Reviews Card Visible' : 'Reviews Card Hidden',
                    style: GoogleFonts.outfit(
                      color: isVisibleForUni ? Colors.green.shade700 : Colors.red.shade700,
                      fontSize: 11,
                    ),
                  ),
                  value: !_disabledReviewUniIds.contains(cleanId),
                  activeTrackColor: U.peach,
                  onChanged: _honestReviewsGlobalEnabled
                      ? (val) {
                          setState(() {
                            if (val) {
                              _disabledReviewUniIds.remove(cleanId);
                            } else {
                              _disabledReviewUniIds.add(cleanId);
                            }
                          });
                        }
                      : null,
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _savingReviewConfig ? null : _saveHonestReviewsConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: U.peach,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _savingReviewConfig
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Save Review Visibility Settings',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
            ),
          ),
        ],
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
              _sectionHeader('Community Moderation'),
              _actionTile(
                icon: Icons.rate_review_outlined,
                title: 'Reviews Moderation Queue',
                subtitle: 'Triage reported and pending college reviews',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReviewModerationQueueScreen()),
                ),
              ),
              _buildHonestReviewsVisibilitySection(),
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
}
