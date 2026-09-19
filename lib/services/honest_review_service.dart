import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/honest_review_model.dart';
import '../utils/review_content_filter.dart';

enum ReviewSortOption { recent, highest, lowest, mostHelpful }

class HonestReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _collectionPath = 'honest_reviews';
  static const String _reportsCollectionPath = 'review_reports';
  static const int kAutoHideReportThreshold = 3;

  /// Fetch current user's existing review for a specific college (if any).
  Future<HonestReview?> getUserReviewForCollege(String collegeId) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final cleanCollegeId = collegeId.toLowerCase().trim();
    final docId = '${cleanCollegeId}_${user.uid}';

    try {
      final doc = await _firestore.collection(_collectionPath).doc(docId).get();
      if (doc.exists && doc.data() != null) {
        return HonestReview.fromFirestore(doc.data()!, doc.id);
      }
    } catch (e) {
      debugPrint('Error fetching user review for college: $e');
    }
    return null;
  }

  /// Delete current user's review for a college.
  Future<void> deleteUserReview(String collegeId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to delete a review.');

    final cleanCollegeId = collegeId.toLowerCase().trim();
    final docId = '${cleanCollegeId}_${user.uid}';

    await _firestore.collection(_collectionPath).doc(docId).delete();
  }

  /// Checks whether the user is restricted from writing reviews due to repeated violations.
  Future<bool> isUserRestrictedFromReviews() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['isRestrictedFromReviews'] == true;
      }
    } catch (e) {
      debugPrint('Error checking user restriction: $e');
    }
    return false;
  }

  /// Calculates the current user's account age in hours.
  int _calculateAccountAgeHours() {
    final user = _auth.currentUser;
    if (user == null) return 0;

    final creationTime = user.metadata.creationTime;
    if (creationTime == null) return 24;

    final diff = DateTime.now().difference(creationTime);
    return diff.inHours;
  }

  /// Submit a new review or edit an existing review in place.
  Future<HonestReview?> submitOrUpdateReview({
    required String collegeId,
    required ReviewDisplayMode displayMode,
    required Map<String, int> subRatings,
    required bool isHosteller,
    required bool wouldChooseAgain,
    required String comment,
    Map<String, String> contextTags = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to submit a review.');

    // Check account restrictions
    final restricted = await isUserRestrictedFromReviews();
    if (restricted) {
      throw Exception('Your account is restricted from posting new reviews due to past community guideline violations.');
    }

    // Run filters
    final filterResult = ReviewContentFilter.analyzeText(comment);
    if (filterResult.containsProfanity) {
      throw Exception('Your review contains inappropriate language and cannot be submitted.');
    }

    final double overallRating = HonestReview.calculateOverallRating(subRatings);
    final int accountAgeHours = _calculateAccountAgeHours();
    final bool flaggedForNamed = filterResult.targetsNamedIndividual;
    final ReviewStatus status = flaggedForNamed ? ReviewStatus.pending : ReviewStatus.published;

    final cleanCollegeId = collegeId.toLowerCase().trim();
    final docId = '${cleanCollegeId}_${user.uid}';
    final docRef = _firestore.collection(_collectionPath).doc(docId);
    final docSnap = await docRef.get();

    final now = DateTime.now();

    if (docSnap.exists) {
      // Update in place
      final Map<String, dynamic> updateData = {
        'displayMode': displayMode.name,
        'subRatings': subRatings,
        'isHosteller': isHosteller,
        'overallRating': overallRating,
        'wouldChooseAgain': wouldChooseAgain,
        'comment': comment,
        'contextTags': contextTags,
        'editedAt': Timestamp.fromDate(now),
        'status': status.name,
        'flaggedForNamedIndividual': flaggedForNamed,
      };

      await docRef.update(updateData);

      final updatedDoc = await docRef.get();
      return HonestReview.fromFirestore(updatedDoc.data()!, updatedDoc.id);
    } else {
      // Create new review doc
      final review = HonestReview(
        id: docId,
        collegeId: cleanCollegeId,
        authorAccountId: user.uid,
        displayMode: displayMode,
        subRatings: subRatings,
        isHosteller: isHosteller,
        overallRating: overallRating,
        wouldChooseAgain: wouldChooseAgain,
        comment: comment,
        contextTags: contextTags,
        createdAt: now,
        status: status,
        flaggedForNamedIndividual: flaggedForNamed,
        authorAccountAgeHours: accountAgeHours,
      );

      await docRef.set(review.toFirestore());

      // Trigger lightweight anti-coordination check in background
      _checkAntiCoordinationPattern(cleanCollegeId);

      return review;
    }
  }

  /// Lightweight anti-coordinated review check.
  /// Flags recent extreme reviews if >=3 reviews posted within 1 hour from young accounts (<48h).
  Future<void> _checkAntiCoordinationPattern(String collegeId) async {
    try {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final snap = await _firestore
          .collection(_collectionPath)
          .where('collegeId', isEqualTo: collegeId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(oneHourAgo))
          .get();

      final recentDocs = snap.docs.map((d) => HonestReview.fromFirestore(d.data(), d.id)).toList();
      final extremeReviews = recentDocs.where((r) =>
        (r.overallRating >= 9.0 || r.overallRating <= 2.0) && r.authorAccountAgeHours < 48
      ).toList();

      if (extremeReviews.length >= 3) {
        final batch = _firestore.batch();
        for (final rev in extremeReviews) {
          final ref = _firestore.collection(_collectionPath).doc(rev.id);
          batch.update(ref, {'flaggedForCoordination': true});
        }
        await batch.commit();
        debugPrint('Anti-coordination rule triggered for college $collegeId: ${extremeReviews.length} reviews flagged.');
      }
    } catch (e) {
      debugPrint('Error running anti-coordination check: $e');
    }
  }

  /// Stream published reviews for a given college.
  Stream<List<HonestReview>> streamCollegeReviews(
    String collegeId, {
    ReviewSortOption sortOption = ReviewSortOption.recent,
    String? filterBranch,
    bool? filterHosteller,
  }) {
    final cleanCollegeId = collegeId.toLowerCase().trim();
    Query query = _firestore
        .collection(_collectionPath)
        .where('collegeId', isEqualTo: cleanCollegeId)
        .where('status', isEqualTo: ReviewStatus.published.name);

    return query.snapshots().map((snap) {
      List<HonestReview> reviews = snap.docs
          .map((d) => HonestReview.fromFirestore(d.data() as Map<String, dynamic>, d.id))
          .toList();

      // Client-side filtering
      if (filterBranch != null && filterBranch.isNotEmpty && filterBranch != 'All') {
        reviews = reviews.where((r) => r.contextTags['branch'] == filterBranch).toList();
      }

      if (filterHosteller != null) {
        reviews = reviews.where((r) => r.isHosteller == filterHosteller).toList();
      }

      // Client-side sorting
      switch (sortOption) {
        case ReviewSortOption.recent:
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          break;
        case ReviewSortOption.highest:
          reviews.sort((a, b) => b.overallRating.compareTo(a.overallRating));
          break;
        case ReviewSortOption.lowest:
          reviews.sort((a, b) => a.overallRating.compareTo(b.overallRating));
          break;
        case ReviewSortOption.mostHelpful:
          reviews.sort((a, b) => b.helpfulCount.compareTo(a.helpfulCount));
          break;
      }

      return reviews;
    });
  }

  /// Toggle helpful / upvote on a review.
  Future<void> toggleHelpfulVote(String reviewId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to vote.');

    final docRef = _firestore.collection(_collectionPath).doc(reviewId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final review = HonestReview.fromFirestore(doc.data()!, doc.id);
    final List<String> updatedUsers = List.from(review.helpfulUserIds);

    if (updatedUsers.contains(user.uid)) {
      updatedUsers.remove(user.uid);
    } else {
      updatedUsers.add(user.uid);
    }

    await docRef.update({
      'helpfulCount': updatedUsers.length,
      'helpfulUserIds': updatedUsers,
    });
  }

  /// Submit a community report for a review.
  Future<void> reportReview({
    required String reviewId,
    required String collegeId,
    required String reason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to report.');

    // Save report doc
    final reportRef = _firestore.collection(_reportsCollectionPath).doc();
    final report = ReviewReport(
      id: reportRef.id,
      reviewId: reviewId,
      collegeId: collegeId,
      reporterAccountId: user.uid,
      reason: reason,
      createdAt: DateTime.now(),
    );
    await reportRef.set(report.toFirestore());

    // Update review report count
    final reviewRef = _firestore.collection(_collectionPath).doc(reviewId);
    final doc = await reviewRef.get();
    if (!doc.exists) return;

    final currentReportCount = (doc.data()?['reportCount'] as num?)?.toInt() ?? 0;
    final newCount = currentReportCount + 1;

    final Map<String, dynamic> updates = {'reportCount': newCount};
    if (newCount >= kAutoHideReportThreshold) {
      updates['status'] = ReviewStatus.hidden.name;
    }

    await reviewRef.update(updates);
  }

  /// Fetch moderation queue items for superusers (pending, reported, or flagged reviews).
  Stream<List<HonestReview>> streamModerationQueue() {
    return _firestore
        .collection(_collectionPath)
        .snapshots()
        .map((snap) {
      final reviews = snap.docs
          .map((d) => HonestReview.fromFirestore(d.data(), d.id))
          .where((r) =>
              r.status == ReviewStatus.pending ||
              r.status == ReviewStatus.hidden ||
              r.reportCount > 0 ||
              r.flaggedForNamedIndividual ||
              r.flaggedForCoordination)
          .toList();

      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    });
  }

  /// Moderator Action: Approve a review.
  Future<void> approveReview(String reviewId) async {
    await _firestore.collection(_collectionPath).doc(reviewId).update({
      'status': ReviewStatus.published.name,
      'flaggedForNamedIndividual': false,
      'flaggedForCoordination': false,
    });
  }

  /// Moderator Action: Remove a review and escalate account violations.
  Future<void> removeReview(String reviewId, String authorAccountId) async {
    await _firestore.collection(_collectionPath).doc(reviewId).update({
      'status': ReviewStatus.removed.name,
    });

    // Escalate user violation count
    final userRef = _firestore.collection('users').doc(authorAccountId);
    final userDoc = await userRef.get();

    int currentViolations = 0;
    if (userDoc.exists && userDoc.data() != null) {
      currentViolations = (userDoc.data()!['reviewViolationCount'] as num?)?.toInt() ?? 0;
    }

    final newViolations = currentViolations + 1;
    final bool restrict = newViolations >= 2;

    await userRef.set({
      'reviewViolationCount': newViolations,
      if (restrict) 'isRestrictedFromReviews': true,
    }, SetOptions(merge: true));
  }
}
