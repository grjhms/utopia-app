import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../widgets/utopia_snackbar.dart';

/// Semantic version model that supports comparing versions like:
/// '4.2.0', '4.2.1', 'v4.3.0', '4.2.0+44', '4.2.0+45'
class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;
  final int? buildNumber;
  final String raw;

  AppVersion({
    required this.parts,
    this.buildNumber,
    required this.raw,
  });

  factory AppVersion.parse(String versionStr) {
    final clean = versionStr.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final plusSplit = clean.split('+');
    final versionPart = plusSplit[0];
    final buildPart = plusSplit.length > 1 ? int.tryParse(plusSplit[1]) : null;

    final parts = versionPart
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    while (parts.length < 3) {
      parts.add(0);
    }

    return AppVersion(
      parts: parts,
      buildNumber: buildPart,
      raw: versionStr,
    );
  }

  @override
  int compareTo(AppVersion other) {
    final maxLen = math.max(parts.length, other.parts.length);
    for (int i = 0; i < maxLen; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) {
        return a.compareTo(b);
      }
    }
    if (buildNumber != null && other.buildNumber != null) {
      return buildNumber!.compareTo(other.buildNumber!);
    }
    return 0;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AppVersion && compareTo(other) == 0);

  @override
  int get hashCode => parts.hashCode ^ (buildNumber?.hashCode ?? 0);

  @override
  String toString() => raw;
}

/// Metadata holding remote update configuration and current state
class UtopiaUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String minSupportedVersion;
  final String title;
  final String message;
  final String storeUrl;
  final bool isForced;
  final bool hasUpdate;
  final bool enabled;

  const UtopiaUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.title,
    required this.message,
    required this.storeUrl,
    required this.isForced,
    required this.hasUpdate,
    required this.enabled,
  });
}

class AppUpdateService {
  static const String defaultStoreUrl =
      'https://play.google.com/store/apps/details?id=com.superwave.utopia';
  static const String defaultMarketUrl =
      'market://details?id=com.superwave.utopia';

  /// Key used in SharedPreferences
  static const String _keyDismissedVersion = 'last_dismissed_update_version';
  static const String _keyDismissedTime = 'last_dismissed_update_time';

  /// Attempts to perform a native Google Play In-App Update on Android devices.
  /// Returns true if a native Play Store update was initiated or completed.
  static Future<bool> tryGooglePlayUpdate({bool isForced = false}) async {
    if (!Platform.isAndroid) return false;

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();

      // If an update was already downloaded in background, complete it
      if (updateInfo.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (isForced && updateInfo.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        } else if (updateInfo.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
          }
          return true;
        } else if (updateInfo.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        }
      }
    } catch (e) {
      debugPrint('AppUpdateService: Google Play InAppUpdate unavailable: $e');
    }

    return false;
  }

  /// Diagnostic check for Google Play In-App Update availability
  static Future<String> checkGooglePlayUpdateStatus() async {
    if (!Platform.isAndroid) {
      return 'Not on Android (current platform: ${Platform.operatingSystem})';
    }
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        return 'Play Store update AVAILABLE (Code: ${info.availableVersionCode}, Immediate: ${info.immediateUpdateAllowed}, Flexible: ${info.flexibleUpdateAllowed})';
      } else if (info.updateAvailability == UpdateAvailability.updateNotAvailable) {
        return 'Play Core reports no update available (app version is up to date on Google Play)';
      } else {
        return 'Play Core availability status: ${info.updateAvailability}';
      }
    } catch (e) {
      return 'Play Core API returned error (normal in debug/sideloaded builds): $e';
    }
  }

  /// Fetch remote update information from Firestore and evaluate whether an update is required
  static Future<UtopiaUpdateInfo?> fetchUpdateInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionStr = packageInfo.version;
      final currentBuildStr = packageInfo.buildNumber;
      final fullCurrentVersion = currentBuildStr.isNotEmpty
          ? '$currentVersionStr+$currentBuildStr'
          : currentVersionStr;

      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get();

      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = doc.data()!;
      final enabled = data['update_enabled'] as bool? ?? true;
      final latestVersionStr =
          (data['latest_version'] as String?)?.trim() ?? currentVersionStr;
      final minVersionStr =
          (data['min_supported_version'] as String?)?.trim() ?? '0.0.0';
      final title = data['update_title'] as String? ?? 'Update available';
      final message = data['update_message'] as String? ??
          'A new version of UTOPIA is available on Google Play with new features and performance improvements.';
      final storeUrl = (data['update_url'] as String?)?.trim().isNotEmpty == true
          ? (data['update_url'] as String).trim()
          : defaultStoreUrl;
      final forceAll = data['force_update'] as bool? ?? false;

      final currentVer = AppVersion.parse(fullCurrentVersion);
      final latestVer = AppVersion.parse(latestVersionStr);
      final minVer = AppVersion.parse(minVersionStr);

      final hasUpdate = currentVer < latestVer;
      final isBelowMin = currentVer < minVer;
      final isForced = forceAll || isBelowMin;

      return UtopiaUpdateInfo(
        currentVersion: currentVersionStr,
        latestVersion: latestVersionStr,
        minSupportedVersion: minVersionStr,
        title: title,
        message: message,
        storeUrl: storeUrl,
        isForced: isForced,
        hasUpdate: hasUpdate,
        enabled: enabled,
      );
    } catch (e) {
      debugPrint('AppUpdateService.fetchUpdateInfo error: $e');
      return null;
    }
  }

  /// Launch Google Play Store or custom download URL
  static Future<bool> openStore({String? customUrl}) async {
    final targetUrl =
        (customUrl != null && customUrl.isNotEmpty) ? customUrl : defaultStoreUrl;

    if (Platform.isAndroid && targetUrl == defaultStoreUrl) {
      try {
        final marketUri = Uri.parse(defaultMarketUrl);
        if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }

    try {
      final uri = Uri.parse(targetUrl);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AppUpdateService.openStore error: $e');
      return false;
    }
  }

  /// Check for update and display dialog if an update is available.
  /// Set [isManual] to true when called from Settings / Utopia screen.
  static Future<void> checkForUpdate(
    BuildContext context, {
    bool isManual = false,
  }) async {
    // 1. First, attempt native Google Play In-App Update on Android
    if (Platform.isAndroid) {
      final playUpdated = await tryGooglePlayUpdate();
      if (playUpdated) {
        return;
      }
    }

    // 2. Fetch remote update info from Firestore
    final info = await fetchUpdateInfo();
    if (info == null) {
      if (isManual && context.mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Unable to check for updates right now. Please try again later.',
          tone: UtopiaSnackBarTone.error,
        );
      }
      return;
    }

    if (!info.enabled) {
      if (isManual && context.mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Update checks are currently disabled.',
          tone: UtopiaSnackBarTone.info,
        );
      }
      return;
    }

    if (!info.hasUpdate) {
      if (isManual && context.mounted) {
        showUtopiaSnackBar(
          context,
          message: 'You are on the latest version of UTOPIA (v${info.currentVersion})',
          tone: UtopiaSnackBarTone.success,
        );
      }
      return;
    }

    // If automatic check and not forced, check if user dismissed this update recently
    if (!isManual && !info.isForced) {
      final prefs = await SharedPreferences.getInstance();
      final lastDismissed = prefs.getString(_keyDismissedVersion);
      if (lastDismissed == info.latestVersion) {
        final lastDismissedTime = prefs.getInt(_keyDismissedTime) ?? 0;
        final diff = DateTime.now().millisecondsSinceEpoch - lastDismissedTime;
        // Don't reprompt within 24 hours of dismissal
        if (diff < const Duration(hours: 24).inMilliseconds) {
          return;
        }
      }
    }

    if (context.mounted) {
      await showUpdateDialog(context, info);
    }
  }

  /// Show minimal, clean M3 update dialog without visual clutter or emojis
  static Future<void> showUpdateDialog(
    BuildContext context,
    UtopiaUpdateInfo info,
  ) async {
    // Clean emojis from title if present
    final cleanTitle = info.title
        .replaceAll(
          RegExp(
            r'[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
            unicode: true,
          ),
          '',
        )
        .trim();
    final displayTitle =
        cleanTitle.isNotEmpty ? cleanTitle : 'Update available';

    await showDialog(
      context: context,
      barrierDismissible: !info.isForced,
      builder: (dialogContext) {
        return PopScope(
          canPop: !info.isForced,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: U.border.withValues(alpha: 0.6),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: appThemeNotifier.value.isDark ? 0.35 : 0.08,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Minimal Icon, Title & Version Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: U.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.system_update_rounded,
                          size: 18,
                          color: U.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Version ${info.latestVersion}',
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (info.isForced)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: U.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Required',
                            style: GoogleFonts.outfit(
                              color: U.red,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Message / Notes
                  if (info.message.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          info.message.trim(),
                          style: GoogleFonts.plusJakartaSans(
                            color: U.sub,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Minimal Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!info.isForced) ...[
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: U.dim,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onPressed: () async {
                            final prefs =
                                await SharedPreferences.getInstance();
                            await prefs.setString(
                              _keyDismissedVersion,
                              info.latestVersion,
                            );
                            await prefs.setInt(
                              _keyDismissedTime,
                              DateTime.now().millisecondsSinceEpoch,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                          child: Text(
                            'Later',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              info.isForced ? U.red : U.primary,
                          foregroundColor: U.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          openStore(customUrl: info.storeUrl);
                          if (!info.isForced && dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        child: Text(
                          'Update',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
