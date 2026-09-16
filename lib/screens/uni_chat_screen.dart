import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../services/uni_chat_service.dart';
import '../services/role_service.dart';
import '../widgets/chat_media_picker.dart';
import '../widgets/unread_indicator_dot.dart';
import '../widgets/utopia_loader.dart';
import 'user_profile_screen.dart';

class UniChatScreen extends StatefulWidget {
  final String universityId;
  const UniChatScreen({super.key, required this.universityId});

  @override
  State<UniChatScreen> createState() => _UniChatScreenState();
}

class _UniChatScreenState extends State<UniChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  bool _sending = false;
  DateTime? _lastSent;
  String? _editingMessageId;
  Map<String, dynamic>? _replyingToMessage;
  bool _showScrollDown = false;
  bool _hasNewMessagesWhileScrolled = false;
  String? _lastSeenTopDocId;
  String _utopiaChatNotifMode = 'replies'; // 'all', 'replies', 'off'
  final Set<String> _touchedMessageIds = {};
  final Set<String> _locallyViewedDocIds = {};
  bool _isSuperUser = false;

  // Search & reaction states
  bool _searchActive = false;
  String _searchQuery = '';
  String? _activeReactionMessageId;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _currentName => FirebaseAuth.instance.currentUser?.displayName ?? 'Student';
  String get _currentEmail => FirebaseAuth.instance.currentUser?.email ?? '';

  static const List<String> _quickReactions = ['❤️', '🔥', '😂', '⚡', '💀', '🎓'];


  int _getViewCount(Map<String, dynamic> data) {
    final views = data['views'];
    if (views is List) {
      return views.isNotEmpty ? views.length : 1;
    }
    final count = data['viewCount'] ?? data['viewsCount'];
    if (count is int && count > 0) {
      return count;
    }
    return 1;
  }

  void _trackVisibleViews(List<QueryDocumentSnapshot> docs) {
    if (_currentUid.isEmpty || _effectiveUniversityId.isEmpty) return;
    final unviewedDocIds = <String>[];
    for (final doc in docs) {
      if (_locallyViewedDocIds.contains(doc.id)) continue;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final views = data['views'];
      final hasViewed = views is List && views.contains(_currentUid);
      if (!hasViewed) {
        _locallyViewedDocIds.add(doc.id);
        unviewedDocIds.add(doc.id);
      } else {
        _locallyViewedDocIds.add(doc.id);
      }
    }
    if (unviewedDocIds.isNotEmpty) {
      UniChatService().markMessagesAsViewed(
        universityId: _effectiveUniversityId,
        messageIds: unviewedDocIds,
        userId: _currentUid,
      );
    }
  }

  // Palette for distinctive student sender identity colors
  static const List<Color> _senderPalette = [
    Color(0xFF38BDF8), // Sky
    Color(0xFF818CF8), // Indigo
    Color(0xFFA78BFA), // Violet
    Color(0xFFF472B6), // Pink
    Color(0xFFFB7185), // Rose
    Color(0xFFFBBF24), // Amber
    Color(0xFF34D399), // Emerald
    Color(0xFF2DD4BF), // Teal
  ];

  Color _getSenderColor(String name) {
    final hash = name.hashCode.abs();
    return _senderPalette[hash % _senderPalette.length];
  }

  late String _effectiveUniversityId;
  late Stream<QuerySnapshot> _messagesStream;

  @override
  void initState() {
    super.initState();
    _effectiveUniversityId = widget.universityId.isNotEmpty && widget.universityId != 'support'
        ? widget.universityId
        : (U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : widget.universityId);

    NotificationService.setActiveChat('uni_$_effectiveUniversityId');
    _loadNotifPreference();
    _checkSuperUserRole();
    _initMessagesStream();
    _resolveUniversityId();
    _scrollController.addListener(_onScroll);
  }

  void _checkSuperUserRole() {
    RoleService().isSuperUser().then((isSuper) {
      if (mounted) setState(() => _isSuperUser = isSuper);
    });
  }

  Future<void> _loadNotifPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('pref_notif_utopia_chat_mode') ?? 'replies';
      if (mounted) {
        setState(() => _utopiaChatNotifMode = mode);
      }
      final uid = _currentUid;
      if (uid.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && mounted) {
          final data = doc.data() ?? {};
          final notifPrefs = (data['notification_preferences'] as Map<String, dynamic>?) ?? {};
          final remoteMode = (notifPrefs['utopia_chat'] as String?) ??
              (data['notif_utopia_chat_mode'] as String?);
          if (remoteMode != null && remoteMode.isNotEmpty && mounted) {
            setState(() => _utopiaChatNotifMode = remoteMode);
            await prefs.setString('pref_notif_utopia_chat_mode', remoteMode);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _updateNotifMode(String mode) async {
    HapticFeedback.selectionClick();
    setState(() => _utopiaChatNotifMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_notif_utopia_chat_mode', mode);

    final uid = _currentUid;
    if (uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'notification_preferences': {
            'utopia_chat': mode,
          },
          'notif_utopia_chat_mode': mode,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating utopia chat notification mode: $e');
      }
    }
  }

  void _initMessagesStream() {
    final uniId = _effectiveUniversityId.isNotEmpty ? _effectiveUniversityId : 'support';
    _messagesStream = FirebaseFirestore.instance
        .collection('uni_chats')
        .doc(uniId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
    UniChatService().markAsSeen(uniId);
  }

  Future<void> _resolveUniversityId() async {
    final uid = _currentUid;
    if (uid.isNotEmpty && (_effectiveUniversityId.isEmpty || _effectiveUniversityId == 'support')) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final selectedId = doc.data()?['selectedUniversityId'] as String?;
        if (selectedId != null && selectedId.isNotEmpty && selectedId != _effectiveUniversityId) {
          if (mounted) {
            setState(() {
              _effectiveUniversityId = selectedId;
              U.cachedUniversityId = selectedId;
              NotificationService.setActiveChat('uni_$selectedId');
              _initMessagesStream();
            });
            unawaited(CacheService().saveAppSetting('cached_university_id', selectedId));
          }
        }
      } catch (_) {}
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final show = offset > 140.0;
    if (show != _showScrollDown) {
      setState(() => _showScrollDown = show);
    }
    if (offset <= 30.0) {
      if (_hasNewMessagesWhileScrolled) {
        setState(() => _hasNewMessagesWhileScrolled = false);
      }
      UniChatService().markAsSeen(_effectiveUniversityId);
    }
  }

  void _scrollToBottom() {
    HapticFeedback.lightImpact();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    if (_hasNewMessagesWhileScrolled) {
      setState(() => _hasNewMessagesWhileScrolled = false);
    }
    UniChatService().markAsSeen(_effectiveUniversityId);
  }

  /// Evaluates whether a string consists ONLY of 1-4 emojis (with optional whitespace).
  bool _isOnlyEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
    );
    final stripped = trimmed.replaceAll(emojiRegex, '').replaceAll(RegExp(r'\s+'), '');
    if (stripped.isNotEmpty) return false;

    final matches = emojiRegex.allMatches(trimmed);
    return matches.isNotEmpty && matches.length <= 4;
  }

  int _countEmojiCharacters(String text) {
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
    );
    return emojiRegex.allMatches(text.trim()).length;
  }

  String? _extractFirstUrl(String text) {
    final urlRegex = RegExp(
      r'(https?:\/\/[^\s]+)',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    if (_editingMessageId != null) {
      final msgId = _editingMessageId!;
      setState(() => _sending = true);
      try {
        await FirebaseFirestore.instance
            .collection('uni_chats')
            .doc(_effectiveUniversityId)
            .collection('messages')
            .doc(msgId)
            .update({
          'text': text,
          'isEdited': true,
          'editedAt': FieldValue.serverTimestamp(),
        });
        _controller.clear();
        setState(() {
          _editingMessageId = null;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to edit message', style: GoogleFonts.plusJakartaSans(color: U.bg)),
              backgroundColor: U.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    if (_lastSent != null && DateTime.now().difference(_lastSent!).inSeconds < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Slow down a moment!', style: GoogleFonts.plusJakartaSans(color: U.bg)),
          backgroundColor: U.red,
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{
        'text': text,
        'senderId': _currentUid,
        'senderName': _currentName,
        'senderEmail': _currentEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'views': [_currentUid],
        'viewCount': 1,
      };

      if (_replyingToMessage != null) {
        payload['replyTo'] = {
          'id': _replyingToMessage!['id'],
          'text': _replyingToMessage!['text'],
          'senderName': _replyingToMessage!['senderName'],
          'senderId': _replyingToMessage!['senderId'] ?? '',
          if (_replyingToMessage!['mediaUrl'] != null) 'mediaUrl': _replyingToMessage!['mediaUrl'],
          if (_replyingToMessage!['mediaType'] != null) 'mediaType': _replyingToMessage!['mediaType'],
        };
      }

      await FirebaseFirestore.instance
          .collection('uni_chats')
          .doc(_effectiveUniversityId)
          .collection('messages')
          .add(payload);

      UniChatService().markAsSeen(_effectiveUniversityId);

      _controller.clear();
      _lastSent = DateTime.now();
      setState(() {
        _replyingToMessage = null;
      });
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message', style: GoogleFonts.plusJakartaSans(color: U.bg)),
            backgroundColor: U.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMedia({
    required String mediaUrl,
    required String mediaType, // 'gif' or 'sticker'
  }) async {
    if (_sending) return;

    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{
        'text': mediaType == 'gif' ? '👾 GIF' : '🎨 Sticker',
        'mediaUrl': mediaUrl,
        'mediaType': mediaType,
        'senderId': _currentUid,
        'senderName': _currentName,
        'senderEmail': _currentEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'views': [_currentUid],
        'viewCount': 1,
      };

      if (_replyingToMessage != null) {
        payload['replyTo'] = {
          'id': _replyingToMessage!['id'],
          'text': _replyingToMessage!['text'],
          'senderName': _replyingToMessage!['senderName'],
          'senderId': _replyingToMessage!['senderId'] ?? '',
          if (_replyingToMessage!['mediaUrl'] != null) 'mediaUrl': _replyingToMessage!['mediaUrl'],
          if (_replyingToMessage!['mediaType'] != null) 'mediaType': _replyingToMessage!['mediaType'],
        };
      }

      await FirebaseFirestore.instance
          .collection('uni_chats')
          .doc(_effectiveUniversityId)
          .collection('messages')
          .add(payload);

      UniChatService().markAsSeen(_effectiveUniversityId);

      setState(() {
        _replyingToMessage = null;
      });
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send $mediaType', style: GoogleFonts.plusJakartaSans(color: U.bg)),
            backgroundColor: U.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleReaction(String messageId, String emoji, dynamic rawReactions) async {
    HapticFeedback.lightImpact();
    final reactions = rawReactions is Map
        ? Map<String, dynamic>.from(rawReactions)
        : <String, dynamic>{};

    final userList = List<dynamic>.from(reactions[emoji] ?? []);
    if (userList.contains(_currentUid)) {
      userList.remove(_currentUid);
      if (userList.isEmpty) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = userList;
      }
    } else {
      userList.add(_currentUid);
      reactions[emoji] = userList;
    }

    try {
      await FirebaseFirestore.instance
          .collection('uni_chats')
          .doc(_effectiveUniversityId)
          .collection('messages')
          .doc(messageId)
          .update({'reactions': reactions});
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
    }
  }

  void _openMediaPicker() {
    ChatMediaPickerSheet.show(
      context,
      onSelectGif: (url) => _sendMedia(mediaUrl: url, mediaType: 'gif'),
      onSelectSticker: (url) => _sendMedia(mediaUrl: url, mediaType: 'sticker'),
      onSelectEmoji: (emoji) {
        _controller.text = '${_controller.text}$emoji';
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      },
    );
  }

  void _openMediaPreview(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (c, _) => const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  ),
                ),
                errorWidget: (c, _, error) => const Icon(Icons.broken_image, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startEditing(String messageId, String currentText) {
    setState(() {
      _replyingToMessage = null;
      _editingMessageId = messageId;
      _controller.text = currentText;
      _controller.selection = TextSelection.collapsed(offset: currentText.length);
    });
    _focusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _controller.clear();
    });
  }

  void _startReply(Map<String, dynamic> data, String messageId) {
    HapticFeedback.lightImpact();
    setState(() {
      _editingMessageId = null;
      _activeReactionMessageId = null;
      _replyingToMessage = {
        'id': messageId,
        'text': data['text'] ?? '',
        'senderName': data['senderName'] ?? 'Student',
        'senderId': data['senderId'] ?? '',
        'mediaUrl': data['mediaUrl'],
        'mediaType': data['mediaType'],
      };
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  Future<void> _unsendMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('uni_chats')
          .doc(_effectiveUniversityId)
          .collection('messages')
          .doc(messageId)
          .delete();
      if (_editingMessageId == messageId) {
        _cancelEditing();
      }
      if (_replyingToMessage != null && _replyingToMessage!['id'] == messageId) {
        _cancelReply();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Message unsent', style: GoogleFonts.plusJakartaSans(color: U.bg)),
            duration: const Duration(milliseconds: 900),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unsend message', style: GoogleFonts.plusJakartaSans(color: U.bg)),
            backgroundColor: U.red,
          ),
        );
      }
    }
  }

  void _showMessageOptions(String messageId, Map<String, dynamic> data, bool isMe) {
    final text = (data['text'] ?? '').toString();
    final mediaUrl = data['mediaUrl'] as String?;
    final isMedia = mediaUrl != null && mediaUrl.isNotEmpty;
    final canUnsend = isMe || _isSuperUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: U.card,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: U.border.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Reaction Bar inside bottom sheet
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: _quickReactions.map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _toggleReaction(messageId, emoji, data['reactions']);
                        },
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.reply_rounded, color: U.primary, size: 20),
                  ),
                  title: Text('Reply', style: GoogleFonts.plusJakartaSans(color: U.text, fontWeight: FontWeight.w600, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(context);
                    _startReply(data, messageId);
                  },
                ),
                if (isMedia)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: U.teal.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.fullscreen_rounded, color: U.teal, size: 20),
                    ),
                    title: Text('View Full Size', style: GoogleFonts.plusJakartaSans(color: U.text, fontWeight: FontWeight.w600, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(context);
                      _openMediaPreview(mediaUrl);
                    },
                  ),
                if (isMe && !isMedia)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: U.blue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.edit_rounded, color: U.blue, size: 20),
                    ),
                    title: Text('Edit message', style: GoogleFonts.plusJakartaSans(color: U.text, fontWeight: FontWeight.w600, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(context);
                      _startEditing(messageId, text);
                    },
                  ),
                if (canUnsend)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: U.red.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: U.red, size: 20),
                    ),
                    title: Text('Unsend message', style: GoogleFonts.plusJakartaSans(color: U.red, fontWeight: FontWeight.w600, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(context);
                      _unsendMessage(messageId);
                    },
                  ),
                if (!isMedia && text.isNotEmpty)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: U.sub.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.copy_rounded, color: U.sub, size: 20),
                    ),
                    title: Text('Copy text', style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied to clipboard', style: GoogleFonts.plusJakartaSans(color: U.bg)),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    NotificationService.setActiveChat(null);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _searchController.dispose();
    UniChatService().markAsSeen(_effectiveUniversityId);
    super.dispose();
  }

  void _showNotificationSettingsSheet() {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: U.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget buildOptionTile({
              required String title,
              required String subtitle,
              required IconData icon,
              required String mode,
            }) {
              final isSelected = _utopiaChatNotifMode == mode;
              return InkWell(
                onTap: () {
                  _updateNotifMode(mode);
                  setSheetState(() {});
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? U.teal.withValues(alpha: 0.14)
                            : U.teal.withValues(alpha: 0.08))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? U.teal.withValues(alpha: 0.4)
                          : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? U.teal.withValues(alpha: 0.15)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          icon,
                          color: isSelected ? U.teal : U.dim,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected ? U.teal : U.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: U.sub,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: U.teal,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: U.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          color: U.teal,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Campus Chat Alerts',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: U.text,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose how you want to be alerted for your university chat.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: U.sub,
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildOptionTile(
                      title: 'All Messages',
                      subtitle: 'Get notified for every message posted in campus chat',
                      icon: Icons.notifications_active_rounded,
                      mode: 'all',
                    ),
                    buildOptionTile(
                      title: 'Replies to You',
                      subtitle: 'Only get notified when someone replies directly',
                      icon: Icons.reply_rounded,
                      mode: 'replies',
                    ),
                    buildOptionTile(
                      title: 'Muted / Off',
                      subtitle: 'Silent mode: No notifications from this chat',
                      icon: Icons.notifications_off_rounded,
                      mode: 'off',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(Timestamp? raw) {
    if (raw == null) return 'Sending...';
    final date = raw.toDate();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final meridiem = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridiem';
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (date.year == now.year) {
      return '${months[date.month - 1]} ${date.day}';
    }
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  bool _shouldShowDateSeparator(List<QueryDocumentSnapshot> docs, int index) {
    final currentData = docs[index].data() as Map<String, dynamic>;
    final currentTs = currentData['timestamp'] as Timestamp?;
    if (currentTs == null) return false;

    if (index == docs.length - 1) return true;

    final nextData = docs[index + 1].data() as Map<String, dynamic>;
    final nextTs = nextData['timestamp'] as Timestamp?;
    if (nextTs == null) return false;

    final currentDate = currentTs.toDate();
    final nextDate = nextTs.toDate();
    return currentDate.year != nextDate.year ||
        currentDate.month != nextDate.month ||
        currentDate.day != nextDate.day;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: _searchActive
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: U.text),
                onPressed: () {
                  setState(() {
                    _searchActive = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            : IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: U.text),
                ),
                onPressed: () => Navigator.pop(context),
              ),
        title: _searchActive
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDarkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search campus messages...',
                    hintStyle: GoogleFonts.plusJakartaSans(color: U.dim, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: U.dim),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(Icons.clear_rounded, size: 16, color: U.dim),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.trim());
                  },
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Chat to Utopia',
                          style: GoogleFonts.plusJakartaSans(
                            color: U.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'CAMPUS',
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF2DD4BF),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: const BoxDecoration(
                          color: Color(0xFF2DD4BF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          'Live Student Stream',
                          style: GoogleFonts.spaceGrotesk(
                            color: U.dim,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        actions: [
          if (!_searchActive)
            IconButton(
              icon: Icon(Icons.search_rounded, color: U.text, size: 22),
              tooltip: 'Search Messages',
              onPressed: () => setState(() => _searchActive = true),
            ),
          IconButton(
            icon: Icon(
              _utopiaChatNotifMode == 'all'
                  ? Icons.notifications_active_rounded
                  : (_utopiaChatNotifMode == 'replies'
                      ? Icons.notifications_rounded
                      : Icons.notifications_off_outlined),
              color: _utopiaChatNotifMode == 'off' ? U.dim : U.teal,
              size: 21,
            ),
            tooltip: 'Notification Settings',
            onPressed: _showNotificationSettingsSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_activeReactionMessageId != null) {
            setState(() => _activeReactionMessageId = null);
          }
        },
        child: Column(
          children: [
            // Chat message stream
            Expanded(
              child: Stack(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _messagesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                        return const Center(child: UtopiaLoader(scale: 0.7));
                      }
                      final allDocs = snapshot.data?.docs ?? [];
                      if (allDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: U.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(Icons.bubble_chart_rounded, color: U.primary, size: 34),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Say hello to your campus!',
                                style: GoogleFonts.plusJakartaSans(
                                  color: U.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Send a message, sticker, or drop a quick vibe.',
                                style: GoogleFonts.plusJakartaSans(color: U.dim, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }

                      // Real-time unread synchronization & scroll badge trigger
                      _trackVisibleViews(allDocs);
                      final topDoc = allDocs.first.data() as Map<String, dynamic>;
                      final topSenderId = topDoc['senderId'] as String?;
                      final topTs = topDoc['timestamp'] as Timestamp?;

                      if (_lastSeenTopDocId != allDocs.first.id &&
                          topSenderId != _currentUid &&
                          topTs != null) {
                        _lastSeenTopDocId = allDocs.first.id;
                        if (_showScrollDown) {
                          if (!_hasNewMessagesWhileScrolled) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _hasNewMessagesWhileScrolled = true);
                            });
                          }
                        } else {
                          UniChatService().markAsSeen(_effectiveUniversityId);
                        }
                      }

                      // Search filtering
                      final docs = _searchQuery.isEmpty
                          ? allDocs
                          : allDocs.where((d) {
                              final map = d.data() as Map<String, dynamic>;
                              final t = (map['text'] ?? '').toString().toLowerCase();
                              final s = (map['senderName'] ?? '').toString().toLowerCase();
                              return t.contains(_searchQuery.toLowerCase()) ||
                                  s.contains(_searchQuery.toLowerCase());
                            }).toList();

                      if (docs.isEmpty && _searchQuery.isNotEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded, size: 44, color: U.dim),
                              const SizedBox(height: 12),
                              Text(
                                'No messages found for "$_searchQuery"',
                                style: GoogleFonts.plusJakartaSans(
                                  color: U.dim,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final messageId = docs[index].id;
                          final isMe = data['senderId'] == _currentUid;
                          final ts = data['timestamp'] as Timestamp?;
                          final showDateSep = _shouldShowDateSeparator(docs, index);

                          return Column(
                            children: [
                              // Date separator (sleek capsule pill)
                              if (showDateSep && ts != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: Row(
                                    children: [
                                      Expanded(child: Divider(color: U.border.withValues(alpha: 0.4), thickness: 0.5)),
                                      Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 14),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDarkTheme
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : Colors.black.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          _formatDateLabel(ts.toDate()),
                                          style: GoogleFonts.spaceGrotesk(
                                            color: U.dim,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(child: Divider(color: U.border.withValues(alpha: 0.4), thickness: 0.5)),
                                    ],
                                  ),
                                ),

                              Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: _SwipeToReplyBubble(
                                  onReply: () => _startReply(data, messageId),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        if (_touchedMessageIds.contains(messageId)) {
                                          _touchedMessageIds.remove(messageId);
                                        } else {
                                          _touchedMessageIds.add(messageId);
                                        }
                                        if (_activeReactionMessageId == messageId) {
                                          _activeReactionMessageId = null;
                                        }
                                      });
                                    },
                                    onDoubleTap: () {
                                      HapticFeedback.mediumImpact();
                                      setState(() {
                                        _activeReactionMessageId =
                                            _activeReactionMessageId == messageId ? null : messageId;
                                      });
                                    },
                                    onLongPress: () => _showMessageOptions(messageId, data, isMe),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        _buildMessageBubble(data, messageId, isMe, ts, isDarkTheme),

                                        // Floating Quick Reaction Dock
                                        if (_activeReactionMessageId == messageId)
                                          Positioned(
                                            top: -46,
                                            right: isMe ? 0 : null,
                                            left: isMe ? null : 0,
                                            child: _buildFloatingReactionDock(messageId, data['reactions']),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  // Floating Scroll-to-Bottom Button
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset: _showScrollDown ? Offset.zero : const Offset(0, 1.5),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _showScrollDown ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !_showScrollDown,
                          child: GestureDetector(
                            onTap: _scrollToBottom,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDarkTheme
                                    ? U.card.withValues(alpha: 0.95)
                                    : Colors.white.withValues(alpha: 0.95),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDarkTheme
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : U.border,
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDarkTheme ? 0.45 : 0.15,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: U.primary,
                                    size: 26,
                                  ),
                                  if (_hasNewMessagesWhileScrolled)
                                    const Positioned(
                                      top: 1,
                                      right: 1,
                                      child: UnreadIndicatorDot(
                                        size: 10,
                                        color: Color(0xFF2DD4BF),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Replying Preview Bar
            if (_replyingToMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: U.card,
                  border: Border(top: BorderSide(color: U.border.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: U.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replying to ${_replyingToMessage!['senderName']}',
                            style: GoogleFonts.plusJakartaSans(
                              color: U.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _replyingToMessage!['mediaUrl'] != null
                                ? (_replyingToMessage!['mediaType'] == 'sticker' ? '🎨 Sticker' : '👾 GIF')
                                : (_replyingToMessage!['text'] ?? ''),
                            style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_replyingToMessage!['mediaUrl'] != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CachedNetworkImage(
                            imageUrl: _replyingToMessage!['mediaUrl'],
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: U.dim.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded, size: 16, color: U.sub),
                      ),
                    ),
                  ],
                ),
              ),

            // Editing Preview Bar
            if (_editingMessageId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: U.card,
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 16, color: U.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing message',
                        style: GoogleFonts.plusJakartaSans(color: U.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelEditing,
                      child: Icon(Icons.close_rounded, size: 18, color: U.sub),
                    ),
                  ],
                ),
              ),


            // Composer Bar
            Container(
              color: U.bg,
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                MediaQuery.paddingOf(context).bottom + 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Media Picker Button
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, right: 8),
                    child: GestureDetector(
                      onTap: _openMediaPicker,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDarkTheme
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: U.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add_reaction_outlined,
                            color: U.teal,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Text Field Input Stadium Pill
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: U.border.withValues(alpha: 0.7),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null ? 'Edit message...' : 'Chat with everyone...',
                          hintStyle: GoogleFonts.plusJakartaSans(color: U.dim, fontSize: 14),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send Button
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            U.primary,
                            U.primary.withValues(alpha: 0.85),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: U.primary.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _editingMessageId != null ? Icons.check_rounded : Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingReactionDock(String messageId, dynamic existingReactions) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E242B) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: U.border.withValues(alpha: 0.8),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _quickReactions.map((emoji) {
          return GestureDetector(
            onTap: () {
              setState(() => _activeReactionMessageId = null);
              _toggleReaction(messageId, emoji, existingReactions);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Builds the message bubble:
  /// - Frameless jumbo emoji if message is only emojis
  /// - Frameless sticker if mediaType == 'sticker' (PLAIN, NO BGS)
  /// - Frameless media if mediaType == 'gif' (PLAIN, NO BGS)
  /// - Adaptive organic elliptical / stadium capsule for text
  Widget _buildMessageBubble(
    Map<String, dynamic> data,
    String messageId,
    bool isMe,
    Timestamp? ts,
    bool isDarkTheme,
  ) {
    final rawText = (data['text'] ?? '').toString();
    final mediaUrl = data['mediaUrl'] as String?;
    final mediaType = data['mediaType'] as String?;
    final isSticker = mediaType == 'sticker';
    final isGif = mediaType == 'gif' || (mediaUrl != null && mediaUrl.contains('.gif') && !isSticker);
    final isOnlyEmojiMsg = mediaUrl == null && _isOnlyEmoji(rawText);
    final isTouched = _touchedMessageIds.contains(messageId);
    final viewCount = _getViewCount(data);
    final reactions = data['reactions'] as Map<String, dynamic>?;

    // M3-correct sent bubble palette: dark mode uses subdued primaryContainer,
    // light mode keeps the vivid primary accent.
    final sentBubbleColor = isDarkTheme ? U.primaryContainer : U.primary;
    final sentBubbleColorEnd = isDarkTheme
        ? Color.lerp(U.primaryContainer, Colors.black, 0.08)!
        : U.primary.withValues(alpha: 0.88);
    final sentTextColor = isDarkTheme ? U.onPrimaryContainer : Colors.white;
    final sentSubColor = isDarkTheme
        ? U.onPrimaryContainer.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.75);
    final sentDimColor = isDarkTheme
        ? U.onPrimaryContainer.withValues(alpha: 0.55)
        : Colors.white70;

    Widget buildViewCountWidget({bool compact = false}) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: isTouched
            ? Padding(
                padding: EdgeInsets.only(
                  top: compact ? 2 : 4,
                  bottom: compact ? 1 : 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: isMe
                          ? sentSubColor
                          : (isDarkTheme ? const Color(0xFF2DD4BF) : U.primary),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$viewCount ${viewCount == 1 ? 'view' : 'views'}',
                      style: GoogleFonts.spaceGrotesk(
                        color: isMe
                            ? sentTextColor
                            : (isDarkTheme ? Colors.white70 : U.text),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      );
    }

    // ── 1. Pure Emoji Message (Jumbo Emojis with No Background / Border) ──
    if (isOnlyEmojiMsg) {
      final count = _countEmojiCharacters(rawText);
      final fontSize = count == 1 ? 52.0 : (count == 2 ? 40.0 : 34.0);

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderHeader(data, messageId, isDarkTheme),
            if (data['replyTo'] != null)
              _buildReplyPreviewSnippet(data['replyTo'], isMe, isDarkTheme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                rawText,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.15,
                ),
              ),
            ),
            _buildReactionsRow(messageId, reactions, isMe, isDarkTheme),
            buildViewCountWidget(compact: true),
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 1),
              child: Text(
                '${_formatTime(ts)}${data['isEdited'] == true ? ' • edited' : ''}',
                style: GoogleFonts.spaceGrotesk(
                  color: U.dim,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── 2. Plain Sticker (Frameless, Transparent, No Background) ──
    if (isSticker && mediaUrl != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderHeader(data, messageId, isDarkTheme),
            if (data['replyTo'] != null)
              _buildReplyPreviewSnippet(data['replyTo'], isMe, isDarkTheme),
            GestureDetector(
              onTap: () => _openMediaPreview(mediaUrl),
              child: SizedBox(
                width: 140,
                height: 140,
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, _) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, _, error) => Icon(Icons.broken_image, color: U.dim),
                ),
              ),
            ),
            _buildReactionsRow(messageId, reactions, isMe, isDarkTheme),
            buildViewCountWidget(compact: true),
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 2),
              child: Text(
                _formatTime(ts),
                style: GoogleFonts.spaceGrotesk(color: U.dim, fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    // ── 3. Plain GIF / Meme (No Container BG, Clean Rounded Floating Media) ──
    if (isGif && mediaUrl != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderHeader(data, messageId, isDarkTheme),
            if (data['replyTo'] != null)
              _buildReplyPreviewSnippet(data['replyTo'], isMe, isDarkTheme),
            GestureDetector(
              onTap: () => _openMediaPreview(mediaUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => Container(
                    height: 140,
                    width: 200,
                    color: isDarkTheme ? Colors.white10 : Colors.black12,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, _, error) => Icon(Icons.broken_image, color: U.dim),
                ),
              ),
            ),
            _buildReactionsRow(messageId, reactions, isMe, isDarkTheme),
            buildViewCountWidget(compact: true),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _formatTime(ts),
                style: GoogleFonts.spaceGrotesk(
                  color: U.dim,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── 4. Standard Text Bubble (Organic Ellipses, Circles & Stadium Shapes) ──
    final style = _getBubbleStyle(rawText, isMe);
    final linkWidget = _buildLinkPreview(rawText, isMe, isDarkTheme);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _buildSenderHeader(data, messageId, isDarkTheme),
            ),
          Container(
            padding: style.padding,
            decoration: BoxDecoration(
              gradient: isMe
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        sentBubbleColor,
                        sentBubbleColorEnd,
                      ],
                    )
                  : null,
              color: isMe
                  ? null
                  : (isDarkTheme ? const Color(0xFF1E242B) : const Color(0xFFF1F5F9)),
              borderRadius: style.borderRadius,
              border: isMe
                  ? null
                  : Border.all(
                      color: isDarkTheme
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 1.0,
                    ),
              boxShadow: [
                BoxShadow(
                  color: isMe
                      ? sentBubbleColor.withValues(alpha: isDarkTheme ? 0.35 : 0.20)
                      : Colors.black.withValues(alpha: isDarkTheme ? 0.20 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (data['replyTo'] != null)
                  _buildReplyPreviewSnippet(data['replyTo'], isMe, isDarkTheme),
                Text(
                  rawText,
                  style: GoogleFonts.plusJakartaSans(
                    color: isMe
                        ? sentTextColor
                        : (isDarkTheme ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A)),
                    fontSize: style.fontSize,
                    fontWeight: style.fontWeight,
                    letterSpacing: style.letterSpacing,
                    height: style.lineHeight,
                  ),
                ),
                ?linkWidget,
                buildViewCountWidget(),
                const SizedBox(height: 3),
                Text(
                  '${_formatTime(ts)}${data['isEdited'] == true ? ' • edited' : ''}',
                  style: GoogleFonts.spaceGrotesk(
                    color: isMe ? sentSubColor : U.dim,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _buildReactionsRow(messageId, reactions, isMe, isDarkTheme),
        ],
      ),
    );
  }

  Widget? _buildLinkPreview(String text, bool isMe, bool isDarkTheme) {
    final url = _extractFirstUrl(text);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? 'Link';
    final sentTextColor = isDarkTheme ? U.onPrimaryContainer : Colors.white;
    final sentDimColor = isDarkTheme
        ? U.onPrimaryContainer.withValues(alpha: 0.55)
        : Colors.white70;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () async {
          HapticFeedback.lightImpact();
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isMe
                ? (isDarkTheme ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.2))
                : (isDarkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link_rounded,
                size: 14,
                color: isMe ? sentTextColor : U.primary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  host,
                  style: GoogleFonts.spaceGrotesk(
                    color: isMe ? sentTextColor : U.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new_rounded,
                size: 11,
                color: isMe ? sentDimColor : U.dim,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactionsRow(
    String messageId,
    Map<String, dynamic>? reactions,
    bool isMe,
    bool isDarkTheme,
  ) {
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        runSpacing: 3,
        children: reactions.entries.map((entry) {
          final emoji = entry.key;
          final userList = entry.value is List ? entry.value as List : [];
          if (userList.isEmpty) return const SizedBox.shrink();
          final userReacted = userList.contains(_currentUid);

          return GestureDetector(
            onTap: () => _toggleReaction(messageId, emoji, reactions),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: userReacted
                    ? (isDarkTheme ? U.teal.withValues(alpha: 0.22) : U.teal.withValues(alpha: 0.15))
                    : (isDarkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: userReacted
                      ? U.teal.withValues(alpha: 0.5)
                      : Colors.transparent,
                  width: 0.9,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 3),
                  Text(
                    '${userList.length}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: userReacted ? U.teal : U.dim,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSenderHeader(Map<String, dynamic> data, String messageId, bool isDarkTheme) {
    final senderName = (data['senderName'] ?? 'Student').toString();
    final senderColor = _getSenderColor(senderName);
    final initial = senderName.isNotEmpty ? senderName[0].toUpperCase() : 'S';

    return GestureDetector(
      onTap: () {
        if (data['senderId'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserProfileScreen(
                uid: data['senderId'],
                displayName: senderName,
                email: data['senderEmail'] ?? '',
              ),
            ),
          );
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: senderColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: senderColor.withValues(alpha: 0.4), width: 1.0),
            ),
            child: Center(
              child: Text(
                initial,
                style: GoogleFonts.spaceGrotesk(
                  color: senderColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              senderName,
              style: GoogleFonts.plusJakartaSans(
                color: senderColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreviewSnippet(
    dynamic replyData,
    bool isMe,
    bool isDarkTheme,
  ) {
    if (replyData is! Map) return const SizedBox.shrink();

    final sender = (replyData['senderName'] ?? 'Student').toString();
    final text = (replyData['text'] ?? '').toString();
    final mediaUrl = replyData['mediaUrl'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? (isDarkTheme ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.2))
            : (isDarkTheme ? Colors.white.withValues(alpha: 0.05) : U.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: isMe ? (isDarkTheme ? U.onPrimaryContainer : Colors.white) : U.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: GoogleFonts.plusJakartaSans(
                    color: isMe ? (isDarkTheme ? U.onPrimaryContainer : Colors.white.withValues(alpha: 0.95)) : U.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(
                    color: isMe ? (isDarkTheme ? U.onPrimaryContainer.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.8)) : U.sub,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _MessageStyleConfig _getBubbleStyle(String text, bool isMe) {
    final trimmed = text.trim();
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wordCount = words.length;
    final charCount = trimmed.length;

    if (wordCount <= 3 && charCount <= 14) {
      // Ultra-short punchy words ("yo", "bet", "real", "lmao", "ok!", "w")
      // Compact stadium oval pill with bold display typography!
      return _MessageStyleConfig(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        lineHeight: 1.2,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        borderRadius: BorderRadius.circular(32),
        isStadium: true,
      );
    } else if (wordCount <= 8 && charCount <= 40) {
      // Short phrase ("where you at?", "heading to library")
      return _MessageStyleConfig(
        fontSize: 17.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        lineHeight: 1.3,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(28),
          topRight: const Radius.circular(28),
          bottomLeft: Radius.circular(isMe ? 28 : 10),
          bottomRight: Radius.circular(isMe ? 10 : 28),
        ),
      );
    } else if (wordCount <= 18 && charCount <= 100) {
      // Medium message
      return _MessageStyleConfig(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        lineHeight: 1.38,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(24),
          topRight: const Radius.circular(24),
          bottomLeft: Radius.circular(isMe ? 24 : 8),
          bottomRight: Radius.circular(isMe ? 8 : 24),
        ),
      );
    } else {
      // Longer paragraphs
      return _MessageStyleConfig(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        lineHeight: 1.45,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(24),
          topRight: const Radius.circular(24),
          bottomLeft: Radius.circular(isMe ? 24 : 8),
          bottomRight: Radius.circular(isMe ? 8 : 24),
        ),
      );
    }
  }
}

class _MessageStyleConfig {
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final double lineHeight;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool isStadium;

  _MessageStyleConfig({
    required this.fontSize,
    required this.fontWeight,
    required this.letterSpacing,
    required this.lineHeight,
    required this.padding,
    required this.borderRadius,
    this.isStadium = false,
  });
}

class _SwipeToReplyBubble extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const _SwipeToReplyBubble({
    required this.child,
    required this.onReply,
  });

  @override
  State<_SwipeToReplyBubble> createState() => _SwipeToReplyBubbleState();
}

class _SwipeToReplyBubbleState extends State<_SwipeToReplyBubble> {
  double _dragOffset = 0.0;
  bool _triggeredHaptic = false;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx > 0 || _dragOffset > 0) {
      setState(() {
        _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, 70.0);
        if (_dragOffset >= 45.0 && !_triggeredHaptic) {
          _triggeredHaptic = true;
          HapticFeedback.lightImpact();
        }
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragOffset >= 45.0) {
      widget.onReply();
    }
    setState(() {
      _dragOffset = 0.0;
      _triggeredHaptic = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: () {
        setState(() {
          _dragOffset = 0.0;
          _triggeredHaptic = false;
        });
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dragOffset > 0)
            Positioned(
              left: 8,
              child: Opacity(
                opacity: (_dragOffset / 45.0).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: (_dragOffset / 45.0).clamp(0.5, 1.0),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      color: U.primary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
