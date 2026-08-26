import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/notification_service.dart';
import '../widgets/utopia_loader.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _isLoading = true;
  bool _chatEnabled = true;
  String _utopiaChatMode = 'replies'; // 'all', 'replies', 'off'
  bool _wavesEnabled = true;
  bool _followsEnabled = true;
  bool _eventsEnabled = true;
  bool _morningEnabled = true;
  bool _focusEnabled = true;

  bool _systemPermissionsGranted = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkSystemPermissions();
  }

  Future<void> _checkSystemPermissions() async {
    final granted =
        await NotificationService.areNotificationPermissionsEnabled();
    if (mounted) {
      setState(() => _systemPermissionsGranted = granted);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Instant load from local cache
    setState(() {
      _chatEnabled = prefs.getBool('pref_notif_chat') ?? true;
      _utopiaChatMode = prefs.getString('pref_notif_utopia_chat_mode') ?? 'replies';
      _wavesEnabled = prefs.getBool('pref_notif_waves') ?? true;
      _followsEnabled = prefs.getBool('pref_notif_follows') ?? true;
      _eventsEnabled = prefs.getBool('pref_notif_events') ?? true;
      _morningEnabled = prefs.getBool('pref_notif_morning') ?? U.morningNotifEnabled;
      _focusEnabled = prefs.getBool('pref_notif_focus') ?? true;
      _isLoading = false;
    });

    // 2. Fetch latest from Firestore if signed in
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && mounted) {
          final data = doc.data() ?? {};
          final notifPrefs = (data['notification_preferences'] as Map<String, dynamic>?) ?? {};

          setState(() {
            _chatEnabled = notifPrefs['chat'] as bool? ??
                data['notif_chat_enabled'] as bool? ??
                _chatEnabled;
            _utopiaChatMode = (notifPrefs['utopia_chat'] as String?) ??
                (data['notif_utopia_chat_mode'] as String?) ??
                _utopiaChatMode;
            _wavesEnabled = notifPrefs['waves'] as bool? ??
                data['notif_waves_enabled'] as bool? ??
                _wavesEnabled;
            _followsEnabled = notifPrefs['follows'] as bool? ??
                data['notif_follows_enabled'] as bool? ??
                _followsEnabled;
            _eventsEnabled = notifPrefs['events'] as bool? ??
                data['notif_events_enabled'] as bool? ??
                _eventsEnabled;
            _morningEnabled = notifPrefs['morning'] as bool? ??
                data['notif_morning_enabled'] as bool? ??
                _morningEnabled;
            _focusEnabled = notifPrefs['focus'] as bool? ??
                data['notif_focus_enabled'] as bool? ??
                _focusEnabled;
          });

          // Sync to cache
          await prefs.setBool('pref_notif_chat', _chatEnabled);
          await prefs.setString('pref_notif_utopia_chat_mode', _utopiaChatMode);
          await prefs.setBool('pref_notif_waves', _wavesEnabled);
          await prefs.setBool('pref_notif_follows', _followsEnabled);
          await prefs.setBool('pref_notif_events', _eventsEnabled);
          await prefs.setBool('pref_notif_morning', _morningEnabled);
          await prefs.setBool('pref_notif_focus', _focusEnabled);
        }
      } catch (_) {}
    }
  }

  Future<void> _updateUtopiaChatMode(String mode) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _utopiaChatMode = mode;
    });

    await prefs.setString('pref_notif_utopia_chat_mode', mode);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'notification_preferences': {
            'chat': _chatEnabled,
            'utopia_chat': _utopiaChatMode,
            'waves': _wavesEnabled,
            'follows': _followsEnabled,
            'events': _eventsEnabled,
            'morning': _morningEnabled,
            'focus': _focusEnabled,
          },
          'notif_utopia_chat_mode': _utopiaChatMode,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating utopia chat notification preference: $e');
      }
    }
  }

  Future<void> _updatePreference(String key, bool value) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      switch (key) {
        case 'chat':
          _chatEnabled = value;
          break;
        case 'waves':
          _wavesEnabled = value;
          break;
        case 'follows':
          _followsEnabled = value;
          break;
        case 'events':
          _eventsEnabled = value;
          break;
        case 'morning':
          _morningEnabled = value;
          morningNotifEnabledNotifier.value = value;
          break;
        case 'focus':
          _focusEnabled = value;
          break;
      }
    });

    await prefs.setBool('pref_notif_$key', value);

    // Save to Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'notification_preferences': {
            'chat': _chatEnabled,
            'utopia_chat': _utopiaChatMode,
            'waves': _wavesEnabled,
            'follows': _followsEnabled,
            'events': _eventsEnabled,
            'morning': _morningEnabled,
            'focus': _focusEnabled,
          },
          'notif_${key}_enabled': value,
          'notif_chat_enabled': _chatEnabled,
          'notif_utopia_chat_mode': _utopiaChatMode,
          'notif_waves_enabled': _wavesEnabled,
          'notif_follows_enabled': _followsEnabled,
          'notif_events_enabled': _eventsEnabled,
          'notif_morning_enabled': _morningEnabled,
          'notif_focus_enabled': _focusEnabled,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating notification preferences: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 19),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notification Settings',
          style: GoogleFonts.newsreader(
            color: U.text,
            fontSize: 22,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: UtopiaLoader(scale: 0.7))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                if (!_systemPermissionsGranted) ...[
                  _buildSystemPermissionWarning(),
                  const SizedBox(height: 16),
                ],
                _buildSectionHeader('Social Notifications'),
                _buildCategoryGroup([
                  _buildToggleTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Direct Messages',
                    subtitle:
                        '1-on-1 chats, shared notes, and friend messages',
                    value: _chatEnabled,
                    onChanged: (val) => _updatePreference('chat', val),
                  ),
                  _buildDivider(),
                  _buildUtopiaChatSelector(),
                  _buildDivider(),
                  _buildToggleTile(
                    icon: Icons.waving_hand_outlined,
                    title: 'Waves & Campus Sparks',
                    subtitle:
                        'Get notified when classmates wave or interact with you',
                    value: _wavesEnabled,
                    onChanged: (val) => _updatePreference('waves', val),
                  ),
                  _buildDivider(),
                  _buildToggleTile(
                    icon: Icons.person_add_outlined,
                    title: 'Follows & Requests',
                    subtitle:
                        'Alerts when someone follows you or accepts your request',
                    value: _followsEnabled,
                    onChanged: (val) => _updatePreference('follows', val),
                  ),
                ]),
                const SizedBox(height: 24),
                _buildSectionHeader('Campus & Events'),
                _buildCategoryGroup([
                  _buildToggleTile(
                    icon: Icons.celebration_outlined,
                    title: 'Events & Certificates',
                    subtitle:
                        'Ending-soon event alerts and certificate releases',
                    value: _eventsEnabled,
                    onChanged: (val) => _updatePreference('events', val),
                  ),
                  _buildDivider(),
                  _buildToggleTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Daily Morning Spark',
                    subtitle:
                        'Morning quotes, daily icebreaker polls, and daily greetings',
                    value: _morningEnabled,
                    onChanged: (val) => _updatePreference('morning', val),
                  ),
                ]),
                const SizedBox(height: 24),
                _buildSectionHeader('Focus & Habits'),
                _buildCategoryGroup([
                  _buildToggleTile(
                    icon: Icons.timer_outlined,
                    title: 'Focus & Routine Reminders',
                    subtitle:
                        'Daily habit trackers, timetable alerts, and study reminders',
                    value: _focusEnabled,
                    onChanged: (val) => _updatePreference('focus', val),
                  ),
                ]),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'Preferences sync across all your devices automatically',
                    style: GoogleFonts.plusJakartaSans(
                      color: U.dim,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSystemPermissionWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications Blocked in Settings',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: U.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Android system notifications are turned off. Enable them to receive live alerts.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: U.sub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              await NotificationService.ensureNotificationPermissions();
              _checkSystemPermissions();
            },
            child: Text(
              'Enable',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.amber.shade700,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: U.dim,
        ),
      ),
    );
  }

  Widget _buildCategoryGroup(List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.04),
          width: 1,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: value ? U.primary.withValues(alpha: 0.1) : U.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? U.primary : U.dim,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: U.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: U.sub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: U.primary,
            inactiveThumbColor: U.dim,
            inactiveTrackColor: U.bg,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 52,
      color: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.04),
    );
  }

  Widget _buildUtopiaChatSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = _utopiaChatMode == 'off' ? U.dim : U.teal;

    final subtitleText = switch (_utopiaChatMode) {
      'all' => 'All Messages • Notify on every new message',
      'replies' => 'Replies to You • Notify only when replied to',
      _ => 'Muted • No notifications from Utopia Chat',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _utopiaChatMode != 'off'
                      ? U.teal.withValues(alpha: 0.12)
                      : U.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _utopiaChatMode == 'all'
                      ? Icons.notifications_active_rounded
                      : (_utopiaChatMode == 'replies'
                          ? Icons.reply_all_rounded
                          : Icons.notifications_off_outlined),
                  color: activeColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Utopia Chat (Global)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: U.text,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: U.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'COMMUNITY',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: U.teal,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: U.sub,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _buildSegmentOption(
                  label: 'All Messages',
                  icon: Icons.notifications_rounded,
                  mode: 'all',
                ),
                _buildSegmentOption(
                  label: 'Replies Only',
                  icon: Icons.reply_rounded,
                  mode: 'replies',
                ),
                _buildSegmentOption(
                  label: 'Muted',
                  icon: Icons.notifications_off_rounded,
                  mode: 'off',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentOption({
    required String label,
    required IconData icon,
    required String mode,
  }) {
    final isSelected = _utopiaChatMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _updateUtopiaChatMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? U.teal.withValues(alpha: 0.22) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isSelected && !isDark
                ? Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.06,
                      ),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? (isDark ? const Color(0xFF2DD4BF) : U.teal)
                    : U.dim,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? const Color(0xFF2DD4BF) : U.text)
                      : U.dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
