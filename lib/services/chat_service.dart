import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime? _lastPresenceUpdateAt;
  String? _lastPresenceUid;

  String chatIdFor(String uidA, String uidB) {
    final ids = [uidA.trim(), uidB.trim()]..sort();
    return '${ids.first}_${ids.last}';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> usersStream() {
    return _firestore.collection('users').orderBy('displayName').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Stream<Map<String, Map<String, dynamic>>> recentChatsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream<Map<String, Map<String, dynamic>>>.value(const {});
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final data = <String, Map<String, dynamic>>{};
          for (final doc in snapshot.docs) {
            data[doc.id] = doc.data();
          }
          return data;
        });
  }

  Stream<Map<String, int>> recentChatRanksStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream<Map<String, int>>.value(const {});
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final docs = [...snapshot.docs];
          docs.sort((a, b) {
            final timeA = a.data()['lastMessageTime'] as Timestamp?;
            final timeB = b.data()['lastMessageTime'] as Timestamp?;
            if (timeA != null && timeB != null) {
              return timeB.compareTo(timeA);
            }
            if (timeA != null) {
              return -1;
            }
            if (timeB != null) {
              return 1;
            }
            return a.id.compareTo(b.id);
          });

          final ranks = <String, int>{};
          for (var index = 0; index < docs.length; index++) {
            final participants =
                (docs[index].data()['participants'] as List<dynamic>? ??
                        const [])
                    .map((value) => value.toString())
                    .toList();
            final otherUid = participants.firstWhere(
              (participant) => participant != uid,
              orElse: () => '',
            );
            if (otherUid.isNotEmpty) {
              ranks[otherUid] = index;
            }
          }
          return ranks;
        });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> chatStream(String chatId) {
    return _firestore.collection('chats').doc(chatId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> userStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Stream<int> unreadCountStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream<int>.value(0);
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          var total = 0;
          for (final doc in snapshot.docs) {
            final value = doc.data()['unreadCount_$uid'];
            if (value is int) {
              total += value;
            }
          }
          return total;
        });
  }

  Future<void> syncCurrentUserProfile({String? displayName}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': displayName ?? user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> touchPresence({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final now = DateTime.now();
    final sameUser = _lastPresenceUid == user.uid;
    final recentlyUpdated =
        _lastPresenceUpdateAt != null &&
        now.difference(_lastPresenceUpdateAt!) < const Duration(minutes: 1);
    if (!force && sameUser && recentlyUpdated) {
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _lastPresenceUid = user.uid;
      _lastPresenceUpdateAt = now;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendMessage({
    required String otherUserId,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final trimmed = text.trim();
    if (user == null || trimmed.isEmpty) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final chatRef = _firestore.collection('chats').doc(chatId);
    final messageRef = chatRef.collection('messages').doc();
    final sentAt = Timestamp.now();
    final previewText = trimmed;

    try {
      final batch = _firestore.batch();
      final messageData = <String, dynamic>{
        'senderId': user.uid,
        'text': trimmed,
        'timestamp': sentAt,
        'read': false,
      };
      if (replyTo != null) {
        messageData['replyTo'] = replyTo;
      }

      batch.set(messageRef, messageData);

      batch.set(chatRef, {
        'participants': [user.uid, otherUserId]..sort(),
        'lastMessageRaw': trimmed,
        'lastMessage': previewText,
        'lastMessageTime': sentAt,
        'unreadCount_${user.uid}': 0,
        'unreadCount_$otherUserId': FieldValue.increment(1),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendNoteShare({
    required String otherUserId,
    required String noteTitle,
    required String filePath,
    String? folderPath,
    required String segmentId,
    required String segmentPreview,
    required String segmentType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final chatRef = _firestore.collection('chats').doc(chatId);
    final messageRef = chatRef.collection('messages').doc();
    final sentAt = Timestamp.now();
    final previewText = 'Shared $noteTitle';

    try {
      final batch = _firestore.batch();
      batch.set(messageRef, {
        'senderId': user.uid,
        'text': previewText,
        'timestamp': sentAt,
        'read': false,
        'type': 'note_share',
        'noteShare': {
          'noteTitle': noteTitle,
          'filePath': filePath,
          'folderPath': folderPath,
          'segmentId': segmentId,
          'segmentPreview': segmentPreview,
          'segmentType': segmentType,
        },
      });

      batch.set(chatRef, {
        'participants': [user.uid, otherUserId]..sort(),
        'lastMessageRaw': previewText,
        'lastMessage': previewText,
        'lastMessageTime': sentAt,
        'unreadCount_${user.uid}': 0,
        'unreadCount_$otherUserId': FieldValue.increment(1),
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> markChatRead(String otherUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final chatRef = _firestore.collection('chats').doc(chatId);

    try {
      final unreadMessages = await chatRef
          .collection('messages')
          .where('senderId', isEqualTo: otherUserId)
          .where('read', isEqualTo: false)
          .get();

      if (unreadMessages.docs.isEmpty) {
        return;
      }

      final batch = _firestore.batch();
      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {'read': true});
      }
      batch.set(chatRef, {
        'unreadCount_${user.uid}': 0,
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearChatHistory(String otherUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final messagesRef =
        _firestore.collection('chats').doc(chatId).collection('messages');

    DocumentSnapshot? cursor;
    while (true) {
      Query query = messagesRef.orderBy('timestamp').limit(300);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < 300) {
        break;
      }

      cursor = snapshot.docs.last;
    }
  }

  Future<void> setTypingState({
    required String otherUserId,
    required bool isTyping,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final chatRef = _firestore.collection('chats').doc(chatId);

    try {
      await chatRef.set({
        'participants': [user.uid, otherUserId]..sort(),
        'typing_${user.uid}': isTyping,
        'typingUpdatedAt_${user.uid}': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> editMessage({
    required String otherUserId,
    required String messageId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final trimmed = text.trim();
    if (user == null || trimmed.isEmpty) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final messageRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    try {
      final snapshot = await messageRef.get();
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          (data['senderId'] ?? '').toString() != user.uid) {
        return;
      }

      await messageRef.update({
        'text': trimmed,
        'edited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });
      await _refreshChatMeta(chatId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> unsendMessage({
    required String otherUserId,
    required String messageId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final chatId = chatIdFor(user.uid, otherUserId);
    final messageRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    try {
      final snapshot = await messageRef.get();
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          (data['senderId'] ?? '').toString() != user.uid) {
        return;
      }

      await messageRef.update({
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'text': '',
        'type': 'text',
        'edited': false,
        'editedAt': FieldValue.delete(),
        'noteShare': FieldValue.delete(),
      });
      await _refreshChatMeta(chatId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _refreshChatMeta(String chatId) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    final latest = await _findLatestVisibleMessage(chatRef);

    if (latest == null) {
      await chatRef.set({
        'lastMessage': '',
        'lastMessageRaw': '',
        'lastMessageTime': FieldValue.delete(),
      }, SetOptions(merge: true));
      return;
    }

    final latestTimestamp = latest['timestamp'];
    final rawText = (latest['text'] ?? '').toString();
    final previewText = rawText;

    await chatRef.set({
      'lastMessageRaw': rawText,
      'lastMessage': previewText,
      'lastMessageTime': latestTimestamp,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> _findLatestVisibleMessage(
    DocumentReference<Map<String, dynamic>> chatRef,
  ) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;

    while (true) {
      var query = chatRef
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(25);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        return null;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if ((data['deleted'] ?? false) != true) {
          return data;
        }
      }

      cursor = snapshot.docs.last;
    }
  }
}
