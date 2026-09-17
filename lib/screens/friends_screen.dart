import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/chat_service.dart';
import '../services/follow_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/superuser_badge.dart';
import 'chat_screen.dart';
import 'follow_requests_screen.dart';
import 'link_graph_screen.dart';

/// Friends screen – shows:
///   • Tab 0: Following (people the current user follows back, i.e., mutual)
///   • Tab 1: Requests badge (navigates to [FollowRequestsScreen])
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final FollowService _followService = FollowService();

  late final TabController _tabController;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isSearching
                    ? Row(
                        key: const ValueKey('search'),
                        children: [
                          Expanded(
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: U.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: U.border),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Icon(Icons.search, color: U.sub, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      autofocus: true,
                                      style: GoogleFonts.outfit(
                                          color: U.text, fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'Search following...',
                                        hintStyle: GoogleFonts.outfit(
                                            color: U.dim),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: Icon(Icons.close,
                                          color: U.sub, size: 16),
                                      onPressed: _searchController.clear,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () => setState(() {
                              _isSearching = false;
                              _searchController.clear();
                            }),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('title'),
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: U.text,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.pop(context),
                            ),
                          if (Navigator.canPop(context))
                            const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Friends',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: U.text,
                              ),
                            ),
                          ),
                          // Requests bell
                          StreamBuilder<int>(
                            stream: _followService
                                .pendingRequestsCountStream(_currentUid),
                            builder: (context, snap) {
                              final count = snap.data ?? 0;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        buildForwardRoute(
                                          FollowRequestsScreen(
                                              currentUid: _currentUid),
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.person_add_outlined,
                                      color: U.primary,
                                      size: 22,
                                    ),
                                    tooltip: 'Link Requests',
                                    splashRadius: 20,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  if (count > 0)
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: U.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            count > 9 ? '9+' : '$count',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _isSearching = true),
                            icon: Icon(
                              Icons.search_rounded,
                              color: U.primary,
                              size: 20,
                            ),
                            tooltip: 'Search',
                            splashRadius: 20,
                            visualDensity: VisualDensity.compact,
                          ),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    buildGraphCrossfadeRoute(const LinkGraphScreen()),
                                  );
                                },
                                icon: Icon(
                                  Icons.hub_outlined,
                                  color: U.primary,
                                  size: 20,
                                ),
                                tooltip: 'Link Graph View',
                                splashRadius: 20,
                                visualDensity: VisualDensity.compact,
                              ),
                              Positioned(
                                top: 0,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: U.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'BETA',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: 7,
                                      fontWeight: FontWeight.w700,
                                      color: U.getContrastColor(U.primary),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 10),
            Divider(color: U.border, height: 1, thickness: 0.5),

            // ── Following list ─────────────────────────────────────────────
            Expanded(
              child: _FollowingList(
                currentUid: _currentUid,
                chatService: _chatService,
                followService: _followService,
                query: _searchController.text.trim().toLowerCase(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowingList extends StatefulWidget {
  const _FollowingList({
    required this.currentUid,
    required this.chatService,
    required this.followService,
    required this.query,
  });

  final String currentUid;
  final ChatService chatService;
  final FollowService followService;
  final String query;

  @override
  State<_FollowingList> createState() => _FollowingListState();
}

class _FollowingListState extends State<_FollowingList> {
  /// Local cache: uid → last-chat-time millis. Persisted to SharedPreferences.
  Map<String, int> _chatOrderCache = {};
  /// Cached user data so the list paints instantly while Firestore loads.
  Map<String, Map<String, dynamic>> _userDataCache = {};
  bool _cacheLoaded = false;

  static const String _orderCacheKey = 'friends_chat_order_cache';
  static const String _userCacheKey = 'friends_user_data_cache';

  @override
  void initState() {
    super.initState();
    _loadLocalCache();
  }

  /// Load cached chat order and user data from SharedPreferences.
  Future<void> _loadLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load chat order cache
      final orderJson = prefs.getString(_orderCacheKey);
      if (orderJson != null) {
        final decoded = (json.decode(orderJson) as Map<String, dynamic>);
        _chatOrderCache = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      // Load user data cache
      final userJson = prefs.getString(_userCacheKey);
      if (userJson != null) {
        final decoded = (json.decode(userJson) as Map<String, dynamic>);
        _userDataCache = decoded.map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        );
      }
    } catch (_) {
      // Corrupt cache – ignore, will be rebuilt from Firestore
    }
    if (mounted) setState(() => _cacheLoaded = true);
  }

  /// Persist chat order to SharedPreferences (fire-and-forget).
  void _saveOrderCache(Map<String, int> order) {
    _chatOrderCache = order;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_orderCacheKey, json.encode(order));
    }).catchError((_) {});
  }

  /// Persist user data to SharedPreferences (fire-and-forget).
  void _saveUserDataCache(Map<String, Map<String, dynamic>> data) {
    _userDataCache = data;
    SharedPreferences.getInstance().then((prefs) {
      // Only cache safe JSON-serialisable fields
      final safe = data.map((k, v) => MapEntry(k, {
        'uid': v['uid'],
        'displayName': v['displayName'],
        'email': v['email'],
        'photoUrl': v['photoUrl'],
        'bio': v['bio'],
        'role': v['role'],
        'branch': v['branch'],
      }));
      prefs.setString(_userCacheKey, json.encode(safe));
    }).catchError((_) {});
  }

  /// Build a map of otherUid → lastMessageTime millis from recentChats data.
  Map<String, int> _buildSortKeys(Map<String, Map<String, dynamic>> recentChats) {
    final sortKeys = <String, int>{};
    for (final entry in recentChats.entries) {
      final chat = entry.value;
      final participants = (chat['participants'] as List<dynamic>? ?? const [])
          .map((p) => p.toString())
          .toList();
      var otherUid = participants.firstWhere(
        (p) => p != widget.currentUid && p.isNotEmpty,
        orElse: () => '',
      );

      // Fallback: extract otherUid from doc ID if participants array was missing
      if (otherUid.isEmpty && entry.key.contains('_')) {
        final parts = entry.key.split('_');
        if (parts.length == 2) {
          if (parts[0] == widget.currentUid) {
            otherUid = parts[1];
          } else if (parts[1] == widget.currentUid) {
            otherUid = parts[0];
          }
        }
      }

      if (otherUid.isEmpty) continue;

      final raw = chat['lastMessageTime'] ?? chat['timestamp'] ?? chat['updatedAt'];
      int? millis;
      if (raw is Timestamp) {
        millis = raw.toDate().millisecondsSinceEpoch;
      } else if (raw is DateTime) {
        millis = raw.millisecondsSinceEpoch;
      } else if (raw is int) {
        millis = raw;
      } else if (raw is String) {
        millis = DateTime.tryParse(raw)?.millisecondsSinceEpoch;
      }

      if (millis != null) {
        // Keep the latest time if multiple chats exist with same user
        if (!sortKeys.containsKey(otherUid) || millis > sortKeys[otherUid]!) {
          sortKeys[otherUid] = millis;
        }
      }
    }
    return sortKeys;
  }

  Map<String, dynamic>? _getChatMeta(
    String otherUid,
    Map<String, Map<String, dynamic>> recentChats,
  ) {
    // Direct match by sorted chatId
    final sortedChatId = widget.chatService.chatIdFor(widget.currentUid, otherUid);
    final byChatId = recentChats[sortedChatId];
    if (byChatId != null) return byChatId;

    // Direct match by unsorted / reverse chatId
    final unsortedChatId = '${widget.currentUid}_$otherUid';
    if (recentChats[unsortedChatId] != null) return recentChats[unsortedChatId];
    final reverseChatId = '${otherUid}_${widget.currentUid}';
    if (recentChats[reverseChatId] != null) return recentChats[reverseChatId];

    // Search all recentChats for any doc where otherUid is a participant or key contains otherUid
    for (final entry in recentChats.entries) {
      final chat = entry.value;
      final participants = (chat['participants'] as List<dynamic>? ?? const [])
          .map((p) => p.toString())
          .toList();
      if (participants.contains(otherUid) || entry.key.contains(otherUid)) return chat;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: widget.chatService.recentChatsStream(),
      builder: (context, recentChatsSnap) {
        final recentChats = recentChatsSnap.data ?? const {};
        final liveSortKeys = _buildSortKeys(recentChats);

        // Merge live sort keys into the local cache so we always have the freshest
        if (liveSortKeys.isNotEmpty) {
          final merged = Map<String, int>.from(_chatOrderCache);
          merged.addAll(liveSortKeys);
          if (merged.toString() != _chatOrderCache.toString()) {
            _saveOrderCache(merged);
          }
        }

        // Effective sort keys: live data takes priority, cached fills gaps
        final effectiveSortKeys = Map<String, int>.from(_chatOrderCache);
        effectiveSortKeys.addAll(liveSortKeys);

        return StreamBuilder<List<String>>(
          stream: widget.followService.followingUidsStream(widget.currentUid),
          builder: (context, followingSnap) {
            if (followingSnap.connectionState == ConnectionState.waiting &&
                recentChatsSnap.connectionState == ConnectionState.waiting &&
                !_cacheLoaded) {
              return const _FriendsSkeleton();
            }

            final followingUids = followingSnap.data ?? [];

            // Collect other UIDs from recent chats
            final recentChatOtherUids = <String>{};
            for (final entry in recentChats.entries) {
              final participants = (entry.value['participants'] as List<dynamic>? ?? const [])
                  .map((p) => p.toString())
                  .toList();
              for (final p in participants) {
                if (p != widget.currentUid && p.isNotEmpty) {
                  recentChatOtherUids.add(p);
                }
              }
            }

            final allRelevantUids = {...followingUids, ...recentChatOtherUids};

            if (allRelevantUids.isEmpty && _userDataCache.isEmpty) {
              return const _FriendsEmptyState(
                icon: Icons.link_rounded,
                title: 'No linked friends or chats yet',
                subtitle: 'Go to People to find classmates and link up.',
              );
            }

            // Batch-fetch user docs using whereIn (max 30 per query)
            final uidsList = allRelevantUids.toList();
            if (uidsList.isEmpty) {
              return _buildList([], recentChats, effectiveSortKeys);
            }

            // Split into batches of 30 (Firestore whereIn limit)
            final batches = <List<String>>[];
            for (var i = 0; i < uidsList.length; i += 30) {
              batches.add(uidsList.sublist(i, i + 30 > uidsList.length ? uidsList.length : i + 30));
            }

            return StreamBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
              stream: _batchUsersStream(batches),
              builder: (context, usersSnap) {
                List<Map<String, dynamic>> users;

                if (usersSnap.hasData && usersSnap.data != null) {
                  // Build from live data
                  users = [];
                  for (final qs in usersSnap.data!) {
                    for (final doc in qs.docs) {
                      users.add({'uid': doc.id, ...doc.data()});
                    }
                  }
                  // Update user data cache
                  final newCache = <String, Map<String, dynamic>>{};
                  for (final u in users) {
                    newCache[u['uid'].toString()] = u;
                  }
                  _saveUserDataCache(newCache);
                } else if (_userDataCache.isNotEmpty) {
                  // Use cached data while waiting
                  users = _userDataCache.values
                      .where((u) => allRelevantUids.contains(u['uid']))
                      .toList();
                } else {
                  return const _FriendsSkeleton();
                }

                return _buildList(users, recentChats, effectiveSortKeys);
              },
            );
          },
        );
      },
    );
  }

  /// Combine multiple batched whereIn queries into a single stream.
  Stream<List<QuerySnapshot<Map<String, dynamic>>>> _batchUsersStream(
    List<List<String>> batches,
  ) {
    if (batches.isEmpty) {
      return Stream.value([]);
    }
    if (batches.length == 1) {
      return FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batches[0])
          .snapshots()
          .map((qs) => [qs]);
    }

    final streams = batches.map((batch) {
      return FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .snapshots();
    }).toList();

    // Combine all streams
    return streams.first.asyncExpand((firstSnapshot) {
      if (streams.length == 1) return Stream.value([firstSnapshot]);
      // For simplicity, combine using CombineLatestStream-style manual approach
      return _combineSnapshots(streams);
    });
  }

  Stream<List<QuerySnapshot<Map<String, dynamic>>>> _combineSnapshots(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> streams,
  ) {
    final latest = List<QuerySnapshot<Map<String, dynamic>>?>.filled(streams.length, null);
    final controller = StreamController<List<QuerySnapshot<Map<String, dynamic>>>>.broadcast();
    final subs = <StreamSubscription>[];

    for (var i = 0; i < streams.length; i++) {
      final idx = i;
      subs.add(streams[idx].listen((snap) {
        latest[idx] = snap;
        if (latest.every((s) => s != null)) {
          controller.add(latest.cast<QuerySnapshot<Map<String, dynamic>>>().toList());
        }
      }));
    }

    controller.onCancel = () {
      for (final sub in subs) {
        sub.cancel();
      }
    };

    return controller.stream;
  }

  Widget _buildList(
    List<Map<String, dynamic>> users,
    Map<String, Map<String, dynamic>> recentChats,
    Map<String, int> sortKeys,
  ) {
    final query = widget.query;

    // Filter by search query
    var filtered = users.where((u) {
      if (query.isEmpty) return true;
      final name = (u['displayName'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final branch = (u['branch'] ?? '').toString().toLowerCase();
      return name.contains(query) || email.contains(query) || branch.contains(query);
    }).toList();

    // Sort: most recent chat first, then alphabetical
    filtered.sort((a, b) {
      final uidA = a['uid'].toString();
      final uidB = b['uid'].toString();
      final timeA = sortKeys[uidA];
      final timeB = sortKeys[uidB];

      // Both have chat times → most recent first
      if (timeA != null && timeB != null) {
        final cmp = timeB.compareTo(timeA);
        if (cmp != 0) return cmp;
      }
      // Only one has a chat time → that one goes first
      if (timeA != null) return -1;
      if (timeB != null) return 1;
      // Neither → alphabetical
      final nameA = (a['displayName'] ?? '').toString().toLowerCase();
      final nameB = (b['displayName'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    if (filtered.isEmpty) {
      return const _FriendsEmptyState(
        icon: Icons.person_search_outlined,
        title: 'No results',
        subtitle: 'Try a different search term.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: filtered.length,
      separatorBuilder: (_, __) => Divider(
        color: U.border,
        height: 1,
        thickness: 0.5,
        indent: 76,
      ),
      itemBuilder: (context, index) {
        final user = filtered[index];
        final uid = user['uid'].toString();
        final chatMeta = _getChatMeta(uid, recentChats);

        return _FriendRow(
          user: user,
          chatMeta: chatMeta,
          currentUid: widget.currentUid,
          followService: widget.followService,
          onTap: () {
            Navigator.of(context).push(
              buildForwardRoute(
                ChatScreen(
                  otherUserId: uid,
                  displayName: UtopiaApp.sanitizeDisplayName(
                    (user['displayName'] ?? 'Friend').toString(),
                  ),
                  email: (user['email'] ?? '').toString(),
                  photoUrl: user['photoUrl']?.toString(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

DateTime? _extractChatTimeFromMeta(Map<String, dynamic>? meta) {
  if (meta == null) return null;
  final raw = meta['lastMessageTime'] ?? meta['timestamp'] ?? meta['updatedAt'];
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

// ─── Friend row ───────────────────────────────────────────────────────────────

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.user,
    required this.chatMeta,
    required this.currentUid,
    required this.followService,
    required this.onTap,
  });

  final Map<String, dynamic> user;
  final Map<String, dynamic>? chatMeta;
  final String currentUid;
  final FollowService followService;
  final VoidCallback onTap;

  String _formatChatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && dt.day != now.day)) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  String _extractText(Map<String, dynamic>? meta) {
    if (meta == null) return '';
    final raw = (meta['lastMessageRaw'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    final preview = (meta['lastMessage'] ?? '').toString().trim();
    if (preview.isNotEmpty) return preview;
    final alt = (meta['last_message'] ?? meta['message'] ?? meta['text'] ?? '').toString().trim();
    if (alt.isNotEmpty) return alt;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final directMsg = _extractText(chatMeta);
    final directTime = _extractChatTimeFromMeta(chatMeta);

    if (directMsg.isNotEmpty && directTime != null) {
      return _buildRowContent(context, directMsg, directTime, chatMeta);
    }

    final otherUid = (user['uid'] ?? '').toString();
    final chatId = ChatService().chatIdFor(currentUid, otherUid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, msgSnap) {
        String msg = directMsg;
        DateTime? dt = directTime;

        if (msgSnap.hasData && msgSnap.data!.docs.isNotEmpty) {
          final docData = msgSnap.data!.docs.first.data();
          final mediaType = docData['mediaType'] as String?;
          final rawText = (docData['text'] ?? docData['content'] ?? docData['message'] ?? '').toString().trim();
          final previewText = mediaType != null && mediaType.isNotEmpty
              ? (mediaType == 'gif' ? '👾 GIF' : (mediaType == 'sticker' ? '🎨 Sticker' : 'Media'))
              : rawText;
          final timestamp = docData['timestamp'];

          if (msg.isEmpty) msg = previewText;
          if (dt == null) {
            if (timestamp is Timestamp) dt = timestamp.toDate();
            else if (timestamp is DateTime) dt = timestamp;
            else if (timestamp is int) dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
          }
        }

        return _buildRowContent(
          context,
          msg.isNotEmpty ? msg : 'No messages yet',
          dt,
          chatMeta,
        );
      },
    );
  }

  Widget _buildRowContent(
    BuildContext context,
    String displayMessage,
    DateTime? lastMessageTime,
    Map<String, dynamic>? meta,
  ) {
    final displayName = UtopiaApp.sanitizeDisplayName((user['displayName'] ?? 'Friend').toString());
    final photoUrl = user['photoUrl']?.toString();
    final lastSeen = user['lastSeen'];
    final unreadCount = (meta?['unreadCount_$currentUid'] as num?)?.toInt() ?? 0;
    final isOnline = lastSeen is Timestamp &&
        DateTime.now().difference(lastSeen.toDate()) <= const Duration(minutes: 5);

    return InkWell(
      onTap: onTap,
      splashColor: U.primary.withValues(alpha: 0.05),
      highlightColor: U.primary.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: U.primary.withValues(alpha: 0.16),
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImageProvider(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? Text(
                          displayName.isEmpty ? 'U' : displayName[0].toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: U.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: U.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Name + last message preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: U.text,
                            fontSize: 15,
                            fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (user['role'] == 'superuser') ...[
                        const SizedBox(width: 4),
                        const SuperUserBadge(size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    displayMessage,
                    style: GoogleFonts.outfit(
                      color: unreadCount > 0 ? U.text : U.sub,
                      fontSize: 12.5,
                      fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Time & unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lastMessageTime != null
                      ? _formatChatTime(lastMessageTime)
                      : isOnline
                          ? 'Online'
                          : _lastSeenLabel(lastSeen),
                  style: GoogleFonts.outfit(
                    color: unreadCount > 0
                        ? U.primary
                        : isOnline
                            ? U.green
                            : U.sub,
                    fontSize: 11,
                    fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          U.primary,
                          U.primary.withValues(alpha: 0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: U.primary.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: GoogleFonts.outfit(
                        color: U.getContrastColor(U.primary),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _lastSeenLabel(dynamic raw) {
    if (raw is! Timestamp) return 'Offline';
    final diff = DateTime.now().difference(raw.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Skeleton / Empty ─────────────────────────────────────────────────────────

class _FriendsSkeleton extends StatelessWidget {
  const _FriendsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 8,
      separatorBuilder: (_, _) =>
          Divider(color: U.border, height: 1, thickness: 0.5, indent: 72),
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: const [
            SkeletonBox(height: 44, width: 44, radius: 22),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 16, width: 140, radius: 8),
                  SizedBox(height: 8),
                  SkeletonBox(height: 12, width: 180, radius: 8),
                ],
              ),
            ),
            SizedBox(width: 12),
            SkeletonBox(height: 12, width: 52, radius: 8),
          ],
        ),
      ),
    );
  }
}

class _FriendsEmptyState extends StatelessWidget {
  const _FriendsEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: U.dim),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.outfit(color: U.sub, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
