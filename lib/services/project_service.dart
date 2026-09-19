import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/project_model.dart';
import 'file_upload_service.dart';

/// Service managing Project Showcase Firestore operations, likes, queries, and media uploads.
class ProjectService {
  static final ProjectService _instance = ProjectService._internal();
  factory ProjectService() => _instance;
  ProjectService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _projectsRef =>
      _firestore.collection('projects');

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  // ─── PROJECT CRUD ───────────────────────────────────────────

  /// Create a new project in Firestore.
  /// If [coverFile] or [galleryFiles] are provided, uploads them first via [FileUploadService].
  Future<String> createProject({
    required ProjectModel project,
    File? coverFile,
    List<File>? galleryFiles,
    String? universityId,
    void Function(String message, double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to create a project.');
    }

    final fileUploadService = FileUploadService();
    String coverUrl = project.coverImage;

    // 1. Upload Cover Image if local file provided
    if (coverFile != null) {
      onProgress?.call('Uploading cover image...', 0.15);
      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}_${coverFile.path.split('/').last.split('\\').last}';
      coverUrl = await fileUploadService.uploadFile(
        file: coverFile,
        originalFilename: filename,
        universityId: universityId ?? 'showcase',
      );
    }

    if (coverUrl.isEmpty) {
      throw Exception('A project cover image is required.');
    }

    // 2. Upload Gallery Images
    List<String> finalGallery = List.from(project.galleryImages);
    if (galleryFiles != null && galleryFiles.isNotEmpty) {
      for (int i = 0; i < galleryFiles.length; i++) {
        final f = galleryFiles[i];
        final progressFrac = 0.3 + (0.5 * ((i + 1) / galleryFiles.length));
        onProgress?.call('Uploading gallery image ${i + 1}/${galleryFiles.length}...', progressFrac);
        final filename = 'gallery_${i}_${DateTime.now().millisecondsSinceEpoch}_${f.path.split('/').last.split('\\').last}';
        final url = await fileUploadService.uploadFile(
          file: f,
          originalFilename: filename,
          universityId: universityId ?? 'showcase',
        );
        finalGallery.add(url);
      }
    }

    onProgress?.call('Publishing project...', 0.9);

    // Build contributor indexing
    final contribUids = <String>{user.uid};
    for (final c in project.contributors) {
      if (c.userId.isNotEmpty) {
        contribUids.add(c.userId);
      }
    }

    final docRef = _projectsRef.doc();
    final updatedProject = project.copyWith(
      id: docRef.id,
      coverImage: coverUrl,
      galleryImages: finalGallery,
      ownerId: user.uid,
      ownerName: project.ownerName.isNotEmpty ? project.ownerName : (user.displayName ?? 'Student'),
      ownerPhotoUrl: project.ownerPhotoUrl ?? user.photoURL,
      contributorUids: contribUids.toList(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      likesCount: 0,
      likedByUserIds: [],
    );

    await docRef.set(updatedProject.toMap());

    // Send notifications to added contributors
    _notifyContributors(updatedProject);

    onProgress?.call('Published!', 1.0);
    return docRef.id;
  }

  /// Update an existing project.
  Future<void> updateProject({
    required String projectId,
    required ProjectModel project,
    File? newCoverFile,
    List<File>? newGalleryFiles,
    String? universityId,
    void Function(String message, double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in.');

    final fileUploadService = FileUploadService();
    String coverUrl = project.coverImage;

    if (newCoverFile != null) {
      onProgress?.call('Uploading updated cover...', 0.2);
      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}_${newCoverFile.path.split('/').last.split('\\').last}';
      coverUrl = await fileUploadService.uploadFile(
        file: newCoverFile,
        originalFilename: filename,
        universityId: universityId ?? 'showcase',
      );
    }

    List<String> finalGallery = List.from(project.galleryImages);
    if (newGalleryFiles != null && newGalleryFiles.isNotEmpty) {
      for (int i = 0; i < newGalleryFiles.length; i++) {
        final f = newGalleryFiles[i];
        final progressFrac = 0.3 + (0.5 * ((i + 1) / newGalleryFiles.length));
        onProgress?.call('Uploading gallery image ${i + 1}...', progressFrac);
        final filename = 'gallery_${i}_${DateTime.now().millisecondsSinceEpoch}_${f.path.split('/').last.split('\\').last}';
        final url = await fileUploadService.uploadFile(
          file: f,
          originalFilename: filename,
          universityId: universityId ?? 'showcase',
        );
        finalGallery.add(url);
      }
    }

    final contribUids = <String>{project.ownerId};
    for (final c in project.contributors) {
      if (c.userId.isNotEmpty) {
        contribUids.add(c.userId);
      }
    }

    final data = project.toMap();
    data['coverImage'] = coverUrl;
    data['galleryImages'] = finalGallery;
    data['contributorUids'] = contribUids.toList();
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());

    await _projectsRef.doc(projectId).update(data);
  }

  /// Delete a project.
  Future<void> deleteProject(String projectId) async {
    await _projectsRef.doc(projectId).delete();
  }

  // ─── LIKES ──────────────────────────────────────────────────

  /// Toggle like state for a project atomically.
  Future<bool> toggleLike(String projectId) async {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) return false;

    final docRef = _projectsRef.doc(projectId);

    return await _firestore.runTransaction<bool>((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return false;

      final data = snap.data() ?? {};
      final likedList = List<String>.from(data['likedByUserIds'] ?? []);
      final currentLikes = (data['likesCount'] as num?)?.toInt() ?? likedList.length;

      bool nowLiked;
      if (likedList.contains(uid)) {
        likedList.remove(uid);
        tx.update(docRef, {
          'likedByUserIds': FieldValue.arrayRemove([uid]),
          'likesCount': (currentLikes > 0) ? currentLikes - 1 : 0,
        });
        nowLiked = false;
      } else {
        likedList.add(uid);
        tx.update(docRef, {
          'likedByUserIds': FieldValue.arrayUnion([uid]),
          'likesCount': currentLikes + 1,
        });
        nowLiked = true;
      }
      return nowLiked;
    });
  }

  // ─── STREAMS & QUERIES ──────────────────────────────────────

  /// Real-time stream of a single project by ID.
  Stream<ProjectModel?> getProjectStream(String projectId) {
    return _projectsRef.doc(projectId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ProjectModel.fromFirestore(snap);
    });
  }

  /// Real-time stream of all projects for the Showcase Feed.
  Stream<List<ProjectModel>> getProjectsStream({
    ProjectCategory? category,
    ProjectStatus? status,
    String? techStackTag,
    bool sortByMostLiked = false,
  }) {
    Query<Map<String, dynamic>> query = _projectsRef;

    if (category != null) {
      query = query.where('category', isEqualTo: category.name);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.toDbString());
    }
    if (techStackTag != null && techStackTag.isNotEmpty) {
      query = query.where('techStack', arrayContains: techStackTag);
    }

    if (sortByMostLiked) {
      query = query.orderBy('likesCount', descending: true);
    } else {
      query = query.orderBy('createdAt', descending: true);
    }

    return query.snapshots().map((snap) {
      return snap.docs.map((d) => ProjectModel.fromFirestore(d)).toList();
    });
  }

  /// Real-time stream of projects where [userId] is owner OR contributor.
  Stream<List<ProjectModel>> getUserProjectsStream(String userId) {
    return _projectsRef
        .where('contributorUids', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs.map((d) => ProjectModel.fromFirestore(d)).toList();
        });
  }

  /// Fetch single project future.
  Future<ProjectModel?> getProjectById(String projectId) async {
    final snap = await _projectsRef.doc(projectId).get();
    if (!snap.exists || snap.data() == null) return null;
    return ProjectModel.fromFirestore(snap);
  }

  // ─── NOTIFICATIONS ──────────────────────────────────────────

  /// Trigger in-app notifications for added contributors.
  Future<void> _notifyContributors(ProjectModel project) async {
    final sender = FirebaseAuth.instance.currentUser;
    if (sender == null) return;

    for (final contrib in project.contributors) {
      if (contrib.userId == sender.uid || contrib.userId.isEmpty) continue;
      try {
        await _firestore.collection('notifications').add({
          'recipientId': contrib.userId,
          'uid': contrib.userId,
          'senderId': sender.uid,
          'senderName': sender.displayName ?? 'Student',
          'senderPhoto': sender.photoURL,
          'title': 'Added to Project Showcase 🚀',
          'body': '${sender.displayName ?? 'A peer'} added you as a contributor to "${project.title}"${contrib.role != null && contrib.role!.isNotEmpty ? ' (${contrib.role})' : ''}.',
          'type': 'project_contributor',
          'projectId': project.id,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
          'isRead': false,
        });
      } catch (e) {
        debugPrint('ProjectService: Failed to notify contributor ${contrib.userId}: $e');
      }
    }
  }
}
