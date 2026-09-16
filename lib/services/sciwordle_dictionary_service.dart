// lib/services/sciwordle_dictionary_service.dart
//
// Service providing English word validation for SciWordle.
// Backed by a local comprehensive lexicon (88k+ valid English words)
// and an optional online fallback for obscure or newly emerging words.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class SciwordleDictionaryService {
  SciwordleDictionaryService._internal();
  static final SciwordleDictionaryService instance = SciwordleDictionaryService._internal();

  factory SciwordleDictionaryService() => instance;

  final Set<String> _words = <String>{};
  bool _isInitialized = false;
  Future<void>? _initFuture;

  bool get isInitialized => _isInitialized;
  int get wordCount => _words.length;

  /// Loads the English word list from the bundled asset.
  Future<void> init([String assetPath = 'assets/words/words_en.txt']) {
    if (_isInitialized) return Future.value();
    return _initFuture ??= _loadAsset(assetPath);
  }

  Future<void> _loadAsset(String assetPath) async {
    try {
      final rawData = await rootBundle.loadString(assetPath);
      final lines = const LineSplitter().convert(rawData);
      for (final line in lines) {
        final w = line.trim().toLowerCase();
        if (w.isNotEmpty) {
          _words.add(w);
        }
      }
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('[SciwordleDictionary] Loaded ${_words.length} English words.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SciwordleDictionary] Failed to load words asset: $e');
      }
      // Provide a baseline fallback set for core safety
      _words.addAll(_coreFallbackWords);
      _isInitialized = true;
    }
  }

  /// Manually populate or test with a given set of words.
  void loadWordsDirectly(Iterable<String> words) {
    for (final w in words) {
      final trimmed = w.trim().toLowerCase();
      if (trimmed.isNotEmpty) {
        _words.add(trimmed);
      }
    }
    _isInitialized = true;
  }

  /// Checks if [guess] is a valid English word for the puzzle.
  /// Always returns true if [guess] equals [targetAnswer].
  Future<bool> isValidWord(
    String guess, {
    required String targetAnswer,
    bool allowOnlineFallback = true,
  }) async {
    final cleanGuess = guess.trim().toLowerCase();
    final cleanAnswer = targetAnswer.trim().toLowerCase();

    // The puzzle answer is always accepted
    if (cleanGuess == cleanAnswer) {
      return true;
    }

    // Must be alphabetic
    if (!RegExp(r'^[a-z]+$').hasMatch(cleanGuess)) {
      return false;
    }

    if (!_isInitialized) {
      await init();
    }

    // Check fast local dictionary
    if (_words.contains(cleanGuess)) {
      return true;
    }

    // Optional online fallback for rare/obscure words
    if (allowOnlineFallback && cleanGuess.length >= 4) {
      final isOnlineValid = await _checkOnlineDictionary(cleanGuess);
      if (isOnlineValid) {
        _words.add(cleanGuess);
        return true;
      }
    }

    return false;
  }

  /// Synchronous local-only check (useful when already initialized).
  bool isValidWordLocal(String guess, {required String targetAnswer}) {
    final cleanGuess = guess.trim().toLowerCase();
    final cleanAnswer = targetAnswer.trim().toLowerCase();

    if (cleanGuess == cleanAnswer) return true;
    if (!RegExp(r'^[a-z]+$').hasMatch(cleanGuess)) return false;

    return _words.contains(cleanGuess);
  }

  /// Queries the free dictionary API as a fallback for words not in the local lexicon.
  Future<bool> _checkOnlineDictionary(String word) async {
    try {
      final url = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
      final response = await http.get(url).timeout(const Duration(milliseconds: 1800));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Core fallback words in case the asset cannot be read.
  static const List<String> _coreFallbackWords = [
    'atom', 'cell', 'gene', 'mass', 'moon', 'star', 'acid', 'base', 'heat',
    'wave', 'body', 'core', 'iron', 'gold', 'lead', 'zinc', 'coal', 'rock',
    'soil', 'wind', 'rain', 'tide', 'volt', 'watt', 'flux', 'lens', 'node',
    'wire', 'salt', 'beam', 'data', 'echo', 'fizz', 'glow', 'halo', 'iris',
    'lava', 'neon', 'orbit', 'organ', 'prism', 'pulse', 'radar', 'range',
    'react', 'scale', 'solar', 'sonic', 'sound', 'space', 'speed', 'spore',
    'steam', 'storm', 'sun', 'vapor', 'virus', 'water', 'audio', 'crane',
    'stare', 'slate', 'roate', 'adieu', 'force', 'light', 'earth', 'plant',
    'metal', 'sound', 'blood', 'brain', 'heart', 'nerve', 'fluid', 'solid',
    'gas', 'plasma', 'laser', 'focus', 'decay', 'dense', 'fault', 'fiber',
    'fossil', 'galaxy', 'magnet', 'matter', 'motion', 'neuron', 'optics',
    'oxygen', 'photon', 'planet', 'proton', 'quantum', 'radius', 'scalar',
    'sensor', 'shadow', 'signal', 'silicon', 'sodium', 'spectrum', 'static',
    'sulfur', 'system', 'theory', 'thermo', 'tissue', 'vacuum', 'vector',
    'velocity', 'volume', 'weight', 'carbon', 'copper', 'silver', 'uranium',
    'radium', 'helium', 'argon', 'krypton', 'xenon', 'radon', 'boron',
    'energy', 'atomic', 'neutron', 'electron', 'gravity', 'nucleus', 'eclipse',
    'erosion', 'enzyme', 'newton', 'pascal', 'joule', 'kelvin', 'hertz',
  ];
}
