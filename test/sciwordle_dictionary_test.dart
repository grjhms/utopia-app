import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:utopia_app/services/sciwordle_dictionary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SciwordleDictionaryService service;

  setUp(() {
    service = SciwordleDictionaryService.instance;
    // Load words directly from the file system for unit test speed and reliability
    final file = File('assets/words/words_en.txt');
    if (file.existsSync()) {
      final lines = file.readAsLinesSync();
      service.loadWordsDirectly(lines);
    }
  });

  group('SciwordleDictionaryService Tests', () {
    test('successfully loads word lexicon with expected volume', () {
      expect(service.isInitialized, isTrue);
      expect(service.wordCount, greaterThan(80000));
    });

    test('accepts target answer unconditionally', () async {
      // Even if target answer is made-up or esoteric, it should always be accepted
      const target = 'xyzzyquantum';
      final valid = await service.isValidWord(
        'xyzzyquantum',
        targetAnswer: target,
        allowOnlineFallback: false,
      );
      expect(valid, isTrue);
    });

    test('accepts common valid English words across various lengths (4 to 8 letters)', () async {
      const validWords = [
        'atom', // 4
        'heat', // 4
        'wave', // 4
        'crane', // 5
        'light', // 5
        'earth', // 5
        'slate', // 5
        'audio', // 5
        'planet', // 6
        'magnet', // 6
        'oxygen', // 6
        'matter', // 6
        'photon', // 6
        'gravity', // 7
        'nucleus', // 7
        'eclipse', // 7
        'erosion', // 7
        'electron', // 8
        'friction', // 8
        'velocity', // 8
      ];

      for (final word in validWords) {
        final isValid = await service.isValidWord(
          word,
          targetAnswer: 'differentword',
          allowOnlineFallback: false,
        );
        expect(isValid, isTrue, reason: 'Expected "$word" to be accepted as valid English');
      }
    });

    test('rejects arbitrary gibberish and invalid letter combinations', () async {
      const invalidWords = [
        'zzzzz',
        'asdfg',
        'qwert',
        'aaaaa',
        'bbbbb',
        'zxqwp',
        'xyzzz',
        'qwertyui',
        'randomnonword123',
      ];

      for (final word in invalidWords) {
        final isValid = await service.isValidWord(
          word,
          targetAnswer: 'gravity',
          allowOnlineFallback: false,
        );
        expect(isValid, isFalse, reason: 'Expected "$word" to be rejected');
      }
    });

    test('handles case-insensitivity and whitespace trimming', () async {
      final validLower = await service.isValidWord('crane', targetAnswer: 'light', allowOnlineFallback: false);
      final validUpper = await service.isValidWord('CRANE', targetAnswer: 'light', allowOnlineFallback: false);
      final validMixed = await service.isValidWord('  CrAnE  ', targetAnswer: 'light', allowOnlineFallback: false);

      expect(validLower, isTrue);
      expect(validUpper, isTrue);
      expect(validMixed, isTrue);
    });

    test('rejects words with numbers or special symbols', () async {
      expect(await service.isValidWord('c0de', targetAnswer: 'test', allowOnlineFallback: false), isFalse);
      expect(await service.isValidWord('pla-n', targetAnswer: 'test', allowOnlineFallback: false), isFalse);
      expect(await service.isValidWord('word!', targetAnswer: 'test', allowOnlineFallback: false), isFalse);
    });

    test('synchronous local validation works consistently', () {
      expect(service.isValidWordLocal('planet', targetAnswer: 'magnet'), isTrue);
      expect(service.isValidWordLocal('zzzzz', targetAnswer: 'magnet'), isFalse);
      expect(service.isValidWordLocal('customanswer', targetAnswer: 'customanswer'), isTrue);
    });
  });
}
