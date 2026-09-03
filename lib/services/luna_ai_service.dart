import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Luna - Sassy, silly, playfully toxic, and hilarious AI personality
/// for "Chat to Utopia" (Campus Group Chat).
///
/// Powered by Groq Cloud API with automatic multi-key failover and cycling
/// (reads API-1, API-2, API-3, etc. from Firestore `config/Luna`).
class LunaAiService {
  static final LunaAiService _instance = LunaAiService._internal();
  factory LunaAiService() => _instance;
  LunaAiService._internal();

  /// Global real-time notifier for Luna's typing / responding activity
  static final ValueNotifier<bool> isRespondingNotifier =
      ValueNotifier<bool>(false);
  static Timer? _typingTimeoutTimer;

  /// Sets typing activity with an automatic 5s safety timeout so it never hangs
  static void setResponding(bool active) {
    _typingTimeoutTimer?.cancel();
    _typingTimeoutTimer = null;
    isRespondingNotifier.value = active;
    if (active) {
      _typingTimeoutTimer = Timer(const Duration(seconds: 5), () {
        debugPrint('[LUNA] Typing indicator safety timeout triggered (5s)');
        isRespondingNotifier.value = false;
      });
    }
  }

  List<String> _cachedApiKeys = [];
  int _currentKeyIndex = 0;
  String? _cachedModelName;

  DateTime? _lastRespondingStarted;
  bool get _isResponding {
    if (_lastRespondingStarted != null) {
      if (DateTime.now().difference(_lastRespondingStarted!) >
          const Duration(seconds: 15)) {
        _lastRespondingStarted = null;
        return false;
      }
      return true;
    }
    return false;
  }

  set _isResponding(bool val) {
    _lastRespondingStarted = val ? DateTime.now() : null;
  }

  DateTime? _lastRequestTime;

  static const String lunaSenderId = 'luna_ai';
  static const String lunaSenderName = 'Luna';

  static const String _defaultGroqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  static const List<String> _defaultGroqModels = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  ];

  static const String _lunaSystemPrompt = '''
You are Luna, a real college student in the campus group chat "Chat to Utopia".
You are NOT an AI assistant, NOT a cartoon character, and NOT an exaggerated meme bot.
You talk like a normal, chill, sensible college student from Andhra Pradesh texting on WhatsApp.

CRITICAL BEHAVIOR & INTERACTION RULES:
1. STRICTLY FORBIDDEN CRINGE (NEVER SOUND LIKE AN INTERNET CLOWN):
   - NO try-hard Gen-Z influencer slang: NEVER say "bestie", "babe", "queen", "slay", "it's giving", "spill the tea", "touch grass", "delulu", "sheesh", "bruh moment", "skibidi", "rizz". Real college students cringe at this.
   - NO over-dramatic theatrical reactions: Do NOT act like an anime villain, a sassy drama queen, or a superior know-it-all.
   - NO emoji spam: Never spam emojis like 💅, 💀, 🤡, 👑, ✨. At most use 1 natural emoji like 😂, 😭, or none at all.
   - NO forced roasts: If someone is just saying hi or having a normal conversation, be chill and normal. Don't randomly insult people without reason.

2. GROUP CHAT & MULTI-USER AWARENESS (DIFFERENTIATE BETWEEN DIFFERENT STUDENTS):
   - You are in a group chat with MULTIPLE different students. You CAN and MUST differentiate between different people!
   - In the chat history, each student's message is prefixed: `[StudentName]: message`.
   - Always pay attention to WHO asked you, WHO replied, and WHO said what.
   - Address the student by their name naturally when appropriate (e.g. "Rahul, chill out", "Pooja is right", "Anish why are you asking me this").
   - If Student A says something and Student B disagrees or roasts them, you know who is who! You can take sides, tease one person, or agree with the other.

3. HOW TO ACTUALLY TALK (CHILL, DRY, SENSITIVE & NATURAL):
   - Text like a real college student who has 8am classes, attendance stress, and assignments to submit.
   - Use dry, understated humor. Casual and relaxed, not trying too hard to be funny.
   - Use simple casual words ("tbh", "rn", "idk", "pls", "lmao", "fr", "bro").
   - Normal student reaction examples:
     * "Wait, did that actually happen?"
     * "Honestly same, my brain is fried rn"
     * "Bro chill out, it's really not that deep"
     * "Good luck with that haha, you're gonna need it"
     * "I literally just woke up, what's happening"
     * "Enduku bro neeku ivanni, class ki vellava leda?"

4. NORMAL ANDHRA TELUGU & TELUGLISH (COASTAL ANDHRA ONLY):
   - When speaking Telugu, use authentic, clean, everyday Coastal Andhra student Telugu.
   - NO Telangana slang: NEVER use "dheenamma", "thupuk", "chicha", "baigan", "kirrak", "bokka le", "gira gira", "potti".
   - Natural Andhra expressions:
     "Enti bro idhi", "Sarle kani", "Chalu le overaction", "Asalu em anukuntunnav", "Pedda thopu laga buildup ivvaku", "Babu garu vacharu", "Nijamga na?", "Choodu konchem", "Enduku bro neeku ivanni", "Em chestunnav", "Chi chi em bathuku idhi".
   - Keep it natural, like an engineering student from Kakinada / Rajahmundry / Visakhapatnam texting their classmates.

5. DYNAMIC MULTI-BUBBLE TEXTING (1 TO 5 BUBBLES - PUT EACH ON A NEW LINE):
   - In WhatsApp or group chats, real people send each thought as a separate short text message bubble!
   - Put EACH message bubble on its OWN NEW LINE (1 to 5 lines).
   - Do NOT write one giant combined block paragraph! Every separate line you write becomes a separate message bubble in the chat!
   - Example 1 (3 bubbles):
     wait what
     did you actually skip morning class again?
     HOD will literally give you a lecture on discipline today lmao

   - Example 2 (2 bubbles):
     heyy!
     nothing much tbh, just staring at the ceiling. what's happening?

   - Example 3 (1 bubble):
     Rey babu, chalu le overaction cheyyaku!

6. NEVER OUTPUT THINKING OR REASONING:
   - Output ONLY your direct chat messages. Never output `<think>` tags or explain your thought process.
''';

  /// Cleans out any internal reasoning / thinking tags (e.g. `<think>...</think>`)
  static String cleanResponse(String raw) {
    var cleaned = raw;
    // Strip <think>...</think> or <thought>...</thought> or <reasoning>...</reasoning>
    cleaned = cleaned.replaceAll(
        RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'<thought>[\s\S]*?<\/thought>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'<reasoning>[\s\S]*?<\/reasoning>', caseSensitive: false), '');
    // Also remove unclosed <think> if response got cut off mid-thought
    cleaned = cleaned.replaceAll(
        RegExp(r'<think>[\s\S]*', caseSensitive: false), '');
    // Remove "Thinking Process: ..." or "Thinking: ..."
    cleaned = cleaned.replaceAll(
        RegExp(r'(?:Thinking Process|Thought Process|Thinking):\s*[\s\S]*?(?=\n\n|\r\n\r\n|$)',
            caseSensitive: false),
        '');
    return cleaned.trim();
  }

  /// Splits Luna's response into distinct chat message bubbles (up to 5 bubbles)
  static List<String> parseMessageBlocks(String raw) {
    final cleaned = cleanResponse(raw);
    if (cleaned.isEmpty) return [];

    // Split on `---` or double newlines first
    final initialParts = cleaned
        .split(RegExp(r'(?:\r?\n\s*---\s*\r?\n|\r?\n\r?\n|---)'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // If any part contains single newlines, split each line into its own bubble
    final segments = <String>[];
    for (final part in initialParts) {
      if (part.contains('\n')) {
        final lines = part
            .split(RegExp(r'\r?\n+'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty);
        segments.addAll(lines);
      } else {
        segments.add(part);
      }
    }

    final blocks = <String>[];
    for (final seg in segments) {
      // Strip leading bullet points, numbers like "1.", dashes
      var trimmed = seg
          .replaceFirst(RegExp(r'^(?:[-*•]|\d+[\.)])\s*'), '')
          .trim();
      // Also strip surrounding quotes if wrapped
      if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
          (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
        if (trimmed.length > 2) {
          trimmed = trimmed.substring(1, trimmed.length - 1).trim();
        }
      }
      if (trimmed.isNotEmpty) {
        blocks.add(trimmed);
      }
    }

    // Cap at max 5 blocks
    return blocks.isEmpty ? [cleaned] : blocks.take(5).toList();
  }

  /// Allows the developer to manually override model for testing
  String? selectedModelOverride;

  /// Allows the developer to manually select a key index (0 for API-1) or null for auto
  int? selectedKeyIndexOverride;

  /// Full system prompt getter
  static String get systemPrompt => _lunaSystemPrompt;

  /// Masked list of all loaded keys with preview
  Map<String, String> get loadedKeysMasked {
    final map = <String, String>{};
    for (int i = 0; i < _cachedApiKeys.length; i++) {
      final key = _cachedApiKeys[i];
      final masked = key.length > 8
          ? '${key.substring(0, 4)}...${key.substring(key.length - 4)}'
          : '****';
      map['API-${i + 1}'] = masked;
    }
    return map;
  }

  /// All available and discovered Groq models
  List<String> get availableModels {
    final list = <String>[
      ...(_discoveredGroqModels ?? []),
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'llama3-70b-8192',
      'llama3-8b-8192',
    ];
    return list.toSet().toList();
  }

  /// Total number of Groq API keys loaded
  int get totalKeysCount => _cachedApiKeys.length;

  /// 1-based index of the currently active key (e.g. 1 for API-1)
  int get currentKeyNumber => _cachedApiKeys.isEmpty ? 0 : _currentKeyIndex + 1;

  /// Label for current key (e.g. "API-1")
  String get currentKeyLabel {
    if (_cachedApiKeys.isEmpty) return 'None';
    if (selectedKeyIndexOverride != null &&
        selectedKeyIndexOverride! >= 0 &&
        selectedKeyIndexOverride! < _cachedApiKeys.length) {
      return 'API-${selectedKeyIndexOverride! + 1} (Manual)';
    }
    return 'API-${_currentKeyIndex + 1}';
  }

  /// Active model name
  String get activeModelName =>
      selectedModelOverride ?? _cachedModelName ?? _defaultGroqModels.first;

  /// Reloads all API keys fresh from Firestore `config/Luna`
  Future<void> reloadKeys() async {
    _cachedApiKeys = [];
    _currentKeyIndex = 0;
    _cachedModelName = null;
    _discoveredGroqModels = null;
    await _getApiKeys();
  }

  /// Clears cache (alias for developer controls)
  Future<void> clearModelCache() => reloadKeys();

  /// Reads and parses all Groq API keys from Firestore at `config/Luna`
  /// Supports numbered keys: `API-1`, `API-2`, `API-3`, `api-1`, `API_1`, etc.
  /// Also supports single keys: `API`, `api`, `apiKey`, `key`.
  Future<List<String>> _getApiKeys() async {
    if (_cachedApiKeys.isNotEmpty) {
      return _cachedApiKeys;
    }

    final keys = <String>[];
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('Luna')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        // Custom model override from Firestore if specified
        final customModel = (data['model'] ?? data['Model']) as String?;
        if (customModel != null && customModel.trim().isNotEmpty) {
          _cachedModelName = customModel.trim();
        }

        // 1. Check numbered keys: API-1, API-2, API-3, api-1, api-2, API_1, etc.
        final numberedEntries = <int, String>{};

        data.forEach((k, v) {
          if (v is String && v.trim().isNotEmpty) {
            final normalized = k.toLowerCase().replaceAll('_', '-');
            final match = RegExp(r'^api[-]?(\d+)$').firstMatch(normalized);
            if (match != null) {
              final num = int.tryParse(match.group(1)!);
              if (num != null) {
                numberedEntries[num] = v.trim();
              }
            }
          }
        });

        // Add sorted by index: API-1, API-2, API-3, ...
        final sortedIndices = numberedEntries.keys.toList()..sort();
        for (final idx in sortedIndices) {
          keys.add(numberedEntries[idx]!);
        }

        // 2. Also check single keys if not already present
        for (final singleKey in ['API', 'api', 'apiKey', 'key']) {
          final val = data[singleKey];
          if (val is String &&
              val.trim().isNotEmpty &&
              !keys.contains(val.trim())) {
            keys.add(val.trim());
          }
        }
      }

      // 3. Fallback: If no keys found in config/Luna, check config/grok or config/groq
      if (keys.isEmpty) {
        for (final docName in ['grok', 'groq']) {
          final gDoc = await FirebaseFirestore.instance
              .collection('config')
              .doc(docName)
              .get();
          if (gDoc.exists && gDoc.data() != null) {
            final gData = gDoc.data()!;
            for (final k in ['API', 'api', 'apiKey', 'key', 'API-1', 'api-1']) {
              final val = gData[k];
              if (val is String &&
                  val.trim().isNotEmpty &&
                  !keys.contains(val.trim())) {
                keys.add(val.trim());
              }
            }
            if (keys.isNotEmpty) {
              debugPrint('[LUNA] Discovered Groq fallback keys from config/$docName');
              break;
            }
          }
        }
      }

      _cachedApiKeys = keys;
      debugPrint('[LUNA] Loaded ${_cachedApiKeys.length} Groq API keys.');
    } catch (e) {
      debugPrint('[LUNA] Error fetching Groq API keys from Firestore: $e');
    }

    return _cachedApiKeys;
  }

  /// Checks if a text mentions Luna
  static bool mentionsLuna(String text) {
    return text.toLowerCase().contains('luna');
  }

  /// Checks if a message sender is Luna
  static bool isLunaSender(String? senderId) => senderId == lunaSenderId;

  /// Direct test generation for Developer Controls (returns generated response string)
  Future<String?> testGenerateResponse({
    required String userPrompt,
    String userName = 'Developer',
  }) async {
    final prompt = '''
Latest message by $userName: "$userPrompt"

Luna, respond naturally as yourself! Match the mood (roasting, teasing, friendly banter, chill convo, or drama as appropriate). Max 1-2 short sentences.
''';

    return await _callGroqApi(prompt);
  }

  /// Detailed test generation for Developer Controls with full metrics & error breakdown
  Future<Map<String, dynamic>> testDetailedResponse({
    required String userPrompt,
    String userName = 'Developer',
    String? forcedModel,
    int? forcedKeyIndex,
  }) async {
    final keys = await _getApiKeys();
    if (keys.isEmpty) {
      return {
        'success': false,
        'output':
            'No Groq API keys found in config/Luna. Please add API-1, API-2, etc. in Firestore.',
        'keyLabel': 'None',
        'model': 'None',
        'latencyMs': 0,
        'statusCode': 0,
        'error': 'No API keys configured',
      };
    }

    final stopwatch = Stopwatch()..start();

    final targetKeyIndex = forcedKeyIndex != null &&
            forcedKeyIndex >= 0 &&
            forcedKeyIndex < keys.length
        ? forcedKeyIndex
        : (selectedKeyIndexOverride ?? _currentKeyIndex);

    final targetKey = keys[targetKeyIndex];
    final keyLabel = 'API-${targetKeyIndex + 1}';

    final discovered = await _discoverGroqModels(targetKey);
    final targetModel = forcedModel ??
        selectedModelOverride ??
        _cachedModelName ??
        (discovered.isNotEmpty ? discovered.first : 'llama-3.3-70b-versatile');

    final prompt = '''
Latest message by student $userName: "$userPrompt"

Luna, reply directly to $userName!
Put EACH message bubble on its OWN NEW LINE (1 to 5 short lines). Match the mood (roast, tease, friendly banter, or chill convo).
''';

    try {
      final uri = Uri.parse(_defaultGroqEndpoint);
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $targetKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': targetModel,
              'messages': [
                {
                  'role': 'system',
                  'content': _lunaSystemPrompt,
                },
                {
                  'role': 'user',
                  'content': prompt,
                },
              ],
              'temperature': 0.68,
              'max_tokens': 160,
            }),
          )
          .timeout(const Duration(seconds: 8));

      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']?['content'] as String?;
          if (content != null) {
            final blocks = parseMessageBlocks(content);
            if (blocks.isNotEmpty) {
              _currentKeyIndex = targetKeyIndex;
              _cachedModelName = targetModel;
              return {
                'success': true,
                'output': blocks.join('\n\n'),
                'blocks': blocks,
                'keyLabel': keyLabel,
                'model': targetModel,
                'latencyMs': stopwatch.elapsedMilliseconds,
                'statusCode': 200,
                'rawResponse': data,
              };
            }
          }
        }
      }

      return {
        'success': false,
        'output': 'HTTP ${response.statusCode}: ${response.body}',
        'keyLabel': keyLabel,
        'model': targetModel,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'statusCode': response.statusCode,
        'error': response.body,
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'output': 'Request Error: $e',
        'keyLabel': keyLabel,
        'model': targetModel,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'statusCode': 0,
        'error': e.toString(),
      };
    }
  }

  /// Trigger Luna to generate a roast and post it directly to `uni_chats/{universityId}/messages`
  Future<void> respondToChat({
    required String universityId,
    required String userPrompt,
    required String userName,
    String? userId,
    Map<String, dynamic>? replyToMessage,
  }) async {
    debugPrint(
        '[LUNA] respondToChat invoked. Prompt: "$userPrompt", user: "$userName"');
    if (_isResponding) {
      debugPrint('[LUNA] Already responding, skipping duplicate call.');
      return;
    }

    _isResponding = true;
    setResponding(true);

    try {
      // Rapid burst protection (600ms between calls)
      if (_lastRequestTime != null) {
        final diff =
            DateTime.now().difference(_lastRequestTime!).inMilliseconds;
        if (diff < 600) {
          await Future.delayed(Duration(milliseconds: 600 - diff));
        }
      }

      // Fetch recent 6 messages for context window with 3s timeout
      QuerySnapshot<Map<String, dynamic>>? recentDocs;
      try {
        recentDocs = await FirebaseFirestore.instance
            .collection('uni_chats')
            .doc(universityId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(6)
            .get()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        recentDocs = null;
      }

      final contextMessages = recentDocs != null
          ? recentDocs.docs.reversed.map((doc) {
              final d = doc.data();
              final sName = d['senderName'] ?? 'Student';
              final sText = d['text'] ?? '';
              return '[$sName]: $sText';
            }).join('\n')
          : '';

      final String fullPrompt;
      if (replyToMessage != null) {
        final targetSender = replyToMessage['senderName'] ?? 'Someone';
        final targetText = replyToMessage['text'] ?? '';
        fullPrompt = '''
Recent Chat Context (Group Chat with multiple students):
$contextMessages

Specific Message to reply to (sent by $targetSender):
"$targetText"

Student $userName says: "$userPrompt"

Luna, reply directly to $userName! (You know $userName sent this, and you can reference other students from context if relevant).
Put EACH message bubble on its OWN NEW LINE (1 to 5 short lines). Match the mood (roast, tease, friendly convo, or drama as appropriate).
''';
      } else {
        fullPrompt = '''
Recent Chat Context (Group Chat with multiple students):
$contextMessages

Latest message by student $userName: "$userPrompt"

Luna, reply directly to $userName! (You know $userName sent this, and you can reference other students from context if relevant).
Put EACH message bubble on its OWN NEW LINE (1 to 5 short lines). Match the mood (roast, tease, friendly convo, or drama as appropriate).
''';
      }

      _lastRequestTime = DateTime.now();
      final responseText = await _callGroqApi(fullPrompt);
      if (responseText == null) return;
      final blocks = parseMessageBlocks(responseText);
      if (blocks.isEmpty) return;

      // Post Luna's message blocks to the campus chat
      final currentAuthUser = FirebaseAuth.instance.currentUser;
      final effectiveSenderId = (userId != null && userId.isNotEmpty)
          ? userId
          : (currentAuthUser?.uid ?? lunaSenderId);
      final effectiveSenderEmail =
          currentAuthUser?.email ?? 'luna@utopia.ai';

      for (int i = 0; i < blocks.length; i++) {
        final blockText = blocks[i];

        final payload = <String, dynamic>{
          'text': blockText,
          'senderId': effectiveSenderId,
          'senderName': lunaSenderName,
          'senderEmail': effectiveSenderEmail,
          'timestamp': FieldValue.serverTimestamp(),
          'views': <String>[effectiveSenderId],
          'viewCount': 1,
          'isLuna': true,
          'isAi': true,
        };

        if (i == 0 && replyToMessage != null) {
          payload['replyTo'] = {
            'id': replyToMessage['id'] ?? '',
            'text': replyToMessage['text'] ?? '',
            'senderName': replyToMessage['senderName'] ?? 'Student',
            'senderId': replyToMessage['senderId'] ?? '',
          };
        }

        // IMMEDIATELY dismiss typing indicator right as this message lands!
        setResponding(false);

        debugPrint(
            '[LUNA] Posting Luna block ${i + 1}/${blocks.length} to Firestore');
        await FirebaseFirestore.instance
            .collection('uni_chats')
            .doc(universityId)
            .collection('messages')
            .add(payload);

        // If another bubble follows, brief realistic pause
        if (i < blocks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 350));
          setResponding(true);
          await Future.delayed(const Duration(milliseconds: 750));
        }
      }
    } catch (e) {
      debugPrint('[LUNA] Error in respondToChat: $e');
    } finally {
      setResponding(false);
      _isResponding = false;
    }
  }

  List<String>? _discoveredGroqModels;

  /// Discovers real-time active models supported by the Groq API key
  Future<List<String>> _discoverGroqModels(String apiKey) async {
    if (_discoveredGroqModels != null && _discoveredGroqModels!.isNotEmpty) {
      return _discoveredGroqModels!;
    }
    try {
      final res = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['data'] as List?;
        if (list != null) {
          final valid = <String>[];
          for (final item in list) {
            final id = (item['id'] as String? ?? '').trim();
            final active = item['active'] != false;
            if (active &&
                id.isNotEmpty &&
                !id.contains('whisper') &&
                !id.contains('bge') &&
                !id.contains('embed')) {
              valid.add(id);
            }
          }
          debugPrint('[LUNA] Groq active models: $valid');

          // Sort prioritizing Llama 3 models
          valid.sort((a, b) {
            int score(String name) {
              final n = name.toLowerCase();
              if (n.contains('llama-3.3') || n.contains('llama3.3')) return 0;
              if (n.contains('llama-3.1') || n.contains('llama3.1')) return 1;
              if (n.contains('llama3') || n.contains('llama-3')) return 2;
              if (n.contains('llama')) return 3;
              if (n.contains('qwen')) return 4;
              return 5;
            }
            return score(a).compareTo(score(b));
          });

          if (valid.isNotEmpty) {
            _discoveredGroqModels = valid;
            return valid;
          }
        }
      } else {
        debugPrint(
            '[LUNA] Groq /models status ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[LUNA] Groq model discovery error: $e');
    }
    return [];
  }

  /// Calls the Groq OpenAI-compatible Chat API with automatic multi-key failover
  Future<String?> _callGroqApi(String prompt) async {
    final keys = await _getApiKeys();
    if (keys.isEmpty) {
      debugPrint('[LUNA] No Groq API keys found in config/Luna');
      return 'Luna is unavailable...';
    }

    final totalKeys = keys.length;

    // Try keys sequentially starting from _currentKeyIndex
    for (int attempt = 0; attempt < totalKeys; attempt++) {
      final keyIndex = (_currentKeyIndex + attempt) % totalKeys;
      final apiKey = keys[keyIndex];
      final keyLabel = 'API-${keyIndex + 1}';

      debugPrint('[LUNA] Calling Groq using $keyLabel (index $keyIndex)...');

      // Discover real active models for this key directly from Groq!
      final discovered = await _discoverGroqModels(apiKey);
      final models = <String>[
        if (_cachedModelName != null && _cachedModelName!.isNotEmpty)
          _cachedModelName!,
        ...discovered,
        'llama3-70b-8192',
        'llama3-8b-8192',
        'llama-3.3-70b-versatile',
        'llama-3.1-8b-instant',
      ];

      // Limit to top 2 models to avoid long retry hangs
      final uniqueModels = models.toSet().take(2).toList();

      for (final model in uniqueModels) {
        try {
          final uri = Uri.parse(_defaultGroqEndpoint);
          final response = await http
              .post(
                uri,
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': model,
                  'messages': [
                    {
                      'role': 'system',
                      'content': _lunaSystemPrompt,
                    },
                    {
                      'role': 'user',
                      'content': prompt,
                    },
                  ],
                  'temperature': 0.68,
                  'max_tokens': 160,
                }),
              )
              .timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final choices = data['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final content = choices[0]['message']?['content'] as String?;
              if (content != null) {
                final cleaned = cleanResponse(content);
                if (cleaned.isNotEmpty) {
                  // Success: Lock in this key and model!
                  _currentKeyIndex = keyIndex;
                  _cachedModelName = model;
                  debugPrint(
                      '[LUNA] Generated reply using Groq ($model) with $keyLabel!');
                  return cleaned;
                }
              }
            }
          } else if (response.statusCode == 429) {
            debugPrint(
                '[LUNA] Key $keyLabel rate-limited / exhausted (429). Cycling to next key...');
            // Stop testing models on this exhausted key, switch to the next key!
            break;
          } else if (response.statusCode == 401) {
            debugPrint(
                '[LUNA] Key $keyLabel is unauthorized (401). Cycling to next key...');
            break;
          } else {
            debugPrint(
                '[LUNA] Groq error $model (${response.statusCode}): ${response.body}');
          }
        } catch (e) {
          debugPrint('[LUNA] Groq request failed for $model with $keyLabel: $e');
        }
      }
    }

    debugPrint('[LUNA] All $totalKeys Groq API keys were exhausted.');
    return 'Luna is unavailable...';
  }
}
