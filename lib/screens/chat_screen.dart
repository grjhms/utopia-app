import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/utopia_loader.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/icebreaker_data.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_motion.dart';
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
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _otherUserStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  Timer? _typingDebounce;
  bool _sending = false;
  bool _typingActive = false;
  String? _lastError;
  Map<String, dynamic>? _replyTo;
  String? _editingMessageId;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _chatId => _chatService.chatIdFor(_currentUid, widget.otherUserId);


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
    unawaited(_chatService.markChatRead(widget.otherUserId));
    _messageController.addListener(_handleComposerChanged);
  }

  @override
  void dispose() {
    NotificationService.setActiveChat(null);
    _typingDebounce?.cancel();
    unawaited(
      _chatService.setTypingState(
        otherUserId: widget.otherUserId,
        isTyping: false,
      ),
    );
    _messageController.removeListener(_handleComposerChanged);
    _composerFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  bool get _isEditing => _editingMessageId != null;

  void _cancelComposerMode() {
    _replyTo = null;
    _editingMessageId = null;
  }

  Future<void> _showOwnMessageActions({
    required String messageId,
    required String text,
    required bool isDeleted,
    required bool canEdit,
  }) async {
    if (isDeleted) {
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: U.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                _MessageActionTile(
                  icon: canEdit ? Icons.edit_outlined : Icons.block_outlined,
                  label: canEdit ? 'Edit message' : 'Edit unavailable',
                  color: canEdit ? U.primary : U.sub,
                  onTap: () =>
                      Navigator.of(context).pop(canEdit ? 'edit' : null),
                ),
                const SizedBox(height: 8),
                _MessageActionTile(
                  icon: Icons.undo_rounded,
                  label: 'Unsend message',
                  color: U.red,
                  onTap: () => Navigator.of(context).pop('unsend'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'edit') {
      setState(() {
        _editingMessageId = messageId;
        _replyTo = null;
        _lastError = null;
      });
      _messageController
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
      _handleComposerChanged();
      return;
    }

    if (action == 'unsend') {
      try {
        await _chatService.unsendMessage(
          otherUserId: widget.otherUserId,
          messageId: messageId,
        );
        if (mounted && _editingMessageId == messageId) {
          setState(() {
            _messageController.clear();
            _cancelComposerMode();
          });
        }
      } catch (e) {
        if (!mounted) {
          return;
        }
        final message = e is FirebaseException
            ? (e.message ?? e.code)
            : 'Could not unsend message';
        setState(() => _lastError = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(message, style: GoogleFonts.outfit(color: U.getContrastColor(U.red))),
          ),
        );
      }
    }
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

  Future<void> _send() async {
    final composedText = _messageController.text.trim();
    if (_sending || composedText.isEmpty) {
      return;
    }

    setState(() => _sending = true);
    try {
      if (_isEditing) {
        await _chatService.editMessage(
          otherUserId: widget.otherUserId,
          messageId: _editingMessageId!,
          text: composedText,
        );
      } else {
        await _chatService.sendMessage(
          otherUserId: widget.otherUserId,
          text: composedText,
          replyTo: _replyTo,
        );
      }
      if (mounted) {
        setState(() {
          _lastError = null;
          _replyTo = null;
          _editingMessageId = null;
        });
      }
      _typingDebounce?.cancel();
      _typingActive = false;
      unawaited(
        _chatService.setTypingState(
          otherUserId: widget.otherUserId,
          isTyping: false,
        ),
      );
      _messageController.clear();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is FirebaseException
            ? (e.message ?? e.code)
            : 'Could not send message';
        setState(() => _lastError = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: U.red,
            content: Text(message, style: GoogleFonts.outfit(color: U.getContrastColor(U.red))),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _onSelectIcebreaker(String text) {
    HapticFeedback.lightImpact();
    _messageController.text = text;
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    _composerFocusNode.requestFocus();
  }

  void _openIcebreakersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChatIcebreakersSheet(
        onSelect: (text) {
          Navigator.pop(ctx);
          _onSelectIcebreaker(text);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
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
          titleSpacing: 0,
          title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _chatStream,
            builder: (context, chatSnapshot) {
              return StreamBuilder<
                DocumentSnapshot<Map<String, dynamic>>
              >(
                stream: _otherUserStream,
                builder: (context, userSnapshot) {
                  final chatData = chatSnapshot.data?.data();
                  final userData = userSnapshot.data?.data();
                  final isOtherTyping =
                      (chatData?['typing_${widget.otherUserId}'] ??
                          false) ==
                      true;
                  final lastSeen = userData?['lastSeen'];
                  final isOnline =
                      lastSeen is Timestamp &&
                      DateTime.now().difference(lastSeen.toDate()) <=
                          const Duration(minutes: 5);
                  final subtitle = isOtherTyping
                      ? 'typing...'
                      : (isOnline
                            ? 'Online'
                            : _lastSeenLabel(
                                lastSeen,
                                fallback: 'Offline',
                              ));

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
                                  backgroundColor: U.primary.withValues(
                                    alpha: 0.16,
                                  ),
                                  backgroundImage:
                                      widget.photoUrl != null &&
                                          widget.photoUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(widget.photoUrl!)
                                      : null,
                                  child:
                                      widget.photoUrl == null ||
                                          widget.photoUrl!.isEmpty
                                      ? Text(
                                          widget.displayName.isEmpty
                                              ? 'U'
                                              : widget.displayName[0]
                                                    .toUpperCase(),
                                          style: GoogleFonts.outfit(
                                            color: U.primary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
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
                                              style: GoogleFonts.outfit(
                                                color: U.text,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (userData?['role'] == 'superuser') ...[
                                            const SizedBox(width: 4),
                                            Icon(Icons.verified_rounded, color: U.red, size: 14),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: isOtherTyping || isOnline
                                              ? U.primary
                                              : U.sub,
                                          fontSize: 11,
                                          fontWeight: isOtherTyping || isOnline
                                              ? FontWeight.w500
                                              : FontWeight.w400,
                                        ),
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
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: const UtopiaLoader(scale: 0.5),
                      );
                    }

                    if (snapshot.hasError) {
                      final error = snapshot.error;
                      final subtitle = error is FirebaseException
                          ? (error.message ?? error.code)
                          : 'Try opening this chat again.';
                      return _ChatEmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Could not load messages',
                        subtitle: subtitle,
                      );
                    }

                    final messages = (snapshot.data?.docs ?? const []).where((
                      doc,
                    ) {
                      final data = doc.data();
                      return (data['deleted'] ?? false) != true;
                    }).toList();
                    if (messages.isEmpty) {
                      return _ChatIcebreakerEmptyState(
                        onSelectIcebreaker: _onSelectIcebreaker,
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      unawaited(_chatService.markChatRead(widget.otherUserId));
                    });

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final data = messages[index].data();
                        final senderId = (data['senderId'] ?? '').toString();
                        final isMe = senderId == _currentUid;
                        final messageType = (data['type'] ?? 'text').toString();
                        final noteShare =
                            data['noteShare'] as Map<String, dynamic>?;
                        final currentTs = data['timestamp'] as Timestamp?;

                        // Determine if a date separator should appear above this message
                        bool showDateSep = false;
                        if (currentTs != null) {
                          if (index == messages.length - 1) {
                            showDateSep = true;
                          } else {
                            final nextData = messages[index + 1].data();
                            final nextTs = nextData['timestamp'] as Timestamp?;
                            if (nextTs != null) {
                              final c = currentTs.toDate();
                              final n = nextTs.toDate();
                              showDateSep = c.year != n.year || c.month != n.month || c.day != n.day;
                            }
                          }
                        }

                        return Column(
                          children: [
                            if (showDateSep && currentTs != null)
                              _ChatDateSeparator(date: currentTs.toDate()),
                            _MessageBubble(
                              messageId: messages[index].id,
                              isMe: isMe,
                              messageType: messageType,
                              text: (data['text'] ?? '').toString(),
                              timestamp: data['timestamp'] as Timestamp?,
                              isRead: (data['read'] ?? false) == true,
                              isEdited: (data['edited'] ?? false) == true,
                              isDeleted: (data['deleted'] ?? false) == true,
                              noteShare: noteShare,
                              replyTo: data['replyTo'] as Map<String, dynamic>?,
                              avatarLetter: isMe
                                  ? (FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.displayName ??
                                            'U')
                                        .characters
                                        .first
                                        .toUpperCase()
                                  : (widget.displayName.isEmpty
                                        ? 'U'
                                        : widget.displayName.characters.first
                                              .toUpperCase()),
                              avatarPhotoUrl: isMe
                                  ? FirebaseAuth.instance.currentUser?.photoURL
                                  : widget.photoUrl,
                              onReply: () {
                                setState(() {
                                  _replyTo = {
                                    'messageId': messages[index].id,
                                    'senderId': senderId,
                                    'senderName': isMe
                                        ? (FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.displayName ??
                                              'You')
                                        : widget.displayName,
                                    'text': (data['deleted'] ?? false) == true
                                        ? 'Message unsent'
                                        : messageType == 'note_share'
                                        ? 'Shared ${(noteShare?['noteTitle'] ?? 'note').toString()}'
                                        : (data['text'] ?? '').toString(),
                                  };
                                });
                              },
                              onLongPress: isMe
                                  ? () => _showOwnMessageActions(
                                      messageId: messages[index].id,
                                      text: (data['text'] ?? '').toString(),
                                      isDeleted: (data['deleted'] ?? false) == true,
                                      canEdit: messageType == 'text',
                                    )
                                  : null,
                              onOpenNoteShare: noteShare == null
                                  ? null
                                  : () => _openNoteShare(noteShare),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _chatStream,
                builder: (context, snapshot) {
                  final isOtherTyping =
                      (snapshot.data?.data()?['typing_${widget.otherUserId}'] ??
                          false) ==
                      true;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: isOtherTyping
                        ? Padding(
                            key: const ValueKey('typing_indicator'),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: U.primary.withValues(
                                    alpha: 0.16,
                                  ),
                                  backgroundImage:
                                      widget.photoUrl != null &&
                                          widget.photoUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(widget.photoUrl!)
                                      : null,
                                  child:
                                      widget.photoUrl == null ||
                                          widget.photoUrl!.isEmpty
                                      ? Text(
                                          widget.displayName.isEmpty
                                              ? 'U'
                                              : widget.displayName[0]
                                                    .toUpperCase(),
                                          style: GoogleFonts.outfit(
                                            color: U.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                const _TypingIndicatorBubble(),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('typing_indicator_empty'),
                          ),
                  );
                },
              ),
              // Composer Container
              Container(
                color: U.bg,
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: U.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: U.border.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isEditing || _replyTo != null) ...[
                              Container(
                                margin: const EdgeInsets.all(6),
                                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                decoration: BoxDecoration(
                                  color: U.surface.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: U.border.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: _isEditing ? U.peach : U.primary,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _isEditing
                                                ? 'Editing message'
                                                : (_replyTo?['senderName'] ?? 'Reply').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: _isEditing ? U.peach : U.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            _isEditing
                                                ? 'Send to save changes'
                                                : (_replyTo?['text'] ?? '').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: U.sub,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(() => _cancelComposerMode()),
                                      splashRadius: 16,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      icon: Icon(Icons.close_rounded, color: U.sub, size: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            TextField(
                              focusNode: _composerFocusNode,
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 5,
                              style: GoogleFonts.outfit(color: U.text, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: _isEditing ? 'Edit message' : 'Message...',
                                hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 14),
                                filled: true,
                                fillColor: Colors.transparent,
                                prefixIcon: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: U.teal,
                                  size: 20,
                                ),
                                suffixIcon: Tooltip(
                                  message: 'Interest Icebreakers & Starters',
                                  child: IconButton(
                                    icon: const Text('💡', style: TextStyle(fontSize: 16)),
                                    onPressed: _openIcebreakersSheet,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                            if (_lastError != null) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Text(
                                  _lastError!,
                                  style: GoogleFonts.outfit(
                                    color: U.red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _sending ? null : _send,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: U.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: U.primary.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _isEditing ? Icons.check_rounded : Icons.send_rounded,
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
}




class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.messageId,
    required this.isMe,
    required this.messageType,
    required this.text,
    required this.timestamp,
    required this.isRead,
    required this.isEdited,
    required this.isDeleted,
    required this.avatarLetter,
    required this.onReply,
    this.onLongPress,
    this.onOpenNoteShare,
    this.noteShare,
    this.avatarPhotoUrl,
    this.replyTo,
  });

  final String messageId;
  final bool isMe;
  final String messageType;
  final String text;
  final Timestamp? timestamp;
  final bool isRead;
  final bool isEdited;
  final bool isDeleted;
  final String avatarLetter;
  final String? avatarPhotoUrl;
  final VoidCallback onReply;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenNoteShare;
  final Map<String, dynamic>? noteShare;
  final Map<String, dynamic>? replyTo;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  static const double _maxSwipeOffset = 34;
  static const double _replyTriggerOffset = 22;
  double _dragOffset = 0;

  bool get _isMe => widget.isMe;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.isDeleted) {
      return;
    }
    final delta = details.primaryDelta ?? 0;
    final nextOffset = (_dragOffset + delta)
        .clamp(_isMe ? -_maxSwipeOffset : 0, _isMe ? 0 : _maxSwipeOffset)
        .toDouble();
    if (nextOffset != _dragOffset) {
      setState(() => _dragOffset = nextOffset);
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (widget.isDeleted) {
      if (_dragOffset != 0) {
        setState(() => _dragOffset = 0);
      }
      return;
    }
    final triggered = _isMe
        ? _dragOffset <= -_replyTriggerOffset
        : _dragOffset >= _replyTriggerOffset;
    if (triggered) {
      widget.onReply();
    }
    if (_dragOffset != 0) {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = _isMe
        ? Color.alphaBlend(U.primary.withValues(alpha: 0.14), U.card)
        : U.card;
    final avatar = CircleAvatar(
      radius: 14,
      backgroundColor: _isMe ? U.primary.withValues(alpha: 0.18) : U.border,
      backgroundImage:
          widget.avatarPhotoUrl != null && widget.avatarPhotoUrl!.isNotEmpty
          ? CachedNetworkImageProvider(widget.avatarPhotoUrl!)
          : null,
      child: widget.avatarPhotoUrl == null || widget.avatarPhotoUrl!.isEmpty
          ? Text(
              widget.avatarLetter,
              style: GoogleFonts.outfit(
                color: _isMe ? U.primary : U.text,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(
        children: [
          Positioned.fill(
            child: _ReplySwipeBackground(
              isMe: _isMe,
              progress: (_dragOffset.abs() / _maxSwipeOffset).clamp(0, 1),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: widget.onLongPress,
              onHorizontalDragUpdate: _handleHorizontalDragUpdate,
              onHorizontalDragEnd: _handleHorizontalDragEnd,
              child: Row(
                mainAxisAlignment: _isMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!_isMe) ...[avatar, const SizedBox(width: 8)],
                  Flexible(
                    child: Column(
                      crossAxisAlignment: _isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.replyTo != null) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      8,
                                    ),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: U.surface.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: U.border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (widget.replyTo?['senderName'] ??
                                                  'Reply')
                                              .toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            color: U.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                          Text(
                                            (widget.replyTo?['text'] ?? '').toString(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: U.sub,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                _buildMessageContent(),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isEdited && !widget.isDeleted) ...[
                              Text(
                                'edited',
                                style: GoogleFonts.outfit(
                                  color: U.sub,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              _formatTime(widget.timestamp),
                              style: GoogleFonts.outfit(
                                color: U.sub,
                                fontSize: 11,
                              ),
                            ),
                            if (_isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                widget.isRead
                                    ? Icons.done_all_rounded
                                    : Icons.done_rounded,
                                size: 15,
                                color: widget.isRead ? U.primary : U.sub,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isMe) ...[const SizedBox(width: 8), avatar],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(Timestamp? raw) {
    if (raw == null) {
      return 'Sending...';
    }
    final date = raw.toDate();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final meridiem = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridiem';
  }

  Widget _buildMessageContent() {
    if (widget.isDeleted) {
      return Text(
        'Message unsent',
        style: GoogleFonts.outfit(
          color: U.sub,
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (widget.messageType == 'note_share' && widget.noteShare != null) {
      return _NoteShareCard(
        noteShare: widget.noteShare!,
        onTap: widget.onOpenNoteShare,
      );
    }
    return Text(
      widget.text,
      style: GoogleFonts.outfit(
        color: U.text,
        fontSize: 15,
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: U.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: U.border),
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
                        style: GoogleFonts.outfit(
                          color: U.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Shared ${segmentType.replaceAll('_', ' ')}',
                        style: GoogleFonts.outfit(
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
                style: GoogleFonts.outfit(
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

class _MessageActionTile extends StatelessWidget {
  const _MessageActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: U.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: U.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplySwipeBackground extends StatelessWidget {
  const _ReplySwipeBackground({required this.isMe, required this.progress});

  final bool isMe;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Opacity(
        opacity: progress,
        child: Transform.scale(
          scale: 0.9 + (progress * 0.12),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: U.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: U.primary.withValues(alpha: 0.35)),
            ),
            child: Icon(Icons.reply_rounded, color: U.primary, size: 18),
          ),
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({
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

class _ChatIcebreakerEmptyState extends StatefulWidget {
  const _ChatIcebreakerEmptyState({required this.onSelectIcebreaker});

  final ValueChanged<String> onSelectIcebreaker;

  @override
  State<_ChatIcebreakerEmptyState> createState() => _ChatIcebreakerEmptyStateState();
}

class _ChatIcebreakerEmptyStateState extends State<_ChatIcebreakerEmptyState> {
  int _selectedCategoryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final categories = IcebreakerData.categories;
    final currentCat = categories[_selectedCategoryIndex.clamp(0, categories.length - 1)];

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 26)),
            ),
            const SizedBox(height: 10),
            Text(
              'Break the Ice 💬',
              style: GoogleFonts.outfit(
                color: U.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick an interest topic to start a conversation effortlessly',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: U.sub, fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            // Categories horizontal selector
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = index == _selectedCategoryIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedCategoryIndex = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cat.color.withValues(alpha: 0.15)
                            : U.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? cat.color : U.border,
                          width: isSelected ? 1.4 : 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat.emoji, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 5),
                          Text(
                            cat.title,
                            style: GoogleFonts.outfit(
                              color: isSelected ? cat.color : U.text,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Icebreaker sentences cards
            ...currentCat.starters.map((starter) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onSelectIcebreaker(starter),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: U.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: U.border.withValues(alpha: 0.7)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💬',
                            style: TextStyle(fontSize: 13, color: currentCat.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              starter,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: U.sub.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ChatIcebreakersSheet extends StatefulWidget {
  const _ChatIcebreakersSheet({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  State<_ChatIcebreakersSheet> createState() => _ChatIcebreakersSheetState();
}

class _ChatIcebreakersSheetState extends State<_ChatIcebreakersSheet> {
  int _selectedCategoryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final categories = IcebreakerData.categories;
    final currentCat = categories[_selectedCategoryIndex.clamp(0, categories.length - 1)];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: U.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: U.border, width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: U.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('💡', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Interest Icebreakers',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, color: U.sub, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            'Tap any prompt to insert into your chat message',
            style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Categories horizontal scroll
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = index == _selectedCategoryIndex;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategoryIndex = index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? cat.color.withValues(alpha: 0.15) : U.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? cat.color : U.border,
                        width: isSelected ? 1.4 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.emoji, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Text(
                          cat.title,
                          style: GoogleFonts.outfit(
                            color: isSelected ? cat.color : U.text,
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Starters list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: currentCat.starters.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final starter = currentCat.starters[index];
                return InkWell(
                  onTap: () => widget.onSelect(starter),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: U.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '💬',
                          style: TextStyle(fontSize: 13, color: currentCat.color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            starter,
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.add_circle_outline_rounded, size: 16, color: currentCat.color),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatDateSeparator extends StatelessWidget {
  const _ChatDateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    String label;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Yesterday';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      if (date.year == now.year) {
        label = '${months[date.month - 1]} ${date.day}';
      } else {
        label = '${months[date.month - 1]} ${date.day}, ${date.year}';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: U.border, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              label,
              style: GoogleFonts.outfit(
                color: U.dim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: U.border, thickness: 0.5)),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: U.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
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
                width: 7,
                height: 7,
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
