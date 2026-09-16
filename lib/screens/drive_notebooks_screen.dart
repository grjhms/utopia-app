import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/drive_notebook_model.dart';
import '../services/google_drive_service.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import 'drive_folder_browser_screen.dart';

class DriveNotebooksScreen extends StatefulWidget {
  const DriveNotebooksScreen({super.key});

  @override
  State<DriveNotebooksScreen> createState() => _DriveNotebooksScreenState();
}

class _DriveNotebooksScreenState extends State<DriveNotebooksScreen> {
  final GoogleDriveService _driveService = GoogleDriveService.instance;
  bool _isLoading = true;
  bool _isConnecting = false;
  List<DriveNotebook> _notebooks = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    await _driveService.initialize();
    final list = await _driveService.getSavedNotebooks();
    if (mounted) {
      setState(() {
        _notebooks = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleConnectDrive() async {
    setState(() => _isConnecting = true);
    try {
      final success = await _driveService.connect();
      if (!mounted) return;

      if (success) {
        showUtopiaSnackBar(
          context,
          message: 'Connected to Google Drive as ${_driveService.connectedEmail}',
          tone: UtopiaSnackBarTone.success,
        );
      } else {
        showUtopiaSnackBar(
          context,
          message: 'Could not connect to Google Drive. Please try again.',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Failed to connect: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleDisconnectDrive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Disconnect Google Drive?',
          style: GoogleFonts.outfit(
            color: U.text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Your linked folders will remain listed, but you will need to reconnect to browse Drive files.',
          style: GoogleFonts.outfit(color: U.sub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: U.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Disconnect', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _driveService.disconnect();
      if (mounted) {
        setState(() {});
        showUtopiaSnackBar(
          context,
          message: 'Google Drive disconnected',
          tone: UtopiaSnackBarTone.info,
        );
      }
    }
  }

  Future<void> _showLinkFolderDialog() async {
    if (!_driveService.isConnected) {
      showUtopiaSnackBar(
        context,
        message: 'Please connect Google Drive first',
        tone: UtopiaSnackBarTone.info,
      );
      return;
    }

    final urlCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool verifying = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: U.surfaceContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: U.outlineVariant.withValues(alpha: 0.5)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: U.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Link Google Drive Folder',
                      style: GoogleFonts.playfairDisplay(
                        color: U.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Paste a share link or folder ID from Google Drive to link it as a notebook.',
                      style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Google Drive Folder Link',
                      style: GoogleFonts.outfit(
                        color: U.sub,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: urlCtrl,
                      autofocus: true,
                      style: GoogleFonts.outfit(color: U.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'https://drive.google.com/drive/folders/...',
                        hintStyle: GoogleFonts.outfit(color: U.dim, fontSize: 14),
                        filled: true,
                        fillColor: U.bg,
                        prefixIcon: Icon(Icons.folder_shared_outlined, color: U.sub, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: U.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: U.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: U.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter a folder link or ID';
                        }
                        if (GoogleDriveService.extractFolderId(v) == null) {
                          return 'Invalid Google Drive folder link format';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: U.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: verifying
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setSheet(() => verifying = true);
                                try {
                                  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
                                  final notebook = await _driveService.verifyAndFetchFolder(
                                    urlCtrl.text.trim(),
                                    ownerUid: uid,
                                  );
                                  if (notebook != null) {
                                    await _driveService.saveNotebook(notebook);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    await _initData();
                                    if (mounted) {
                                      showUtopiaSnackBar(
                                        context,
                                        message: 'Linked "${notebook.name}"',
                                        tone: UtopiaSnackBarTone.success,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  setSheet(() => verifying = false);
                                  if (mounted) {
                                    showUtopiaSnackBar(
                                      context,
                                      message: e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', ''),
                                      tone: UtopiaSnackBarTone.error,
                                    );
                                  }
                                }
                              },
                        child: verifying
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                'Verify & Link Folder',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _handleDeleteNotebook(DriveNotebook notebook) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Remove Notebook?',
          style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Text(
          'This will remove "${notebook.name}" from your UTOPIA notebooks. Your Google Drive files will not be deleted.',
          style: GoogleFonts.outfit(color: U.sub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: U.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _driveService.removeNotebook(notebook.folderId);
      await _initData();
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Removed "${notebook.name}"',
          tone: UtopiaSnackBarTone.info,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: U.surfaceContainer,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: U.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Drive Notebooks',
                        style: GoogleFonts.playfairDisplay(
                          color: U.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          letterSpacing: -0.5,
                        ),
                      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),
                    ),
                    if (_driveService.isConnected)
                      _ActionButton(
                        icon: Icons.add_rounded,
                        label: 'Link Folder',
                        onTap: _showLinkFolderDialog,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Connect and sync your Google Drive study material',
                  style: GoogleFonts.outfit(color: U.dim, fontSize: 13),
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
              ),

              // Drive Connection Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _DriveConnectionStatusCard(
                  isConnected: _driveService.isConnected,
                  email: _driveService.connectedEmail,
                  isConnecting: _isConnecting,
                  onConnect: _handleConnectDrive,
                  onDisconnect: _handleDisconnectDrive,
                  isDark: isDark,
                ),
              ),

              // Notebook List
              Expanded(
                child: _isLoading
                    ? const Center(child: UtopiaLoader(scale: 0.7))
                    : _notebooks.isEmpty
                        ? _EmptyNotebooksState(
                            isConnected: _driveService.isConnected,
                            onLinkFolder: _showLinkFolderDialog,
                            onConnect: _handleConnectDrive,
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                            itemCount: _notebooks.length,
                            itemBuilder: (context, i) {
                              final notebook = _notebooks[i];
                              return _NotebookCard(
                                notebook: notebook,
                                index: i,
                                isDark: isDark,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DriveFolderBrowserScreen(
                                        notebook: notebook,
                                      ),
                                    ),
                                  );
                                },
                                onDelete: () => _handleDeleteNotebook(notebook),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: U.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: U.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: 150.ms),
    );
  }
}

class _DriveConnectionStatusCard extends StatelessWidget {
  final bool isConnected;
  final String? email;
  final bool isConnecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final bool isDark;

  const _DriveConnectionStatusCard({
    required this.isConnected,
    required this.email,
    required this.isConnecting,
    required this.onConnect,
    required this.onDisconnect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? (isDark
                ? U.primary.withValues(alpha: 0.08)
                : U.primary.withValues(alpha: 0.06))
            : U.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isConnected
              ? U.primary.withValues(alpha: 0.3)
              : U.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isConnected
                  ? U.primary.withValues(alpha: 0.15)
                  : (isDark ? Colors.white10 : Colors.black12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_to_drive_rounded,
              color: isConnected ? U.primary : U.sub,
              size: 24,
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
                      isConnected ? 'Google Drive Linked' : 'Connect Google Drive',
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isConnected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: U.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Active',
                          style: GoogleFonts.outfit(
                            color: U.green,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isConnected
                      ? (email != null && email!.isNotEmpty
                          ? email!
                          : 'Ready to browse linked folders')
                      : 'Sign in to access and sync your Drive folders',
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isConnected)
            IconButton(
              tooltip: 'Disconnect',
              onPressed: onDisconnect,
              icon: Icon(Icons.link_off_rounded, color: U.dim, size: 20),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: U.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: isConnecting ? null : onConnect,
              child: isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Connect',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
            ),
        ],
      ),
    );
  }
}

class _NotebookCard extends StatelessWidget {
  final DriveNotebook notebook;
  final int index;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotebookCard({
    required this.notebook,
    required this.index,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: U.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.folder_rounded,
                      color: U.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notebook.name,
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.cloud_done_rounded, color: U.primary.withValues(alpha: 0.7), size: 13),
                            const SizedBox(width: 4),
                            Text(
                              'Google Drive',
                              style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                            ),
                            if (notebook.isOffline) ...[
                              Text('  •  ', style: GoogleFonts.outfit(color: U.dim, fontSize: 12)),
                              Icon(Icons.offline_pin_rounded, color: U.green, size: 13),
                              const SizedBox(width: 3),
                              Text('Offline Ready', style: GoogleFonts.outfit(color: U.green, fontSize: 12)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: U.surfaceContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    icon: Icon(Icons.more_vert_rounded, color: U.sub, size: 20),
                    onSelected: (v) {
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: U.red, size: 18),
                            const SizedBox(width: 10),
                            Text('Remove', style: GoogleFonts.outfit(color: U.red, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ).animate().fadeIn(delay: (index * 60).ms, duration: 400.ms).slideY(begin: 0.1, end: 0),
    );
  }
}

class _EmptyNotebooksState extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onLinkFolder;
  final VoidCallback onConnect;

  const _EmptyNotebooksState({
    required this.isConnected,
    required this.onLinkFolder,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_shared_outlined, color: U.primary, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              isConnected ? 'No Drive Folders Linked' : 'Drive Not Connected',
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isConnected
                  ? 'Paste a Google Drive folder link to add it to your notebook collection.'
                  : 'Connect your Google Drive account to browse and sync study notebooks.',
              style: GoogleFonts.outfit(color: U.sub, fontSize: 14, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: U.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: isConnected ? onLinkFolder : onConnect,
              icon: Icon(isConnected ? Icons.add_link_rounded : Icons.login_rounded, size: 18),
              label: Text(
                isConnected ? 'Link Folder' : 'Connect Google Drive',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms),
      ),
    );
  }
}
