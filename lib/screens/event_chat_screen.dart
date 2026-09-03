import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import '../widgets/chat_media_picker.dart';
import '../widgets/utopia_loader.dart';

class EventChatScreen extends StatefulWidget {
  final EventModel event;
  const EventChatScreen({super.key, required this.event});

  @override
  State<EventChatScreen> createState() => _EventChatScreenState();
}

class _EventChatScreenState extends State<EventChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;
  bool _showScrollDown = false;
  Map<String, dynamic>? _replyingTo;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Palette for distinctive student sender identity colors in group/event chat
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final show = (maxScroll - currentScroll) > 160.0;
    if (show != _showScrollDown) {
      setState(() => _showScrollDown = show);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _sendMessage({String? overrideText}) async {
    final text = (overrideText ?? _messageController.text).trim();
    if (text.isEmpty || widget.event.id == null || _isSending) return;

    setState(() => _isSending = true);
    if (overrideText == null) {
      _messageController.clear();
    }

    String fullMessage = text;
    if (_replyingTo != null) {
      final replySender = _replyingTo!['userName'] ?? 'User';
      final replyText = _replyingTo!['message'] ?? '';
      fullMessage = '💬 Replying to @$replySender: "$replyText"\n$text';
    }

    final success = await EventService.instance.sendChatMessage(widget.event.id!, fullMessage);

    if (mounted) {
      setState(() {
        _isSending = false;
        if (success) {
          _replyingTo = null;
        }
      });
      if (success) {
        Future.delayed(const Duration(milliseconds: 120), () => _scrollToBottom());
      }
    }
  }

  void _openMediaPicker() {
    ChatMediaPickerSheet.show(
      context,
      onSelectGif: (url) => _sendMessage(overrideText: '👾 GIF: $url'),
      onSelectSticker: (url) => _sendMessage(overrideText: '🎨 Sticker: $url'),
      onSelectEmoji: (emoji) {
        _messageController.text = '${_messageController.text}$emoji';
        _messageController.selection = TextSelection.collapsed(offset: _messageController.text.length);
      },
    );
  }

  void _startReply(EventChatMessage msg) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyingTo = {
        'id': msg.id,
        'userName': msg.userName,
        'message': msg.message,
      };
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  void _showMessageOptions(EventChatMessage msg, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: U.card,
      elevation: 2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: U.border.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
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
                  title: Text('Reply', style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startReply(msg);
                  },
                ),
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
                  title: Text('Copy text', style: GoogleFonts.outfit(color: U.text, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: msg.message));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied to clipboard', style: GoogleFonts.outfit(color: U.bg)),
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

  bool _isOnlyEmoji(String text) {
    if (text.isEmpty) return false;
    final runes = text.runes.toList();
    if (runes.length > 3) return false;
    for (final rune in runes) {
      if (rune < 0x1F000 && rune != 0x2764 && rune != 0xFE0F && rune != 0x200D) {
        return false;
      }
    }
    return true;
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
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

  bool _shouldShowDateSeparator(List<EventChatMessage> messages, int index) {
    if (index == 0) return true;
    final curr = messages[index].createdAt;
    final prev = messages[index - 1].createdAt;
    if (curr == null || prev == null) return false;
    return curr.year != prev.year || curr.month != prev.month || curr.day != prev.day;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = appThemeNotifier.value.isDark;

    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.bg,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: U.text, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.event_note_rounded, color: U.primary, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.event.title,
                    style: GoogleFonts.outfit(
                      color: U.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: U.teal,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        'Event Community Chat',
                        style: GoogleFonts.outfit(
                          color: U.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.auto_awesome_rounded, color: U.teal, size: 22),
            tooltip: 'GIFs & Stickers',
            onPressed: _openMediaPicker,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                widget.event.id != null
                    ? StreamBuilder<List<EventChatMessage>>(
                        stream: EventService.instance.streamChat(widget.event.id!),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                            return const Center(child: UtopiaLoader(scale: 0.7));
                          }

                          final messages = snapshot.data ?? [];

                          if (messages.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: U.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(Icons.forum_outlined, color: U.primary, size: 30),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Be the first to say hi!',
                                    style: GoogleFonts.outfit(
                                      color: U.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Connect with participants and organizers.',
                                    style: GoogleFonts.outfit(color: U.dim, fontSize: 13),
                                  ),
                                ],
                              ),
                            );
                          }

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!_showScrollDown) {
                              _scrollToBottom(animated: false);
                            }
                          });

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];
                              final isMe = msg.userId == _currentUid;
                              final showDate = _shouldShowDateSeparator(messages, index);

                              return Column(
                                children: [
                                  if (showDate && msg.createdAt != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Divider(
                                              color: U.border.withValues(alpha: 0.5),
                                              thickness: 0.5,
                                            ),
                                          ),
                                          Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 12),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isDarkTheme
                                                  ? Colors.white.withValues(alpha: 0.05)
                                                  : Colors.black.withValues(alpha: 0.04),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _formatDateLabel(msg.createdAt!),
                                              style: GoogleFonts.outfit(
                                                color: U.dim,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Divider(
                                              color: U.border.withValues(alpha: 0.5),
                                              thickness: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Align(
                                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                    child: _EventSwipeToReply(
                                      onReply: () => _startReply(msg),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onLongPress: () => _showMessageOptions(msg, isMe),
                                        onDoubleTap: () => _startReply(msg),
                                        child: _buildBubble(msg, isMe, isDarkTheme),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      )
                    : Center(
                        child: Text('Chat not available', style: GoogleFonts.outfit(color: U.sub)),
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
                          onTap: () => _scrollToBottom(),
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
                            child: Center(
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: U.primary,
                                size: 26,
                              ),
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
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: U.card,
                border: Border(top: BorderSide(color: U.border.withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
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
                          'Replying to ${_replyingTo!['userName'] ?? 'User'}',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _replyingTo!['message'] ?? '',
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Container(
                      padding: const EdgeInsets.all(4),
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

          // Docked M3 Composer Bar
          Container(
            color: U.bg,
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.paddingOf(context).bottom + 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Media / Emoji Picker Button
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, right: 8),
                  child: GestureDetector(
                    onTap: _openMediaPicker,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isDarkTheme
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(
                          color: U.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.add_reaction_outlined,
                          color: U.teal,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ),

                // Text Field Input Container
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: U.border.withValues(alpha: 0.6),
                      ),
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      style: GoogleFonts.outfit(color: U.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Type in event chat...',
                        hintStyle: GoogleFonts.outfit(color: U.dim, fontSize: 14),
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send Button
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          U.primary,
                          U.primary.withValues(alpha: 0.88),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: U.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(EventChatMessage msg, bool isMe, bool isDarkTheme) {
    final rawText = msg.message;
    final isEmoji = _isOnlyEmoji(rawText);

    if (isEmoji) {
      final fontSize = rawText.runes.length == 1 ? 48.0 : (rawText.runes.length == 2 ? 38.0 : 32.0);
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderNameTag(msg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(rawText, style: TextStyle(fontSize: fontSize, height: 1.15)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 1),
              child: Text(
                _formatTime(msg.createdAt),
                style: GoogleFonts.outfit(color: U.dim, fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: isMe
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  U.primary,
                  U.primary.withValues(alpha: 0.88),
                ],
              )
            : null,
        color: isMe ? null : U.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 5),
          bottomRight: Radius.circular(isMe ? 5 : 20),
        ),
        border: isMe
            ? null
            : Border.all(
                color: isDarkTheme
                    ? Colors.white.withValues(alpha: 0.08)
                    : U.border.withValues(alpha: 0.6),
                width: 0.8,
              ),
        boxShadow: [
          BoxShadow(
            color: isMe
                ? U.primary.withValues(alpha: isDarkTheme ? 0.25 : 0.18)
                : Colors.black.withValues(alpha: isDarkTheme ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildSenderNameTag(msg),
            ),
          Text(
            rawText,
            style: GoogleFonts.outfit(
              color: isMe ? Colors.white : U.text,
              fontSize: 15,
              height: 1.35,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTime(msg.createdAt),
            style: GoogleFonts.outfit(
              color: isMe ? Colors.white.withValues(alpha: 0.72) : U.dim,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSenderNameTag(EventChatMessage msg) {
    final senderName = msg.userName.isNotEmpty ? msg.userName : 'Student';
    final senderColor = _getSenderColor(senderName);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          senderName,
          style: GoogleFonts.outfit(
            color: msg.isOrganizer ? U.teal : senderColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (msg.isOrganizer) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: U.teal.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: U.teal, size: 10),
                const SizedBox(width: 2),
                Text(
                  'Host',
                  style: GoogleFonts.outfit(
                    color: U.teal,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EventSwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const _EventSwipeToReply({
    required this.child,
    required this.onReply,
  });

  @override
  State<_EventSwipeToReply> createState() => _EventSwipeToReplyState();
}

class _EventSwipeToReplyState extends State<_EventSwipeToReply> {
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

