import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/chat_media_picker.dart';
import '../widgets/superuser_badge.dart';
import '../widgets/unread_indicator_dot.dart';
import '../widgets/utopia_loader.dart';
import 'note_viewer_screen.dart';
import 'user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.initialText,
  });

  final String otherUserId;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String? initialText;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _otherUserStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  Timer? _typingDebounce;
  bool _sending = false;
  bool _typingActive = false;
  Map<String, dynamic>? _replyTo;
  String? _editingMessageId;

  bool _showScrollDown = false;
  bool _hasNewMessagesWhileScrolled = false;
  String? _lastSeenTopDocId;
  final Set<String> _touchedMessageIds = {};

  // Search & reaction states
  bool _searchActive = false;
  String _searchQuery = '';
  String? _activeReactionMessageId;

  static const List<String> _quickReactions = ['❤️', '🔥', '😂', '⚡', '💀', '🎓'];

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _currentName => FirebaseAuth.instance.currentUser?.displayName ?? 'You';
  String get _chatId => _chatService.chatIdFor(_currentUid, widget.otherUserId);

  bool get _isEditing => _editingMessageId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _messageController.text = widget.initialText!;
    }
    _chatStream = _chatService.chatStream(_chatId);
    _otherUserStream = _chatService.userStream(widget.otherUserId);
    _messagesStream = _chatService.messagesStream(_chatId);

    NotificationService.setActiveChat(_chatId);
    unawaited(NotificationService.clearChatNotification(_chatId));
    unawaited(_chatService.markChatRead(widget.otherUserId));
    _messageController.addListener(_handleComposerChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    unawaited(NotificationService.clearChatNotification(_chatId));
    unawaited(_chatService.markChatRead(widget.otherUserId));
    NotificationService.setActiveChat(null);
    _typingDebounce?.cancel();
    unawaited(
      _chatService.setTypingState(
        otherUserId: widget.otherUserId,
        isTyping: false,
      ),
    );
    _messageController.removeListener(_handleComposerChanged);
    _scrollController.removeListener(_onScroll);
    _composerFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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
      unawaited(_chatService.markChatRead(widget.otherUserId));
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
    unawaited(_chatService.markChatRead(widget.otherUserId));
  }

  void _handleComposerChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _typingActive) {
      _typingActive = hasText;
      unawaited(
        _chatService.setTypingState(
          otherUserId: widget.otherUserId,
          isTyping: hasText,
        ),
      );
    }

    _typingDebounce?.cancel();
    if (!hasText) {
      return;
    }

    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _typingActive = false;
      unawaited(
        _chatService.setTypingState(
          otherUserId: widget.otherUserId,
          isTyping: false,
        ),
      );
    });
  }

  Future<bool> _handleBackNavigation() async {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_composerFocusNode.hasFocus || keyboardVisible) {
      _composerFocusNode.unfocus();
      return false;
    }
    return true;
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

  void _startReply(Map<String, dynamic> data, String messageId, String senderName) {
    HapticFeedback.lightImpact();
    setState(() {
      _editingMessageId = null;
      _activeReactionMessageId = null;
      _replyTo = {
        'id': messageId,
        'messageId': messageId,
        'text': data['text'] ?? '',
        'senderName': senderName,
        'senderId': data['senderId'] ?? '',
        'mediaUrl': data['mediaUrl'],
        'mediaType': data['mediaType'],
      };
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyTo = null;
    });
  }

  void _startEditing(String messageId, String currentText) {
    setState(() {
      _replyTo = null;
      _editingMessageId = messageId;
      _messageController.text = currentText;
      _messageController.selection = TextSelection.collapsed(offset: currentText.length);
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _messageController.clear();
    });
  }

  Future<void> _send() async {
    final composedText = _messageController.text.trim();
    if (_sending || composedText.isEmpty) {
      return;
    }

    if (_isEditing) {
      final msgId = _editingMessageId!;
      setState(() => _sending = true);
      try {
        await _chatService.editMessage(
          otherUserId: widget.otherUserId,
          messageId: msgId,
          text: composedText,
        );
        _messageController.clear();
        setState(() {
          _editingMessageId = null;
        });
      } catch (e) {
        if (mounted) {
          final message = e is FirebaseException ? (e.message ?? e.code) : 'Failed to edit message';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message, style: GoogleFonts.plusJakartaSans(color: U.bg)),
              backgroundColor: U.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    setState(() => _sending = true);
    try {
      await _chatService.sendMessage(
        otherUserId: widget.otherUserId,
        text: composedText,
        replyTo: _replyTo != null
            ? {
                'id': _replyTo!['id'] ?? _replyTo!['messageId'],
                'messageId': _replyTo!['messageId'] ?? _replyTo!['id'],
                'text': _replyTo!['text'] ?? '',
                'senderName': _replyTo!['senderName'] ?? '',
                'senderId': _replyTo!['senderId'] ?? '',
                if (_replyTo!['mediaUrl'] != null) 'mediaUrl': _replyTo!['mediaUrl'],
                if (_replyTo!['mediaType'] != null) 'mediaType': _replyTo!['mediaType'],
              }
            : null,
      );

      _typingDebounce?.cancel();
      _typingActive = false;
      unawaited(
        _chatService.setTypingState(
          otherUserId: widget.otherUserId,
          isTyping: false,
        ),
      );

      _messageController.clear();
      setState(() {
        _replyTo = null;
        _editingMessageId = null;
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is FirebaseException ? (e.message ?? e.code) : 'Failed to send message';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: GoogleFonts.plusJakartaSans(color: U.bg)),
            backgroundColor: U.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendMedia({
    required String mediaUrl,
    required String mediaType, // 'gif' or 'sticker'
  }) async {
    if (_sending) return;

    setState(() => _sending = true);
    try {
      await _chatService.sendMedia(
        otherUserId: widget.otherUserId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        replyTo: _replyTo != null
            ? {
                'id': _replyTo!['id'] ?? _replyTo!['messageId'],
                'messageId': _replyTo!['messageId'] ?? _replyTo!['id'],
                'text': _replyTo!['text'] ?? '',
                'senderName': _replyTo!['senderName'] ?? '',
                'senderId': _replyTo!['senderId'] ?? '',
                if (_replyTo!['mediaUrl'] != null) 'mediaUrl': _replyTo!['mediaUrl'],
                if (_replyTo!['mediaType'] != null) 'mediaType': _replyTo!['mediaType'],
              }
            : null,
      );

      setState(() {
        _replyTo = null;
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
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
          .collection('chats')
          .doc(_chatId)
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
        _messageController.text = '${_messageController.text}$emoji';
        _messageController.selection = TextSelection.collapsed(offset: _messageController.text.length);
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

  Future<void> _unsendMessage(String messageId) async {
    try {
      await _chatService.unsendMessage(
        otherUserId: widget.otherUserId,
        messageId: messageId,
      );
      if (_editingMessageId == messageId) {
        _cancelEditing();
      }
      if (_replyTo != null && (_replyTo!['id'] == messageId || _replyTo!['messageId'] == messageId)) {
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
    final messageType = (data['type'] ?? 'text').toString();
    final senderName = isMe ? _currentName : widget.displayName;

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
                    _startReply(data, messageId, senderName);
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
                if (isMe && !isMedia && messageType == 'text')
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
                if (isMe)
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

  void _openNoteShare(Map<String, dynamic> noteShare) {
    final filePath = (noteShare['filePath'] ?? '').toString();
    if (filePath.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteViewerScreen(
          title: (noteShare['noteTitle'] ?? 'Shared note').toString(),
          filePath: filePath,
          folderPath: (noteShare['folderPath'] ?? '').toString(),
          initialSegmentId: (noteShare['segmentId'] ?? '').toString(),
        ),
      ),
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

  bool _shouldShowDateSeparator(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, int index) {
    final currentData = docs[index].data();
    final currentTs = currentData['timestamp'] as Timestamp?;
    if (currentTs == null) return false;

    if (index == docs.length - 1) return true;

    final nextData = docs[index + 1].data();
    final nextTs = nextData['timestamp'] as Timestamp?;
    if (nextTs == null) return false;

    final currentDate = currentTs.toDate();
    final nextDate = nextTs.toDate();
    return currentDate.year != nextDate.year ||
        currentDate.month != nextDate.month ||
        currentDate.day != nextDate.day;
  }

  String _lastSeenLabel(dynamic raw, {required String fallback}) {
    if (raw is! Timestamp) {
      return fallback;
    }

    final diff = DateTime.now().difference(raw.toDate());
    if (diff.inMinutes < 1) {
      return 'Last seen just now';
    }
    if (diff.inMinutes < 60) {
      return 'Last seen ${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return 'Last seen ${diff.inHours}h ago';
    }
    return 'Last seen ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = appThemeNotifier.value.isDark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final canLeave = await _handleBackNavigation();
        if (canLeave && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: U.bg,
        appBar: AppBar(
          backgroundColor: U.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          foregroundColor: U.text,
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
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search in conversation...',
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
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _chatStream,
                  builder: (context, chatSnapshot) {
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _otherUserStream,
                      builder: (context, userSnapshot) {
                        final chatData = chatSnapshot.data?.data();
                        final userData = userSnapshot.data?.data();
                        final isOtherTyping = (chatData?['typing_${widget.otherUserId}'] ?? false) == true;
                        final lastSeen = userData?['lastSeen'];
                        final isOnline = lastSeen is Timestamp &&
                            DateTime.now().difference(lastSeen.toDate()) <= const Duration(minutes: 5);
                        final subtitle = isOtherTyping
                            ? 'typing...'
                            : (isOnline ? 'Online' : _lastSeenLabel(lastSeen, fallback: 'Offline'));

                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              buildForwardRoute(
                                UserProfileScreen(
                                  uid: widget.otherUserId,
                                  displayName: widget.displayName,
                                  email: widget.email,
                                  photoUrl: widget.photoUrl,
                                ),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: U.primary.withValues(alpha: 0.16),
                                backgroundImage: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                                    ? CachedNetworkImageProvider(widget.photoUrl!)
                                    : null,
                                child: widget.photoUrl == null || widget.photoUrl!.isEmpty
                                    ? Text(
                                        widget.displayName.isEmpty ? 'U' : widget.displayName[0].toUpperCase(),
                                        style: GoogleFonts.spaceGrotesk(
                                          color: U.primary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            UtopiaApp.sanitizeDisplayName(widget.displayName),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.plusJakartaSans(
                                              color: U.text,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                        if (userData?['role'] == 'superuser') ...[
                                          const SizedBox(width: 4),
                                          const SuperUserBadge(size: 14),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 1),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isOnline && !isOtherTyping)
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
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.spaceGrotesk(
                                              color: isOtherTyping || isOnline ? const Color(0xFF2DD4BF) : U.sub,
                                              fontSize: 11,
                                              fontWeight: isOtherTyping || isOnline
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
          actions: [
            if (!_searchActive)
              IconButton(
                icon: Icon(Icons.search_rounded, color: U.text, size: 22),
                tooltip: 'Search Conversation',
                onPressed: () => setState(() => _searchActive = true),
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
              Expanded(
                child: Stack(
                  children: [
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return const Center(child: UtopiaLoader(scale: 0.7));
                        }

                        final allDocs = (snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                            .where((doc) {
                          final data = doc.data();
                          return (data['deleted'] ?? false) != true;
                        }).toList();

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
                                    child: Icon(Icons.forum_outlined, color: U.primary, size: 34),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Say hello to ${widget.displayName}!',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: U.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Send a message, sticker, or share a note.',
                                  style: GoogleFonts.plusJakartaSans(color: U.dim, fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }

                        // Check for new incoming message while user is scrolled up
                        if (allDocs.isNotEmpty) {
                          final topDoc = allDocs.first.data();
                          final topSenderId = topDoc['senderId'] as String?;
                          final topTs = topDoc['timestamp'] as Timestamp?;
                          if (_lastSeenTopDocId != allDocs.first.id && topSenderId != _currentUid && topTs != null) {
                            _lastSeenTopDocId = allDocs.first.id;
                            if (_showScrollDown) {
                              if (!_hasNewMessagesWhileScrolled) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) setState(() => _hasNewMessagesWhileScrolled = true);
                                });
                              }
                            } else {
                              unawaited(_chatService.markChatRead(widget.otherUserId));
                            }
                          }
                        }

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(_chatService.markChatRead(widget.otherUserId));
                        });

                        // Search filtering
                        final docs = _searchQuery.isEmpty
                            ? allDocs
                            : allDocs.where((d) {
                                final map = d.data();
                                final t = (map['text'] ?? '').toString().toLowerCase();
                                return t.contains(_searchQuery.toLowerCase());
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
                            final data = docs[index].data();
                            final messageId = docs[index].id;
                            final isMe = (data['senderId'] ?? '') == _currentUid;
                            final ts = data['timestamp'] as Timestamp?;
                            final showDateSep = _shouldShowDateSeparator(docs, index);
                            final senderName = isMe ? _currentName : widget.displayName;

                            return Column(
                              children: [
                                // Date separator
                                if (showDateSep && ts != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: U.border.withValues(alpha: 0.4),
                                            thickness: 0.5,
                                          ),
                                        ),
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
                                        Expanded(
                                          child: Divider(
                                            color: U.border.withValues(alpha: 0.4),
                                            thickness: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Align(
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: _SwipeToReplyBubble(
                                    onReply: () => _startReply(data, messageId, senderName),
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

              // ── Live Typing Indicator Bubble ──
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _chatStream,
                builder: (context, snapshot) {
                  final isOtherTyping = (snapshot.data?.data()?['typing_${widget.otherUserId}'] ?? false) == true;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: isOtherTyping
                        ? Padding(
                            key: const ValueKey('typing_indicator'),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: U.primary.withValues(alpha: 0.16),
                                    backgroundImage: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                                        ? CachedNetworkImageProvider(widget.photoUrl!)
                                        : null,
                                    child: widget.photoUrl == null || widget.photoUrl!.isEmpty
                                        ? Text(
                                            widget.displayName.isEmpty ? 'U' : widget.displayName[0].toUpperCase(),
                                            style: GoogleFonts.spaceGrotesk(
                                              color: U.primary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  const _TypingIndicatorBubble(),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('typing_indicator_empty')),
                  );
                },
              ),

              // Replying Preview Bar
              if (_replyTo != null)
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
                              'Replying to ${_replyTo!['senderName'] ?? 'Message'}',
                              style: GoogleFonts.plusJakartaSans(
                                color: U.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _replyTo!['mediaUrl'] != null
                                  ? (_replyTo!['mediaType'] == 'sticker' ? '🎨 Sticker' : '👾 GIF')
                                  : (_replyTo!['text'] ?? ''),
                              style: GoogleFonts.plusJakartaSans(color: U.sub, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_replyTo!['mediaUrl'] != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CachedNetworkImage(
                              imageUrl: _replyTo!['mediaUrl'],
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
                  6,
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
                          controller: _messageController,
                          focusNode: _composerFocusNode,
                          minLines: 1,
                          maxLines: 5,
                          style: GoogleFonts.plusJakartaSans(color: U.text, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: _editingMessageId != null ? 'Edit message...' : 'Message...',
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
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: U.getContrastColor(U.primary),
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _editingMessageId != null ? Icons.check_rounded : Icons.send_rounded,
                                  color: U.getContrastColor(U.primary),
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
  /// - Note share card if type == 'note_share'
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
    final isNoteShare = data['type'] == 'note_share';
    final isOnlyEmojiMsg = mediaUrl == null && !isNoteShare && _isOnlyEmoji(rawText);
    final isRead = (data['read'] ?? false) == true;
    final reactions = data['reactions'] as Map<String, dynamic>?;

    // M3-correct sent bubble palette (matches Utopia uni chat):
    // dark mode uses subdued primaryContainer, light mode keeps vivid primary.
    final sentBubbleColor = isDarkTheme ? U.primaryContainer : U.primary;
    final sentBubbleColorEnd = isDarkTheme
        ? Color.lerp(U.primaryContainer, Colors.black, 0.08)!
        : U.primary.withValues(alpha: 0.88);
    final sentTextColor = isDarkTheme ? U.onPrimaryContainer : U.getContrastColor(sentBubbleColor);
    final sentSubColor = isDarkTheme
        ? U.onPrimaryContainer.withValues(alpha: 0.75)
        : U.getContrastColor(sentBubbleColor).withValues(alpha: 0.75);

    // Delivery / read receipt icon
    Widget buildDeliveryStatus({bool forGradient = false}) {
      if (!isMe) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          isRead ? Icons.done_all_rounded : Icons.done_rounded,
          size: 14,
          color: forGradient
              ? sentTextColor.withValues(alpha: 0.85)
              : (isRead ? sentBubbleColor : U.dim),
        ),
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
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_formatTime(ts)}${data['edited'] == true || data['isEdited'] == true ? ' • edited' : ''}',
                    style: GoogleFonts.spaceGrotesk(
                      color: U.dim,
                      fontSize: 10,
                    ),
                  ),
                  buildDeliveryStatus(),
                ],
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
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(ts),
                    style: GoogleFonts.spaceGrotesk(color: U.dim, fontSize: 10),
                  ),
                  buildDeliveryStatus(),
                ],
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
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(ts),
                    style: GoogleFonts.spaceGrotesk(
                      color: U.dim,
                      fontSize: 10,
                    ),
                  ),
                  buildDeliveryStatus(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── 4. Note Share Message ──
    if (isNoteShare && data['noteShare'] != null) {
      final noteShare = data['noteShare'] as Map<String, dynamic>;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? sentBubbleColor.withValues(alpha: 0.12) : U.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isMe ? sentBubbleColor.withValues(alpha: 0.3) : U.border.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (data['replyTo'] != null)
              _buildReplyPreviewSnippet(data['replyTo'], isMe, isDarkTheme),
            _NoteShareCard(
              noteShare: noteShare,
              onTap: () => _openNoteShare(noteShare),
            ),
            _buildReactionsRow(messageId, reactions, isMe, isDarkTheme),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(ts),
                    style: GoogleFonts.spaceGrotesk(color: U.dim, fontSize: 10),
                  ),
                  buildDeliveryStatus(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── 5. Standard Text Bubble (Organic Ellipses, Circles & Stadium Shapes) ──
    final style = _getBubbleStyle(rawText, isMe);
    final linkWidget = _buildLinkPreview(rawText, isMe, isDarkTheme);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
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
                      ? sentBubbleColor.withValues(alpha: isDarkTheme ? 0.28 : 0.20)
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
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_formatTime(ts)}${data['edited'] == true || data['isEdited'] == true ? ' • edited' : ''}',
                      style: GoogleFonts.spaceGrotesk(
                        color: isMe ? sentSubColor : U.dim,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    buildDeliveryStatus(forGradient: isMe),
                  ],
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
    final sentTextColor = isDarkTheme ? U.onPrimaryContainer : U.getContrastColor(U.primary);
    final sentDimColor = isDarkTheme
        ? U.onPrimaryContainer.withValues(alpha: 0.55)
        : U.getContrastColor(U.primary).withValues(alpha: 0.7);

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
                ? sentTextColor.withValues(alpha: 0.2)
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

  Widget _buildReplyPreviewSnippet(
    dynamic replyData,
    bool isMe,
    bool isDarkTheme,
  ) {
    if (replyData is! Map) return const SizedBox.shrink();

    final sender = (replyData['senderName'] ?? (isMe ? 'You' : widget.displayName)).toString();
    final text = (replyData['text'] ?? '').toString();
    final mediaUrl = replyData['mediaUrl'] as String?;
    final sentTextColor = isDarkTheme ? U.onPrimaryContainer : U.getContrastColor(U.primary);
    final sentBubbleColor = isDarkTheme ? U.primaryContainer : U.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.black.withValues(alpha: 0.2)
            : (isDarkTheme ? Colors.white.withValues(alpha: 0.05) : U.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: isMe ? sentTextColor : sentBubbleColor,
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
                    color: isMe ? sentTextColor.withValues(alpha: 0.95) : sentBubbleColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(
                    color: isMe ? sentTextColor.withValues(alpha: 0.8) : U.sub,
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

class _NoteShareCard extends StatelessWidget {
  const _NoteShareCard({required this.noteShare, this.onTap});

  final Map<String, dynamic> noteShare;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final noteTitle = (noteShare['noteTitle'] ?? 'Shared note').toString();
    final preview = (noteShare['segmentPreview'] ?? '').toString();
    final segmentType = (noteShare['segmentType'] ?? 'section').toString();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: U.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: U.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: U.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.notes_rounded, color: U.primary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        noteTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: U.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Shared ${segmentType.replaceAll('_', ' ')}',
                        style: GoogleFonts.plusJakartaSans(
                          color: U.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_new_rounded, size: 16, color: U.sub),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: U.sub,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble();

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E242B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: U.border.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 5),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress = (_controller.value + (index * 0.18)) % 1.0;
                final emphasized = Curves.easeInOutCubicEmphasized.transform(
                  progress < 0.5 ? progress * 2 : (1 - progress) * 2,
                );
                final scale = 0.72 + (emphasized * 0.45);
                final opacity = 0.35 + (emphasized * 0.65);
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  color: U.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
