import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../models/honest_review_model.dart';
import '../services/honest_review_service.dart';
import '../utils/review_content_filter.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import 'profile_screen.dart'; // contains kBTechBranches

class ComposeHonestReviewScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  final HonestReview? existingReview;

  const ComposeHonestReviewScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    this.existingReview,
  });

  @override
  State<ComposeHonestReviewScreen> createState() => _ComposeHonestReviewScreenState();
}

class _ComposeHonestReviewScreenState extends State<ComposeHonestReviewScreen> {
  final HonestReviewService _reviewService = HonestReviewService();
  final _commentController = TextEditingController();

  bool _isHosteller = false;
  bool _wouldChooseAgain = true;
  ReviewDisplayMode _displayMode = ReviewDisplayMode.anonymous;

  // Ratings 1-5 (0 means skipped/optional)
  int _ratingAcademics = 4;
  int _ratingFaculty = 4;
  int _ratingInfra = 4;
  int _ratingPlacements = 4;
  int _ratingCampusLife = 4;
  int _ratingHostel = 0;

  String? _selectedYear;
  String? _selectedBranch;
  bool _includeContextTags = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _yearOptions = ['1st year', '2nd year', '3rd year', 'Final year'];

  @override
  void initState() {
    super.initState();
    if (widget.existingReview != null) {
      final r = widget.existingReview!;
      _isHosteller = r.isHosteller;
      _wouldChooseAgain = r.wouldChooseAgain;
      _displayMode = r.displayMode;
      _commentController.text = r.comment;

      _ratingAcademics = r.subRatings['academics'] ?? 4;
      _ratingFaculty = r.subRatings['faculty'] ?? 4;
      _ratingInfra = r.subRatings['infrastructure'] ?? 4;
      _ratingPlacements = r.subRatings['placements'] ?? 4;
      _ratingCampusLife = r.subRatings['campusLife'] ?? 4;
      _ratingHostel = r.subRatings['hostel'] ?? 0;

      _selectedYear = r.contextTags['year'];
      _selectedBranch = r.contextTags['branch'];
      _includeContextTags = _selectedYear != null || _selectedBranch != null;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Map<String, int> get _currentSubRatings {
    final Map<String, int> ratings = {
      'academics': _ratingAcademics,
      'faculty': _ratingFaculty,
      'infrastructure': _ratingInfra,
      'placements': _ratingPlacements,
      'campusLife': _ratingCampusLife,
    };
    if (_isHosteller) {
      ratings['hostel'] = _ratingHostel;
    }
    return ratings;
  }

  double get _computedOverall => HonestReview.calculateOverallRating(_currentSubRatings);

  String? get _commentLengthValidationMessage {
    return ReviewContentFilter.validateCommentLength(
      _currentSubRatings,
      _commentController.text,
      minWords: 20,
    );
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _errorMessage = null;
    });

    final commentText = _commentController.text.trim();

    if (commentText.isNotEmpty) {
      final lengthError = _commentLengthValidationMessage;
      if (lengthError != null) {
        setState(() => _errorMessage = lengthError);
        showUtopiaSnackBar(
          context,
          message: lengthError,
          tone: UtopiaSnackBarTone.error,
        );
        return;
      }

      final filter = ReviewContentFilter.analyzeText(commentText);
      if (filter.containsProfanity) {
        final msg = filter.flaggedReason ?? 'Comment contains prohibited language.';
        setState(() => _errorMessage = msg);
        showUtopiaSnackBar(
          context,
          message: msg,
          tone: UtopiaSnackBarTone.error,
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final Map<String, String> contextTags = {};
      if (_includeContextTags) {
        if (_selectedYear != null && _selectedYear!.isNotEmpty) {
          contextTags['year'] = _selectedYear!;
        }
        if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
          contextTags['branch'] = _selectedBranch!;
        }
      }
      contextTags['living'] = _isHosteller ? 'Hosteller' : 'Day Scholar';

      final review = await _reviewService.submitOrUpdateReview(
        collegeId: widget.collegeId,
        displayMode: _displayMode,
        subRatings: _currentSubRatings,
        isHosteller: _isHosteller,
        wouldChooseAgain: _wouldChooseAgain,
        comment: commentText,
        contextTags: contextTags,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (review != null && review.status == ReviewStatus.pending) {
        showUtopiaSnackBar(
          context,
          message: 'Review submitted! It contains a named reference and is currently under moderator review.',
          tone: UtopiaSnackBarTone.info,
        );
      } else {
        showUtopiaSnackBar(
          context,
          message: widget.existingReview != null ? 'Review updated successfully!' : 'Review submitted successfully!',
          tone: UtopiaSnackBarTone.success,
        );
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Error submitting review: $e');
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        setState(() {
          _isSubmitting = false;
          _errorMessage = errorMsg;
        });
        showUtopiaSnackBar(
          context,
          message: 'Failed to submit: $errorMsg',
          tone: UtopiaSnackBarTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, child) {
        final primaryColor = U.peach;

        return Scaffold(
          backgroundColor: U.bg,
          appBar: AppBar(
            backgroundColor: U.bg,
            foregroundColor: U.text,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              widget.existingReview != null ? 'Edit Review' : 'Rate & Review',
              style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w700, fontSize: 20, color: U.text),
            ),
          ),
          body: _isSubmitting
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const UtopiaLoader(scale: 0.8),
                      const SizedBox(height: 12),
                      Text('Submitting your review...', style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // College Name & Overall Score Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: M3Shapes.cardRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              widget.collegeName,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.robotoFlex(
                                color: U.text,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  _computedOverall.toStringAsFixed(1),
                                  style: GoogleFonts.robotoFlex(
                                    color: primaryColor,
                                    fontSize: 48,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  ' / 5',
                                  style: GoogleFonts.robotoFlex(
                                    color: U.sub,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Overall Derived Rating',
                              style: GoogleFonts.robotoFlex(
                                color: U.sub,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Question 1: Hostel Status
                      _buildSectionHeader('1. Accommodation Status'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: M3Shapes.largeRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Do you live in the hostel?',
                              style: GoogleFonts.robotoFlex(fontSize: 15, fontWeight: FontWeight.w600, color: U.text),
                            ),
                            Switch.adaptive(
                              value: _isHosteller,
                              activeTrackColor: primaryColor,
                              activeColor: U.getContrastColor(primaryColor),
                              inactiveTrackColor: U.sub.withValues(alpha: 0.2),
                              inactiveThumbColor: U.sub,
                              trackOutlineColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Colors.transparent
                                    : U.sub.withValues(alpha: 0.4),
                              ),
                              onChanged: (val) {
                                setState(() => _isHosteller = val);
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Question 2: Sub-category Ratings (1-5 Stars, Tap to Skip)
                      _buildSectionHeader('2. Rate Categories (1 - 5 Stars)'),
                      const SizedBox(height: 6),
                      Text(
                        'Tap stars to set rating. Tap selected star again to skip category.',
                        style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
                      ),
                      const SizedBox(height: 12),

                      _buildStarRatingPicker(
                        title: 'Academics & Curriculum',
                        icon: Icons.school_rounded,
                        value: _ratingAcademics,
                        onChanged: (v) => setState(() => _ratingAcademics = v),
                      ),
                      _buildStarRatingPicker(
                        title: 'Faculty & Teaching Quality',
                        icon: Icons.person_rounded,
                        value: _ratingFaculty,
                        onChanged: (v) => setState(() => _ratingFaculty = v),
                      ),
                      _buildStarRatingPicker(
                        title: 'Infrastructure & Labs',
                        icon: Icons.business_rounded,
                        value: _ratingInfra,
                        onChanged: (v) => setState(() => _ratingInfra = v),
                      ),
                      _buildStarRatingPicker(
                        title: 'Placements & Career Support',
                        icon: Icons.work_rounded,
                        value: _ratingPlacements,
                        onChanged: (v) => setState(() => _ratingPlacements = v),
                      ),
                      _buildStarRatingPicker(
                        title: 'Campus Life & Extracurriculars',
                        icon: Icons.festival_rounded,
                        value: _ratingCampusLife,
                        onChanged: (v) => setState(() => _ratingCampusLife = v),
                      ),

                      if (_isHosteller)
                        _buildStarRatingPicker(
                          title: 'Hostel & Food Quality',
                          icon: Icons.hotel_rounded,
                          value: _ratingHostel,
                          onChanged: (v) => setState(() => _ratingHostel = v),
                        ),

                      const SizedBox(height: 24),

                      // Question 3: Would Choose Again
                      _buildSectionHeader('3. Overall Satisfaction'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: M3Shapes.largeRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Would you choose this college again?',
                                style: GoogleFonts.robotoFlex(fontSize: 15, fontWeight: FontWeight.w600, color: U.text),
                              ),
                            ),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment<bool>(value: true, label: Text('Yes')),
                                ButtonSegment<bool>(value: false, label: Text('No')),
                              ],
                              selected: {_wouldChooseAgain},
                              onSelectionChanged: (val) {
                                setState(() => _wouldChooseAgain = val.first);
                              },
                              style: SegmentedButton.styleFrom(
                                backgroundColor: U.card,
                                selectedBackgroundColor: primaryColor,
                                foregroundColor: U.text,
                                selectedForegroundColor: U.getContrastColor(primaryColor),
                                side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Question 4: Comment Box (Optional)
                      _buildSectionHeader('4. Detailed Review (Optional)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        maxLines: 4,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.robotoFlex(fontSize: 14, color: U.text),
                        decoration: InputDecoration(
                          hintText: 'Optional: Share your genuine experience about faculty, placements, campus life...',
                          hintStyle: GoogleFonts.robotoFlex(color: U.sub),
                          filled: true,
                          fillColor: U.card,
                          border: OutlineInputBorder(
                            borderRadius: M3Shapes.largeRadius,
                            borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: M3Shapes.largeRadius,
                            borderSide: BorderSide(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: M3Shapes.largeRadius,
                            borderSide: BorderSide(color: primaryColor, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Dynamic length requirement notification if triggered
                      if (_commentLengthValidationMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            _commentLengthValidationMessage!,
                            style: GoogleFonts.robotoFlex(color: Colors.amber.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // Question 5: Reviewer Context Tags
                      _buildSectionHeader('5. Reviewer Context (Optional)'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: M3Shapes.largeRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Include Year & Branch in review',
                                    style: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.w600, color: U.text),
                                  ),
                                  Text(
                                    'Allows students to filter reviews by department',
                                    style: GoogleFonts.robotoFlex(fontSize: 11.5, color: U.sub),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _includeContextTags,
                              activeTrackColor: primaryColor,
                              activeColor: U.getContrastColor(primaryColor),
                              inactiveTrackColor: U.sub.withValues(alpha: 0.2),
                              inactiveThumbColor: U.sub,
                              trackOutlineColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Colors.transparent
                                    : U.sub.withValues(alpha: 0.4),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _includeContextTags = val;
                                  if (!val) {
                                    _selectedYear = null;
                                    _selectedBranch = null;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      if (_includeContextTags) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                isExpanded: true,
                                value: _selectedYear,
                                dropdownColor: U.card,
                                style: TextStyle(color: U.text),
                                decoration: InputDecoration(
                                  labelText: 'Year',
                                  labelStyle: GoogleFonts.robotoFlex(fontSize: 13, color: U.sub),
                                  filled: true,
                                  fillColor: U.card,
                                  border: OutlineInputBorder(borderRadius: M3Shapes.largeRadius),
                                  suffixIcon: _selectedYear != null
                                      ? IconButton(
                                          icon: const Icon(Icons.cancel_rounded, size: 18),
                                          color: U.sub,
                                          onPressed: () => setState(() => _selectedYear = null),
                                          tooltip: 'Clear Year',
                                        )
                                      : null,
                                ),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('None (Clear)', style: GoogleFonts.robotoFlex(fontSize: 13, color: Colors.red.shade400)),
                                  ),
                                  ..._yearOptions.map(
                                    (y) => DropdownMenuItem<String?>(
                                      value: y,
                                      child: Text(y, style: GoogleFonts.robotoFlex(fontSize: 13, color: U.text), overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => setState(() => _selectedYear = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                isExpanded: true,
                                value: _selectedBranch,
                                hint: Text('Branch', style: GoogleFonts.robotoFlex(fontSize: 13, color: U.sub), overflow: TextOverflow.ellipsis),
                                dropdownColor: U.card,
                                style: TextStyle(color: U.text),
                                decoration: InputDecoration(
                                  labelText: 'Branch',
                                  labelStyle: GoogleFonts.robotoFlex(fontSize: 13, color: U.sub),
                                  filled: true,
                                  fillColor: U.card,
                                  border: OutlineInputBorder(borderRadius: M3Shapes.largeRadius),
                                  suffixIcon: _selectedBranch != null
                                      ? IconButton(
                                          icon: const Icon(Icons.cancel_rounded, size: 18),
                                          color: U.sub,
                                          onPressed: () => setState(() => _selectedBranch = null),
                                          tooltip: 'Clear Branch',
                                        )
                                      : null,
                                ),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('None (Clear)', style: GoogleFonts.robotoFlex(fontSize: 13, color: Colors.red.shade400)),
                                  ),
                                  ...kBTechBranches.map(
                                    (b) => DropdownMenuItem<String?>(
                                      value: b,
                                      child: Text(b, style: GoogleFonts.robotoFlex(fontSize: 13, color: U.text), overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => setState(() => _selectedBranch = v),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Anonymity Settings
                      _buildSectionHeader('6. Display Mode & Privacy'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: M3Shapes.largeRadius,
                          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<ReviewDisplayMode>(
                              segments: const [
                                ButtonSegment<ReviewDisplayMode>(
                                  value: ReviewDisplayMode.anonymous,
                                  label: Text('Post Anonymously'),
                                  icon: Icon(Icons.security_rounded),
                                ),
                                ButtonSegment<ReviewDisplayMode>(
                                  value: ReviewDisplayMode.public,
                                  label: Text('Post Publicly'),
                                  icon: Icon(Icons.person_rounded),
                                ),
                              ],
                              selected: {_displayMode},
                              onSelectionChanged: (val) {
                                setState(() => _displayMode = val.first);
                              },
                              style: SegmentedButton.styleFrom(
                                backgroundColor: U.card,
                                selectedBackgroundColor: primaryColor,
                                foregroundColor: U.text,
                                selectedForegroundColor: U.getContrastColor(primaryColor),
                                side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: U.sub),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Anonymity is UI-only. Your profile name and photo will be hidden from other students (shown as "Verified Student"), but your account ID is retained internally for moderation and anti-abuse purposes.',
                                    style: GoogleFonts.robotoFlex(fontSize: 11.5, color: U.sub, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.robotoFlex(color: Colors.red.shade700, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: U.getContrastColor(primaryColor),
                            shape: RoundedRectangleBorder(borderRadius: M3Shapes.largeRadius),
                            elevation: 2,
                          ),
                          child: Text(
                            widget.existingReview != null ? 'Update Review' : 'Submit Honest Review',
                            style: GoogleFonts.robotoFlex(
                              color: U.getContrastColor(primaryColor),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      if (widget.existingReview != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _handleDeleteReview,
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            label: Text(
                              'Delete My Review',
                              style: GoogleFonts.robotoFlex(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(borderRadius: M3Shapes.largeRadius),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _handleDeleteReview() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.card,
        title: Text('Delete Review?', style: GoogleFonts.robotoFlex(color: U.text, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete your review for this college? This action cannot be undone.',
          style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: U.sub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSubmitting = true);
      try {
        await _reviewService.deleteUserReview(widget.collegeId);
        if (mounted) {
          showUtopiaSnackBar(
            context,
            message: 'Review deleted successfully.',
            tone: UtopiaSnackBarTone.info,
          );
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _errorMessage = 'Failed to delete review: $e';
          });
        }
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.robotoFlex(fontSize: 16, fontWeight: FontWeight.bold, color: U.text),
    );
  }

  Widget _buildStarRatingPicker({
    required String title,
    required IconData icon,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: M3Shapes.largeRadius,
        border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: U.peach),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.w600, color: U.text),
                ),
                Text(
                  value > 0 ? '$value of 5 stars' : 'Skipped (Optional)',
                  style: GoogleFonts.robotoFlex(
                    fontSize: 11.5,
                    color: value > 0 ? U.peach : U.dim,
                    fontWeight: value > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (index) {
              final starNum = index + 1;
              final isFilled = starNum <= value;
              return GestureDetector(
                onTap: () {
                  if (value == starNum) {
                    onChanged(0);
                  } else {
                    onChanged(starNum);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFilled ? Colors.amber.shade700 : U.sub.withValues(alpha: 0.35),
                    size: 26,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
