import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../main.dart';
import '../models/university_model.dart';
import 'cache_service.dart';

class UniversityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch all active universities from the Firestore 'universities' collection.
  Future<List<UniversityModel>> fetchAllUniversities() async {
    try {
      final List<QuerySnapshot<Map<String, dynamic>>> snapshots = [];

      // Query all possible collection name variants (with/without trailing space, case variations)
      final collectionsToTry = ['universities', 'universities ', 'Universities', 'Universities '];

      for (final colName in collectionsToTry) {
        try {
          final snap = await _firestore.collection(colName).get(const GetOptions(source: Source.server));
          snapshots.add(snap);
        } catch (_) {
          try {
            final snap = await _firestore.collection(colName).get();
            snapshots.add(snap);
          } catch (_) {}
        }

        try {
          final groupSnap = await _firestore.collectionGroup(colName).get(const GetOptions(source: Source.server));
          snapshots.add(groupSnap);
        } catch (_) {
          try {
            final groupSnap = await _firestore.collectionGroup(colName).get();
            snapshots.add(groupSnap);
          } catch (_) {}
        }
      }

      final allDocs = snapshots.expand((s) => s.docs).toList();
      debugPrint('UniversityService: Total raw docs fetched across all collection variants: ${allDocs.length}');

      final List<UniversityModel> result = [];
      final Set<String> seenIds = {};

      for (final doc in allDocs) {
        final data = doc.data();
        if (data['isActive'] == false || data['enabled'] == false) continue;
        final model = UniversityModel.fromMap(data, doc.id);
        if (seenIds.contains(model.id.toLowerCase())) continue;
        seenIds.add(model.id.toLowerCase());
        result.add(model);
      }

      result.sort((a, b) => a.name.compareTo(b.name));
      debugPrint('UniversityService: Resolved ${result.length} unique universities: ${result.map((u) => u.name).toList()}');
      return result;
    } catch (e) {
      debugPrint('Error fetching universities from Firestore: $e');
      return [];
    }
  }

  /// Real-time stream of all active universities from Firestore.
  Stream<List<UniversityModel>> streamUniversities() {
    late final StreamController<List<UniversityModel>> controller;
    final List<StreamSubscription> subs = [];

    void emitLatest() {
      fetchAllUniversities().then((list) {
        if (!controller.isClosed) controller.add(list);
      }).catchError((_) {});
    }

    controller = StreamController<List<UniversityModel>>.broadcast(
      onListen: () {
        emitLatest();
        final collectionsToTry = ['universities', 'universities ', 'Universities', 'Universities '];
        for (final colName in collectionsToTry) {
          try {
            subs.add(_firestore.collection(colName).snapshots().listen((_) => emitLatest(), onError: (_) {}));
          } catch (_) {}
          try {
            subs.add(_firestore.collectionGroup(colName).snapshots().listen((_) => emitLatest(), onError: (_) {}));
          } catch (_) {}
        }
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        subs.clear();
      },
    );

    return controller.stream;
  }

  /// Retrieve a university model by matching its ID or shortName.
  Future<UniversityModel?> getUniversityById(String universityId) async {
    final cleanId = universityId.trim().toLowerCase();
    if (cleanId.isEmpty) return null;

    final allUnis = await fetchAllUniversities();
    for (final u in allUnis) {
      if (u.id.trim().toLowerCase() == cleanId || 
          u.shortName.trim().toLowerCase() == cleanId) {
        return u;
      }
    }
    return null;
  }

  /// Check whether a university ID is valid and present in Firestore.
  Future<bool> isUniversityValid(String universityId) async {
    final uni = await getUniversityById(universityId);
    return uni != null;
  }

  /// Get the current user's selected university ID from their user document.
  Future<String?> getUserSelectedUniversity(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['selectedUniversityId'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Set the user's selected university in Firestore and local cache.
  Future<void> setUserSelectedUniversity(
    String uid,
    String universityId, {
    String? universityName,
  }) async {
    final cleanId = universityId.trim();
    final cleanName = universityName?.trim() ?? '';

    await _firestore.collection('users').doc(uid).set({
      'selectedUniversityId': cleanId,
      if (cleanName.isNotEmpty) ...{
        'universityName': cleanName,
        'university': cleanName,
      },
    }, SetOptions(merge: true));

    await CacheService().saveAppSetting('cached_university_id', cleanId);
    U.cachedUniversityId = cleanId;

    if (cleanName.isNotEmpty) {
      await CacheService().saveAppSetting('cached_university_name', cleanName);
      U.cachedUniversityName = cleanName;
    }
  }

  /// Clear the user's selected university in Firestore and local cache,
  /// causing the app to fall back to the university selection screen.
  Future<void> clearUserSelectedUniversity(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'selectedUniversityId': FieldValue.delete(),
        'universityName': FieldValue.delete(),
        'university': FieldValue.delete(),
      });
    } catch (_) {
      try {
        await _firestore.collection('users').doc(uid).set({
          'selectedUniversityId': null,
          'universityName': null,
          'university': null,
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    await CacheService().saveAppSetting('cached_university_id', '');
    await CacheService().saveAppSetting('cached_university_name', '');
    U.cachedUniversityId = '';
    U.cachedUniversityName = '';
  }
}
