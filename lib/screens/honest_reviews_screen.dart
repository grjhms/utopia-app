import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/honest_review_model.dart';
import '../services/honest_review_service.dart';
import '../theme/m3_expressive_theme.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import 'compose_honest_review_screen.dart';
import 'profile_screen.dart'; // contains kBTechBranches

class HonestReviewsScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;

  const HonestReviewsScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
  });

  @override
  State<HonestReviewsScreen> createState() => _HonestReviewsScreenState();
}

class _HonestReviewsScreenState extends State<HonestReviewsScreen> {
  final HonestReviewService _reviewService = HonestReviewService();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  ReviewSortOption _sortOption = ReviewSortOption.recent;
  String? _selectedBranch;
  bool? _selectedHostellerFilter; // null = all, true = hosteller, false = day scholar

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
              'Honest Reviews',
              style: GoogleFonts.robotoFlex(fontWeight: FontWeight.w700, fontSize: 20, color: U.text),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: InkWell(
                    onTap: () => _showLegalNoticeSheet(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.25), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_rounded, color: Colors.green, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            'Sec 79 Protected',
                            style: GoogleFonts.robotoFlex(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ComposeHonestReviewScreen(
                    collegeId: widget.collegeId,
                    collegeName: widget.collegeName,
                  ),
                ),
              );
              if (updated == true && mounted) {
                setState(() {});
              }
            },
            backgroundColor: U.peach,
            icon: Icon(Icons.rate_review_rounded, color: U.getContrastColor(U.peach)),
            label: Text(
              'Write Review',
              style: GoogleFonts.robotoFlex(color: U.getContrastColor(U.peach), fontWeight: FontWeight.bold),
            ),
          ),
          body: StreamBuilder<List<HonestReview>>(
            stream: _reviewService.streamCollegeReviews(
              widget.collegeId,
              sortOption: _sortOption,
              filterBranch: _selectedBranch,
              filterHosteller: _selectedHostellerFilter,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const UtopiaLoader(scale: 0.8),
                      const SizedBox(height: 12),
                      Text('Loading reviews...', style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13)),
                    ],
                  ),
                );
              }

              final reviews = snapshot.data ?? [];
              final HonestReview? myReview = reviews.cast<HonestReview?>().firstWhere(
                    (r) => r?.authorAccountId == _currentUid,
                    orElse: () => null,
                  );

              return CustomScrollView(
                slivers: [
                  // Top Stats & Breakdown Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildHeaderStats(reviews),
                    ),
                  ),

                  // Filter & Sorting Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _buildFilterBar(),
                    ),
                  ),

                  // User's own review banner if present
                  if (myReview != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: U.peach.withValues(alpha: 0.12),
                            borderRadius: M3Shapes.largeRadius,
                            border: Border.all(color: U.peach.withValues(alpha: 0.3), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: U.peach, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'You have submitted a review for this college.',
                                  style: GoogleFonts.robotoFlex(color: U.text, fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final updated = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => ComposeHonestReviewScreen(
                                        collegeId: widget.collegeId,
                                        collegeName: widget.collegeName,
                                        existingReview: myReview,
                                      ),
                                    ),
                                  );
                                  if (updated == true && mounted) {
                                    setState(() {});
                                  }
                                },
                                child: Text(
                                  'Edit / Delete',
                                  style: GoogleFonts.robotoFlex(color: U.peach, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Review Feed List
                  reviews.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              children: [
                                Icon(Icons.rate_review_outlined, size: 48, color: U.sub),
                                const SizedBox(height: 12),
                                Text(
                                  'No reviews match your filters yet.',
                                  style: GoogleFonts.robotoFlex(fontSize: 16, color: U.sub),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final review = reviews[index];
                              return _buildReviewCard(review);
                            },
                            childCount: reviews.length,
                          ),
                        ),

                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeaderStats(List<HonestReview> reviews) {
    if (reviews.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: M3Shapes.cardRadius,
          border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Column(
          children: [
            Text(
              widget.collegeName,
              style: GoogleFonts.robotoFlex(fontSize: 18, fontWeight: FontWeight.bold, color: U.text),
            ),
            const SizedBox(height: 8),
            Text(
              'No reviews yet. Share your experience to help prospective students!',
              textAlign: TextAlign.center,
              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final total = reviews.length;
    final overallSum = reviews.fold<double>(0, (acc, r) => acc + r.overallRating);
    final avgOverall = (overallSum / total).toStringAsFixed(1);

    final wouldChooseAgainCount = reviews.where((r) => r.wouldChooseAgain).length;
    final percentChooseAgain = ((wouldChooseAgainCount / total) * 100).round();

    // Calculate category averages
    double catAvg(String key) {
      final matches = reviews.where((r) => r.subRatings.containsKey(key) && r.subRatings[key]! > 0).toList();
      if (matches.isEmpty) return 0.0;
      final sum = matches.fold<int>(0, (acc, r) => acc + r.subRatings[key]!);
      return double.parse((sum / matches.length).toStringAsFixed(1));
    }

    final acad = catAvg('academics');
    final fac = catAvg('faculty');
    final infra = catAvg('infrastructure');
    final place = catAvg('placements');
    final campus = catAvg('campusLife');

    final hostelReviews = reviews.where((r) => r.isHosteller && r.subRatings.containsKey('hostel')).toList();
    double hostelAvg = 0.0;
    if (hostelReviews.isNotEmpty) {
      final hostelSum = hostelReviews.fold<int>(0, (acc, r) => acc + r.subRatings['hostel']!);
      hostelAvg = double.parse((hostelSum / hostelReviews.length).toStringAsFixed(1));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: M3Shapes.cardRadius,
        border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                children: [
                  Text(
                    avgOverall,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: U.peach,
                    ),
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        double.parse(avgOverall) >= (i + 1) * 2 - 1 ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: Colors.amber.shade700,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$total reviews',
                    style: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Container(width: 1, height: 70, color: U.outlineVariant.withValues(alpha: 0.35)),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: M3Shapes.mediumRadius,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.thumb_up_rounded, color: Colors.green, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$percentChooseAgain% would choose again',
                              style: GoogleFonts.robotoFlex(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Text(
            'Category Breakdown',
            style: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.bold, color: U.text),
          ),
          const SizedBox(height: 10),

          _buildCategoryBar('Academics', acad),
          _buildCategoryBar('Faculty', fac),
          _buildCategoryBar('Infrastructure', infra),
          _buildCategoryBar('Placements', place),
          _buildCategoryBar('Campus Life', campus),
          if (hostelReviews.isNotEmpty)
            _buildCategoryBar('Hostel & Food (${hostelReviews.length} hostellers)', hostelAvg),

          const SizedBox(height: 14),
          Divider(height: 1, thickness: 0.5, color: U.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 10),

          InkWell(
            onTap: () => _showLegalNoticeSheet(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, color: Colors.green.shade600, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Legally Protected Intermediary Platform (Sec 79 IT Act)',
                      style: GoogleFonts.robotoFlex(
                        color: Colors.green.shade600,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: Colors.green.shade600, size: 15),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(String label, double rating) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: rating / 5.0,
                minHeight: 8,
                backgroundColor: U.outlineVariant.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(U.peach),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              '$rating★',
              textAlign: TextAlign.end,
              style: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.bold, color: U.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Sort Menu
          PopupMenuButton<ReviewSortOption>(
            color: U.card,
            onSelected: (val) => setState(() => _sortOption = val),
            itemBuilder: (context) => [
              PopupMenuItem(value: ReviewSortOption.recent, child: Text('Most Recent', style: TextStyle(color: U.text))),
              PopupMenuItem(value: ReviewSortOption.highest, child: Text('Highest Rating', style: TextStyle(color: U.text))),
              PopupMenuItem(value: ReviewSortOption.lowest, child: Text('Lowest Rating', style: TextStyle(color: U.text))),
              PopupMenuItem(value: ReviewSortOption.mostHelpful, child: Text('Most Helpful', style: TextStyle(color: U.text))),
            ],
            child: Chip(
              avatar: Icon(Icons.sort_rounded, size: 16, color: U.peach),
              label: Text(_sortOptionName(_sortOption), style: GoogleFonts.robotoFlex(fontSize: 12, color: U.text)),
              backgroundColor: U.peach.withValues(alpha: 0.12),
              side: BorderSide(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
            ),
          ),
          const SizedBox(width: 8),

          // Hosteller Filter
          ChoiceChip(
            showCheckmark: false,
            label: Text('All Students'),
            selected: _selectedHostellerFilter == null,
            backgroundColor: U.card,
            selectedColor: U.peach.withValues(alpha: 0.15),
            side: BorderSide(
              color: _selectedHostellerFilter == null ? U.peach : U.outlineVariant.withValues(alpha: 0.35),
            ),
            labelStyle: GoogleFonts.robotoFlex(
              fontSize: 12,
              fontWeight: _selectedHostellerFilter == null ? FontWeight.bold : FontWeight.normal,
              color: _selectedHostellerFilter == null ? U.peach : U.sub,
            ),
            onSelected: (sel) {
              if (sel) setState(() => _selectedHostellerFilter = null);
            },
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            showCheckmark: false,
            label: Text('Hostellers'),
            selected: _selectedHostellerFilter == true,
            backgroundColor: U.card,
            selectedColor: U.peach.withValues(alpha: 0.15),
            side: BorderSide(
              color: _selectedHostellerFilter == true ? U.peach : U.outlineVariant.withValues(alpha: 0.35),
            ),
            labelStyle: GoogleFonts.robotoFlex(
              fontSize: 12,
              fontWeight: _selectedHostellerFilter == true ? FontWeight.bold : FontWeight.normal,
              color: _selectedHostellerFilter == true ? U.peach : U.sub,
            ),
            onSelected: (sel) {
              if (sel) setState(() => _selectedHostellerFilter = true);
            },
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            showCheckmark: false,
            label: Text('Day Scholars'),
            selected: _selectedHostellerFilter == false,
            backgroundColor: U.card,
            selectedColor: U.peach.withValues(alpha: 0.15),
            side: BorderSide(
              color: _selectedHostellerFilter == false ? U.peach : U.outlineVariant.withValues(alpha: 0.35),
            ),
            labelStyle: GoogleFonts.robotoFlex(
              fontSize: 12,
              fontWeight: _selectedHostellerFilter == false ? FontWeight.bold : FontWeight.normal,
              color: _selectedHostellerFilter == false ? U.peach : U.sub,
            ),
            onSelected: (sel) {
              if (sel) setState(() => _selectedHostellerFilter = false);
            },
          ),
          const SizedBox(width: 8),

          // Branch Filter Dropdown
          DropdownButton<String>(
            value: _selectedBranch,
            hint: Text('Filter Branch', style: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub)),
            style: GoogleFonts.robotoFlex(fontSize: 12, color: U.text),
            dropdownColor: U.card,
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: null, child: Text('All Branches', style: TextStyle(color: U.text))),
              ...kBTechBranches.map((b) => DropdownMenuItem(value: b, child: Text(b, style: TextStyle(color: U.text)))),
            ],
            onChanged: (val) => setState(() => _selectedBranch = val),
          ),
        ],
      ),
    );
  }

  String _sortOptionName(ReviewSortOption opt) {
    switch (opt) {
      case ReviewSortOption.recent:
        return 'Sort: Recent';
      case ReviewSortOption.highest:
        return 'Sort: Highest';
      case ReviewSortOption.lowest:
        return 'Sort: Lowest';
      case ReviewSortOption.mostHelpful:
        return 'Sort: Helpful';
    }
  }

  Widget _buildReviewCard(HonestReview review) {
    final isUpvoted = review.helpfulUserIds.contains(_currentUid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: M3Shapes.cardRadius,
        border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header (Anonymous vs Public) + Badges
          Row(
            children: [
              FutureBuilder<DocumentSnapshot>(
                future: review.isAnonymous
                    ? null
                    : FirebaseFirestore.instance.collection('users').doc(review.authorAccountId).get(),
                builder: (context, snapshot) {
                  String name = 'Verified Student';
                  String? photoUrl;

                  if (!review.isAnonymous && snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    name = data['displayName'] ?? 'Student';
                    photoUrl = data['photoUrl'];
                  }

                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: U.peach.withValues(alpha: 0.2),
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Icon(
                                review.isAnonymous ? Icons.security_rounded : Icons.person_rounded,
                                size: 18,
                                color: U.peach,
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            review.isAnonymous ? 'Verified Student' : name,
                            style: GoogleFonts.robotoFlex(fontWeight: FontWeight.bold, fontSize: 14, color: U.text),
                          ),
                          Text(
                            DateFormat('MMM d, yyyy').format(review.createdAt) +
                                (review.editedAt != null ? ' (edited)' : ''),
                            style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const Spacer(),

              // Rating Score Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: U.peach,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${review.overallRating} ★',
                  style: GoogleFonts.robotoFlex(color: U.getContrastColor(U.peach), fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Context Tags & Badges
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Home College Soft Affiliation Signal
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(review.authorAccountId).get(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    final userUni = (data['selectedUniversityId'] ?? '').toString().toLowerCase().trim();
                    if (userUni == widget.collegeId.toLowerCase().trim()) {
                      return _buildTagChip('Student', Colors.blue);
                    }
                  }
                  return const SizedBox();
                },
              ),

              // New Account Tag (<24h)
              if (review.isNewAccount) _buildTagChip('New Account', Colors.orange),

              if (review.contextTags['year'] != null)
                _buildTagChip(review.contextTags['year']!, Colors.purple),
              if (review.contextTags['branch'] != null)
                _buildTagChip(review.contextTags['branch']!, Colors.teal),
              _buildTagChip(review.isHosteller ? 'Hosteller' : 'Day Scholar', Colors.indigo),
            ],
          ),

          const SizedBox(height: 12),

          // Comment Text
          Text(
            review.comment,
            style: GoogleFonts.robotoFlex(fontSize: 14, height: 1.4, color: U.text),
          ),

          const SizedBox(height: 14),

          // Sub-ratings pill summary (only showing rated categories)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: review.subRatings.entries.where((e) => e.value > 0).map((e) {
              return Text(
                '${_formatCategoryKey(e.key)}: ${e.value}/5★',
                style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub),
              );
            }).toList(),
          ),

          Divider(height: 24, color: U.outlineVariant.withValues(alpha: 0.35)),

          // Upvote & Report Actions
          Row(
            children: [
              InkWell(
                onTap: () async {
                  await _reviewService.toggleHelpfulVote(review.id);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isUpvoted ? U.peach.withValues(alpha: 0.15) : U.outlineVariant.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isUpvoted ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        size: 16,
                        color: isUpvoted ? U.peach : U.sub,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Helpful (${review.helpfulCount})',
                        style: GoogleFonts.robotoFlex(
                          fontSize: 12,
                          fontWeight: isUpvoted ? FontWeight.bold : FontWeight.normal,
                          color: isUpvoted ? U.peach : U.sub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),

              // Report Button
              PopupMenuButton<String>(
                color: U.card,
                onSelected: (reason) async {
                  await _reviewService.reportReview(
                    reviewId: review.id,
                    collegeId: widget.collegeId,
                    reason: reason,
                  );
                  if (mounted) {
                    showUtopiaSnackBar(
                      context,
                      message: 'Review reported. Thank you for helping keep Utopia safe!',
                      tone: UtopiaSnackBarTone.success,
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'Harassment', child: Text('Harassment', style: TextStyle(color: U.text))),
                  PopupMenuItem(value: 'Fake/Spam', child: Text('Fake / Spam', style: TextStyle(color: U.text))),
                  PopupMenuItem(value: 'Targets an Individual', child: Text('Targets an Individual', style: TextStyle(color: U.text))),
                  PopupMenuItem(value: 'Off-topic/Irrelevant', child: Text('Off-topic / Irrelevant', style: TextStyle(color: U.text))),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.flag_outlined, size: 18, color: U.sub),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.robotoFlex(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showLegalNoticeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: U.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.sub.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.verified_user_rounded, color: Colors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Legally Protected & Safe Platform',
                            style: GoogleFonts.robotoFlex(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: U.text,
                            ),
                          ),
                          Text(
                            'Compliant with IT Act 2000 (Section 79) & Google Play Policies',
                            style: GoogleFonts.robotoFlex(fontSize: 11.5, color: U.sub),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 0.5),

              // Scrollable Legal Points
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLegalPoint(
                        icon: Icons.gavel_rounded,
                        title: 'Intermediary Safe Harbor (Sec 79 IT Act)',
                        description:
                            'UTOPIA is a legally protected intermediary platform under Section 79 of the Information Technology Act. Honest opinions on college infrastructure, placements, and campus life are legally protected.',
                      ),
                      const SizedBox(height: 12),
                      _buildLegalPoint(
                        icon: Icons.shield_outlined,
                        title: 'No Named Defamation Allowed',
                        description:
                            'To protect staff and students, comments mentioning specific individual names are held for moderation prior to publication.',
                      ),
                      const SizedBox(height: 12),
                      _buildLegalPoint(
                        icon: Icons.flag_outlined,
                        title: 'Community Reporting & Triage',
                        description:
                            'Any review reported 3 times is automatically hidden and sent to the superuser moderation queue for review.',
                      ),
                    ],
                  ),
                ),
              ),

              // Pinned Bottom Button Area
              Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: U.peach,
                      foregroundColor: U.getContrastColor(U.peach),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(
                      'Understood',
                      style: GoogleFonts.robotoFlex(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: U.getContrastColor(U.peach),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegalPoint({required IconData icon, required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: U.peach),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.robotoFlex(fontSize: 13, fontWeight: FontWeight.bold, color: U.text),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.robotoFlex(fontSize: 12, color: U.sub, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatCategoryKey(String key) {
    switch (key) {
      case 'academics':
        return 'Acad';
      case 'faculty':
        return 'Faculty';
      case 'infrastructure':
        return 'Infra';
      case 'placements':
        return 'Placements';
      case 'campusLife':
        return 'Campus';
      case 'hostel':
        return 'Hostel';
      default:
        return key;
    }
  }
}
