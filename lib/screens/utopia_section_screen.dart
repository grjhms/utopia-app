import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/role_service.dart';
import '../services/app_update_service.dart';
import 'developer_panel_screen.dart';

class UtopiaSectionScreen extends StatefulWidget {
  final bool initialIsSuperUser;

  const UtopiaSectionScreen({
    super.key,
    required this.initialIsSuperUser,
  });

  @override
  State<UtopiaSectionScreen> createState() => _UtopiaSectionScreenState();
}

class _UtopiaSectionScreenState extends State<UtopiaSectionScreen> {
  bool _isSuperUser = false;
  String _appVersion = '1.0.0';
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _isSuperUser = widget.initialIsSuperUser;
    RoleService().isSuperUser().then((v) {
      if (mounted) {
        setState(() => _isSuperUser = v);
      }
    });
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (_) {}
  }

  Future<void> _launchBugReport() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'johnmosesg150@gmail.com',
      query: 'subject=${Uri.encodeComponent("UTOPIA Bug Report / Suggestion")}',
    );
    try {
      await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(emailLaunchUri);
      } catch (_) {}
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      await AppUpdateService.checkForUpdate(context, isManual: true);
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  Widget _groupedTile({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                  ),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right, color: U.dim, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        title: Text(
          'UTOPIA',
          style: GoogleFonts.outfit(
            color: U.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        foregroundColor: U.text,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // Premium Logo Section
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Image.asset(
                        'assets/icon_cropped.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'UTOPIA',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'App Version $_appVersion',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // Settings Group
            Container(
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: U.border),
              ),
              child: Column(
                children: [
                  // Check for Updates
                  _groupedTile(
                    icon: Icons.system_update_rounded,
                    label: 'Check for Updates',
                    sub: _checkingUpdate
                        ? 'Checking for updates...'
                        : 'Current: v$_appVersion',
                    color: U.primary,
                    trailing: _checkingUpdate
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: U.primary,
                            ),
                          )
                        : null,
                    onTap: _checkUpdate,
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: U.border.withValues(alpha: 0.5),
                  ),
                  // Report Bugs & Suggestions
                  _groupedTile(
                    icon: Icons.bug_report_outlined,
                    label: 'Report Bugs & Suggestions',
                    sub: 'Help us improve UTOPIA',
                    color: U.teal,
                    onTap: _launchBugReport,
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: U.border.withValues(alpha: 0.5),
                  ),
                  // Legal & Privacy Policies
                  _groupedTile(
                    icon: Icons.gavel_outlined,
                    label: 'Legal & Policies',
                    sub: 'Privacy policy & terms of service',
                    color: U.primary,
                    onTap: () => launchUrl(
                      Uri.parse('https://inferalis.space/utopia/policy/'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),

                  if (_isSuperUser) ...[
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: U.border.withValues(alpha: 0.5),
                    ),
                    // Super Controls
                    _groupedTile(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Super Controls',
                      sub: 'Analytics, broadcasts, and app-wide settings',
                      color: U.primary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeveloperPanelScreen(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
