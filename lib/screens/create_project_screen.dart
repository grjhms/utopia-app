import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/project_model.dart';
import '../services/project_service.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/utopia_snackbar.dart';

/// Multi-step screen to Create or Edit a Project Showcase entry.
class CreateProjectScreen extends StatefulWidget {
  final ProjectModel? existingProject;

  const CreateProjectScreen({
    super.key,
    this.existingProject,
  });

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  int _currentStep = 0;
  bool _isSaving = false;
  String _uploadStatus = '';
  double _uploadProgress = 0.0;

  bool get _isEditing => widget.existingProject != null;

  // Step 1: Basics
  final _titleController = TextEditingController();
  final _taglineController = TextEditingController();
  final _descriptionController = TextEditingController();
  ProjectCategory _selectedCategory = ProjectCategory.app;
  ProjectStatus _selectedStatus = ProjectStatus.inProgress;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _showMarkdownPreview = false;

  // Step 2: Media
  File? _coverFile;
  String? _existingCoverUrl;
  final List<File> _galleryFiles = [];
  final List<String> _existingGalleryUrls = [];
  final ImagePicker _picker = ImagePicker();

  // Step 3: Tech Stack
  final _techController = TextEditingController();
  final List<String> _techStack = [];
  static const List<String> _curatedTechSuggestions = [
    'Flutter', 'Firebase', 'Python', 'React', 'Next.js', 'Node.js',
    'PyTorch', 'TensorFlow', 'OpenCV', 'Rust', 'Go', 'C++',
    'Arduino', 'Raspberry Pi', 'ESP32', 'Figma', 'Tailwind CSS',
    'Supabase', 'Docker', 'GraphQL', 'Swift', 'Kotlin', 'Solidity',
    'SolidWorks', 'Blender', 'Three.js', 'FastAPI', 'Django',
  ];

  // Step 4: Links
  final _githubController = TextEditingController();
  final _demoController = TextEditingController();
  final _videoController = TextEditingController();
  final List<_CustomLinkEntry> _customLinks = [];

  // Step 5: Contributors (wired in Phase 3)
  final List<ProjectContributor> _contributors = [];

  @override
  void initState() {
    super.initState();
    _populateExistingData();
  }

  void _populateExistingData() {
    final p = widget.existingProject;
    if (p != null) {
      _titleController.text = p.title;
      _taglineController.text = p.tagline;
      _descriptionController.text = p.description;
      _selectedCategory = p.category;
      _selectedStatus = p.status;
      _startDate = p.startDate;
      _endDate = p.endDate;

      _existingCoverUrl = p.coverImage;
      _existingGalleryUrls.addAll(p.galleryImages);

      _techStack.addAll(p.techStack);

      _githubController.text = p.links.github ?? '';
      _demoController.text = p.links.liveDemo ?? '';
      _videoController.text = p.links.video ?? '';
      for (final cl in p.links.other) {
        _customLinks.add(_CustomLinkEntry(
          labelController: TextEditingController(text: cl.label),
          urlController: TextEditingController(text: cl.url),
        ));
      }

      _contributors.addAll(p.contributors);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _taglineController.dispose();
    _descriptionController.dispose();
    _techController.dispose();
    _githubController.dispose();
    _demoController.dispose();
    _videoController.dispose();
    for (final cl in _customLinks) {
      cl.dispose();
    }
    super.dispose();
  }

  // ── Step Navigation & Validation ──

  bool _validateStep(int step) {
    switch (step) {
      case 0: // Step 1: Basics
        if (_titleController.text.trim().isEmpty) {
          _showToast('Please enter a project title.');
          return false;
        }
        if (_taglineController.text.trim().isEmpty) {
          _showToast('Please provide a short one-line tagline.');
          return false;
        }
        if (_descriptionController.text.trim().isEmpty) {
          _showToast('Please write a project description.');
          return false;
        }
        return true;

      case 1: // Step 2: Media
        if (_coverFile == null && (_existingCoverUrl == null || _existingCoverUrl!.isEmpty)) {
          _showToast('A cover image is required for your project showcase.');
          return false;
        }
        return true;

      case 2: // Step 3: Tech Stack
        if (_techStack.isEmpty) {
          _showToast('Please add at least 1 technology tag to your tech stack.');
          return false;
        }
        return true;

      case 3: // Step 4: Links
        // Links are optional, but validate format if present
        return true;

      case 4: // Step 5: Contributors
        return true;

      default:
        return true;
    }
  }

  void _nextStep() {
    if (_validateStep(_currentStep)) {
      if (_currentStep < 5) {
        setState(() => _currentStep++);
      } else {
        _submitProject();
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showToast(String msg) {
    showUtopiaSnackBar(
      context,
      message: msg,
      tone: UtopiaSnackBarTone.error,
    );
  }

  // ── Media Pickers ──

  Future<void> _pickCoverImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        _coverFile = File(picked.path);
      });
    }
  }

  Future<void> _pickGalleryImages() async {
    final remainingSlots = 6 - (_existingGalleryUrls.length + _galleryFiles.length);
    if (remainingSlots <= 0) {
      _showToast('Maximum 6 gallery images allowed.');
      return;
    }

    final pickedList = await _picker.pickMultiImage(
      maxWidth: 1920,
      imageQuality: 85,
    );

    if (pickedList.isNotEmpty) {
      setState(() {
        final toAdd = pickedList.take(remainingSlots).map((x) => File(x.path)).toList();
        _galleryFiles.addAll(toAdd);
      });
    }
  }

  // ── Tech Stack Actions ──

  void _addTechTag(String tag) {
    final clean = tag.trim();
    if (clean.isNotEmpty && !_techStack.any((t) => t.toLowerCase() == clean.toLowerCase())) {
      setState(() {
        _techStack.add(clean);
        _techController.clear();
      });
    }
  }

  void _removeTechTag(String tag) {
    setState(() {
      _techStack.removeWhere((t) => t.toLowerCase() == tag.toLowerCase());
    });
  }

  // ── Custom Links Actions ──

  void _addCustomLink() {
    setState(() {
      _customLinks.add(_CustomLinkEntry(
        labelController: TextEditingController(),
        urlController: TextEditingController(),
      ));
    });
  }

  void _removeCustomLink(int index) {
    setState(() {
      _customLinks[index].dispose();
      _customLinks.removeAt(index);
    });
  }

  // ── Publish / Save Project ──

  Future<void> _submitProject() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showToast('You must be signed in.');
      return;
    }

    setState(() {
      _isSaving = true;
      _uploadStatus = 'Preparing project...';
      _uploadProgress = 0.05;
    });

    try {
      // Build ProjectLinks
      final customLinkList = _customLinks
          .where((cl) => cl.labelController.text.trim().isNotEmpty && cl.urlController.text.trim().isNotEmpty)
          .map((cl) => ProjectCustomLink(
                label: cl.labelController.text.trim(),
                url: cl.urlController.text.trim(),
              ))
          .toList();

      final links = ProjectLinks(
        github: _githubController.text.trim().isNotEmpty ? _githubController.text.trim() : null,
        liveDemo: _demoController.text.trim().isNotEmpty ? _demoController.text.trim() : null,
        video: _videoController.text.trim().isNotEmpty ? _videoController.text.trim() : null,
        other: customLinkList,
      );

      // Fetch user university
      String? uniId;
      String? userBranch;
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        uniId = userDoc.data()?['selectedUniversityId'] as String?;
        userBranch = userDoc.data()?['branch'] as String?;
      } catch (_) {}

      final project = ProjectModel(
        id: widget.existingProject?.id ?? '',
        title: _titleController.text.trim(),
        tagline: _taglineController.text.trim(),
        description: _descriptionController.text.trim(),
        coverImage: _existingCoverUrl ?? '',
        galleryImages: _existingGalleryUrls,
        techStack: _techStack,
        category: _selectedCategory,
        status: _selectedStatus,
        links: links,
        ownerId: widget.existingProject?.ownerId ?? user.uid,
        ownerName: widget.existingProject?.ownerName ?? (user.displayName ?? 'Student'),
        ownerPhotoUrl: widget.existingProject?.ownerPhotoUrl ?? user.photoURL,
        ownerBranch: userBranch,
        contributors: _contributors,
        startDate: _startDate,
        endDate: _endDate,
        createdAt: widget.existingProject?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        likesCount: widget.existingProject?.likesCount ?? 0,
        likedByUserIds: widget.existingProject?.likedByUserIds ?? [],
      );

      final projectService = ProjectService();

      if (_isEditing) {
        await projectService.updateProject(
          projectId: widget.existingProject!.id,
          project: project,
          newCoverFile: _coverFile,
          newGalleryFiles: _galleryFiles,
          universityId: uniId,
          onProgress: (msg, p) {
            if (mounted) setState(() { _uploadStatus = msg; _uploadProgress = p; });
          },
        );
        if (mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Project updated successfully! 🎉',
            tone: UtopiaSnackBarTone.success,
          );
          Navigator.of(context).pop();
        }
      } else {
        await projectService.createProject(
          project: project,
          coverFile: _coverFile,
          galleryFiles: _galleryFiles,
          universityId: uniId,
          onProgress: (msg, p) {
            if (mounted) setState(() { _uploadStatus = msg; _uploadProgress = p; });
          },
        );
        if (mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Project published to Showcase! 🚀',
            tone: UtopiaSnackBarTone.success,
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showUtopiaSnackBar(
          context,
          message: 'Error saving project: $e',
          tone: UtopiaSnackBarTone.error,
        );
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
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: _isSaving ? null : _previousStep,
        ),
        title: Text(
          _isEditing ? 'Edit Project' : 'Showcase Project',
          style: GoogleFonts.robotoFlex(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: U.text,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Step ${_currentStep + 1} of 6',
                style: GoogleFonts.robotoFlex(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: U.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isSaving
            ? _buildSavingOverlay()
            : Column(
                children: [
                  // Step Indicator Bar
                  _buildStepProgressBar(),

                  // Step Content
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: _buildCurrentStepContent(),
                    ),
                  ),

                  // Bottom Action Bar
                  _buildBottomActionBar(),
                ],
              ),
      ),
    );
  }

  // ── Step Progress Indicator ──

  Widget _buildStepProgressBar() {
    const stepTitles = ['Basics', 'Media', 'Tech', 'Links', 'Team', 'Preview'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          Row(
            children: List.generate(6, (i) {
              final isCompleted = i < _currentStep;
              final isCurrent = i == _currentStep;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.symmetric(horizontal: i == 0 ? 0 : 3),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? U.primary
                        : (isCurrent ? U.primary.withValues(alpha: 0.8) : U.outlineVariant.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stepTitles[_currentStep],
                style: GoogleFonts.robotoFlex(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: U.primary,
                ),
              ),
              Text(
                _getStepSubtitle(_currentStep),
                style: GoogleFonts.robotoFlex(
                  fontSize: 12,
                  color: U.sub,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getStepSubtitle(int step) {
    switch (step) {
      case 0: return 'Title & Category';
      case 1: return 'Cover & Gallery';
      case 2: return 'Tech Stack Tags';
      case 3: return 'Links & Demos';
      case 4: return 'Contributors';
      case 5: return 'Review & Publish';
      default: return '';
    }
  }

  // ── Step Content Switcher ──

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Basics();
      case 1:
        return _buildStep2Media();
      case 2:
        return _buildStep3TechStack();
      case 3:
        return _buildStep4Links();
      case 4:
        return _buildStep5Contributors();
      case 5:
        return _buildStep6Preview();
      default:
        return const SizedBox.shrink();
    }
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 1: BASICS (Title, Tagline, Category, Status, Description)
  // ════════════════════════════════════════════════════════════════

  Widget _buildStep1Basics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Project Details',
          subtitle: 'Tell the campus about your idea and what problem it solves.',
          icon: Icons.lightbulb_outline_rounded,
        ),
        const SizedBox(height: 18),

        // Title Input
        _buildTextField(
          controller: _titleController,
          label: 'Project Title *',
          hint: 'e.g. Orbit AI - Autonomous Drone Fleet',
          maxLength: 80,
          prefixIcon: Icons.title_rounded,
        ),
        const SizedBox(height: 16),

        // Tagline Input
        _buildTextField(
          controller: _taglineController,
          label: 'One-liner Tagline *',
          hint: 'e.g. Edge computer vision for real-time campus navigation',
          maxLength: 140,
          prefixIcon: Icons.bolt_rounded,
        ),
        const SizedBox(height: 20),

        // Category Selector
        Text(
          'CATEGORY',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProjectCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            return ChoiceChip(
              showCheckmark: false,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getCategoryIcon(cat),
                    size: 15,
                    color: isSelected ? U.getContrastColor(U.primary) : U.sub,
                  ),
                  const SizedBox(width: 6),
                  Text(cat.label),
                ],
              ),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedCategory = cat);
              },
              selectedColor: U.primary,
              backgroundColor: U.card,
              labelStyle: GoogleFonts.robotoFlex(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? U.getContrastColor(U.primary) : U.text,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: M3Shapes.fullRadius,
                side: BorderSide(
                  color: isSelected ? U.primary : U.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Status Selector
        Text(
          'PROJECT STATUS',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProjectStatus.values.map((st) {
            final isSelected = _selectedStatus == st;
            final color = _getStatusColor(st);
            return ChoiceChip(
              showCheckmark: false,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isSelected ? U.getContrastColor(color) : color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(st.label),
                ],
              ),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedStatus = st);
              },
              selectedColor: color,
              backgroundColor: U.card,
              labelStyle: GoogleFonts.robotoFlex(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? U.getContrastColor(color) : U.text,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: M3Shapes.fullRadius,
                side: BorderSide(
                  color: isSelected ? color : U.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Timeline & Dates
        Text(
          'PROJECT TIMELINE',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: U.primary,
                          onPrimary: U.getContrastColor(U.primary),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() => _startDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: U.card,
                    borderRadius: M3Shapes.mediumRadius,
                    border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 16, color: U.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Date',
                              style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _startDate != null ? _formatMonthYear(_startDate!) : 'Select Date',
                              style: GoogleFonts.robotoFlex(fontSize: 13, color: U.text, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? (_startDate ?? DateTime.now()),
                    firstDate: _startDate ?? DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: U.primary,
                          onPrimary: U.getContrastColor(U.primary),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() => _endDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: U.card,
                    borderRadius: M3Shapes.mediumRadius,
                    border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_rounded, size: 16, color: U.peach),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End / Completion',
                              style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedStatus == ProjectStatus.inProgress
                                  ? 'Present (Ongoing)'
                                  : (_endDate != null ? _formatMonthYear(_endDate!) : 'Ongoing'),
                              style: GoogleFonts.robotoFlex(fontSize: 13, color: U.text, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Description with Markdown Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DESCRIPTION (MARKDOWN SUPPORTED) *',
              style: GoogleFonts.robotoFlex(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: U.primary,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _showMarkdownPreview = !_showMarkdownPreview),
              icon: Icon(
                _showMarkdownPreview ? Icons.edit_note_rounded : Icons.visibility_outlined,
                size: 16,
                color: U.primary,
              ),
              label: Text(
                _showMarkdownPreview ? 'Edit' : 'Preview',
                style: GoogleFonts.robotoFlex(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: U.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_showMarkdownPreview)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: U.card,
              borderRadius: M3Shapes.largeRadius,
              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: _descriptionController.text.trim().isEmpty
                ? Center(
                    child: Text(
                      'Nothing to preview yet. Type something in markdown!',
                      style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13),
                    ),
                  )
                : MarkdownBody(
                    data: _descriptionController.text,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: GoogleFonts.robotoFlex(color: U.text, fontSize: 14, height: 1.5),
                      h1: GoogleFonts.robotoFlex(color: U.text, fontSize: 20, fontWeight: FontWeight.w800),
                      h2: GoogleFonts.robotoFlex(color: U.text, fontSize: 17, fontWeight: FontWeight.w700),
                      h3: GoogleFonts.robotoFlex(color: U.text, fontSize: 15, fontWeight: FontWeight.w600),
                      code: GoogleFonts.jetBrainsMono(
                        backgroundColor: U.surfaceContainerHighest,
                        color: U.primary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
          )
        else
          _buildTextField(
            controller: _descriptionController,
            label: 'Project Overview & Details',
            hint: 'Describe architecture, motivation, key features, and future goals...\n\nSupports **bold**, *italics*, bullet points, and links.',
            maxLines: 8,
            alignLabelWithHint: true,
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 2: MEDIA (Hero Cover Image & Gallery Uploads)
  // ════════════════════════════════════════════════════════════════

  Widget _buildStep2Media() {
    final hasCover = _coverFile != null || (_existingCoverUrl != null && _existingCoverUrl!.isNotEmpty);
    final totalGallery = _existingGalleryUrls.length + _galleryFiles.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Media & Visuals',
          subtitle: 'Add a high-quality hero cover and up to 6 gallery screenshots/demos.',
          icon: Icons.photo_library_outlined,
        ),
        const SizedBox(height: 18),

        // Hero Cover Section
        Text(
          'HERO COVER IMAGE *',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 8),

        GestureDetector(
          onTap: _pickCoverImage,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: U.card,
              borderRadius: M3Shapes.cardRadius,
              border: Border.all(
                color: hasCover ? U.primary.withValues(alpha: 0.5) : U.outlineVariant.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: M3Shapes.cardRadius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_coverFile != null)
                    Image.file(_coverFile!, fit: BoxFit.cover)
                  else if (_existingCoverUrl != null && _existingCoverUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: _existingCoverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(child: CircularProgressIndicator(color: U.primary)),
                      errorWidget: (context, url, error) => const Icon(Icons.broken_image_rounded, size: 40),
                    )
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: U.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add_photo_alternate_rounded, size: 32, color: U.primary),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Upload Cover Banner (Required)',
                          style: GoogleFonts.robotoFlex(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: U.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Recommended: 16:9 landscape aspect ratio',
                          style: GoogleFonts.robotoFlex(
                            fontSize: 12,
                            color: U.sub,
                          ),
                        ),
                      ],
                    ),
                  if (hasCover)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: M3Shapes.fullRadius,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Change',
                              style: GoogleFonts.robotoFlex(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
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
        ),
        const SizedBox(height: 28),

        // Gallery Images Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'GALLERY IMAGES ($totalGallery / 6)',
              style: GoogleFonts.robotoFlex(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: U.primary,
              ),
            ),
            if (totalGallery < 6)
              TextButton.icon(
                onPressed: _pickGalleryImages,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Images'),
                style: TextButton.styleFrom(
                  foregroundColor: U.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        if (totalGallery == 0)
          GestureDetector(
            onTap: _pickGalleryImages,
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: U.card.withValues(alpha: 0.6),
                borderRadius: M3Shapes.largeRadius,
                border: Border.all(
                  color: U.outlineVariant.withValues(alpha: 0.4),
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.collections_outlined, size: 28, color: U.sub),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to add screenshots, diagrams, or UI mockups',
                      style: GoogleFonts.robotoFlex(fontSize: 12.5, color: U.sub),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalGallery + (totalGallery < 6 ? 1 : 0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index == totalGallery && totalGallery < 6) {
                return GestureDetector(
                  onTap: _pickGalleryImages,
                  child: Container(
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: M3Shapes.mediumRadius,
                      border: Border.all(color: U.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Center(
                      child: Icon(Icons.add_photo_alternate_outlined, color: U.primary, size: 28),
                    ),
                  ),
                );
              }

              final isExisting = index < _existingGalleryUrls.length;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: M3Shapes.mediumRadius,
                    child: isExisting
                        ? CachedNetworkImage(
                            imageUrl: _existingGalleryUrls[index],
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            _galleryFiles[index - _existingGalleryUrls.length],
                            fit: BoxFit.cover,
                          ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isExisting) {
                            _existingGalleryUrls.removeAt(index);
                          } else {
                            _galleryFiles.removeAt(index - _existingGalleryUrls.length);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 3: TECH STACK (Autocomplete, Suggestions & Custom Tags)
  // ════════════════════════════════════════════════════════════════

  Widget _buildStep3TechStack() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Technologies & Tools',
          subtitle: 'Highlight frameworks, libraries, hardware, and languages used.',
          icon: Icons.code_rounded,
        ),
        const SizedBox(height: 18),

        // Tag Input Field + Add Button
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _techController,
                label: 'Add Tech Tag',
                hint: 'e.g. Flutter, PyTorch, Docker',
                prefixIcon: Icons.tag_rounded,
                onSubmitted: _addTechTag,
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: U.primary,
                shape: RoundedRectangleBorder(borderRadius: M3Shapes.mediumRadius),
                padding: const EdgeInsets.all(14),
              ),
              onPressed: () => _addTechTag(_techController.text),
              icon: Icon(Icons.add_rounded, color: U.getContrastColor(U.primary), size: 22),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Active Selected Tags
        Text(
          'SELECTED STACK (${_techStack.length})',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 10),

        if (_techStack.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: U.card.withValues(alpha: 0.5),
              borderRadius: M3Shapes.mediumRadius,
              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'No tags added yet. Select from suggestions below or type your own.',
                style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12.5),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _techStack.map((tag) {
              return Chip(
                backgroundColor: U.primary.withValues(alpha: 0.14),
                side: BorderSide(color: U.primary.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                label: Text(
                  tag,
                  style: GoogleFonts.robotoFlex(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: U.primary,
                  ),
                ),
                deleteIcon: Icon(Icons.cancel_rounded, size: 16, color: U.primary),
                onDeleted: () => _removeTechTag(tag),
              );
            }).toList(),
          ),
        const SizedBox(height: 28),

        // Suggested Popular Tags
        Text(
          'POPULAR SUGGESTIONS',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.sub,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _curatedTechSuggestions.map((sug) {
            final isAdded = _techStack.any((t) => t.toLowerCase() == sug.toLowerCase());
            return ActionChip(
              avatar: isAdded
                  ? Icon(Icons.check_rounded, size: 14, color: U.getContrastColor(U.primary))
                  : const Icon(Icons.add_rounded, size: 14, color: null),
              label: Text(sug),
              backgroundColor: isAdded ? U.primary : U.card,
              labelStyle: GoogleFonts.robotoFlex(
                fontSize: 12,
                fontWeight: isAdded ? FontWeight.w700 : FontWeight.w500,
                color: isAdded ? U.getContrastColor(U.primary) : U.text,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: M3Shapes.fullRadius,
                side: BorderSide(
                  color: isAdded ? U.primary : U.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              onPressed: () {
                if (isAdded) {
                  _removeTechTag(sug);
                } else {
                  _addTechTag(sug);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 4: LINKS (GitHub, Live Demo, Video & Custom Extensible Links)
  // ════════════════════════════════════════════════════════════════

  Widget _buildStep4Links() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Project Links & Demos',
          subtitle: 'Connect your repository, live deployment, presentation video, or documentation.',
          icon: Icons.link_rounded,
        ),
        const SizedBox(height: 18),

        // GitHub Repository
        _buildTextField(
          controller: _githubController,
          label: 'GitHub Repository URL',
          hint: 'https://github.com/username/project',
          prefixIcon: Icons.code_rounded,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),

        // Live Demo / Website
        _buildTextField(
          controller: _demoController,
          label: 'Live Demo / Website URL',
          hint: 'https://myproject.app or https://huggingface.co/...',
          prefixIcon: Icons.launch_rounded,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),

        // Video / Presentation Link
        _buildTextField(
          controller: _videoController,
          label: 'Video Demo / Walkthrough URL',
          hint: 'https://youtube.com/watch?v=... or Loom / Drive link',
          prefixIcon: Icons.play_circle_outline_rounded,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 28),

        // Dynamic Custom Links Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CUSTOM LINKS',
              style: GoogleFonts.robotoFlex(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: U.primary,
              ),
            ),
            TextButton.icon(
              onPressed: _addCustomLink,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Custom Link'),
              style: TextButton.styleFrom(
                foregroundColor: U.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_customLinks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: U.card.withValues(alpha: 0.5),
              borderRadius: M3Shapes.mediumRadius,
              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'Add custom links like Figma mockups, Research Paper PDFs, or App Store URLs.',
                style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _customLinks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final cl = _customLinks[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: M3Shapes.largeRadius,
                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: cl.labelController,
                            label: 'Label',
                            hint: 'e.g. Figma Design',
                            dense: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: U.red, size: 20),
                          onPressed: () => _removeCustomLink(index),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: cl.urlController,
                      label: 'URL',
                      hint: 'https://...',
                      dense: true,
                      keyboardType: TextInputType.url,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 5: CONTRIBUTORS (Search & Role Assignment)
  // ════════════════════════════════════════════════════════════════

  Widget _buildStep5Contributors() {
    final user = FirebaseAuth.instance.currentUser;
    final ownerName = widget.existingProject?.ownerName ?? (user?.displayName ?? 'You');
    final ownerPhoto = widget.existingProject?.ownerPhotoUrl ?? user?.photoURL;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Project Contributors',
          subtitle: 'Search and tag collaborators, assign specific roles, and share credit.',
          icon: Icons.people_alt_outlined,
        ),
        const SizedBox(height: 18),

        // Owner Card (Lead / Creator)
        Text(
          'PROJECT CREATOR & LEAD',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: M3Shapes.largeRadius,
            border: Border.all(color: U.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: U.primary.withValues(alpha: 0.15),
                backgroundImage: ownerPhoto != null && ownerPhoto.isNotEmpty
                    ? CachedNetworkImageProvider(ownerPhoto)
                    : null,
                child: ownerPhoto == null || ownerPhoto.isEmpty
                    ? Text(
                        ownerName.isNotEmpty ? ownerName[0].toUpperCase() : 'U',
                        style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w700, color: U.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: GoogleFonts.robotoFlex(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: U.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Primary Owner & Publisher',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 12,
                        color: U.sub,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.12),
                  borderRadius: M3Shapes.fullRadius,
                  border: Border.all(color: U.primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Owner',
                  style: GoogleFonts.robotoFlex(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: U.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Teammates Header + Add Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TEAMMATES & CONTRIBUTORS (${_contributors.length})',
              style: GoogleFonts.robotoFlex(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: U.primary,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _openAddContributorModal,
              icon: Icon(Icons.person_add_alt_1_rounded, size: 16, color: U.getContrastColor(U.primary)),
              label: Text(
                'Add Teammate',
                style: GoogleFonts.robotoFlex(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: U.getContrastColor(U.primary),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: U.primary,
                foregroundColor: U.getContrastColor(U.primary),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_contributors.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: U.card.withValues(alpha: 0.5),
              borderRadius: M3Shapes.largeRadius,
              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(Icons.groups_outlined, size: 36, color: U.sub),
                const SizedBox(height: 8),
                Text(
                  'Solo project or built with a team?',
                  style: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.w600, color: U.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap "Add Teammate" to search campus peers and assign roles (e.g., UI/UX, Backend, Hardware).',
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
            itemCount: _contributors.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final c = _contributors[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: M3Shapes.largeRadius,
                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: U.peach.withValues(alpha: 0.15),
                          backgroundImage: c.photoUrl != null && c.photoUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(c.photoUrl!)
                              : null,
                          child: c.photoUrl == null || c.photoUrl!.isEmpty
                              ? Text(
                                  c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                                  style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w700, color: U.peach),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: GoogleFonts.robotoFlex(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: U.text,
                                ),
                              ),
                              if (c.branch != null && c.branch!.isNotEmpty)
                                Text(
                                  c.branch!,
                                  style: GoogleFonts.robotoFlex(fontSize: 11.5, color: U.sub),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline_rounded, color: U.red, size: 20),
                          tooltip: 'Remove contributor',
                          onPressed: () {
                            setState(() {
                              _contributors.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Role Input
                    TextField(
                      controller: TextEditingController(text: c.role)
                        ..selection = TextSelection.collapsed(offset: (c.role ?? '').length),
                      onChanged: (val) {
                        _contributors[index] = c.copyWith(role: val.trim());
                      },
                      style: GoogleFonts.robotoFlex(fontSize: 13, color: U.text),
                      decoration: InputDecoration(
                        labelText: 'Role / Contribution',
                        hintText: 'e.g. Lead Designer, Backend, ML Research',
                        hintStyle: GoogleFonts.robotoFlex(fontSize: 12.5, color: U.dim),
                        labelStyle: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub),
                        filled: true,
                        fillColor: U.surfaceContainerHigh,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: M3Shapes.mediumRadius,
                          borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: M3Shapes.mediumRadius,
                          borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: M3Shapes.mediumRadius,
                          borderSide: BorderSide(color: U.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  void _openAddContributorModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddContributorSheet(
        alreadyAddedIds: {
          FirebaseAuth.instance.currentUser?.uid ?? '',
          ..._contributors.map((c) => c.userId),
        },
        onContributorSelected: (contrib) {
          setState(() {
            _contributors.add(contrib);
          });
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 6: PREVIEW (Interactive Live Detail View)
  // ════════════════════════════════════════════════════════════════

  Widget _buildStep6Preview() {
    final user = FirebaseAuth.instance.currentUser;
    final ownerName = widget.existingProject?.ownerName ?? (user?.displayName ?? 'You');
    final ownerPhoto = widget.existingProject?.ownerPhotoUrl ?? user?.photoURL;
    final hasCover = _coverFile != null || (_existingCoverUrl != null && _existingCoverUrl!.isNotEmpty);
    final allGallery = [..._existingGalleryUrls, ..._galleryFiles.map((f) => f.path)];

    final customLinkList = _customLinks
        .where((cl) => cl.labelController.text.trim().isNotEmpty && cl.urlController.text.trim().isNotEmpty)
        .map((cl) => ProjectCustomLink(
              label: cl.labelController.text.trim(),
              url: cl.urlController.text.trim(),
            ))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview Header Notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: U.teal.withValues(alpha: 0.12),
            borderRadius: M3Shapes.mediumRadius,
            border: Border.all(color: U.teal.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.remove_red_eye_rounded, size: 18, color: U.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This preview shows how your project will look on the campus feed and detail view.',
                  style: GoogleFonts.robotoFlex(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: U.teal,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Hero Cover Banner
        if (hasCover)
          Container(
            height: 210,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: M3Shapes.cardRadius,
              color: U.card,
              border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: M3Shapes.cardRadius,
              child: _coverFile != null
                  ? Image.file(_coverFile!, fit: BoxFit.cover)
                  : CachedNetworkImage(imageUrl: _existingCoverUrl!, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 16),

        // Category & Status Badges
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.15),
                borderRadius: M3Shapes.fullRadius,
                border: Border.all(color: U.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getCategoryIcon(_selectedCategory), size: 14, color: U.primary),
                  const SizedBox(width: 5),
                  Text(
                    _selectedCategory.label,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: U.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _getStatusColor(_selectedStatus).withValues(alpha: 0.15),
                borderRadius: M3Shapes.fullRadius,
                border: Border.all(color: _getStatusColor(_selectedStatus).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _getStatusColor(_selectedStatus),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedStatus.label,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _getStatusColor(_selectedStatus),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Title & Tagline
        Text(
          _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : 'Untitled Project',
          style: GoogleFonts.robotoFlex(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: U.text,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _taglineController.text.trim().isNotEmpty ? _taglineController.text.trim() : 'No tagline provided',
          style: GoogleFonts.robotoFlex(
            fontSize: 14,
            color: U.sub,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),

        // Creator Profile Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: M3Shapes.largeRadius,
            border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: U.primary.withValues(alpha: 0.15),
                backgroundImage: ownerPhoto != null && ownerPhoto.isNotEmpty
                    ? CachedNetworkImageProvider(ownerPhoto)
                    : null,
                child: ownerPhoto == null || ownerPhoto.isEmpty
                    ? Text(
                        ownerName.isNotEmpty ? ownerName[0].toUpperCase() : 'U',
                        style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w700, color: U.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: GoogleFonts.robotoFlex(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: U.text,
                      ),
                    ),
                    Text(
                      'Project Creator',
                      style: GoogleFonts.robotoFlex(fontSize: 11.5, color: U.sub),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: U.red.withValues(alpha: 0.1),
                  borderRadius: M3Shapes.fullRadius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_rounded, size: 14, color: U.red),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.existingProject?.likesCount ?? 0}',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: U.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tech Stack
        if (_techStack.isNotEmpty) ...[
          Text(
            'TECH STACK',
            style: GoogleFonts.robotoFlex(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: U.primary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _techStack.map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: M3Shapes.fullRadius,
                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text(
                  t,
                  style: GoogleFonts.robotoFlex(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: U.text,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Links Section
        if (_githubController.text.trim().isNotEmpty ||
            _demoController.text.trim().isNotEmpty ||
            _videoController.text.trim().isNotEmpty ||
            customLinkList.isNotEmpty) ...[
          Text(
            'LINKS & RESOURCES',
            style: GoogleFonts.robotoFlex(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: U.primary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_githubController.text.trim().isNotEmpty)
                _buildLinkPill(
                  icon: Icons.code_rounded,
                  label: 'GitHub',
                  color: U.primary,
                ),
              if (_demoController.text.trim().isNotEmpty)
                _buildLinkPill(
                  icon: Icons.launch_rounded,
                  label: 'Live Demo',
                  color: U.teal,
                ),
              if (_videoController.text.trim().isNotEmpty)
                _buildLinkPill(
                  icon: Icons.play_arrow_rounded,
                  label: 'Video Demo',
                  color: U.peach,
                ),
              for (final cl in customLinkList)
                _buildLinkPill(
                  icon: Icons.link_rounded,
                  label: cl.label,
                  color: U.lavender,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        // Gallery Strip
        if (allGallery.isNotEmpty) ...[
          Text(
            'GALLERY (${allGallery.length})',
            style: GoogleFonts.robotoFlex(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: U.primary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: allGallery.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = allGallery[index];
                return ClipRRect(
                  borderRadius: M3Shapes.mediumRadius,
                  child: Container(
                    width: 150,
                    color: U.card,
                    child: item.startsWith('http')
                        ? CachedNetworkImage(imageUrl: item, fit: BoxFit.cover)
                        : Image.file(File(item), fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Contributors Section
        if (_contributors.isNotEmpty) ...[
          Text(
            'CONTRIBUTORS (${_contributors.length})',
            style: GoogleFonts.robotoFlex(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: U.primary,
            ),
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _contributors.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final c = _contributors[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: M3Shapes.mediumRadius,
                  border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: U.peach.withValues(alpha: 0.15),
                      backgroundImage: c.photoUrl != null && c.photoUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(c.photoUrl!)
                          : null,
                      child: c.photoUrl == null || c.photoUrl!.isEmpty
                          ? Text(
                              c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                              style: GoogleFonts.robotoFlex(fontSize: 11, fontWeight: FontWeight.w700, color: U.peach),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.name,
                        style: GoogleFonts.robotoFlex(fontSize: 13, fontWeight: FontWeight.w600, color: U.text),
                      ),
                    ),
                    if (c.role != null && c.role!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: U.surfaceContainerHighest,
                          borderRadius: M3Shapes.fullRadius,
                        ),
                        child: Text(
                          c.role!,
                          style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],

        // Markdown Description
        Text(
          'ABOUT PROJECT',
          style: GoogleFonts.robotoFlex(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: U.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: M3Shapes.largeRadius,
            border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: MarkdownBody(
            data: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : 'No description provided.',
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: GoogleFonts.robotoFlex(color: U.text, fontSize: 14, height: 1.5),
              h1: GoogleFonts.robotoFlex(color: U.text, fontSize: 20, fontWeight: FontWeight.w800),
              h2: GoogleFonts.robotoFlex(color: U.text, fontSize: 17, fontWeight: FontWeight.w700),
              h3: GoogleFonts.robotoFlex(color: U.text, fontSize: 15, fontWeight: FontWeight.w600),
              code: GoogleFonts.jetBrainsMono(
                backgroundColor: U.surfaceContainerHighest,
                color: U.primary,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: M3Shapes.fullRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.robotoFlex(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }


  // ── Bottom Action Bar ──

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: U.surfaceContainerHigh,
        border: Border(top: BorderSide(color: U.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton.icon(
              onPressed: _previousStep,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: U.text,
                side: BorderSide(color: U.outlineVariant.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: M3Shapes.mediumRadius),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _nextStep,
              icon: Icon(
                _currentStep == 5 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                size: 18,
                color: U.getContrastColor(U.primary),
              ),
              label: Text(
                _currentStep == 5
                    ? (_isEditing ? 'Save Changes' : 'Publish Project')
                    : 'Continue',
                style: GoogleFonts.robotoFlex(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: U.getContrastColor(U.primary),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: U.primary,
                foregroundColor: U.getContrastColor(U.primary),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: M3Shapes.mediumRadius),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Saving / Upload Overlay ──

  Widget _buildSavingOverlay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                color: U.primary,
                strokeWidth: 4,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _uploadStatus,
              style: GoogleFonts.robotoFlex(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: U.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Uploading project visuals to Cloudinary and publishing...',
              style: GoogleFonts.robotoFlex(
                fontSize: 13,
                color: U.sub,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable Component Helpers ──

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: U.primary.withValues(alpha: 0.12),
            borderRadius: M3Shapes.mediumRadius,
          ),
          child: Icon(icon, color: U.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.robotoFlex(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: U.text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.robotoFlex(
                  fontSize: 12.5,
                  color: U.sub,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? prefixIcon,
    int maxLines = 1,
    int? maxLength,
    bool alignLabelWithHint = false,
    bool dense = false,
    TextInputType? keyboardType,
    void Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.robotoFlex(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: U.text,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
          style: GoogleFonts.robotoFlex(
            fontSize: 14,
            color: U.text,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.robotoFlex(fontSize: 13, color: U.dim),
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: U.sub) : null,
            filled: true,
            fillColor: U.card,
            isDense: dense,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 14 : (dense ? 10 : 14),
            ),
            alignLabelWithHint: alignLabelWithHint,
            counterStyle: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub),
            border: OutlineInputBorder(
              borderRadius: M3Shapes.mediumRadius,
              borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: M3Shapes.mediumRadius,
              borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: M3Shapes.mediumRadius,
              borderSide: BorderSide(color: U.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getCategoryIcon(ProjectCategory cat) {
    switch (cat) {
      case ProjectCategory.app: return Icons.phone_android_rounded;
      case ProjectCategory.hardware: return Icons.memory_rounded;
      case ProjectCategory.research: return Icons.science_outlined;
      case ProjectCategory.design: return Icons.palette_outlined;
      case ProjectCategory.hackathon: return Icons.emoji_events_outlined;
      case ProjectCategory.other: return Icons.auto_awesome_outlined;
    }
  }

  Color _getStatusColor(ProjectStatus st) {
    switch (st) {
      case ProjectStatus.inProgress: return U.peach;
      case ProjectStatus.completed: return U.green;
      case ProjectStatus.lookingForTeammates: return U.teal;
    }
  }

  String _formatMonthYear(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _CustomLinkEntry {
  final TextEditingController labelController;
  final TextEditingController urlController;

  _CustomLinkEntry({
    required this.labelController,
    required this.urlController,
  });

  void dispose() {
    labelController.dispose();
    urlController.dispose();
  }
}

/// Bottom Sheet for searching and adding campus peers as contributors.
class _AddContributorSheet extends StatefulWidget {
  final Set<String> alreadyAddedIds;
  final void Function(ProjectContributor) onContributorSelected;

  const _AddContributorSheet({
    required this.alreadyAddedIds,
    required this.onContributorSelected,
  });

  @override
  State<_AddContributorSheet> createState() => _AddContributorSheetState();
}

class _AddContributorSheetState extends State<_AddContributorSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75 + (bottomInset > 0 ? bottomInset : 0),
      decoration: BoxDecoration(
        color: U.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: U.outlineVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.person_search_rounded, color: U.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Teammates',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: U.text,
                        ),
                      ),
                      Text(
                        'Search students across campus to collaborate',
                        style: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: U.sub,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: M3Shapes.fullRadius,
                border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: U.sub, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: false,
                      style: GoogleFonts.robotoFlex(fontSize: 13.5, color: U.text),
                      decoration: InputDecoration(
                        hintText: 'Search by name, branch, roll number...',
                        hintStyle: GoogleFonts.robotoFlex(fontSize: 13, color: U.dim),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => _searchCtrl.clear(),
                      child: Icon(Icons.clear_rounded, size: 18, color: U.sub),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // User Results Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: U.primary));
                }

                final docs = snapshot.data?.docs ?? [];
                final filtered = docs.where((d) {
                  final uid = d.id;
                  if (widget.alreadyAddedIds.contains(uid)) return false;

                  final data = d.data();
                  final name = (data['displayName'] ?? '').toString().toLowerCase();
                  final branch = (data['branch'] ?? '').toString().toLowerCase();
                  final roll = (data['rollNumber'] ?? '').toString().toLowerCase();

                  if (_searchQuery.isEmpty) return true;
                  return name.contains(_searchQuery) ||
                      branch.contains(_searchQuery) ||
                      roll.contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off_outlined, size: 36, color: U.sub),
                          const SizedBox(height: 10),
                          Text(
                            _searchQuery.isEmpty ? 'No other users found.' : 'No students found matching "$_searchQuery".',
                            style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final d = filtered[index];
                    final data = d.data();
                    final uid = d.id;
                    final name = (data['displayName'] ?? 'Student').toString();
                    final branch = (data['branch'] ?? '').toString();
                    final photoUrl = (data['photoUrl'] ?? data['photoURL'])?.toString();

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: M3Shapes.largeRadius,
                        border: Border.all(color: U.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: U.primary.withValues(alpha: 0.15),
                            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(photoUrl)
                                : null,
                            child: photoUrl == null || photoUrl.isEmpty
                                ? Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                    style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w700, color: U.primary),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.robotoFlex(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: U.text,
                                  ),
                                ),
                                if (branch.isNotEmpty)
                                  Text(
                                    branch,
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 11.5,
                                      color: U.sub,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              final contributor = ProjectContributor(
                                userId: uid,
                                name: name,
                                photoUrl: photoUrl,
                                branch: branch.isNotEmpty ? branch : null,
                                role: '',
                              );
                              widget.onContributorSelected(contributor);
                              Navigator.of(context).pop();
                            },
                            icon: Icon(Icons.add_rounded, size: 16, color: U.getContrastColor(U.primary)),
                            label: Text(
                              'Add',
                              style: GoogleFonts.robotoFlex(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: U.getContrastColor(U.primary),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: U.primary,
                              foregroundColor: U.getContrastColor(U.primary),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: M3Shapes.fullRadius),
                              elevation: 0,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

