import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/cache_service.dart';
import '../services/email_service.dart';
import '../services/file_upload_service.dart';
import '../services/people_interaction_service.dart';
import '../services/platform_support.dart';
import '../services/role_service.dart';
import '../widgets/instagram_badge.dart';
import '../widgets/superuser_badge.dart';
import '../widgets/wave_count_badge.dart';
import '../widgets/sciwordle_badge.dart';
import '../widgets/sciwordle_profile_card.dart';
import '../models/project_model.dart';
import '../services/project_service.dart';
import 'create_project_screen.dart';
import 'project_detail_screen.dart';
import 'app_shell.dart';
import 'university_selection_screen.dart';
import 'user_profile_screen.dart';
import 'utopia_section_screen.dart';
import 'whatsapp_profile_crop_screen.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/app_motion.dart';

const List<String> kBTechBranches = [
  'Agri Engg',
  'CSE (AI & ML)',
  'CSE (AI & ML - Microsoft)',
  'CSE (AI & ML - Google)',
  'Civil Engg',
  'CSE',
  'CSE (Data Science)',
  'CSE (Data Science - Google)',
  'CSE (Google Cloud)',
  'CSE (SAP)',
  'EEE',
  'ECE',
  'Mechanical Engg',
  'Mining Engg',
  'Petroleum Tech',
];

/// Simple, clean, Material 3 Expressive Profile Screen
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSuperUser = false;
  bool _updatingTheme = false;

  @override
  void initState() {
    super.initState();
    PeopleInteractionService().syncMyWavesCount();
    RoleService().isSuperUser().then((v) {
      if (mounted) setState(() => _isSuperUser = v);
    });
  }

  Future<void> _signOut() async {
    RoleService().clearCache();
    await CacheService().deleteAppSetting('cached_university_id');
    await CacheService().deleteAppSetting('cached_university_name');
    AppShell.resetSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_open_count');
    await prefs.remove('last_seen_popup_event_id');
    U.cachedUniversityId = '';
    U.cachedUniversityName = '';
    if (PlatformSupport.supportsGoogleSignIn) {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '402670858978-94eqn0qvvrtv59ijne3hn1g5flr4ahve.apps.googleusercontent.com',
      );
      await GoogleSignIn.instance.signOut();
    }
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showSignOutDialog() {
    final isDark = appThemeNotifier.value.isDark;
    const dangerRed = Color(0xFFEF4444);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
            width: 0.8,
          ),
        ),
        title: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: dangerRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.logout_rounded, color: dangerRed, size: 24),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Sign Out',
              style: GoogleFonts.robotoFlex(
                color: U.text,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to sign out of UTOPIA?',
          textAlign: TextAlign.center,
          style: GoogleFonts.robotoFlex(
            color: U.sub,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: U.text,
                    side: BorderSide(color: U.outlineVariant.withValues(alpha: 0.6)),
                    shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.robotoFlex(
                      color: U.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _signOut();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: dangerRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Sign Out',
                    style: GoogleFonts.robotoFlex(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectThemeStyle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _updatingTheme) return;

    final initialThemeKey = U.currentThemeKey;
    final selectedKey = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ThemeStyleSheet(currentKey: initialThemeKey),
    );

    if (selectedKey != null && selectedKey != initialThemeKey) {
      setState(() => _updatingTheme = true);
      U.applyTheme(selectedKey);
      await CacheService().saveAppSetting('theme_accent', selectedKey);
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'themeAccent': selectedKey,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error saving theme: $e');
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()),
          (route) => false,
        );
      }
    } else if (selectedKey == null && U.currentThemeKey != initialThemeKey) {
      U.applyTheme(initialThemeKey);
    }
  }

  Future<void> _openEditProfile({
    required String name,
    required String bio,
    required String instagram,
    required String github,
    required String discord,
    required String branch,
    required String rollNumber,
    required String? photoUrl,
  }) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditProfileSheet(
        initialName: name,
        initialBio: bio,
        initialInstagram: instagram,
        initialGithub: github,
        initialDiscord: discord,
        initialBranch: branch,
        initialRollNumber: rollNumber,
        initialPhotoUrl: photoUrl,
      ),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  void _openRaiseIssue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _RaiseIssueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = appThemeNotifier.value;
    final isDark = theme.isDark;
    final user = FirebaseAuth.instance.currentUser;
    final userDocStream = user == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userDocStream,
          builder: (context, snapshot) {
            final userData = snapshot.data?.data() ?? {};
            final displayName = UtopiaApp.sanitizeDisplayName(
              (userData['displayName'] as String?) ?? user?.displayName,
            );
            final bio = (userData['bio'] ?? '').toString().trim();
            final branch = (userData['branch'] ?? '').toString().trim();
            final instagramId = (userData['instagramId'] ?? '').toString().trim();
            final githubId = (userData['githubId'] ?? userData['githubUsername'] ?? '').toString().trim();
            final discordId = (userData['discordId'] ?? userData['discordUsername'] ?? '').toString().trim();
            final rollNumber = (userData['rollNumber'] ?? '').toString().trim();
            final showRollNumber = (userData['showRollNumberOnProfile'] as bool?) ?? true;
            final wavesCount = (userData['wavesReceivedCount'] as num?)?.toInt() ?? 0;
            final rawPhotoUrl = (userData['photoUrl'] as String?)?.trim();
            final displayPhotoUrl = (rawPhotoUrl != null && rawPhotoUrl.isNotEmpty)
                ? rawPhotoUrl
                : user?.photoURL;
            final email = user?.email ?? '';
            final sciwordleTitle = (userData['sciwordleTitle'] ?? '').toString().trim();
            final showSciwordleBadge = userData['showSciwordleBadge'] != false;
            final sciwordleScore = (userData['sciwordleScore'] as num?)?.toInt() ?? 0;
            final sciwordleStreak = (userData['sciwordleStreak'] as num?)?.toInt() ?? 0;
            final sciwordleBestStreak = (userData['sciwordleBestStreak'] as num?)?.toInt() ?? 0;

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
              children: [
                // Top App Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (Navigator.canPop(context))
                      IconButton.filledTonal(
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        onPressed: () => Navigator.pop(context),
                      )
                    else
                      const SizedBox(width: 40),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.share_outlined, size: 20),
                      tooltip: 'Share UTOPIA',
                      onPressed: () {
                        SharePlus.instance.share(
                          ShareParams(
                            text: 'Join me on UTOPIA! 🚀 The academic productivity platform.\n\nhttps://inferalis.space/download-utopia',
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Header Title
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACCOUNT',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: theme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Profile',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: theme.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage your academic identity & preferences',
                      style: GoogleFonts.robotoFlex(
                        color: U.sub,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0),
                const SizedBox(height: 20),

                // ── Material 3 Expressive Profile Hero Card ──
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: U.surfaceContainer,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
                          width: 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                      // Avatar
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (showSciwordleBadge && sciwordleTitle.isNotEmpty)
                                    ? SciwordleBadge.getTitleThemeColor(sciwordleTitle)
                                    : theme.primary.withValues(alpha: 0.45),
                                width: (showSciwordleBadge && sciwordleTitle.isNotEmpty) ? 2.8 : 2.0,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 44,
                              backgroundColor: theme.primary.withValues(alpha: 0.12),
                              backgroundImage: displayPhotoUrl != null && displayPhotoUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(displayPhotoUrl)
                                  : null,
                              child: (displayPhotoUrl == null || displayPhotoUrl.isEmpty)
                                  ? Text(
                                      (displayName.isNotEmpty ? displayName[0] : 'U').toUpperCase(),
                                      style: GoogleFonts.robotoFlex(
                                        color: theme.primary,
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          if (showSciwordleBadge && sciwordleTitle.isNotEmpty)
                            Positioned(
                              top: -14,
                              child: SciwordleBadge(
                                title: sciwordleTitle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Name + Verified Superuser
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: GoogleFonts.robotoFlex(
                                color: U.text,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isSuperUser) ...[
                            const SizedBox(width: 6),
                            const SuperUserBadge(size: 18),
                          ],
                        ],
                      ),

                      // Email Pill
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: email));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: U.surfaceContainerHigh,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(milliseconds: 1500),
                                content: Text(
                                  'Email copied to clipboard',
                                  style: GoogleFonts.robotoFlex(color: U.text, fontSize: 12.5),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: U.surfaceContainerLowest.withValues(alpha: 0.7),
                              borderRadius: M3Shapes.fullRadius,
                              border: Border.all(
                                color: U.outlineVariant.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mail_outline_rounded, size: 12, color: U.sub),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    email,
                                    style: GoogleFonts.robotoFlex(
                                      color: U.sub,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Bio
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: U.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: U.outlineVariant.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            bio,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.robotoFlex(
                              color: U.text.withValues(alpha: 0.9),
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],

                      // Badges Wrap (Branch, Instagram, GitHub, Discord, Waves, Roll)
                      if (branch.isNotEmpty ||
                          instagramId.isNotEmpty ||
                          githubId.isNotEmpty ||
                          discordId.isNotEmpty ||
                          wavesCount > 0 ||
                          rollNumber.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (branch.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: theme.primary.withValues(alpha: 0.12),
                                  borderRadius: M3Shapes.fullRadius,
                                  border: Border.all(
                                    color: theme.primary.withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.school_rounded, size: 13, color: theme.primary),
                                    const SizedBox(width: 5),
                                    Text(
                                      branch,
                                      style: GoogleFonts.robotoFlex(
                                        color: theme.primary,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (rollNumber.isNotEmpty && showRollNumber)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: U.surfaceContainerHighest,
                                  borderRadius: M3Shapes.fullRadius,
                                  border: Border.all(
                                    color: U.outlineVariant.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.badge_outlined, size: 13, color: U.sub),
                                    const SizedBox(width: 5),
                                    Text(
                                      rollNumber,
                                      style: GoogleFonts.robotoFlex(
                                        color: U.text,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (instagramId.isNotEmpty)
                              InstagramBadge(handle: instagramId),
                            if (githubId.isNotEmpty)
                              GithubBadge(handle: githubId),
                            if (discordId.isNotEmpty)
                              DiscordBadge(handle: discordId),
                            WaveCountBadge(count: wavesCount),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Edit Profile Button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openEditProfile(
                            name: displayName,
                            bio: bio,
                            instagram: instagramId,
                            github: githubId,
                            discord: discordId,
                            branch: branch,
                            rollNumber: rollNumber,
                            photoUrl: displayPhotoUrl,
                          ),
                          icon: Icon(Icons.edit_rounded, size: 16, color: theme.primary),
                          label: Text(
                            'Edit Profile',
                            style: GoogleFonts.robotoFlex(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: theme.primary,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.primary.withValues(alpha: 0.12),
                            foregroundColor: theme.primary,
                            shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                    top: 14,
                    right: 14,
                    child: Material(
                      color: U.surfaceContainerLowest.withValues(alpha: 0.8),
                      shape: const CircleBorder(),
                      child: Tooltip(
                        message: 'View live profile',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            if (user != null) {
                              Navigator.of(context).push(
                                buildForwardRoute(
                                  UserProfileScreen(
                                    uid: user.uid,
                                    displayName: displayName,
                                    email: email,
                                    photoUrl: displayPhotoUrl,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.arrow_outward_rounded,
                              size: 18,
                              color: theme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 80.ms, duration: 350.ms),
                const SizedBox(height: 16),

                // ── Projects Showcase Section ──
                _UserProjectsProfileSection(userId: user?.uid ?? ''),
                const SizedBox(height: 16),

                // ── SciWordle League Performance Card (Collapsed by default) ──
                if (user != null) ...[
                  SciwordleProfileCard(
                    uid: user.uid,
                    initialScore: sciwordleScore,
                    initialStreak: sciwordleStreak,
                    initialBestStreak: sciwordleBestStreak,
                    initialTitle: sciwordleTitle,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Grouped Settings Menu (Simple, Single Section) ──
                Container(
                  decoration: BoxDecoration(
                    color: U.surfaceContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.palette_rounded,
                        color: theme.peach,
                        title: 'App Themes & Colors',
                        subtitle: _updatingTheme
                            ? 'Updating theme...'
                            : '${U.themeForKey(U.currentThemeKey).label} (${isDark ? 'Dark' : 'Light'})',
                        onTap: _selectThemeStyle,
                      ),
                      Divider(height: 1, thickness: 0.5, color: U.outlineVariant.withValues(alpha: 0.35)),
                      _SettingsTile(
                        icon: Icons.school_rounded,
                        color: theme.blue,
                        title: 'University Campus',
                        subtitle: U.cachedUniversityName.isNotEmpty
                            ? U.cachedUniversityName
                            : 'Choose your campus',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UniversitySelectionScreen(),
                          ),
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: U.outlineVariant.withValues(alpha: 0.35)),
                      _SettingsTile(
                        icon: Icons.rocket_launch_rounded,
                        color: theme.lavender,
                        title: 'About UTOPIA',
                        subtitle: 'Platform info and releases',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UtopiaSectionScreen(
                              initialIsSuperUser: _isSuperUser,
                            ),
                          ),
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: U.outlineVariant.withValues(alpha: 0.35)),
                      _SettingsTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        color: theme.teal,
                        title: 'Feedback & Support',
                        subtitle: 'Report a bug or request features',
                        onTap: _openRaiseIssue,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 140.ms, duration: 350.ms),
                const SizedBox(height: 24),

                // Sign Out
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _showSignOutDialog,
                    icon: Icon(Icons.logout_rounded, size: 16, color: U.red),
                    label: Text(
                      'Sign Out',
                      style: GoogleFonts.robotoFlex(
                        color: U.red,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: U.red.withValues(alpha: 0.35), width: 0.8),
                      shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                      backgroundColor: U.red.withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Designed by John Moses',
                    style: GoogleFonts.robotoFlex(
                      color: U.dim,
                      fontSize: 11,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return M3Pressable(
      onTap: onTap,
      scaleFactor: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.14),
              ),
              child: Center(
                child: Icon(icon, color: color, size: 19),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.robotoFlex(
                      color: U.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.robotoFlex(
                      color: U.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: U.dim, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Simple, Clean, Single-Source Edit Profile Sheet ──
class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialName,
    required this.initialBio,
    required this.initialInstagram,
    required this.initialGithub,
    required this.initialDiscord,
    required this.initialBranch,
    required this.initialRollNumber,
    required this.initialPhotoUrl,
  });

  final String initialName;
  final String initialBio;
  final String initialInstagram;
  final String initialGithub;
  final String initialDiscord;
  final String initialBranch;
  final String initialRollNumber;
  final String? initialPhotoUrl;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _instagramController;
  late final TextEditingController _githubController;
  late final TextEditingController _discordController;
  late final TextEditingController _rollController;
  String? _selectedBranch;
  String? _photoUrl;
  bool _uploadingPhoto = false;
  bool _saving = false;
  bool _showThemeOnProfile = true;
  bool _showRollNumberOnProfile = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _bioController = TextEditingController(text: widget.initialBio);
    _instagramController = TextEditingController(text: widget.initialInstagram);
    _githubController = TextEditingController(text: widget.initialGithub);
    _discordController = TextEditingController(text: widget.initialDiscord);
    _rollController = TextEditingController(text: widget.initialRollNumber);
    _photoUrl = widget.initialPhotoUrl;
    _selectedBranch = widget.initialBranch.isNotEmpty && kBTechBranches.contains(widget.initialBranch)
        ? widget.initialBranch
        : null;
    _loadProfileSettings();
  }

  Future<void> _loadProfileSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final val = doc.data()?['showThemeOnProfile'] as bool?;
      final rollVal = doc.data()?['showRollNumberOnProfile'] as bool?;
      if (mounted) {
        setState(() {
          _showThemeOnProfile = val ?? true;
          _showRollNumberOnProfile = rollVal ?? true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _instagramController.dispose();
    _githubController.dispose();
    _discordController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (picked == null) return;

      if (!mounted) return;
      final croppedFile = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => WhatsAppProfileCropScreen(
            imageFile: File(picked.path),
          ),
        ),
      );
      if (croppedFile == null) return; // User cancelled cropping

      setState(() => _uploadingPhoto = true);
      final uniId = U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'profiles';
      final downloadUrl = await FileUploadService().uploadProfilePhoto(
        file: croppedFile,
        universityId: uniId,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePhotoURL(downloadUrl);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'photoUrl': downloadUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await user.reload();
      }

      if (mounted) {
        setState(() => _photoUrl = downloadUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(
              e is FileUploadException ? e.message : 'Failed to update photo',
              style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      setState(() => _uploadingPhoto = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePhotoURL(null);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'photoUrl': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await user.reload();
      }
      if (mounted) {
        setState(() => _photoUrl = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text('Failed to remove photo', style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    final nextName = _nameController.text.trim();
    final nextBio = _bioController.text.trim();
    final nextInstagram = _instagramController.text.trim().replaceAll('@', '');
    final nextGithub = GithubBadge.sanitizeHandle(_githubController.text);
    final nextDiscord = DiscordBadge.sanitizeHandle(_discordController.text);
    final nextRollNumber = _rollController.text.trim().toUpperCase();

    if (nextName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: U.red,
          content: Text('Name cannot be empty', style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(nextName);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'displayName': nextName,
            'bio': nextBio,
            'instagramId': nextInstagram,
            'githubId': nextGithub,
            'discordId': nextDiscord,
            'branch': _selectedBranch ?? '',
            'showThemeOnProfile': _showThemeOnProfile,
            'showRollNumberOnProfile': _showRollNumberOnProfile,
            'rollNumber': nextRollNumber,
            'email': user.email ?? '',
            'lastSeen': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            if (_photoUrl != null) 'photoUrl': _photoUrl,
          },
          SetOptions(merge: true),
        );
        await user.reload();
      }
      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text('Could not update profile', style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = appThemeNotifier.value;
    final isDark = theme.isDark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.90,
        minChildSize: 0.50,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: U.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
                width: 0.8,
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Drag handle
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: U.outlineVariant,
                        borderRadius: M3Shapes.fullRadius,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Top Header Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _saving ? null : () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.robotoFlex(
                              color: U.sub,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          'Edit Profile',
                          style: GoogleFonts.robotoFlex(
                            color: U.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Save',
                                  style: GoogleFonts.robotoFlex(fontSize: 13.5, fontWeight: FontWeight.w700),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, thickness: 0.5, color: U.outlineVariant.withValues(alpha: 0.35)),

                  // Form List
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
                      children: [
                        // Avatar Editor
                        Center(
                          child: Column(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 42,
                                    backgroundColor: theme.primary.withValues(alpha: 0.12),
                                    backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                                        ? CachedNetworkImageProvider(_photoUrl!)
                                        : null,
                                    child: (_photoUrl == null || _photoUrl!.isEmpty)
                                        ? Text(
                                            (_nameController.text.isNotEmpty ? _nameController.text : 'U')[0].toUpperCase(),
                                            style: GoogleFonts.robotoFlex(
                                              color: theme.primary,
                                              fontSize: 32,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : null,
                                  ),
                                  if (_uploadingPhoto)
                                    Container(
                                      width: 84,
                                      height: 84,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Photo Action Chips
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ActionChip(
                                    avatar: Icon(Icons.photo_camera_rounded, size: 15, color: theme.primary),
                                    label: Text('Camera', style: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.w600)),
                                    onPressed: _uploadingPhoto ? null : () => _pickPhoto(ImageSource.camera),
                                  ),
                                  const SizedBox(width: 8),
                                  ActionChip(
                                    avatar: Icon(Icons.photo_library_rounded, size: 15, color: theme.primary),
                                    label: Text('Gallery', style: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.w600)),
                                    onPressed: _uploadingPhoto ? null : () => _pickPhoto(ImageSource.gallery),
                                  ),
                                  if (_photoUrl != null && _photoUrl!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    ActionChip(
                                      avatar: Icon(Icons.delete_outline_rounded, size: 15, color: U.red),
                                      label: Text('Remove', style: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.w600, color: U.red)),
                                      onPressed: _uploadingPhoto ? null : _removePhoto,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Name
                        _fieldLabel('FULL NAME'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          maxLength: 40,
                          textInputAction: TextInputAction.next,
                          scrollPadding: const EdgeInsets.only(bottom: 80, top: 20),
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5),
                          cursorColor: theme.primary,
                          decoration: _inputDec(
                            hint: 'Your name',
                            icon: Icon(Icons.person_outline_rounded, size: 20, color: theme.primary),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Bio
                        _fieldLabel('BIO'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _bioController,
                          maxLines: 3,
                          maxLength: 150,
                          scrollPadding: const EdgeInsets.only(bottom: 80, top: 20),
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14),
                          cursorColor: theme.primary,
                          decoration: _inputDec(
                            hint: 'About you...',
                            icon: Padding(
                              padding: const EdgeInsets.only(bottom: 36),
                              child: Icon(Icons.format_quote_rounded, size: 20, color: theme.primary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Instagram
                        _fieldLabel('INSTAGRAM USERNAME'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _instagramController,
                          maxLength: 30,
                          textInputAction: TextInputAction.next,
                          scrollPadding: const EdgeInsets.only(bottom: 80, top: 20),
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5),
                          cursorColor: theme.primary,
                          decoration: _inputDec(
                            hint: 'username',
                            prefixText: '@ ',
                            icon: const Padding(
                              padding: EdgeInsets.all(12),
                              child: RealInstagramIcon(size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // GitHub
                        _fieldLabel('GITHUB USERNAME'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _githubController,
                          maxLength: 39,
                          textInputAction: TextInputAction.next,
                          scrollPadding: const EdgeInsets.only(bottom: 80, top: 20),
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5),
                          cursorColor: theme.primary,
                          decoration: _inputDec(
                            hint: 'username',
                            prefixText: '@ ',
                            icon: const Padding(
                              padding: EdgeInsets.all(12),
                              child: RealGithubIcon(size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Discord
                        _fieldLabel('DISCORD USERNAME OR TAG'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _discordController,
                          maxLength: 37,
                          textInputAction: TextInputAction.next,
                          scrollPadding: const EdgeInsets.only(bottom: 80, top: 20),
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5),
                          cursorColor: theme.primary,
                          decoration: _inputDec(
                            hint: 'username or username#0000',
                            prefixText: '@ ',
                            icon: const Padding(
                              padding: EdgeInsets.all(12),
                              child: RealDiscordIcon(size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Branch Dropdown
                        _fieldLabel('BRANCH / SPECIALIZATION'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBranch,
                          isExpanded: true,
                          dropdownColor: U.surfaceContainerHigh,
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14),
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: U.sub),
                          decoration: _inputDec(
                            hint: 'Select branch...',
                            icon: Icon(Icons.school_outlined, size: 20, color: theme.primary),
                          ),
                          items: kBTechBranches.map((branch) {
                            return DropdownMenuItem<String>(
                              value: branch,
                              child: Text(
                                branch,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13.5),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedBranch = val),
                        ),
                        const SizedBox(height: 16),

                        // Roll Number
                        _fieldLabel('ROLL NUMBER (OPTIONAL)'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _rollController,
                          maxLength: 20,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          scrollPadding: const EdgeInsets.only(bottom: 80, top: 20),
                          style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5, letterSpacing: 0.5),
                          cursorColor: theme.primary,
                          decoration: _inputDec(
                            hint: 'e.g. 21A91A0501',
                            icon: Icon(Icons.badge_outlined, size: 20, color: theme.primary),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Show Theme on Profile toggle
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? U.surfaceContainerLowest.withValues(alpha: 0.6)
                                : U.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: U.outlineVariant.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.palette_outlined, size: 20, color: theme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Show Theme on Profile',
                                      style: GoogleFonts.robotoFlex(
                                        color: U.text,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Display your color palette publicly',
                                      style: GoogleFonts.robotoFlex(
                                        color: U.sub,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _showThemeOnProfile,
                                activeThumbColor: theme.primary,
                                onChanged: (val) => setState(() => _showThemeOnProfile = val),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Show Roll Number on Profile toggle
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? U.surfaceContainerLowest.withValues(alpha: 0.6)
                                : U.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: U.outlineVariant.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.badge_outlined, size: 20, color: theme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Show Roll Number on Profile',
                                      style: GoogleFonts.robotoFlex(
                                        color: U.text,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Make your student roll ID visible to other students',
                                      style: GoogleFonts.robotoFlex(
                                        color: U.sub,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _showRollNumberOnProfile,
                                activeThumbColor: theme.primary,
                                onChanged: (val) => setState(() => _showRollNumberOnProfile = val),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.robotoFlex(
        color: U.sub,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }

  InputDecoration _inputDec({
    required String hint,
    required Widget icon,
    String? prefixText,
  }) {
    final theme = appThemeNotifier.value;
    final isDark = theme.isDark;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.robotoFlex(color: U.dim, fontSize: 13.5),
      prefixIcon: icon,
      prefixText: prefixText,
      prefixStyle: GoogleFonts.robotoFlex(color: theme.primary, fontWeight: FontWeight.w700, fontSize: 14.5),
      filled: true,
      fillColor: isDark
          ? U.surfaceContainerLowest.withValues(alpha: 0.6)
          : U.surfaceContainerHighest.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.4), width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.4), width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.primary, width: 1.5),
      ),
    );
  }
}

// ── Simple & Clean Theme Selector Sheet ──
class _ThemeStyleSheet extends StatefulWidget {
  const _ThemeStyleSheet({required this.currentKey});

  final String currentKey;

  @override
  State<_ThemeStyleSheet> createState() => _ThemeStyleSheetState();
}

class _ThemeStyleSheetState extends State<_ThemeStyleSheet> {
  @override
  Widget build(BuildContext context) {
    final filteredThemes = appThemes;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.40,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: U.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: U.outlineVariant.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: U.outlineVariant,
                      borderRadius: M3Shapes.fullRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dark Monochrome UI',
                            style: GoogleFonts.robotoFlex(
                              color: U.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Clean, content-first black & gray palette',
                            style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: U.sub, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Content List
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      // Dark Mode Enforcement Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerLow,
                          borderRadius: M3Shapes.mediumRadius,
                          border: Border.all(color: U.border.withValues(alpha: 0.5), width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.dark_mode_rounded, color: U.text, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dark Mode Only',
                                    style: GoogleFonts.robotoFlex(
                                      color: U.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Optimized for high contrast legibility',
                                    style: GoogleFonts.robotoFlex(
                                      color: U.sub,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Section Title
                      Text(
                        'MONOCHROME VARIANTS',
                        style: GoogleFonts.robotoFlex(
                          color: U.sub,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Palette List
                      ...filteredThemes.map((t) {
                        final isSelected = t.key == appThemeNotifier.value.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ThemePaletteTile(
                            theme: t,
                            isSelected: isSelected,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              appThemeNotifier.value = t;
                              Navigator.pop(context, t.key);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemePaletteTile extends StatelessWidget {
  const _ThemePaletteTile({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  final AppTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeTheme = appThemeNotifier.value;
    final isDark = activeTheme.isDark;

    return M3Pressable(
      onTap: onTap,
      scaleFactor: 0.98,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeTheme.primary.withValues(alpha: 0.10)
              : (isDark ? U.surfaceContainerLowest.withValues(alpha: 0.5) : U.surfaceContainer),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeTheme.primary : U.outlineVariant.withValues(alpha: 0.35),
            width: isSelected ? 1.6 : 0.8,
          ),
        ),
        child: Row(
          children: [
            // Theme Mini-Card Swatch
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: theme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.border,
                  width: 1.2,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Theme Name & Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.label,
                    style: GoogleFonts.robotoFlex(
                      color: U.text,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    theme.description,
                    style: GoogleFonts.robotoFlex(
                      color: U.sub,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Selection indicator
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: activeTheme.primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: U.dim.withValues(alpha: 0.35), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Raise Issue / Contact Support Sheet ──
class _RaiseIssueSheet extends StatefulWidget {
  const _RaiseIssueSheet();

  @override
  State<_RaiseIssueSheet> createState() => _RaiseIssueSheetState();
}

class _RaiseIssueSheetState extends State<_RaiseIssueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  File? _selectedFile;
  String? _selectedFilename;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FileUploadService().pickFile();
      if (result != null) {
        final size = await result.$1.length();
        if (size > 5 * 1024 * 1024) {
          throw Exception('Image size must be less than 5 MB.');
        }
        setState(() {
          _selectedFile = result.$1;
          _selectedFilename = result.$2;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(e.toString(), style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13)),
          ),
        );
      }
    }
  }

  void _clearImage() {
    setState(() {
      _selectedFile = null;
      _selectedFilename = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.displayName ?? 'Student';
      final userEmail = user?.email ?? 'anonymous';

      String imageUrl = '';
      if (_selectedFile != null) {
        final univId = U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'support';
        imageUrl = await FileUploadService().uploadFile(
          file: _selectedFile!,
          originalFilename: _selectedFilename ?? 'image.png',
          universityId: univId,
        );
      }

      final success = await EmailService().sendIssueReport(
        userName: userName,
        userEmail: userEmail,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        imageUrls: imageUrl,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: U.green,
              content: Text(
                'Report submitted successfully!',
                style: GoogleFonts.robotoFlex(color: U.bg, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception('Failed to send report');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(e.toString(), style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = appThemeNotifier.value;
    final isDark = theme.isDark;

    return Container(
      decoration: BoxDecoration(
        color: U.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
          width: 0.8,
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: U.outlineVariant,
                      borderRadius: M3Shapes.fullRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 14.5)),
                    ),
                    Text(
                      'Feedback & Support',
                      style: GoogleFonts.robotoFlex(color: U.text, fontSize: 16.5, fontWeight: FontWeight.w700),
                    ),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: _submitting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : Text('Submit', style: GoogleFonts.robotoFlex(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  enabled: !_submitting,
                  style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14.5),
                  decoration: InputDecoration(
                    labelText: 'TITLE',
                    hintText: 'e.g. Attendance page sync issue',
                    filled: true,
                    fillColor: isDark
                        ? U.surfaceContainerLowest.withValues(alpha: 0.6)
                        : U.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descController,
                  enabled: !_submitting,
                  maxLines: 4,
                  style: GoogleFonts.robotoFlex(color: U.text, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'DESCRIPTION',
                    hintText: 'Describe the issue in detail...',
                    filled: true,
                    fillColor: isDark
                        ? U.surfaceContainerLowest.withValues(alpha: 0.6)
                        : U.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Enter a description' : null,
                ),
                const SizedBox(height: 14),
                if (_selectedFile == null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickImage,
                      icon: Icon(Icons.add_a_photo_outlined, size: 17, color: theme.primary),
                      label: Text('Attach Screenshot (Optional)', style: GoogleFonts.robotoFlex(color: theme.primary, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? U.surfaceContainerLowest : U.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: U.outlineVariant.withValues(alpha: 0.45)),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Image.file(_selectedFile!, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedFilename ?? 'screenshot.png',
                            style: GoogleFonts.robotoFlex(color: U.text, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: _submitting ? null : _clearImage,
                          icon: Icon(Icons.close_rounded, color: U.red, size: 18),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile Section displaying projects authored or contributed to by the user.
class _UserProjectsProfileSection extends StatelessWidget {
  final String userId;

  const _UserProjectsProfileSection({required this.userId});

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final theme = appThemeNotifier.value;
    final isDark = theme.isDark;

    return StreamBuilder<List<ProjectModel>>(
      stream: ProjectService().getUserProjectsStream(userId),
      builder: (context, snapshot) {
        final projects = snapshot.data ?? [];

        return Container(
          decoration: BoxDecoration(
            color: U.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: U.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.rocket_launch_rounded, color: U.primary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'PROJECTS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.robotoFlex(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: U.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: U.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: U.primary.withValues(alpha: 0.28),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'BETA',
                            style: GoogleFonts.robotoFlex(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: U.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (projects.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: U.primary.withValues(alpha: 0.14),
                              borderRadius: M3Shapes.fullRadius,
                            ),
                            child: Text(
                              '${projects.length}',
                              style: GoogleFonts.robotoFlex(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: U.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Post / Showcase Button
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: U.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (projects.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: U.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: U.outlineVariant.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 28, color: U.sub),
                      const SizedBox(height: 6),
                      Text(
                        'No projects showcased yet',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: U.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Publish your academic projects, hackathons, or apps to get recognized.',
                        style: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: projects.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = projects[index];
                    final isOwner = p.ownerId == userId;
                    final role = isOwner
                        ? 'Owner & Lead'
                        : (p.contributors.firstWhere(
                            (c) => c.userId == userId,
                            orElse: () => ProjectContributor(userId: userId, name: '', role: 'Contributor'),
                          ).role ?? 'Contributor');

                    return InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProjectDetailScreen(projectId: p.id, initialProject: p),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: U.outlineVariant.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 56,
                                height: 56,
                                color: U.surfaceContainerHighest,
                                child: p.coverImage.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: p.coverImage,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Center(
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: U.primary),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Icon(Icons.code_rounded, color: U.sub, size: 24),
                                      )
                                    : Icon(Icons.palette_outlined, color: U.sub, size: 24),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: U.text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isOwner
                                              ? U.primary.withValues(alpha: 0.12)
                                              : U.peach.withValues(alpha: 0.12),
                                          borderRadius: M3Shapes.fullRadius,
                                        ),
                                        child: Text(
                                          role,
                                          style: GoogleFonts.robotoFlex(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: isOwner ? U.primary : U.peach,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.schedule_rounded, size: 11, color: U.sub),
                                          const SizedBox(width: 3),
                                          Text(
                                            p.relativeTime,
                                            style: GoogleFonts.robotoFlex(fontSize: 10.5, color: U.sub, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.favorite_rounded, size: 12, color: U.red),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${p.likesCount}',
                                            style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: U.dim),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

