import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/honest_review_model.dart';
import '../services/honest_review_service.dart';
import '../widgets/utopia_loader.dart';

class ReviewModerationQueueScreen extends StatefulWidget {
  const ReviewModerationQueueScreen({super.key});

  @override
  State<ReviewModerationQueueScreen> createState() => _ReviewModerationQueueScreenState();
}

class _ReviewModerationQueueScreenState extends State<ReviewModerationQueueScreen> {
  final HonestReviewService _reviewService = HonestReviewService();

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
              'Reviews Moderation Queue',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: U.text),
            ),
          ),
          body: StreamBuilder<List<HonestReview>>(
            stream: _reviewService.streamModerationQueue(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      UtopiaLoader(scale: 0.8),
                      SizedBox(height: 12),
                      Text('Loading moderation queue...'),
                    ],
                  ),
                );
              }

              final queueItems = snapshot.data ?? [];

              if (queueItems.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.published_with_changes_rounded, size: 56, color: Colors.green.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Queue is clear!',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: U.text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'No pending or reported reviews requiring triage.',
                        style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: queueItems.length,
                itemBuilder: (context, index) {
                  final review = queueItems[index];
                  return _buildQueueCard(review);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildQueueCard(HonestReview review) {
    final List<String> flagReasons = [];
    if (review.flaggedForNamedIndividual) {
      flagReasons.add('Named Individual Reference');
    }
    if (review.flaggedForCoordination) {
      flagReasons.add('Anti-Coordination Spike');
    }
    if (review.reportCount > 0) {
      flagReasons.add('Community Reports (${review.reportCount})');
    }
    if (review.status == ReviewStatus.hidden) {
      flagReasons.add('Auto-Hidden');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: review.reportCount >= 3 || review.flaggedForNamedIndividual
              ? Colors.amber.shade700
              : U.outlineVariant.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // College & Status Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: U.peach.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  review.collegeId.toUpperCase(),
                  style: GoogleFonts.outfit(color: U.peach, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: review.status == ReviewStatus.pending ? Colors.orange.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  review.status.name.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: review.status == ReviewStatus.pending ? Colors.orange.shade800 : Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${review.overallRating} ★',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: U.peach),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Flag Reasons Chips
          if (flagReasons.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: flagReasons.map((reason) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        reason,
                        style: GoogleFonts.outfit(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 10),

          // Author Meta Info
          Row(
            children: [
              Text(
                'Author UID: ${review.authorAccountId.substring(0, review.authorAccountId.length > 8 ? 8 : review.authorAccountId.length)}...',
                style: GoogleFonts.outfit(fontSize: 11, color: U.sub),
              ),
              const SizedBox(width: 12),
              Text(
                'Account Age: ${review.authorAccountAgeHours}h',
                style: GoogleFonts.outfit(fontSize: 11, color: review.isNewAccount ? Colors.orange.shade700 : U.sub),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, HH:mm').format(review.createdAt),
                style: GoogleFonts.outfit(fontSize: 11, color: U.sub),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Review Comment Text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: U.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              review.comment,
              style: GoogleFonts.outfit(fontSize: 13.5, color: U.text),
            ),
          ),

          const SizedBox(height: 14),

          // Action Buttons: 1-Tap Approve / Remove
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await _reviewService.approveReview(review.id);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Review approved & published!', style: GoogleFonts.outfit())),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18),
                  label: Text('Approve', style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await _reviewService.removeReview(review.id, review.authorAccountId);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Review removed & author violation recorded.', style: GoogleFonts.outfit())),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                  label: Text('Remove', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
