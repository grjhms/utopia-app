import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UniChatService {
  static final UniChatService _instance = UniChatService._internal();
  factory UniChatService() => _instance;
  UniChatService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Mark the chat for [universityId] as seen by the current user.
  /// Stores in Firestore user document under `lastSeenUniChat.{universityId}`
  /// and local SharedPreferences so it persists across device sessions and relogins.
  Future<void> markAsSeen(String universityId) async {
    final cleanUniId = universityId.trim().toLowerCase();
    final uid = _currentUid;
    final nowMillis = DateTime.now().millisecondsSinceEpoch;

    // Fast local persistence
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_seen_unichat_${cleanUniId}_millis', nowMillis);
    } catch (_) {}

    // Cross-session & relogin persistence in Firestore user document
    if (uid != null && uid.isNotEmpty) {
      try {
        await _firestore.collection('users').doc(uid).set({
          'lastSeenUniChat': {
            cleanUniId: FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Mark a single message as viewed by [userId] in [universityId].
  Future<void> markMessageAsViewed({
    required String universityId,
    required String messageId,
    required String userId,
  }) async {
    final cleanUniId = universityId.trim().toLowerCase();
    if (userId.isEmpty || cleanUniId.isEmpty || messageId.isEmpty) return;
    try {
      await _firestore
          .collection('uni_chats')
          .doc(cleanUniId)
          .collection('messages')
          .doc(messageId)
          .update({
        'views': FieldValue.arrayUnion([userId]),
        'viewCount': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  /// Batch mark multiple messages as viewed by [userId] in [universityId].
  Future<void> markMessagesAsViewed({
    required String universityId,
    required List<String> messageIds,
    required String userId,
  }) async {
    final cleanUniId = universityId.trim().toLowerCase();
    if (userId.isEmpty || cleanUniId.isEmpty || messageIds.isEmpty) return;
    try {
      final batch = _firestore.batch();
      final collection = _firestore
          .collection('uni_chats')
          .doc(cleanUniId)
          .collection('messages');
      for (final id in messageIds.take(20)) {
        batch.update(collection.doc(id), {
          'views': FieldValue.arrayUnion([userId]),
          'viewCount': FieldValue.increment(1),
        });
      }
      await batch.commit();
    } catch (_) {}
  }

  final Map<String, Stream<bool>> _unreadStreams = {};

  /// Real-time stream indicating whether the current user has unread messages
  /// in [universityId] chat.
  ///
  /// Evaluates to `false` if:
  /// - User is logged out
  /// - There are no messages
  /// - The latest message was authored by the current user
  /// - The latest message timestamp is <= user's lastSeen timestamp (from Firestore or local fallback)
  ///
  /// Evaluates to `true` if:
  /// - There is a message authored by another user with timestamp > lastSeen timestamp
  /// - The user has never viewed the chat yet and there are messages from others
  Stream<bool> unreadStatusStream(String universityId) {
    final cleanUniId = universityId.trim().toLowerCase();
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(false);
    }

    final cacheKey = '${uid}_$cleanUniId';
    if (_unreadStreams.containsKey(cacheKey)) {
      return _unreadStreams[cacheKey]!;
    }

    final userDocStream = _firestore.collection('users').doc(uid).snapshots();
    final latestMessageStream = _firestore
        .collection('uni_chats')
        .doc(cleanUniId.isNotEmpty ? cleanUniId : 'support')
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots();

    final stream = _combineStreams(userDocStream, latestMessageStream, cleanUniId, uid);
    _unreadStreams[cacheKey] = stream;
    return stream;
  }

  Stream<bool> _combineStreams(
    Stream<DocumentSnapshot<Map<String, dynamic>>> userStream,
    Stream<QuerySnapshot<Map<String, dynamic>>> messageStream,
    String universityId,
    String uid,
  ) {
    late StreamController<bool> controller;
    StreamSubscription? userSub;
    StreamSubscription? msgSub;

    Timestamp? lastSeenTimestamp;
    QueryDocumentSnapshot<Map<String, dynamic>>? latestMsgDoc;
    bool hasReceivedUser = false;
    bool hasReceivedMsg = false;

    void evaluate() {
      if (!hasReceivedUser || !hasReceivedMsg) return;

      if (latestMsgDoc == null) {
        controller.add(false);
        return;
      }

      final data = latestMsgDoc!.data();
      final senderId = data['senderId'] as String?;
      if (senderId == uid) {
        // User themselves sent the latest message, so it is already seen
        controller.add(false);
        return;
      }

      final msgTimestamp = data['timestamp'] as Timestamp?;
      if (msgTimestamp == null) {
        // Pending local message
        controller.add(false);
        return;
      }

      if (lastSeenTimestamp == null) {
        // User has no recorded seen timestamp in Firestore -> unread
        controller.add(true);
        return;
      }

      // Check if the latest message timestamp is strictly newer than lastSeen
      final isNewer = msgTimestamp.compareTo(lastSeenTimestamp!) > 0;
      controller.add(isNewer);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        userSub = userStream.listen(
          (userDoc) {
            hasReceivedUser = true;
            if (userDoc.exists) {
              final userData = userDoc.data();
              final map = userData?['lastSeenUniChat'] as Map<String, dynamic>?;
              final ts = map?[universityId];
              if (ts is Timestamp) {
                lastSeenTimestamp = ts;
              }
            }
            evaluate();
          },
          onError: (_) {
            hasReceivedUser = true;
            evaluate();
          },
        );

        msgSub = messageStream.listen(
          (querySnap) {
            hasReceivedMsg = true;
            if (querySnap.docs.isNotEmpty) {
              latestMsgDoc = querySnap.docs.first;
            } else {
              latestMsgDoc = null;
            }
            evaluate();
          },
          onError: (_) {
            hasReceivedMsg = true;
            evaluate();
          },
        );
      },
      onCancel: () {
        userSub?.cancel();
        msgSub?.cancel();
      },
    );

    return controller.stream.distinct();
  }
}
