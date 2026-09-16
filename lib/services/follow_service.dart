import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../main.dart';
import 'notification_service.dart';

enum LinkStatus {
  notLinked,
  requested, // current user sent link request to target
  hasIncomingRequest, // target user sent link request to current user
  linked; // mutually linked (one accepts, both are linked)

  bool get isLinked => this == LinkStatus.linked;
  bool get isRequested => this == LinkStatus.requested;
  bool get hasIncoming => this == LinkStatus.hasIncomingRequest;
  bool get isNotLinked => this == LinkStatus.notLinked;

  // Backward-compatibility aliases for legacy FollowStatus code
  static const LinkStatus notFollowing = LinkStatus.notLinked;
  static const LinkStatus following = LinkStatus.linked;
}

/// Backward compatibility typedef
typedef FollowStatus = LinkStatus;

class FollowService {
  static final FollowService _instance = FollowService._internal();
  factory FollowService() => _instance;
  FollowService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Reads ────────────────────────────────────────────────────────────────

  /// Stream of total linked users count for [uid].
  Stream<int> linksCountStream(String uid) {
    return _db
        .collection('follows')
        .where('followerId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.size);
  }

  /// Backward-compatibility aliases
  Stream<int> followersCountStream(String uid) => linksCountStream(uid);
  Stream<int> followingCountStream(String uid) => linksCountStream(uid);

  /// Returns the mutual link status between [currentUid] and [targetUid].
  Stream<LinkStatus> linkStatusStream(String currentUid, String targetUid) {
    if (currentUid.isEmpty || targetUid.isEmpty || currentUid == targetUid) {
      return Stream.value(LinkStatus.notLinked);
    }

    final outgoingStream = _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .snapshots();

    final incomingStream = _db
        .collection('follows')
        .where('followerId', isEqualTo: targetUid)
        .where('followingId', isEqualTo: currentUid)
        .snapshots();

    late StreamController<LinkStatus> controller;
    QuerySnapshot<Map<String, dynamic>>? lastOutgoing;
    QuerySnapshot<Map<String, dynamic>>? lastIncoming;
    StreamSubscription? subOut;
    StreamSubscription? subIn;

    void update() {
      if (controller.isClosed) return;

      final outDocs = lastOutgoing?.docs ?? [];
      final inDocs = lastIncoming?.docs ?? [];

      final outAccepted = outDocs.any((d) => d.data()['status'] == 'accepted');
      final inAccepted = inDocs.any((d) => d.data()['status'] == 'accepted');

      if (outAccepted || inAccepted) {
        controller.add(LinkStatus.linked);
        return;
      }

      final outPending = outDocs.any((d) => d.data()['status'] == 'pending');
      if (outPending) {
        controller.add(LinkStatus.requested);
        return;
      }

      final inPending = inDocs.any((d) => d.data()['status'] == 'pending');
      if (inPending) {
        controller.add(LinkStatus.hasIncomingRequest);
        return;
      }

      controller.add(LinkStatus.notLinked);
    }

    controller = StreamController<LinkStatus>(
      onListen: () {
        subOut = outgoingStream.listen((snap) {
          lastOutgoing = snap;
          update();
        }, onError: (e) {
          debugPrint('outgoingStream error: $e');
        });

        subIn = incomingStream.listen((snap) {
          lastIncoming = snap;
          update();
        }, onError: (e) {
          debugPrint('incomingStream error: $e');
        });
      },
      onCancel: () {
        subOut?.cancel();
        subIn?.cancel();
      },
    );

    return controller.stream.distinct();
  }

  /// Backward compatibility stream
  Stream<FollowStatus> followStatusStream(String currentUid, String targetUid) {
    return linkStatusStream(currentUid, targetUid);
  }

  /// List of UIDs that [uid] is linked with (accepted only).
  Stream<List<String>> linkedUidsStream(String uid) {
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

  /// Backward compatibility aliases
  Stream<List<String>> followingUidsStream(String uid) => linkedUidsStream(uid);
  Stream<List<String>> followersUidsStream(String uid) => linkedUidsStream(uid);

  /// Pending link requests sent TO [uid] (i.e. classmates who want to link up).
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

  /// Count of pending link requests for [uid].
  Stream<int> pendingRequestsCountStream(String uid) {
    return _db
        .collection('follows')
        .where('followingId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.size);
  }

  /// Check if [currentUid] can chat with [otherUid] (must be linked).
  Future<bool> canChat(String currentUid, String otherUid) async {
    if (currentUid.isEmpty || otherUid.isEmpty || currentUid == otherUid) {
      return false;
    }
    final a = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: otherUid)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (a.docs.isNotEmpty) return true;

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

  /// Send a link request to [targetUid].
  /// If [targetUid] already requested to link with currentUid, automatically accepts so both are linked!
  Future<void> sendLinkRequest(String targetUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currentUid = user.uid;
    if (currentUid == targetUid) return;

    // 1. If target already requested to link with us, accept immediately
    final incoming = await _db
        .collection('follows')
        .where('followerId', isEqualTo: targetUid)
        .where('followingId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (incoming.docs.isNotEmpty) {
      await acceptRequest(incoming.docs.first.id);
      return;
    }

    // 2. Check if already linked or request already sent
    final existing = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .limit(1)
        .get();

    if (existing.docs.isEmpty) {
      await _db.collection('follows').add({
        'followerId': currentUid,
        'followingId': targetUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Dispatch push notification to target user
      try {
        final senderName = UtopiaApp.sanitizeDisplayName(
          user.displayName ?? user.email?.split('@').first ?? 'Classmate',
        );
        await NotificationService.dispatchPushNotification(
          recipientId: targetUid,
          title: 'New Link Request 🔗',
          message: '$senderName wants to link up with you on UTOPIA',
          type: 'link_request',
        );
      } catch (e) {
        debugPrint('Error dispatching link_request notification: $e');
      }
    }
  }

  /// Accept a link request (doc identified by [requestDocId]).
  /// "one accepts, both are linked": Updates the request doc to accepted AND
  /// creates/updates the reverse doc to accepted so both users are mutually linked.
  Future<void> acceptRequest(String requestDocId) async {
    final requestDoc = await _db.collection('follows').doc(requestDocId).get();
    if (!requestDoc.exists) return;

    final data = requestDoc.data();
    if (data == null) return;

    final requesterId = (data['followerId'] ?? '').toString();
    final receiverId = (data['followingId'] ?? '').toString();

    // 1. Accept original link request
    await _db.collection('follows').doc(requestDocId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // 2. Automatically create/update reverse doc so BOTH are linked
    if (requesterId.isNotEmpty && receiverId.isNotEmpty) {
      final reverseExisting = await _db
          .collection('follows')
          .where('followerId', isEqualTo: receiverId)
          .where('followingId', isEqualTo: requesterId)
          .limit(1)
          .get();

      if (reverseExisting.docs.isNotEmpty) {
        await reverseExisting.docs.first.reference.update({
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('follows').add({
          'followerId': receiverId,
          'followingId': requesterId,
          'status': 'accepted',
          'createdAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      }

      // 3. Dispatch push notification to the original requester
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        final accepterName = UtopiaApp.sanitizeDisplayName(
          currentUser?.displayName ?? currentUser?.email?.split('@').first ?? 'Classmate',
        );
        await NotificationService.dispatchPushNotification(
          recipientId: requesterId,
          title: 'Linked Up! 🔗',
          message: '$accepterName accepted your link request. You are now linked!',
          type: 'link_accept',
        );
      } catch (e) {
        debugPrint('Error dispatching link_accept notification: $e');
      }
    }
  }

  /// Accept an incoming link request from a specific [targetUid].
  Future<void> acceptIncomingFrom(String targetUid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty || targetUid.isEmpty) return;

    final incoming = await _db
        .collection('follows')
        .where('followerId', isEqualTo: targetUid)
        .where('followingId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (incoming.docs.isNotEmpty) {
      await acceptRequest(incoming.docs.first.id);
    }
  }

  /// Cancel an outgoing pending link request to [targetUid].
  Future<void> cancelRequest(String targetUid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty || targetUid.isEmpty) return;

    final existing = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
  }

  /// Unlink both users mutually. Deletes documents in BOTH directions.
  Future<void> unlink(String targetUid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty || targetUid.isEmpty) return;

    // 1. Delete outgoing link doc
    final outDocs = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .get();
    for (final doc in outDocs.docs) {
      await doc.reference.delete();
    }

    // 2. Delete reverse link doc
    final inDocs = await _db
        .collection('follows')
        .where('followerId', isEqualTo: targetUid)
        .where('followingId', isEqualTo: currentUid)
        .get();
    for (final doc in inDocs.docs) {
      await doc.reference.delete();
    }
  }

  /// Decline / ignore a link request.
  Future<void> declineRequest(String requestDocId) async {
    await _db.collection('follows').doc(requestDocId).delete();
  }

  /// Remove link with [uid] (alias to unlink).
  Future<void> removeFollower(String uid) => unlink(uid);

  /// Toggle link helper:
  /// - If linked: unlinks both.
  /// - If requested: cancels request.
  /// - If has incoming request: accepts request.
  /// - If not linked: sends link request.
  Future<void> toggleLink(String targetUid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty || targetUid.isEmpty || currentUid == targetUid) return;

    // 1. Check incoming request
    final incoming = await _db
        .collection('follows')
        .where('followerId', isEqualTo: targetUid)
        .where('followingId', isEqualTo: currentUid)
        .limit(1)
        .get();

    if (incoming.docs.isNotEmpty) {
      final inStatus = incoming.docs.first.data()['status'] as String?;
      if (inStatus == 'pending') {
        await acceptRequest(incoming.docs.first.id);
        return;
      }
    }

    // 2. Check outgoing
    final outgoing = await _db
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .where('followingId', isEqualTo: targetUid)
        .limit(1)
        .get();

    if (outgoing.docs.isNotEmpty) {
      final outStatus = outgoing.docs.first.data()['status'] as String?;
      if (outStatus == 'accepted') {
        await unlink(targetUid);
      } else {
        await outgoing.docs.first.reference.delete();
      }
      return;
    }

    if (incoming.docs.isNotEmpty) {
      // Reverse link was accepted -> unlink both
      await unlink(targetUid);
      return;
    }

    // 3. Not linked -> send link request
    await sendLinkRequest(targetUid);
  }

  /// Legacy alias
  Future<void> toggleFollow(String targetUid) => toggleLink(targetUid);

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

/// Backward compatibility class alias
typedef LinkService = FollowService;
