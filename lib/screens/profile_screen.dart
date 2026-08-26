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
import '../widgets/wave_count_badge.dart';
import 'app_shell.dart';
import 'university_selection_screen.dart';
import 'utopia_section_screen.dart';

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


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSuperUser = false;
  bool _updatingTheme = false;

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

  void _showSignOutConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: U.border, width: 0.5)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: U.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout_rounded, color: U.red, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign Out',
              style: GoogleFonts.plusJakartaSans(
                color: U.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to sign out of UTOPIA?',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            color: U.sub,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: U.text,
                    side: BorderSide(color: U.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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
                    backgroundColor: U.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Sign Out',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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
    if (user == null || _updatingTheme) {
      return;
    }

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
        // Immediate clean app restart upon coming back from theme selection page!
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()),
          (route) => false,
        );
      }
    } else if (selectedKey == null && U.currentThemeKey != initialThemeKey) {
      // Revert if sheet dismissed without selecting
      U.applyTheme(initialThemeKey);
    }
  }




  @override
  void initState() {
    super.initState();
    PeopleInteractionService().syncMyWavesCount();
    RoleService().isSuperUser().then((v) {
      if (mounted) setState(() => _isSuperUser = v);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }



  bool _uploadingPhoto = false;

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _uploadingPhoto = true);

      final file = File(picked.path);
      final uniId = U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'profiles';
      final downloadUrl = await FileUploadService().uploadProfilePhoto(
        file: file,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.primary,
            content: Text(
              'Profile photo updated successfully!',
              style: GoogleFonts.plusJakartaSans(color: U.bg, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(
              e is FileUploadException ? e.message : 'Failed to update profile photo. Please try again.',
              style: GoogleFonts.plusJakartaSans(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.card,
            content: Text(
              'Profile photo removed.',
              style: GoogleFonts.plusJakartaSans(color: U.text),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text('Failed to remove photo.', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  void _showChangePhotoModal(BuildContext context, {String? currentPhotoUrl}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: U.border, width: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: U.border.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Profile Photo',
                style: GoogleFonts.plusJakartaSans(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.photo_camera_rounded, color: U.primary, size: 20),
              ),
              title: Text(
                'Take Photo',
                style: GoogleFonts.plusJakartaSans(
                  color: U.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Use camera to capture new photo',
                style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.photo_library_rounded, color: U.primary, size: 20),
              ),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.plusJakartaSans(
                  color: U.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Upload an existing photo from device',
                style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto(ImageSource.gallery);
              },
            ),
            if (currentPhotoUrl != null && currentPhotoUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: U.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: U.red, size: 20),
                ),
                title: Text(
                  'Remove Current Photo',
                  style: GoogleFonts.plusJakartaSans(
                    color: U.red,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openRaiseIssueSheet() {
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
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userDocStream,
              builder: (context, snapshot) {
                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 140),
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Back Button (Left)
                        if (Navigator.canPop(context))
                          _HeaderButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Back',
                            onTap: () => Navigator.pop(context),
                          )
                        else
                          const SizedBox(width: 44),
                        // Share Button (Right)
                        _HeaderButton(
                          icon: Icons.share_outlined,
                          tooltip: 'Share App',
                          onTap: () {
                            Share.share('Join me on UTOPIA! 🚀 The productivity platform.\n\nhttps://inferalis.space/download-utopia');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Header Typography
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MY ACCOUNT',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                            color: theme.primary.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Profile',
                          style: GoogleFonts.outfit(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: theme.text,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Manage your academic identity',
                          style: GoogleFonts.plusJakartaSans(
                            color: U.sub,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 450.ms, curve: Curves.easeOutCubic).slideY(
                          begin: 0.1,
                          end: 0,
                          duration: 450.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 32),

                    // Premium Profile Header Card
                    Builder(
                      builder: (context) {
                        final userData = snapshot.data?.data() ?? {};
                        final bio = (userData['bio'] ?? '').toString().trim();
                        final branch = (userData['branch'] ?? '').toString().trim();
                        final instagramId = (userData['instagramId'] ?? '').toString().trim();
                        final wavesCount = (userData['wavesReceivedCount'] as num?)?.toInt() ?? 0;
                        final rawPhotoUrl = (userData['photoUrl'] as String?)?.trim();
                        final displayPhotoUrl = (rawPhotoUrl != null && rawPhotoUrl.isNotEmpty)
                            ? rawPhotoUrl
                            : user?.photoURL;
                        return Container(
                          decoration: BoxDecoration(
                            color: U.card,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: U.border.withValues(alpha: 0.7),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? Colors.black : theme.primary)
                                    .withValues(alpha: isDark ? 0.25 : 0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Avatar stack
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  GestureDetector(
                                    onTap: _uploadingPhoto ? null : () => _showChangePhotoModal(context, currentPhotoUrl: displayPhotoUrl),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.primary.withValues(alpha: 0.3),
                                          width: 2,
                                        ),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 44,
                                            backgroundColor: theme.primary.withValues(alpha: 0.1),
                                            backgroundImage: displayPhotoUrl != null && displayPhotoUrl.isNotEmpty
                                                ? CachedNetworkImageProvider(displayPhotoUrl)
                                                : null,
                                            child: (displayPhotoUrl == null || displayPhotoUrl.isEmpty)
                                                ? Text(
                                                    (user?.displayName ?? 'U')[0].toUpperCase(),
                                                    style: GoogleFonts.plusJakartaSans(
                                                      color: theme.primary,
                                                      fontSize: 32,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          if (_uploadingPhoto)
                                            Container(
                                              width: 88,
                                              height: 88,
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.55),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _uploadingPhoto ? null : () => _showChangePhotoModal(context, currentPhotoUrl: displayPhotoUrl),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: U.card,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: U.border),
                                      ),
                                      child: Icon(Icons.camera_alt_outlined, size: 14, color: theme.primary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      UtopiaApp.sanitizeDisplayName(user?.displayName),
                                      style: GoogleFonts.outfit(
                                        color: U.text,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_isSuperUser) ...[
                                    const SizedBox(width: 6),
                                    Icon(Icons.verified_rounded, color: U.red, size: 18),
                                  ],
                                ],
                              ),
                              if (bio.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Divider(color: U.border.withValues(alpha: 0.5), thickness: 0.5),
                                const SizedBox(height: 16),
                                Text(
                                  bio,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: U.text.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (branch.isNotEmpty || instagramId.isNotEmpty || wavesCount > 0) ...[
                                const SizedBox(height: 14),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if (branch.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: theme.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: theme.primary.withValues(alpha: 0.25),
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
                                              style: GoogleFonts.plusJakartaSans(
                                                color: theme.primary,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (instagramId.isNotEmpty)
                                      InstagramBadge(handle: instagramId),
                                    WaveCountBadge(count: wavesCount),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final updated = await showModalBottomSheet<bool>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => _EditProfileSheet(
                                      initialName: user?.displayName ?? 'Student',
                                      initialBio: bio,
                                      initialInstagram: instagramId,
                                      initialBranch: branch,
                                      initialPhotoUrl: displayPhotoUrl,
                                    ),
                                  );
                                  if (updated == true && mounted) {
                                    setState(() {});
                                  }
                                },
                                icon: Icon(Icons.edit_outlined, size: 14, color: theme.primary),
                                label: Text(
                                  'Edit Profile',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: theme.primary,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: theme.primary.withValues(alpha: 0.5), width: 0.8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  backgroundColor: theme.primary.withValues(alpha: 0.05),
                                  minimumSize: Size.zero,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ).animate().fadeIn(delay: 100.ms, duration: 450.ms).slideY(
                          begin: 0.1,
                          end: 0,
                          delay: 100.ms,
                          duration: 450.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 24),

                    // Grouped Settings List
                    Container(
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: U.border.withValues(alpha: 0.7),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? Colors.black : theme.primary)
                                .withValues(alpha: isDark ? 0.25 : 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _groupedTile(
                            icon: Icons.palette_rounded,
                            label: 'Switch Theme',
                            sub: _updatingTheme ? 'Updating theme...' : '${U.themeForKey(U.currentThemeKey).label} theme',
                            color: theme.peach,
                            onTap: _selectThemeStyle,
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: U.border.withValues(alpha: 0.5),
                          ),
                          _groupedTile(
                            icon: Icons.school_rounded,
                            label: 'Change University',
                            sub: 'Switch to a different university',
                            color: theme.blue,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UniversitySelectionScreen(),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: U.border.withValues(alpha: 0.5),
                          ),
                          _groupedTile(
                            icon: Icons.rocket_launch_rounded,
                            label: 'UTOPIA',
                            sub: 'About and development',
                            color: theme.lavender,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UtopiaSectionScreen(
                                  initialIsSuperUser: _isSuperUser,
                                ),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: U.border.withValues(alpha: 0.5),
                          ),
                          _groupedTile(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Raise Issue / Contact',
                            sub: 'Send support request or feedback',
                            color: theme.teal,
                            onTap: _openRaiseIssueSheet,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 450.ms).slideY(
                          begin: 0.1,
                          end: 0,
                          delay: 200.ms,
                          duration: 450.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 24),

                    // Sign Out Button
                    Center(
                      child: TextButton.icon(
                        onPressed: _showSignOutConfirmDialog,
                        icon: Icon(Icons.logout_rounded, size: 16, color: U.red.withValues(alpha: 0.8)),
                        label: Text(
                          'Sign Out',
                          style: GoogleFonts.outfit(
                            color: U.red.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Designed by Inferno',
                        style: GoogleFonts.plusJakartaSans(
                          color: U.dim,
                          fontSize: 11,
                          letterSpacing: 0.1,
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

  Widget _groupedTile({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.18),
                    color.withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
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
                    style: GoogleFonts.plusJakartaSans(
                      color: U.sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: U.dim, size: 16),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark 
                ? Colors.white.withValues(alpha: 0.08) 
                : Colors.black.withValues(alpha: 0.05),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.1) 
                  : Colors.black.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: U.text,
            size: 20,
          ),
        ),
      ),
    );
  }
}


class _ThemeStyleSheet extends StatefulWidget {
  const _ThemeStyleSheet({required this.currentKey});

  final String currentKey;

  @override
  State<_ThemeStyleSheet> createState() => _ThemeStyleSheetState();
}

class _ThemeStyleSheetState extends State<_ThemeStyleSheet> {
  late bool _isDarkSelected;

  @override
  void initState() {
    super.initState();
    final activeTheme = appThemes.firstWhere(
      (t) => t.key == widget.currentKey,
      orElse: () => appThemes.first,
    );
    _isDarkSelected = activeTheme.isDark;
  }

  @override
  Widget build(BuildContext context) {
    final filteredThemes = appThemes.where((t) => t.isDark == _isDarkSelected).toList();
    final lightCount = appThemes.where((t) => !t.isDark).length;
    final darkCount = appThemes.where((t) => t.isDark).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.50,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: U.border.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: U.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App Themes & Colors',
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose your preferred theme palette',
                          style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: U.sub, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ── Mode Toggle Buttons ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: U.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: U.border.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildModeButton(
                          label: 'Light ($lightCount)',
                          icon: Icons.wb_sunny_rounded,
                          isSelected: !_isDarkSelected,
                          onTap: () {
                            setState(() => _isDarkSelected = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildModeButton(
                          label: 'Dark ($darkCount)',
                          icon: Icons.dark_mode_rounded,
                          isSelected: _isDarkSelected,
                          onTap: () {
                            setState(() => _isDarkSelected = true);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // ── Grid of Themes with UI Previews ──
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: filteredThemes.length,
                    itemBuilder: (context, index) {
                      final theme = filteredThemes[index];
                      final selected = theme.key == appThemeNotifier.value.key;
                      return _CompactThemeCard(
                        theme: theme,
                        selected: selected,
                        onTap: () {
                          appThemeNotifier.value = theme;
                          Navigator.pop(context, theme.key);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? U.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? U.primary.withValues(alpha: 0.4) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? U.primary : U.sub,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? U.primary : U.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactThemeCard extends StatelessWidget {
  const _CompactThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? theme.primary : U.border.withValues(alpha: 0.6),
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: theme.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title & Checkmark
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    theme.label,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: selected ? theme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? theme.primary : U.sub.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded, size: 12, color: theme.bg)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              theme.description,
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),

            // Mini App Preview Screen Box
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.border.withValues(alpha: 0.7),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mini Navbar row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 28,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.text.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Mini Card Box inside preview
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.border.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: theme.primary.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: theme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: theme.text,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    width: 28,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: theme.sub.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(1.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Color Swatches Row
            Row(
              children: [
                _SwatchBlock(color: theme.bg),
                const SizedBox(width: 4),
                _SwatchBlock(color: theme.card),
                const SizedBox(width: 4),
                _SwatchBlock(color: theme.primary),
                const SizedBox(width: 4),
                _SwatchBlock(color: theme.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchBlock extends StatelessWidget {
  const _SwatchBlock({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialName,
    required this.initialBio,
    this.initialInstagram = '',
    this.initialBranch = '',
    this.initialPhotoUrl,
  });

  final String initialName;
  final String initialBio;
  final String initialInstagram;
  final String initialBranch;
  final String? initialPhotoUrl;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _instagramController;
  String? _selectedBranch;
  String? _photoUrl;
  bool _uploadingPhoto = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _bioController = TextEditingController(text: widget.initialBio);
    _instagramController = TextEditingController(text: widget.initialInstagram);
    _photoUrl = widget.initialPhotoUrl;
    _selectedBranch = widget.initialBranch.isNotEmpty && kBTechBranches.contains(widget.initialBranch)
        ? widget.initialBranch
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _uploadingPhoto = true);

      final file = File(picked.path);
      final uniId = U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'profiles';
      final downloadUrl = await FileUploadService().uploadProfilePhoto(
        file: file,
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
        setState(() {
          _photoUrl = downloadUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.primary,
            content: Text(
              'Profile photo updated!',
              style: GoogleFonts.plusJakartaSans(color: U.bg, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating photo in edit sheet: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(
              e is FileUploadException ? e.message : 'Failed to update photo.',
              style: GoogleFonts.plusJakartaSans(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
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
        setState(() {
          _photoUrl = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.card,
            content: Text('Profile photo removed.', style: GoogleFonts.plusJakartaSans(color: U.text)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text('Failed to remove photo.', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: U.border, width: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: U.border.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Change Photo',
                style: GoogleFonts.plusJakartaSans(
                  color: U.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.photo_camera_rounded, color: U.primary, size: 20),
              ),
              title: Text('Take Photo', style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('Use camera to capture new photo', style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.photo_library_rounded, color: U.primary, size: 20),
              ),
              title: Text('Choose from Gallery', style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('Upload an existing photo from device', style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto(ImageSource.gallery);
              },
            ),
            if (_photoUrl != null && _photoUrl!.isNotEmpty) ...[
              const SizedBox(height: 4),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: U.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: U.red, size: 20),
                ),
                title: Text('Remove Current Photo', style: GoogleFonts.plusJakartaSans(color: U.red, fontSize: 15, fontWeight: FontWeight.w600)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final nextName = _nameController.text.trim();
    final nextBio = _bioController.text.trim();
    final nextInstagram = _instagramController.text.trim().replaceAll('@', '');

    if (nextName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: U.red,
          content: Text('Name cannot be empty', style: GoogleFonts.plusJakartaSans(color: U.bg)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Update Auth
        await user.updateDisplayName(nextName);
        
        // Update Firestore users collection
        final updateMap = <String, dynamic>{
          'displayName': nextName,
          'bio': nextBio,
          'instagramId': nextInstagram,
          'branch': _selectedBranch ?? '',
          'email': user.email ?? '',
          'lastSeen': FieldValue.serverTimestamp(),
        };
        if (_photoUrl != null) {
          updateMap['photoUrl'] = _photoUrl;
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          updateMap,
          SetOptions(merge: true),
        );

        await user.reload();
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text('Could not update profile', style: GoogleFonts.plusJakartaSans(color: U.bg)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(top: BorderSide(color: U.border, width: 0.5)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: U.border.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: U.sub,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'Edit Profile',
                  style: GoogleFonts.plusJakartaSans(
                    color: U.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(U.primary),
                          ),
                        )
                      : Text(
                          'Save',
                          style: GoogleFonts.plusJakartaSans(
                            color: U.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Profile Photo Center
            Center(
              child: GestureDetector(
                onTap: _uploadingPhoto ? null : _showPhotoOptions,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: U.primary.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor: U.primary.withValues(alpha: 0.1),
                            backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(_photoUrl!)
                                : null,
                            child: (_photoUrl == null || _photoUrl!.isEmpty)
                                ? Text(
                                    (_nameController.text.isNotEmpty ? _nameController.text : 'U')[0].toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      color: U.primary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          if (_uploadingPhoto)
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
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
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: U.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: U.border),
                      ),
                      child: Icon(Icons.camera_alt_outlined, size: 13, color: U.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _uploadingPhoto ? null : _showPhotoOptions,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Change Photo',
                  style: GoogleFonts.plusJakartaSans(
                    color: U.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Name Field
            Text(
              'NAME',
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              maxLength: 40,
              style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
              cursorColor: U.primary,
              decoration: InputDecoration(
                hintText: 'Enter your name...',
                hintStyle: GoogleFonts.plusJakartaSans(color: U.dim),
                counterText: '',
                filled: true,
                fillColor: U.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Bio Field
            Text(
              'BIO',
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 2,
              maxLength: 150,
              style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
              cursorColor: U.primary,
              decoration: InputDecoration(
                hintText: 'Tell us about yourself...',
                hintStyle: GoogleFonts.plusJakartaSans(color: U.dim),
                filled: true,
                fillColor: U.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Instagram User ID Field
            Text(
              'INSTAGRAM USER ID',
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instagramController,
              maxLength: 30,
              style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
              cursorColor: U.primary,
              decoration: InputDecoration(
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: RealInstagramIcon(size: 18),
                ),
                hintText: 'e.g. john_doe',
                hintStyle: GoogleFonts.plusJakartaSans(color: U.dim),
                counterText: '',
                filled: true,
                fillColor: U.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Branch Name Dropdown Field
            Text(
              'BRANCH NAME',
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedBranch,
              isExpanded: true,
              dropdownColor: U.card,
              style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: U.sub),
              decoration: InputDecoration(
                hintText: 'Select B.Tech branch...',
                hintStyle: GoogleFonts.plusJakartaSans(color: U.dim, fontSize: 14),
                filled: true,
                fillColor: U.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: kBTechBranches.map((branch) {
                return DropdownMenuItem<String>(
                  value: branch,
                  child: Text(
                    branch,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedBranch = val),
            ),
          ],
        ),
      ),
    );
  }
}

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
  String _loadingMessage = '';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: U.red,
          content: Text(e.toString(), style: GoogleFonts.plusJakartaSans(color: U.bg)),
        ),
      );
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
    
    setState(() {
      _submitting = true;
      _loadingMessage = _selectedFile != null ? 'Uploading image...' : 'Sending email...';
    });

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

      setState(() {
        _loadingMessage = 'Sending report...';
      });

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
              content: Text('Report submitted successfully!', style: GoogleFonts.plusJakartaSans(color: U.bg)),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception('Failed to send email. Please try again.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(e.toString(), style: GoogleFonts.plusJakartaSans(color: U.bg)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _loadingMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: U.border, width: 0.5)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.border.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Header Row
              Row(
                children: [
                  TextButton(
                    onPressed: _submitting ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.sub,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Raise Issue / Contact',
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: GoogleFonts.plusJakartaSans(
                        color: U.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: U.primary,
                      foregroundColor: U.getContrastColor(U.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                U.getContrastColor(U.primary),
                              ),
                            ),
                          )
                        : Text(
                            'Submit',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
              if (_submitting) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    _loadingMessage,
                    style: GoogleFonts.plusJakartaSans(
                      color: U.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              
              // Issue Title Input
              Text(
                'ISSUE TITLE',
                style: GoogleFonts.plusJakartaSans(
                  color: U.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                enabled: !_submitting,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
                cursorColor: U.primary,
                decoration: InputDecoration(
                  hintText: 'e.g. App crashes when syncing',
                  hintStyle: GoogleFonts.plusJakartaSans(color: U.dim),
                  filled: true,
                  fillColor: U.bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 20),

              // Description Input
              Text(
                'DESCRIPTION',
                style: GoogleFonts.plusJakartaSans(
                  color: U.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                enabled: !_submitting,
                maxLines: 5,
                style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
                cursorColor: U.primary,
                decoration: InputDecoration(
                  hintText: 'Describe the issue or contact reason in detail...',
                  hintStyle: GoogleFonts.plusJakartaSans(color: U.dim),
                  filled: true,
                  fillColor: U.bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a description' : null,
              ),
              const SizedBox(height: 24),

              // Image Attachment
              Text(
                'ATTACHMENT',
                style: GoogleFonts.plusJakartaSans(
                  color: U.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedFile == null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickImage,
                    icon: Icon(Icons.add_a_photo_outlined, size: 18, color: U.primary),
                    label: Text(
                      'Attach Screenshot / Image (Optional)',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: U.primary.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: U.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: U.border.withValues(alpha: 0.5)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: Image.file(
                            _selectedFile!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFilename ?? 'screenshot.png',
                              style: GoogleFonts.plusJakartaSans(
                                color: U.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ready to upload',
                              style: GoogleFonts.plusJakartaSans(
                                color: U.sub,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting ? null : _clearImage,
                        icon: Icon(Icons.close_rounded, color: U.red, size: 20),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

