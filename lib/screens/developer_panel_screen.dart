import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';

import '../main.dart';
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


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
      _loadNewsConfig();
    });
  }

  @override
  void dispose() {
    _newsTitleController.dispose();
    _newsDescController.dispose();
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
}
