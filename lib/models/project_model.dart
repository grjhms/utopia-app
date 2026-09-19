import 'package:cloud_firestore/cloud_firestore.dart';

/// Categories for projects in the UTOPIA Showcase.
enum ProjectCategory {
  app,
  hardware,
  research,
  design,
  hackathon,
  other;

  String get label {
    switch (this) {
      case ProjectCategory.app:
        return 'App';
      case ProjectCategory.hardware:
        return 'Hardware';
      case ProjectCategory.research:
        return 'Research';
      case ProjectCategory.design:
        return 'Design';
      case ProjectCategory.hackathon:
        return 'Hackathon';
      case ProjectCategory.other:
        return 'Other';
    }
  }

  static ProjectCategory fromString(String? value) {
    if (value == null) return ProjectCategory.other;
    final lower = value.toLowerCase().trim();
    for (final cat in ProjectCategory.values) {
      if (cat.name.toLowerCase() == lower || cat.label.toLowerCase() == lower) {
        return cat;
      }
    }
    return ProjectCategory.other;
  }
}

/// Project development / team status.
enum ProjectStatus {
  inProgress,
  completed,
  lookingForTeammates;

  String get label {
    switch (this) {
      case ProjectStatus.inProgress:
        return 'In Progress';
      case ProjectStatus.completed:
        return 'Completed';
      case ProjectStatus.lookingForTeammates:
        return 'Looking for Teammates';
    }
  }

  static ProjectStatus fromString(String? value) {
    if (value == null) return ProjectStatus.inProgress;
    final lower = value.toLowerCase().trim().replaceAll(' ', '_');
    switch (lower) {
      case 'completed':
        return ProjectStatus.completed;
      case 'looking_for_teammates':
      case 'lookingforteammates':
        return ProjectStatus.lookingForTeammates;
      case 'in_progress':
      case 'inprogress':
      default:
        return ProjectStatus.inProgress;
    }
  }

  String toDbString() {
    switch (this) {
      case ProjectStatus.inProgress:
        return 'in_progress';
      case ProjectStatus.completed:
        return 'completed';
      case ProjectStatus.lookingForTeammates:
        return 'looking_for_teammates';
    }
  }
}

/// A contributor on a project.
class ProjectContributor {
  final String userId;
  final String name;
  final String? photoUrl;
  final String? branch;
  final String? role; // e.g. "UI/UX Design", "Backend Developer"
  final double? contributionPercent;

  const ProjectContributor({
    required this.userId,
    required this.name,
    this.photoUrl,
    this.branch,
    this.role,
    this.contributionPercent,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
      if (branch != null && branch!.isNotEmpty) 'branch': branch,
      if (role != null && role!.isNotEmpty) 'role': role,
      if (contributionPercent != null) 'contributionPercent': contributionPercent,
    };
  }

  factory ProjectContributor.fromMap(Map<String, dynamic> map) {
    return ProjectContributor(
      userId: (map['userId'] ?? '').toString(),
      name: (map['name'] ?? 'Contributor').toString(),
      photoUrl: map['photoUrl']?.toString(),
      branch: map['branch']?.toString(),
      role: map['role']?.toString(),
      contributionPercent: (map['contributionPercent'] as num?)?.toDouble(),
    );
  }

  ProjectContributor copyWith({
    String? userId,
    String? name,
    String? photoUrl,
    String? branch,
    String? role,
    double? contributionPercent,
  }) {
    return ProjectContributor(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      branch: branch ?? this.branch,
      role: role ?? this.role,
      contributionPercent: contributionPercent ?? this.contributionPercent,
    );
  }
}

/// Custom link pair (e.g., Figma, Paper PDF, App Store).
class ProjectCustomLink {
  final String label;
  final String url;

  const ProjectCustomLink({
    required this.label,
    required this.url,
  });

  Map<String, dynamic> toMap() => {'label': label, 'url': url};

  factory ProjectCustomLink.fromMap(Map<String, dynamic> map) {
    return ProjectCustomLink(
      label: (map['label'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
    );
  }
}

/// Structured collection of links for a project.
class ProjectLinks {
  final String? github;
  final String? liveDemo;
  final String? video;
  final List<ProjectCustomLink> other;

  const ProjectLinks({
    this.github,
    this.liveDemo,
    this.video,
    this.other = const [],
  });

  bool get isEmpty =>
      (github == null || github!.isEmpty) &&
      (liveDemo == null || liveDemo!.isEmpty) &&
      (video == null || video!.isEmpty) &&
      other.isEmpty;

  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toMap() {
    return {
      if (github != null && github!.isNotEmpty) 'github': github,
      if (liveDemo != null && liveDemo!.isNotEmpty) 'liveDemo': liveDemo,
      if (video != null && video!.isNotEmpty) 'video': video,
      'other': other.map((l) => l.toMap()).toList(),
    };
  }

  factory ProjectLinks.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ProjectLinks();
    final rawOther = map['other'];
    List<ProjectCustomLink> otherLinks = [];
    if (rawOther is List) {
      otherLinks = rawOther
          .whereType<Map>()
          .map((m) => ProjectCustomLink.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    return ProjectLinks(
      github: map['github']?.toString(),
      liveDemo: map['liveDemo']?.toString(),
      video: map['video']?.toString(),
      other: otherLinks,
    );
  }

  ProjectLinks copyWith({
    String? github,
    String? liveDemo,
    String? video,
    List<ProjectCustomLink>? other,
  }) {
    return ProjectLinks(
      github: github ?? this.github,
      liveDemo: liveDemo ?? this.liveDemo,
      video: video ?? this.video,
      other: other ?? this.other,
    );
  }
}

/// Project data model for UTOPIA Showcase.
class ProjectModel {
  final String id;
  final String title;
  final String tagline;
  final String description; // Basic markdown supported
  final String coverImage; // Cloudinary URL
  final List<String> galleryImages; // Max 6 images
  final List<String> techStack; // Tags
  final ProjectCategory category;
  final ProjectStatus status;
  final ProjectLinks links;
  final String ownerId;
  final String ownerName;
  final String? ownerPhotoUrl;
  final String? ownerBranch;
  final List<ProjectContributor> contributors;
  final List<String> contributorUids;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int likesCount;
  final List<String> likedByUserIds;

  const ProjectModel({
    required this.id,
    required this.title,
    required this.tagline,
    required this.description,
    required this.coverImage,
    this.galleryImages = const [],
    this.techStack = const [],
    required this.category,
    required this.status,
    required this.links,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhotoUrl,
    this.ownerBranch,
    this.contributors = const [],
    this.contributorUids = const [],
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
    this.likesCount = 0,
    this.likedByUserIds = const [],
  });

  bool isLikedBy(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return likedByUserIds.contains(uid);
  }

  bool isOwner(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return ownerId == uid;
  }

  bool isContributor(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return contributorUids.contains(uid);
  }

  String get formattedTimeline {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (startDate != null && endDate != null) {
      return '${months[startDate!.month - 1]} ${startDate!.year} - ${months[endDate!.month - 1]} ${endDate!.year}';
    } else if (startDate != null && status == ProjectStatus.inProgress) {
      return '${months[startDate!.month - 1]} ${startDate!.year} - Present';
    } else if (startDate != null) {
      return '${months[startDate!.month - 1]} ${startDate!.year}';
    } else {
      return '${months[createdAt.month - 1]} ${createdAt.year}';
    }
  }

  String get formattedDate {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}';
  }

  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[createdAt.month - 1]} ${createdAt.year}';
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'tagline': tagline,
      'description': description,
      'coverImage': coverImage,
      'galleryImages': galleryImages,
      'techStack': techStack,
      'category': category.name,
      'status': status.toDbString(),
      'links': links.toMap(),
      'ownerId': ownerId,
      'ownerName': ownerName,
      if (ownerPhotoUrl != null && ownerPhotoUrl!.isNotEmpty) 'ownerPhotoUrl': ownerPhotoUrl,
      if (ownerBranch != null && ownerBranch!.isNotEmpty) 'ownerBranch': ownerBranch,
      'contributors': contributors.map((c) => c.toMap()).toList(),
      'contributorUids': contributorUids,
      if (startDate != null) 'startDate': Timestamp.fromDate(startDate!),
      if (endDate != null) 'endDate': Timestamp.fromDate(endDate!),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'likesCount': likesCount,
      'likedByUserIds': likedByUserIds,
    };
  }

  factory ProjectModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return ProjectModel.fromMap(doc.id, data);
  }

  factory ProjectModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is DateTime) return val;
      return DateTime.now();
    }

    DateTime? parseOptionalDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val);
      if (val is DateTime) return val;
      return null;
    }

    final rawGallery = data['galleryImages'];
    List<String> gallery = [];
    if (rawGallery is List) {
      gallery = rawGallery.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }

    final rawTech = data['techStack'];
    List<String> tech = [];
    if (rawTech is List) {
      tech = rawTech.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }

    final rawContributors = data['contributors'];
    List<ProjectContributor> contribs = [];
    if (rawContributors is List) {
      contribs = rawContributors
          .whereType<Map>()
          .map((m) => ProjectContributor.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    final rawContribUids = data['contributorUids'];
    List<String> contribUids = [];
    if (rawContribUids is List) {
      contribUids = rawContribUids.map((e) => e.toString()).toList();
    }

    final rawLiked = data['likedByUserIds'];
    List<String> likedUids = [];
    if (rawLiked is List) {
      likedUids = rawLiked.map((e) => e.toString()).toList();
    }

    final ownerId = (data['ownerId'] ?? '').toString();

    // Ensure ownerId is in contributorUids
    if (!contribUids.contains(ownerId) && ownerId.isNotEmpty) {
      contribUids.insert(0, ownerId);
    }

    return ProjectModel(
      id: id,
      title: (data['title'] ?? '').toString(),
      tagline: (data['tagline'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      coverImage: (data['coverImage'] ?? '').toString(),
      galleryImages: gallery,
      techStack: tech,
      category: ProjectCategory.fromString(data['category']?.toString()),
      status: ProjectStatus.fromString(data['status']?.toString()),
      links: ProjectLinks.fromMap(data['links'] as Map<String, dynamic>?),
      ownerId: ownerId,
      ownerName: (data['ownerName'] ?? 'Student').toString(),
      ownerPhotoUrl: data['ownerPhotoUrl']?.toString(),
      ownerBranch: data['ownerBranch']?.toString(),
      contributors: contribs,
      contributorUids: contribUids,
      startDate: parseOptionalDate(data['startDate']),
      endDate: parseOptionalDate(data['endDate']),
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      likesCount: (data['likesCount'] as num?)?.toInt() ?? likedUids.length,
      likedByUserIds: likedUids,
    );
  }

  ProjectModel copyWith({
    String? id,
    String? title,
    String? tagline,
    String? description,
    String? coverImage,
    List<String>? galleryImages,
    List<String>? techStack,
    ProjectCategory? category,
    ProjectStatus? status,
    ProjectLinks? links,
    String? ownerId,
    String? ownerName,
    String? ownerPhotoUrl,
    String? ownerBranch,
    List<ProjectContributor>? contributors,
    List<String>? contributorUids,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? likesCount,
    List<String>? likedByUserIds,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      title: title ?? this.title,
      tagline: tagline ?? this.tagline,
      description: description ?? this.description,
      coverImage: coverImage ?? this.coverImage,
      galleryImages: galleryImages ?? this.galleryImages,
      techStack: techStack ?? this.techStack,
      category: category ?? this.category,
      status: status ?? this.status,
      links: links ?? this.links,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerPhotoUrl: ownerPhotoUrl ?? this.ownerPhotoUrl,
      ownerBranch: ownerBranch ?? this.ownerBranch,
      contributors: contributors ?? this.contributors,
      contributorUids: contributorUids ?? this.contributorUids,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      likesCount: likesCount ?? this.likesCount,
      likedByUserIds: likedByUserIds ?? this.likedByUserIds,
    );
  }
}
