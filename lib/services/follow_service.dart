import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum FollowStatus { notFollowing, requested, following }

class FollowService {
  static final FollowService _instance = FollowService._internal();
  factory FollowService() => _instance;
  FollowService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Reads ────────────────────────────────────────────────────────────────

  /// Stream of followers count for a user.
  Stream<int> followersCountStream(String uid) {
    return _db
        .collection('follows')
        .where('followingId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.size);
  }

  /// Stream of following count for a user.
  Stream<int> followingCountStream(String uid) {
    return _db
        .collection('follows')
        .where('followerId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.size);
  }

  /// Returns the follow status of [currentUid] → [targetUid].
  Stream<FollowStatus> followStatusStream(
      String currentUid, String targetUid) {
    return _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .limit(1)
        .snapshots()
        .map((s) {
      if (s.docs.isEmpty) return FollowStatus.notFollowing;
      final status = s.docs.first.data()['status'] as String?;
      if (status == 'accepted') return FollowStatus.following;
      if (status == 'pending') return FollowStatus.requested;
      return FollowStatus.notFollowing;
    });
  }

  /// List of UIDs that [uid] is following (accepted only).
  Stream<List<String>> followingUidsStream(String uid) {
    return _db
        .collection('follows')
        .where('followerId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.docs
            .map((d) => (d.data()['followingId'] ?? '') as String)
            .where((id) => id.isNotEmpty)
            .toList());
  }

  /// List of UIDs that follow [uid] (accepted only).
  Stream<List<String>> followersUidsStream(String uid) {
    return _db
        .collection('follows')
        .where('followingId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.docs
            .map((d) => (d.data()['followerId'] ?? '') as String)
            .where((id) => id.isNotEmpty)
            .toList());
  }

  /// Pending follow requests sent TO [uid] (i.e., other people who want to follow them).
  Stream<List<Map<String, dynamic>>> pendingRequestsStream(String uid) {
    return _db
        .collection('follows')
        .where('followingId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> result = [];
      for (final doc in snapshot.docs) {
        final followerId = (doc.data()['followerId'] ?? '') as String;
        if (followerId.isEmpty) continue;
        try {
          final userDoc = await _db.collection('users').doc(followerId).get();
          if (userDoc.exists) {
            result.add({
              'requestDocId': doc.id,
              'uid': followerId,
              ...?userDoc.data(),
            });
          }
        } catch (_) {}
      }
      return result;
    }).handleError((e) {
      return <Map<String, dynamic>>[];
    });
  }

  /// Count of pending requests for [uid].
  Stream<int> pendingRequestsCountStream(String uid) {
    return _db
        .collection('follows')
        .where('followingId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.size);
  }

  /// Check if [currentUid] can chat with [otherUid] (at least one follows the other).
  Future<bool> canChat(String currentUid, String otherUid) async {
    // check current follows other
    final a = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: otherUid)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (a.docs.isNotEmpty) return true;
    
    // check other follows current
    final b = await _db
        .collection('follows')
        .where('followerId', isEqualTo: otherUid)
        .where('followingId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    return b.docs.isNotEmpty;
  }

  /// Stream of canChat (realtime).
  Stream<bool> canChatStream(String currentUid, String otherUid) {
    if (currentUid.isEmpty || otherUid.isEmpty || currentUid == otherUid) {
      return Stream.value(false);
    }
    final currentFollowsOther = _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: otherUid)
        .where('status', isEqualTo: 'accepted')
        .snapshots();

    final otherFollowsCurrent = _db
        .collection('follows')
        .where('followerId', isEqualTo: otherUid)
        .where('followingId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .snapshots();

    late StreamController<bool> controller;
    bool a = false;
    bool b = false;
    StreamSubscription? subA;
    StreamSubscription? subB;

    void update() {
      if (!controller.isClosed) {
        controller.add(a || b);
      }
    }

    controller = StreamController<bool>(
      onListen: () {
        subA = currentFollowsOther.listen((snap) {
          a = snap.docs.isNotEmpty;
          update();
        }, onError: (_) {});

        subB = otherFollowsCurrent.listen((snap) {
          b = snap.docs.isNotEmpty;
          update();
        }, onError: (_) {});
      },
      onCancel: () {
        subA?.cancel();
        subB?.cancel();
      },
    );

    return controller.stream;
  }

  // ─── Writes ───────────────────────────────────────────────────────────────

  /// Send or cancel a follow request / unfollow.
  Future<void> toggleFollow(String targetUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currentUid = user.uid;
    if (currentUid == targetUid) return;

    final existing = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      // Already following or requested → remove
      await existing.docs.first.reference.delete();
    } else {
      // Send a follow request (always pending – target must accept)
      await _db.collection('follows').add({
        'followerId': currentUid,
        'followingId': targetUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Accept a follow request (doc identified by [requestDocId]).
  /// Automatically creates mutual follow so both users follow each other and become friends.
  Future<void> acceptRequest(String requestDocId) async {
    final requestDoc = await _db.collection('follows').doc(requestDocId).get();
    if (!requestDoc.exists) return;

    final data = requestDoc.data();
    if (data == null) return;

    final followerId = (data['followerId'] ?? '').toString();
    final followingId = (data['followingId'] ?? '').toString();

    // 1. Accept original follow request
    await _db
        .collection('follows')
        .doc(requestDocId)
        .update({'status': 'accepted', 'acceptedAt': FieldValue.serverTimestamp()});

    // 2. Automatically create/update reverse follow so both users follow each other (mutual friends)
    if (followerId.isNotEmpty && followingId.isNotEmpty) {
      final reverseExisting = await _db
          .collection('follows')
          .where('followerId', isEqualTo: followingId)
          .where('followingId', isEqualTo: followerId)
          .limit(1)
          .get();

      if (reverseExisting.docs.isNotEmpty) {
        await reverseExisting.docs.first.reference.update({
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('follows').add({
          'followerId': followingId,
          'followingId': followerId,
          'status': 'accepted',
          'createdAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  /// Decline / ignore a follow request.
  Future<void> declineRequest(String requestDocId) async {
    await _db.collection('follows').doc(requestDocId).delete();
  }

  /// Remove a follower (i.e., remove their accepted follow of you).
  Future<void> removeFollower(String followerUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final existing = await _db
        .collection('follows')
        .where('followerId', isEqualTo: followerUid)
        .where('followingId', isEqualTo: user.uid)
        .limit(1)
        .get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
  }

  // ─── Bio helpers ──────────────────────────────────────────────────────────

  Future<void> updateBio(String bio) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set(
      {'bio': bio},
      SetOptions(merge: true),
    );
  }
}
