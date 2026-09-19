import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../models/honest_review_model.dart';
import '../services/honest_review_service.dart';
import '../screens/honest_reviews_screen.dart';
import '../screens/compose_honest_review_screen.dart';

class HonestReviewsSummaryCard extends StatelessWidget {
  final String collegeId;
  final String collegeName;

  const HonestReviewsSummaryCard({
    super.key,
    required this.collegeId,
    required this.collegeName,
  });

  @override
  Widget build(BuildContext context) {
    final HonestReviewService reviewService = HonestReviewService();

    return StreamBuilder<List<HonestReview>>(
      stream: reviewService.streamCollegeReviews(collegeId),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? [];
        final count = reviews.length;

        double avgRating = 0.0;
        if (count > 0) {
          final sum = reviews.fold<double>(0, (acc, r) => acc + r.overallRating);
          avgRating = double.parse((sum / count).toStringAsFixed(1));
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: U.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: U.outlineVariant.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HonestReviewsScreen(
                      collegeId: collegeId,
                      collegeName: collegeName,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: U.peach.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.rate_review_rounded, color: U.peach, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Honest Reviews',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: U.text,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 16, color: U.sub),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        // Rating Big Number
                        Text(
                          count > 0 ? '$avgRating' : 'N/A',
                          style: GoogleFonts.outfit(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: U.peach,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: List.generate(5, (index) {
                                final starThreshold = (index + 1) * 2;
                                return Icon(
                                  count > 0 && avgRating >= starThreshold - 1
                                      ? Icons.star_rounded
                                      : (count > 0 && avgRating >= starThreshold - 1.5
                                          ? Icons.star_half_rounded
                                          : Icons.star_outline_rounded),
                                  color: Colors.amber.shade700,
                                  size: 18,
                                );
                              }),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              count > 0 ? 'based on $count reviews' : 'Be the first to review!',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: U.sub,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ComposeHonestReviewScreen(
                                  collegeId: collegeId,
                                  collegeName: collegeName,
                                ),
                              ),
                            );
                          },
                          icon: Icon(Icons.edit_note_rounded, size: 18, color: U.getContrastColor(U.peach)),
                          label: Text(
                            'Rate',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: U.getContrastColor(U.peach)),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: U.peach,
                            foregroundColor: U.getContrastColor(U.peach),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
