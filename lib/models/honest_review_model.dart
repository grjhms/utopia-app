import 'package:cloud_firestore/cloud_firestore.dart';

enum ReviewDisplayMode { anonymous, public }
enum ReviewStatus { published, pending, hidden, removed }

class HonestReview {
  final String id;
  final String collegeId;
  final String authorAccountId;
  final ReviewDisplayMode displayMode;
  final Map<String, int> subRatings; // e.g. {'academics': 8, 'faculty': 9, ...}
  final bool isHosteller;
  final double overallRating;
  final bool wouldChooseAgain;
  final String comment;
  final Map<String, String> contextTags; // e.g. {'year': '2nd year', 'branch': 'CSE'}
  final DateTime createdAt;
  final DateTime? editedAt;
  final ReviewStatus status;
  final int reportCount;
  final int helpfulCount;
  final List<String> helpfulUserIds;
  final bool flaggedForNamedIndividual;
  final bool flaggedForCoordination;
  final int authorAccountAgeHours;

  HonestReview({
    required this.id,
    required this.collegeId,
    required this.authorAccountId,
    required this.displayMode,
    required this.subRatings,
    required this.isHosteller,
    required this.overallRating,
    required this.wouldChooseAgain,
    required this.comment,
    this.contextTags = const {},
    required this.createdAt,
    this.editedAt,
    this.status = ReviewStatus.published,
    this.reportCount = 0,
    this.helpfulCount = 0,
    this.helpfulUserIds = const [],
    this.flaggedForNamedIndividual = false,
    this.flaggedForCoordination = false,
    this.authorAccountAgeHours = 24,
  });

  bool get isAnonymous => displayMode == ReviewDisplayMode.anonymous;
  bool get isNewAccount => authorAccountAgeHours < 24;

  static double calculateOverallRating(Map<String, int> ratings) {
    if (ratings.isEmpty) return 0.0;
    int sum = 0;
    int count = 0;
    ratings.forEach((_, score) {
      if (score > 0) {
        sum += score;
        count++;
      }
    });
    if (count == 0) return 0.0;
    double rawAvg = sum / count;
    return double.parse(rawAvg.toStringAsFixed(1));
  }

  factory HonestReview.fromFirestore(Map<String, dynamic> data, String docId) {
    final subRatingsRaw = Map<String, dynamic>.from(data['subRatings'] ?? {});
    final Map<String, int> subRatings = subRatingsRaw.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );

    final contextTagsRaw = Map<String, dynamic>.from(data['contextTags'] ?? {});
    final Map<String, String> contextTags = contextTagsRaw.map(
      (k, v) => MapEntry(k, v.toString()),
    );

    final helpfulUsersRaw = List<dynamic>.from(data['helpfulUserIds'] ?? []);
    final List<String> helpfulUserIds = helpfulUsersRaw.map((e) => e.toString()).toList();

    ReviewDisplayMode displayMode = ReviewDisplayMode.anonymous;
    if (data['displayMode'] == 'public') {
      displayMode = ReviewDisplayMode.public;
    }

    ReviewStatus status = ReviewStatus.published;
    final statusStr = (data['status'] ?? 'published').toString().toLowerCase();
    if (statusStr == 'pending') status = ReviewStatus.pending;
    if (statusStr == 'hidden') status = ReviewStatus.hidden;
    if (statusStr == 'removed') status = ReviewStatus.removed;

    DateTime createdAt = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }

    DateTime? editedAt;
    if (data['editedAt'] is Timestamp) {
      editedAt = (data['editedAt'] as Timestamp).toDate();
    }

    final double overall = (data['overallRating'] as num?)?.toDouble() ?? calculateOverallRating(subRatings);

    return HonestReview(
      id: docId,
      collegeId: (data['collegeId'] ?? '').toString(),
      authorAccountId: (data['authorAccountId'] ?? '').toString(),
      displayMode: displayMode,
      subRatings: subRatings,
      isHosteller: data['isHosteller'] == true,
      overallRating: overall,
      wouldChooseAgain: data['wouldChooseAgain'] == true,
      comment: (data['comment'] ?? '').toString(),
      contextTags: contextTags,
      createdAt: createdAt,
      editedAt: editedAt,
      status: status,
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      helpfulCount: (data['helpfulCount'] as num?)?.toInt() ?? 0,
      helpfulUserIds: helpfulUserIds,
      flaggedForNamedIndividual: data['flaggedForNamedIndividual'] == true,
      flaggedForCoordination: data['flaggedForCoordination'] == true,
      authorAccountAgeHours: (data['authorAccountAgeHours'] as num?)?.toInt() ?? 24,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'collegeId': collegeId,
      'authorAccountId': authorAccountId,
      'displayMode': displayMode.name,
      'subRatings': subRatings,
      'isHosteller': isHosteller,
      'overallRating': overallRating,
      'wouldChooseAgain': wouldChooseAgain,
      'comment': comment,
      'contextTags': contextTags,
      'createdAt': Timestamp.fromDate(createdAt),
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'status': status.name,
      'reportCount': reportCount,
      'helpfulCount': helpfulCount,
      'helpfulUserIds': helpfulUserIds,
      'flaggedForNamedIndividual': flaggedForNamedIndividual,
      'flaggedForCoordination': flaggedForCoordination,
      'authorAccountAgeHours': authorAccountAgeHours,
    };
  }
}

class ReviewReport {
  final String id;
  final String reviewId;
  final String collegeId;
  final String reporterAccountId;
  final String reason;
  final DateTime createdAt;

  ReviewReport({
    required this.id,
    required this.reviewId,
    required this.collegeId,
    required this.reporterAccountId,
    required this.reason,
    required this.createdAt,
  });

  factory ReviewReport.fromFirestore(Map<String, dynamic> data, String docId) {
    DateTime createdAt = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }
    return ReviewReport(
      id: docId,
      reviewId: (data['reviewId'] ?? '').toString(),
      collegeId: (data['collegeId'] ?? '').toString(),
      reporterAccountId: (data['reporterAccountId'] ?? '').toString(),
      reason: (data['reason'] ?? 'Spam').toString(),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reviewId': reviewId,
      'collegeId': collegeId,
      'reporterAccountId': reporterAccountId,
      'reason': reason,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
