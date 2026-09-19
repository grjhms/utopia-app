import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

enum MediaPickerTab { gifs, stickers, emojis }

class StickerPack {
  final String id;
  final String name;
  final String icon;
  final List<String> stickers;

  const StickerPack({
    required this.id,
    required this.name,
    required this.icon,
    required this.stickers,
  });
}

class ChatMediaPickerSheet extends StatefulWidget {
  final ValueChanged<String> onSelectGif;
  final ValueChanged<String> onSelectSticker;
  final ValueChanged<String> onSelectEmoji;

  const ChatMediaPickerSheet({
    super.key,
    required this.onSelectGif,
    required this.onSelectSticker,
    required this.onSelectEmoji,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSelectGif,
    required ValueChanged<String> onSelectSticker,
    required ValueChanged<String> onSelectEmoji,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChatMediaPickerSheet(
        onSelectGif: onSelectGif,
        onSelectSticker: onSelectSticker,
        onSelectEmoji: onSelectEmoji,
      ),
    );
  }

  @override
  State<ChatMediaPickerSheet> createState() => _ChatMediaPickerSheetState();
}

class _ChatMediaPickerSheetState extends State<ChatMediaPickerSheet> {
  static const String _giphyApiKey = 'GlVGYHkr3WSBnllca54iNt0yFbjz7L65';

  MediaPickerTab _activeTab = MediaPickerTab.gifs;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _stickerScrollController = ScrollController();
  Timer? _debounce;
  bool _loading = false;
  String _activeGifCategory = 'Trending';
  int _selectedPackIndex = 0;
  List<String> _gifResults = [];
  List<String> _onlineStickerResults = [];

  // Curated fallback sticker packs
  static const List<StickerPack> _stickerPacks = [
    StickerPack(
      id: 'pepe',
      name: 'Pepe & Memes',
      icon: '🐸',
      stickers: [
        'https://media0.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/MDJ9IbxxvDUQM/200.gif',
        'https://media4.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/3oKIPnAiaMCws8nOsE/200.gif',
        'https://media2.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/3o7TKTDnUxE0gpn344/200.gif',
        'https://media1.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/l4FGpP4lxGGgK5CBW/200.gif',
        'https://media3.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/l0MYEqEzwMWFCg8rm/200.gif',
        'https://media4.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/26FLdmG4SRA3UPDPy/200.gif',
      ],
    ),
    StickerPack(
      id: 'mochi',
      name: 'Mochi Peach & Bubu',
      icon: '🐱',
      stickers: [
        'https://media0.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOXVjc3hhaXMzdzVydHdhYzFwM25rdXViOTQ0NmdmazdrczRtY3QzbCZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/XUA7ZZcBl0McuVqwd8/200.gif',
        'https://media3.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOXVjc3hhaXMzdzVydHdhYzFwM25rdXViOTQ0NmdmazdrczRtY3QzbCZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/rrasLFSTyi4Th1e8Xo/200.gif',
        'https://media2.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOXVjc3hhaXMzdzVydHdhYzFwM25rdXViOTQ0NmdmazdrczRtY3QzbCZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/tR1ZZeJXR9RUDvaFVP/200.gif',
        'https://media3.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOXVjc3hhaXMzdzVydHdhYzFwM25rdXViOTQ0NmdmazdrczRtY3QzbCZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/c39G3b12cyqmEhOxib/200.gif',
        'https://media4.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOXVjc3hhaXMzdzVydHdhYzFwM25rdXViOTQ0NmdmazdrczRtY3QzbCZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/2cuI0vwb7w0wmDv7b0/200.gif',
      ],
    ),
    StickerPack(
      id: 'doge',
      name: 'Doge & Cheems',
      icon: '🐶',
      stickers: [
        'https://media1.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/l4FGpP4lxGGgK5CBW/200.gif',
        'https://media4.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/3oKIPnAiaMCws8nOsE/200.gif',
        'https://media2.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/3o7TKTDnUxE0gpn344/200.gif',
        'https://media0.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/MDJ9IbxxvDUQM/200.gif',
      ],
    ),
    StickerPack(
      id: 'anime',
      name: 'Anime & Chibi Hits',
      icon: '⚡',
      stickers: [
        'https://media3.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/l0MYEqEzwMWFCg8rm/200.gif',
        'https://media4.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/26FLdmG4SRA3UPDPy/200.gif',
        'https://media0.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/MDJ9IbxxvDUQM/200.gif',
      ],
    ),
    StickerPack(
      id: 'campus',
      name: 'Campus Life & Study',
      icon: '🎓',
      stickers: [
        'https://media4.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/26FLdmG4SRA3UPDPy/200.gif',
        'https://media2.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/3o7TKTDnUxE0gpn344/200.gif',
        'https://media3.giphy.com/media/v1.Y2lkPWE1YTU4ZDcwOWUzbGJ2OHB4OWp4cTFsOWZtNW96aDR6Y2EwNHRtdXFyc2F6M2ZvaSZlcD12MV9zdGlja2Vyc19zZWFyY2gmY3Q9cw/l0MYEqEzwMWFCg8rm/200.gif',
      ],
    ),
  ];

  final List<String> _gifCategories = [
    'Trending',
    'Pop Culture',
    'Memes',
    'Anime',
    'Student Life',
    'Reactions',
    'Hype',
    'Love',
    'Sad',
    'Gaming',
    'Animals',
  ];

  static const List<Map<String, dynamic>> _emojiCategories = [
    {
      'name': 'Smileys & Emotion',
      'icon': '😀',
      'emojis': [
        '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
        '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
        '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
        '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
        '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮',
        '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐',
        '😕', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '😦', '😧',
        '📁', '🔥', '💯', '✨', '🎉', '🚀', '❤️', '🧡', '💛', '💚',
        '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓',
      ]
    },
    {
      'name': 'Gestures & People',
      'icon': '👋',
      'emojis': [
        '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞',
        '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍',
        '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝',
        '🙏', '✍️', '💅', '🤳', '💪', '🧠', '🫀', '👀', '👁️', '👅',
      ]
    },
    {
      'name': 'Campus & Study',
      'icon': '🎓',
      'emojis': [
        '🎓', '📚', '📖', '📝', '✏️', '💻', '🖥️', '📱', '💡', '🔬',
        '🧪', '📊', '📈', '📋', '📌', '☕', '🧃', '🥪', '🍕', '🎯',
        '🏆', '🥇', '⚡', '🌟', '🎨', '🎧', '⏰', '⏳', '📅', '💬',
      ]
    },
    {
      'name': 'Animals & Nature',
      'icon': '🐱',
      'emojis': [
        '🐱', '🐶', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
        '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦆',
        '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋',
      ]
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchGifs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _stickerScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (_activeTab == MediaPickerTab.gifs) {
        _fetchGifs(query: query);
      } else if (_activeTab == MediaPickerTab.stickers) {
        _fetchStickers(query: query);
      } else {
        setState(() {});
      }
    });
  }

  /// Live real-time search on the global online GIF library
  Future<void> _fetchGifs({String? query}) async {
    setState(() => _loading = true);
    final isQueryEmpty = query == null || query.trim().isEmpty;

    try {
      Uri url;
      if (isQueryEmpty && _activeGifCategory == 'Trending') {
        url = Uri.parse(
          'https://api.giphy.com/v1/gifs/trending?api_key=$_giphyApiKey&limit=36&rating=g',
        );
      } else {
        final term = isQueryEmpty
            ? _activeGifCategory.toLowerCase()
            : query.trim();
        url = Uri.parse(
          'https://api.giphy.com/v1/gifs/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(term)}&limit=36&rating=g',
        );
      }

      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data['data'] ?? [];
        final urls = items
            .map((item) => item['images']?['fixed_height']?['url'] as String?)
            .whereType<String>()
            .toList();

        if (mounted) {
          setState(() {
            _gifResults = urls;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// Live real-time search on the global online Sticker library
  Future<void> _fetchStickers({String? query}) async {
    if (query == null || query.trim().isEmpty) {
      setState(() {
        _onlineStickerResults = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    final term = query.trim();

    try {
      final url = Uri.parse(
        'https://api.giphy.com/v1/stickers/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(term)}&limit=36&rating=g',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data['data'] ?? [];
        final urls = items
            .map((item) => item['images']?['fixed_height']?['url'] as String?)
            .whereType<String>()
            .toList();

        if (mounted) {
          setState(() {
            _onlineStickerResults = urls;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _selectGifCategory(String cat) {
    setState(() {
      _activeGifCategory = cat;
      _searchController.clear();
    });
    _fetchGifs();
  }

  void _selectStickerPack(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPackIndex = index;
      _searchController.clear();
      _onlineStickerResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = appThemeNotifier.value.isDark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72 + keyboardHeight,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      decoration: BoxDecoration(
        color: U.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkTheme ? 0.65 : 0.2),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
        border: Border.all(
          color: isDarkTheme ? Colors.white.withValues(alpha: 0.08) : U.border,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: U.dim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),

          // Primary Tab Bar Selector (GIFs Library / Stickers / Emoji)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDarkTheme
                    ? U.card.withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildTabButton(
                    tab: MediaPickerTab.gifs,
                    title: 'GIFs',
                    icon: Icons.gif_box_rounded,
                  ),
                  _buildTabButton(
                    tab: MediaPickerTab.stickers,
                    title: 'Stickers',
                    icon: Icons.auto_awesome_mosaic_rounded,
                  ),
                  _buildTabButton(
                    tab: MediaPickerTab.emojis,
                    title: 'Emoji',
                    icon: Icons.emoji_emotions_rounded,
                  ),
                ],
              ),
            ),
          ),

          // Search Bar (Live real-time search)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: U.border.withValues(alpha: 0.6),
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: GoogleFonts.outfit(color: U.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _activeTab == MediaPickerTab.emojis
                      ? 'Search emojis...'
                      : (_activeTab == MediaPickerTab.gifs
                          ? 'Search online GIFs (e.g. cat, dance, meme)...'
                          : 'Search online stickers or browse packs...'),
                  hintStyle: GoogleFonts.outfit(color: U.dim, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: U.teal, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: U.sub, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Category Chips for GIFs
          if (_activeTab == MediaPickerTab.gifs)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _gifCategories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _gifCategories[index];
                  final isSelected = _activeGifCategory == cat && _searchController.text.isEmpty;
                  return GestureDetector(
                    onTap: () => _selectGifCategory(cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: [
                                  U.primary,
                                  U.primary.withValues(alpha: 0.85),
                                ],
                              )
                            : null,
                        color: isSelected
                            ? null
                            : (isDarkTheme
                                ? Colors.white.withValues(alpha: 0.04)
                                : U.card),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? U.primary.withValues(alpha: 0.6)
                              : U.border.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          cat,
                          style: GoogleFonts.outfit(
                            color: isSelected ? U.getContrastColor(U.primary) : U.sub,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Content Area
          Expanded(
            child: _activeTab == MediaPickerTab.emojis
                ? _buildEmojiGrid()
                : (_activeTab == MediaPickerTab.gifs
                    ? _buildGifGrid()
                    : _buildStickerSection(isDarkTheme)),
          ),

          // Bottom Sticker Pack Dock Tray (Telegram / WhatsApp Style)
          if (_activeTab == MediaPickerTab.stickers && _searchController.text.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: isDarkTheme ? U.card : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: U.border.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _stickerPacks.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final pack = _stickerPacks[index];
                      final isSelected = _selectedPackIndex == index;
                      return GestureDetector(
                        onTap: () => _selectStickerPack(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? U.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? U.primary
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(pack.icon, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              Text(
                                pack.name,
                                style: GoogleFonts.outfit(
                                  color: isSelected ? U.primary : U.sub,
                                  fontSize: 12,
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
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required MediaPickerTab tab,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _activeTab = tab;
            _searchController.clear();
          });
          if (tab == MediaPickerTab.gifs) {
            _fetchGifs();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? U.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: U.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? U.getContrastColor(U.primary) : U.sub,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: isSelected ? U.getContrastColor(U.primary) : U.sub,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGifGrid() {
    if (_loading && _gifResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    if (_gifResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: U.dim, size: 36),
            const SizedBox(height: 8),
            Text(
              'No online GIFs found',
              style: GoogleFonts.outfit(color: U.dim, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.25,
      ),
      itemCount: _gifResults.length,
      itemBuilder: (context, index) {
        final url = _gifResults[index];
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
            widget.onSelectGif(url);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: U.card,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, _) => Container(
                  color: U.surface,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Icon(Icons.broken_image, color: U.dim),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStickerSection(bool isDarkTheme) {
    // If user is searching stickers online
    if (_searchController.text.isNotEmpty) {
      if (_loading && _onlineStickerResults.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      }

      if (_onlineStickerResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, color: U.dim, size: 36),
              const SizedBox(height: 8),
              Text(
                'No online stickers found',
                style: GoogleFonts.outfit(color: U.dim, fontSize: 14),
              ),
            ],
          ),
        );
      }

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: _onlineStickerResults.length,
        itemBuilder: (context, index) {
          final url = _onlineStickerResults[index];
          return _buildStickerTile(url);
        },
      );
    }

    // Browse curated Sticker Pack Library
    final currentPack = _stickerPacks[_selectedPackIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(currentPack.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                currentPack.name,
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${currentPack.stickers.length} stickers',
                style: GoogleFonts.outfit(
                  color: U.dim,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _stickerScrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.0,
            ),
            itemCount: currentPack.stickers.length,
            itemBuilder: (context, index) {
              final url = currentPack.stickers[index];
              return _buildStickerTile(url);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStickerTile(String url) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context);
        widget.onSelectSticker(url);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: U.card.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: U.border.withValues(alpha: 0.35),
          ),
        ),
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, _) => const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            errorWidget: (context, url, error) => Icon(Icons.broken_image, color: U.dim),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiGrid() {
    final search = _searchController.text.trim().toLowerCase();
    List<String> emojisToShow = [];

    if (search.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _emojiCategories.length,
        itemBuilder: (context, catIndex) {
          final cat = _emojiCategories[catIndex];
          final emojis = (cat['emojis'] as List<String>);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      cat['icon'] as String,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cat['name'] as String,
                      style: GoogleFonts.outfit(
                        color: U.sub,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.0,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, emojiIdx) {
                  final emoji = emojis[emojiIdx];
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onSelectEmoji(emoji);
                    },
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      );
    } else {
      // Collect matching emojis
      for (final cat in _emojiCategories) {
        for (final e in (cat['emojis'] as List<String>)) {
          if (cat['name'].toString().toLowerCase().contains(search) ||
              e.contains(search)) {
            emojisToShow.add(e);
          }
        }
      }
      if (emojisToShow.isEmpty) {
        for (final cat in _emojiCategories) {
          emojisToShow.addAll(cat['emojis'] as List<String>);
        }
      }

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1.0,
        ),
        itemCount: emojisToShow.length,
        itemBuilder: (context, emojiIdx) {
          final emoji = emojisToShow[emojiIdx];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onSelectEmoji(emoji);
            },
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 26),
              ),
            ),
          );
        },
      );
    }
  }
}
