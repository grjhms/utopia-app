import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import '../services/file_upload_service.dart';
import '../services/role_service.dart';
import '../services/secure_storage_service.dart';
import '../services/attendance_cache_service.dart';
import 'profile_screen.dart'; // To reuse kBTechBranches

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _universityId = '';
  String _userBranch = '';
  String _rollNumber = '';
  bool _isSuperUser = false;
  String _userName = '';
  List<DocumentSnapshot> _assignments = [];
  List<String> _studentSubjects = [];

  // Toggle for local testing to simulate being a superuser
  bool _isSuperUserOverride = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserDataAndAssignments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserDataAndAssignments() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Check role via RoleService
      final isSuper = await RoleService().isSuperUser();

      // Load user profile details
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String uniId = U.cachedUniversityId;
      String branch = '';
      String name = UtopiaApp.sanitizeDisplayName(user.displayName);
      String roll = '';

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        uniId = data['selectedUniversityId'] as String? ?? U.cachedUniversityId;
        branch = data['branch'] as String? ?? '';
        name = UtopiaApp.sanitizeDisplayName(data['displayName'] ?? user.displayName);
        roll = data['rollNumber'] as String? ?? '';
      }

      // Fetch subjects from Attendance Cache using roll number
      List<String> subjects = [];
      if (roll.isNotEmpty) {
        final cache = await AttendanceCacheService.load(roll);
        if (cache != null) {
          final subjectsList = cache.data['subjects'] as List<dynamic>? ?? [];
          subjects = subjectsList
              .map((s) => (s['subject'] as String? ?? '').trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }

      if (mounted) {
        setState(() {
          _universityId = uniId;
          _userBranch = branch;
          _userName = name;
          _rollNumber = roll;
          _studentSubjects = subjects;
          _isSuperUser = isSuper;
        });
      }

      await _fetchAssignments();
    } catch (e) {
      debugPrint('Error loading assignments data: $e');
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Error loading page: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchAssignments() async {
    if (_universityId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('assignments')
          .where('universityId', isEqualTo: _universityId)
          .get();

      if (mounted) {
        setState(() {
          _assignments = snap.docs;
        });
      }
    } catch (e) {
      debugPrint('Error fetching assignments: $e');
    }
  }

  Future<void> _saveStudentInfo(String roll, String branch, {String? name}) async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final Map<String, dynamic> updateData = {
          'rollNumber': roll.trim().toUpperCase(),
          'branch': branch,
        };
        if (name != null && name.trim().isNotEmpty) {
          updateData['displayName'] = name.trim();
        }

        // Save to Firestore users collection
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          updateData,
          SetOptions(merge: true),
        );

        if (name != null && name.trim().isNotEmpty) {
          await user.updateDisplayName(name.trim());
        }

        // Save roll number to secure storage for cross-feature syncing
        final creds = await SecureStorageService.getCredentials();
        final currentPwd = creds?['password'] ?? '';
        final currentCol = creds?['college'] ?? 'aus';
        await SecureStorageService.saveCredentials(roll, currentPwd, currentCol);

        // Clear RoleService cache and re-check role status
        RoleService().clearCache();
        final isSuper = await RoleService().isSuperUser();

        // Fetch subjects from Attendance Cache using roll number
        final cache = await AttendanceCacheService.load(roll.trim().toUpperCase());
        List<String> subjects = [];
        if (cache != null) {
          final subjectsList = cache.data['subjects'] as List<dynamic>? ?? [];
          subjects = subjectsList
              .map((s) => (s['subject'] as String? ?? '').trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }

        if (mounted) {
          setState(() {
            _rollNumber = roll.trim().toUpperCase();
            _userBranch = branch;
            if (name != null && name.trim().isNotEmpty) {
              _userName = name.trim();
            }
            _isSuperUser = isSuper;
            _studentSubjects = subjects;
          });
        }

        await _fetchAssignments();

        if (mounted) {
          showUtopiaSnackBar(
            context,
            message: _hasPostPermission
                ? 'Welcome back, Administrator!'
                : 'Student profile verified and subjects loaded!',
            tone: UtopiaSnackBarTone.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Failed to authenticate: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logoutAssignments() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Clear from Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'rollNumber': '',
        }, SetOptions(merge: true));

        // Clear local state
        _rollNumber = '';
        _studentSubjects = [];
        _isSuperUser = false;
        _isSuperUserOverride = false;
        await _fetchAssignments();

        if (mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Logged out of Assignments Portal.',
            tone: UtopiaSnackBarTone.info,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showUtopiaSnackBar(
          context,
          message: 'Logout failed: $e',
          tone: UtopiaSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Combined permission check (database role or local debug override)
  bool get _hasPostPermission => _isSuperUser || _isSuperUserOverride;

  void _toggleSuperUserOverride() {
    setState(() {
      _isSuperUserOverride = !_isSuperUserOverride;
    });

    showUtopiaSnackBar(
      context,
      message: _isSuperUserOverride
          ? 'Dev Mode: Superuser features enabled.'
          : 'Dev Mode: Enforcing database roles.',
      tone: UtopiaSnackBarTone.info,
    );
  }

  void _showCreateAssignmentSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final titleController = TextEditingController();
    final descController = TextEditingController();
    final subjectController = TextEditingController();
    String selectedBranch = 'All Branches';
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedTime = const TimeOfDay(hour: 23, minute: 59);

    File? attachedFile;
    String? attachedFileName;
    String? uploadedFileUrl;
    bool isUploadingFile = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final theme = appThemeNotifier.value;
          final isDark = theme.isDark;

          Future<void> pickAndUploadAttachment() async {
            try {
              final picked = await FileUploadService().pickFile();
              if (picked == null) return;

              setSheetState(() {
                attachedFile = picked.$1;
                attachedFileName = picked.$2;
                isUploadingFile = true;
              });

              final url = await FileUploadService().uploadFile(
                file: attachedFile!,
                originalFilename: attachedFileName!,
                universityId: _universityId,
              );

              setSheetState(() {
                uploadedFileUrl = url;
                isUploadingFile = false;
              });
            } catch (e) {
              setSheetState(() {
                attachedFile = null;
                attachedFileName = null;
                isUploadingFile = false;
              });
              showUtopiaSnackBar(
                sheetContext,
                message: e.toString(),
                tone: UtopiaSnackBarTone.error,
              );
            }
          }

          Future<void> selectDueDate() async {
            final pickedDate = await showDatePicker(
              context: sheetContext,
              initialDate: selectedDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (context, child) {
                return Theme(
                  data: isDark
                      ? ThemeData.dark().copyWith(
                          colorScheme: ColorScheme.dark(
                            primary: theme.primary,
                            onPrimary: Colors.black,
                            surface: U.card,
                            onSurface: U.text,
                          ),
                          dialogBackgroundColor: U.bg,
                        )
                      : ThemeData.light().copyWith(
                          colorScheme: ColorScheme.light(
                            primary: theme.primary,
                            onPrimary: Colors.white,
                            surface: U.card,
                            onSurface: U.text,
                          ),
                          dialogBackgroundColor: U.bg,
                        ),
                  child: child!,
                );
              },
            );
            if (pickedDate != null) {
              if (!sheetContext.mounted) return;
              final pickedTime = await showTimePicker(
                context: sheetContext,
                initialTime: selectedTime,
                builder: (context, child) {
                  return Theme(
                    data: isDark ? ThemeData.dark() : ThemeData.light(),
                    child: child!,
                  );
                },
              );
              if (pickedTime != null) {
                setSheetState(() {
                  selectedDate = pickedDate;
                  selectedTime = pickedTime;
                });
              }
            }
          }

          Future<void> saveAssignment() async {
            final title = titleController.text.trim();
            final desc = descController.text.trim();
            final subject = subjectController.text.trim();

            if (title.isEmpty || subject.isEmpty) {
              showUtopiaSnackBar(
                sheetContext,
                message: 'Title and Subject are required.',
                tone: UtopiaSnackBarTone.info,
              );
              return;
            }

            setSheetState(() => isSaving = true);
            try {
              final dueDateTime = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime.hour,
                selectedTime.minute,
              );

              final newDoc = FirebaseFirestore.instance.collection('assignments').doc();
              await newDoc.set({
                'id': newDoc.id,
                'title': title,
                'description': desc,
                'subject': subject,
                'branch': selectedBranch,
                'universityId': _universityId,
                'dueDate': Timestamp.fromDate(dueDateTime),
                'createdAt': FieldValue.serverTimestamp(),
                'teacherId': user.uid,
                'teacherName': _userName.isNotEmpty ? _userName : 'Administrator',
                'attachmentUrl': uploadedFileUrl,
                'attachmentName': attachedFileName,
              });

              if (mounted) {
                showUtopiaSnackBar(
                  context,
                  message: 'Assignment successfully posted!',
                  tone: UtopiaSnackBarTone.success,
                );
                Navigator.pop(sheetContext);
                _fetchAssignments();
              }
            } catch (e) {
              setSheetState(() => isSaving = false);
              if (sheetContext.mounted) {
                showUtopiaSnackBar(
                  sheetContext,
                  message: 'Failed to post assignment: $e',
                  tone: UtopiaSnackBarTone.error,
                );
              }
            }
          }

          return Container(
            decoration: BoxDecoration(
              color: U.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: U.border, width: 0.5)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: U.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Post New Assignment',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Subject input
                  TextField(
                    controller: subjectController,
                    style: GoogleFonts.outfit(color: U.text),
                    decoration: InputDecoration(
                      labelText: 'Subject Name',
                      labelStyle: GoogleFonts.outfit(color: U.sub),
                      hintText: 'e.g. Operating Systems, Mathematics-II',
                      hintStyle: GoogleFonts.outfit(color: U.dim),
                      filled: true,
                      fillColor: U.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title input
                  TextField(
                    controller: titleController,
                    style: GoogleFonts.outfit(color: U.text),
                    decoration: InputDecoration(
                      labelText: 'Assignment Title',
                      labelStyle: GoogleFonts.outfit(color: U.sub),
                      hintText: 'e.g. Lab Report 3 or Midterm Homework',
                      hintStyle: GoogleFonts.outfit(color: U.dim),
                      filled: true,
                      fillColor: U.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Branch selection Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: selectedBranch,
                    dropdownColor: U.card,
                    style: GoogleFonts.outfit(color: U.text),
                    decoration: InputDecoration(
                      labelText: 'Target Branch',
                      labelStyle: GoogleFonts.outfit(color: U.sub),
                      filled: true,
                      fillColor: U.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.border),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'All Branches',
                        child: Text('All Branches'),
                      ),
                      ...kBTechBranches.map((branch) => DropdownMenuItem(
                            value: branch,
                            child: Text(branch),
                          ))
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setSheetState(() {
                          selectedBranch = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Description
                  TextField(
                    controller: descController,
                    maxLines: 4,
                    style: GoogleFonts.outfit(color: U.text),
                    decoration: InputDecoration(
                      labelText: 'Instructions / Description',
                      labelStyle: GoogleFonts.outfit(color: U.sub),
                      hintText: 'Provide details about the assignment...',
                      hintStyle: GoogleFonts.outfit(color: U.dim),
                      filled: true,
                      fillColor: U.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: U.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Due Date Selection
                  InkWell(
                    onTap: selectDueDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: U.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: U.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Due Date & Time',
                                style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${selectedDate.day}/${selectedDate.month}/${selectedDate.year} at ${selectedTime.format(sheetContext)}',
                                style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Icon(Icons.calendar_today_rounded, color: U.primary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // File Attachment button/preview
                  if (attachedFileName != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: U.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: U.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file_outlined, color: U.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              attachedFileName!,
                              style: GoogleFonts.outfit(color: U.text, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isUploadingFile)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                            )
                          else
                            IconButton(
                              icon: Icon(Icons.close_rounded, color: U.red),
                              onPressed: () {
                                setSheetState(() {
                                  attachedFile = null;
                                  attachedFileName = null;
                                  uploadedFileUrl = null;
                                });
                              },
                            ),
                        ],
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: pickAndUploadAttachment,
                      icon: Icon(Icons.attach_file_rounded, color: U.primary),
                      label: Text(
                        'Attach Document / PDF',
                        style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: U.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  const SizedBox(height: 32),
                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: isSaving
                        ? const Center(child: UtopiaLoader(scale: 0.5))
                        : FilledButton(
                            onPressed: isUploadingFile ? null : saveAssignment,
                            style: FilledButton.styleFrom(
                              backgroundColor: U.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Post Assignment',
                              style: GoogleFonts.outfit(
                                color: U.bg,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditStudentInfoSheet() {
    final nameController = TextEditingController(text: _userName);
    final rollController = TextEditingController(text: _rollNumber);
    String selectedBranch = _userBranch.isNotEmpty ? _userBranch : kBTechBranches.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: U.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: U.border, width: 0.5)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: U.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Update Info',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                style: GoogleFonts.outfit(color: U.text),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  filled: true,
                  fillColor: U.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: rollController,
                style: GoogleFonts.outfit(color: U.text),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Roll Number / ID',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  filled: true,
                  fillColor: U.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedBranch,
                dropdownColor: U.card,
                style: GoogleFonts.outfit(color: U.text),
                decoration: InputDecoration(
                  labelText: 'Academic Branch',
                  labelStyle: GoogleFonts.outfit(color: U.sub),
                  filled: true,
                  fillColor: U.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: U.border),
                  ),
                ),
                items: kBTechBranches.map((branch) => DropdownMenuItem(
                      value: branch,
                      child: Text(branch),
                    )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    selectedBranch = val;
                  }
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final roll = rollController.text.trim();
                    if (roll.isEmpty) return;
                    Navigator.pop(ctx);
                    _saveStudentInfo(roll, selectedBranch, name: name);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: U.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Save Changes',
                    style: GoogleFonts.outfit(
                      color: U.bg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAssignment(String assignmentId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: U.red, size: 24),
            const SizedBox(width: 10),
            Text(
              'Delete Assignment',
              style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the assignment "$title"? This action is permanent.',
          style: GoogleFonts.outfit(color: U.sub, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                await FirebaseFirestore.instance.collection('assignments').doc(assignmentId).delete();
                if (mounted) {
                  showUtopiaSnackBar(
                    context,
                    message: 'Assignment deleted successfully.',
                    tone: UtopiaSnackBarTone.success,
                  );
                }
                _fetchAssignments();
              } catch (e) {
                if (mounted) {
                  showUtopiaSnackBar(
                    context,
                    message: 'Failed to delete assignment: $e',
                    tone: UtopiaSnackBarTone.error,
                  );
                }
              } finally {
                setState(() => _isLoading = false);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: U.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStr = months[dt.month - 1];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '$monthStr ${dt.day}, ${dt.year} at $hour:$minuteStr $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = appThemeNotifier.value;

    // Filter assignments
    // 1. "My Branch" - shows matches with user's branch OR "All Branches".
    // 2. "All" - shows all.
    final List<DocumentSnapshot> myBranchList = _assignments.where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final targetBranch = data['branch'] as String? ?? 'All Branches';
      return targetBranch == 'All Branches' || _userBranch.isEmpty || targetBranch.toLowerCase() == _userBranch.toLowerCase();
    }).toList();

    // Sort lists in memory by due date
    myBranchList.sort((a, b) {
      final aDue = (a.get('dueDate') as Timestamp).toDate();
      final bDue = (b.get('dueDate') as Timestamp).toDate();
      return aDue.compareTo(bDue);
    });

    final List<DocumentSnapshot> allList = List<DocumentSnapshot>.from(_assignments);
    allList.sort((a, b) {
      final aDue = (a.get('dueDate') as Timestamp).toDate();
      final bDue = (b.get('dueDate') as Timestamp).toDate();
      return aDue.compareTo(bDue);
    });

    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Assignments',
          style: GoogleFonts.outfit(
            color: U.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Invisible/Subtle key toggle for developer simulation
          IconButton(
            icon: Icon(
              Icons.vpn_key_outlined,
              color: _isSuperUserOverride ? theme.primary : U.dim.withValues(alpha: 0.3),
              size: 20,
            ),
            tooltip: 'Simulate Superuser Role (Dev Only)',
            onPressed: _toggleSuperUserOverride,
          ),
          if (_rollNumber.isNotEmpty)
            IconButton(
              icon: Icon(Icons.logout_rounded, color: U.text, size: 20),
              tooltip: 'Logout from Portal',
              onPressed: _logoutAssignments,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: UtopiaLoader(scale: 0.7))
            : (_rollNumber.isEmpty && !_isSuperUserOverride)
                ? _buildLoginCard()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header showing Roll No/ID and Role/Branch
                      _buildStudentHeader(),

                      // Warning if subjects not fetched from cache
                      _buildSubjectsWarning(),

                      // Pill Tab Selector
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: U.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: U.border, width: 0.5),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicator: BoxDecoration(
                              color: theme.primary,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primary.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            labelColor: U.getContrastColor(theme.primary),
                            unselectedLabelColor: U.sub,
                            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                            tabs: const [
                              Tab(text: 'Active Tasks'),
                              Tab(text: 'All Branches'),
                            ],
                          ),
                        ),
                      ),
                      // Tab Contents
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildAssignmentList(myBranchList),
                            _buildAssignmentList(allList),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
      floatingActionButton: (_rollNumber.isNotEmpty && _hasPostPermission)
          ? FloatingActionButton.extended(
              onPressed: _showCreateAssignmentSheet,
              backgroundColor: theme.primary,
              foregroundColor: U.bg,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Post Assignment',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hintText,
    required String labelText,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autocorrect: false,
      style: GoogleFonts.outfit(color: U.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: GoogleFonts.outfit(
          color: U.sub.withValues(alpha: 0.8),
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.outfit(color: U.sub, fontSize: 14),
        filled: true,
        fillColor: U.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: U.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: U.primary),
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    final theme = appThemeNotifier.value;
    final nameController = TextEditingController(text: _userName);
    final rollController = TextEditingController(text: _rollNumber);
    String selectedBranch = _userBranch.isNotEmpty ? _userBranch : kBTechBranches.first;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.assignment_ind_rounded,
                      color: theme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Connect Assignments',
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Access your subjects and academic task portal',
                    style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: U.card,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: U.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildField(
                      controller: nameController,
                      hintText: 'e.g. John Doe',
                      labelText: 'Full Name',
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: rollController,
                      hintText: 'e.g. 21A91A0501 or FACULTY01',
                      labelText: 'Roll Number / Employee ID',
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedBranch,
                      dropdownColor: U.card,
                      style: GoogleFonts.outfit(color: U.text, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Academic Branch (Students)',
                        labelStyle: GoogleFonts.outfit(color: U.sub, fontSize: 14),
                        filled: true,
                        fillColor: U.surface,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: U.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: theme.primary),
                        ),
                      ),
                      items: kBTechBranches.map((branch) => DropdownMenuItem(
                            value: branch,
                            child: Text(branch),
                          )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          selectedBranch = val;
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          final name = nameController.text.trim();
                          final roll = rollController.text.trim();
                          if (roll.isEmpty) {
                            showUtopiaSnackBar(
                              context,
                              message: 'Please enter your Roll Number / ID.',
                              tone: UtopiaSnackBarTone.info,
                            );
                            return;
                          }
                          _saveStudentInfo(roll, selectedBranch, name: name);
                        },
                        icon: const Icon(Icons.sync_lock_rounded, size: 18),
                        label: Text(
                          'Connect Portal',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: U.bg,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentHeader() {
    final theme = appThemeNotifier.value;
    final isSuper = _hasPostPermission;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primary.withValues(alpha: 0.1), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            isSuper ? Icons.admin_panel_settings_outlined : Icons.account_circle_outlined,
            color: theme.primary,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName.isNotEmpty ? _userName : (isSuper ? 'Administrator' : 'Student'),
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSuper
                      ? 'Role: Superuser  |  ID: $_rollNumber'
                      : 'Roll: $_rollNumber  |  Branch: $_userBranch',
                  style: GoogleFonts.plusJakartaSans(
                    color: U.sub,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: theme.primary, size: 20),
            tooltip: 'Update Info',
            onPressed: _showEditStudentInfoSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsWarning() {
    final theme = appThemeNotifier.value;
    if (_studentSubjects.isNotEmpty || _hasPostPermission) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.peach.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.peach.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: theme.peach, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No subjects cached. Connect your portal in the Attendance screen to sync your subjects. Showing all assignments for $_userBranch in the meantime.',
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentList(List<DocumentSnapshot> assignmentsList) {
    if (assignmentsList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.assignment_outlined,
                  color: U.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No Assignments Found',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Great job! There are no assignments listed under this section.',
                style: GoogleFonts.plusJakartaSans(
                  color: U.sub,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Grouping logic
    final Map<String, List<DocumentSnapshot>> grouped = {};

    // If student subjects are fetched, pre-populate them so we display subjects even with 0 assignments
    if (_studentSubjects.isNotEmpty) {
      for (final sub in _studentSubjects) {
        grouped[sub] = [];
      }
    }

    final List<DocumentSnapshot> otherAssignments = [];

    for (final doc in assignmentsList) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final subject = (data['subject'] as String? ?? '').trim();

      // Find matching subject in student subjects (case-insensitive)
      String? matchedSubject;
      if (_studentSubjects.isNotEmpty) {
        for (final sub in _studentSubjects) {
          if (sub.toLowerCase() == subject.toLowerCase() ||
              subject.toLowerCase().contains(sub.toLowerCase()) ||
              sub.toLowerCase().contains(subject.toLowerCase())) {
            matchedSubject = sub;
            break;
          }
        }
      }

      if (matchedSubject != null) {
        grouped[matchedSubject]!.add(doc);
      } else {
        if (_studentSubjects.isNotEmpty) {
          // If we have enrolled subjects but this assignment is for another subject, put in others
          otherAssignments.add(doc);
        } else {
          // If we don't have enrolled subjects, group by the assignment's own subject name
          if (subject.isNotEmpty) {
            grouped.putIfAbsent(subject, () => []).add(doc);
          } else {
            grouped.putIfAbsent('General / Other', () => []).add(doc);
          }
        }
      }
    }

    final List<String> subjectsKeys = grouped.keys.toList();
    // Sort subjects by name
    subjectsKeys.sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: subjectsKeys.length + (otherAssignments.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        final theme = appThemeNotifier.value;

        // Check if this is the "Other Subjects" item at the end
        if (index == subjectsKeys.length) {
          return _buildSubjectGroupCard(
            subjectName: 'Other Subjects',
            assignments: otherAssignments,
            theme: theme,
            isOther: true,
          );
        }

        final subjectName = subjectsKeys[index];
        final subjectAssignments = grouped[subjectName]!;

        return _buildSubjectGroupCard(
          subjectName: subjectName,
          assignments: subjectAssignments,
          theme: theme,
          isOther: false,
        );
      },
    );
  }

  Widget _buildSubjectGroupCard({
    required String subjectName,
    required List<DocumentSnapshot> assignments,
    required dynamic theme,
    required bool isOther,
  }) {
    // Custom subject tag color based on hash or title
    Color subjectColor;
    switch (subjectName.toLowerCase().replaceAll(RegExp(r'\s+'), '')) {
      case 'mathematics':
      case 'maths':
      case 'math':
      case 'm1':
      case 'm2':
      case 'm3':
        subjectColor = theme.blue;
        break;
      case 'operatingsystems':
      case 'os':
        subjectColor = theme.teal;
        break;
      case 'computernetworks':
      case 'cn':
        subjectColor = theme.lavender;
        break;
      case 'dsa':
      case 'datastructures':
        subjectColor = theme.green;
        break;
      default:
        subjectColor = theme.primary;
    }

    final activeCount = assignments.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.primary.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Subject color indicator circle
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: subjectColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    subjectName,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Badge for active count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeCount > 0
                        ? theme.primary.withValues(alpha: 0.08)
                        : U.dim.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    activeCount == 0 ? 'No tasks' : '$activeCount active',
                    style: GoogleFonts.outfit(
                      color: activeCount > 0 ? theme.primary : U.dim,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: U.border.withValues(alpha: 0.3), height: 1, thickness: 0.5),

          // Assignments under this subject
          if (assignments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: theme.green.withValues(alpha: 0.6), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'No pending assignments for this subject.',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.dim,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: assignments.length,
              itemBuilder: (context, index) {
                final doc = assignments[index];
                return _buildAssignmentItemCard(doc, index, subjectColor);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAssignmentItemCard(DocumentSnapshot doc, int index, Color subjectColor) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final id = data['id'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    final desc = data['description'] as String? ?? '';
    final branch = data['branch'] as String? ?? 'All Branches';
    final teacherName = data['teacherName'] as String? ?? 'Administrator';
    final attachmentUrl = data['attachmentUrl'] as String?;
    final attachmentName = data['attachmentName'] as String? ?? 'Attachment';
    final dueDate = (data['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now();

    final now = DateTime.now();
    final isPastDue = dueDate.isBefore(now);
    final difference = dueDate.difference(now);

    String relativeDueText = '';
    if (isPastDue) {
      relativeDueText = 'Past Due';
    } else if (difference.inDays > 0) {
      relativeDueText = 'Due in ${difference.inDays} ${difference.inDays == 1 ? "day" : "days"}';
    } else if (difference.inHours > 0) {
      relativeDueText = 'Due in ${difference.inHours} ${difference.inHours == 1 ? "hour" : "hours"}';
    } else {
      relativeDueText = 'Due in ${difference.inMinutes} mins';
    }

    final theme = appThemeNotifier.value;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: U.border.withValues(alpha: 0.2), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: U.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (branch.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.primary.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    branch,
                    style: GoogleFonts.outfit(
                      color: theme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              // Relative due text
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPastDue
                      ? U.red.withValues(alpha: 0.08)
                      : theme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  relativeDueText,
                  style: GoogleFonts.outfit(
                    color: isPastDue ? U.red : theme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: GoogleFonts.plusJakartaSans(
                color: U.sub,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Attachment Capsule (if attachment exists)
          if (attachmentUrl != null && attachmentUrl.isNotEmpty) ...[
            GestureDetector(
              onTap: () async {
                try {
                  final uri = Uri.parse(attachmentUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  if (mounted) {
                    showUtopiaSnackBar(
                      context,
                      message: 'Could not open link: $e',
                      tone: UtopiaSnackBarTone.error,
                    );
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: U.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: U.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined, color: theme.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        attachmentName,
                        style: GoogleFonts.outfit(
                          color: U.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.open_in_new_rounded, color: U.dim, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Footer Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Posted by $teacherName',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.sub,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due: ${_formatDateTime(dueDate)}',
                      style: GoogleFonts.plusJakartaSans(
                        color: U.dim,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              // Delete button (Only for superusers)
              if (_hasPostPermission)
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: U.red, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _confirmDeleteAssignment(id, title),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
