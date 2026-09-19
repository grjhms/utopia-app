class ReviewContentFilterResult {
  final bool containsProfanity;
  final bool targetsNamedIndividual;
  final String? flaggedReason;
  final List<String> detectedWords;

  ReviewContentFilterResult({
    required this.containsProfanity,
    required this.targetsNamedIndividual,
    this.flaggedReason,
    this.detectedWords = const [],
  });
}

class ReviewContentFilter {
  // Built-in wordlist for profanity and vulgarity detection (English & common transliterated slurs)
  static final Set<String> _profanityList = {
    'abuse', 'asshole', 'bastard', 'bitch', 'bullshit', 'crap', 'cunt', 'dick',
    'dumbass', 'fuck', 'fucking', 'fucker', 'idiot', 'motherfucker', 'nigger',
    'pussy', 'scamster', 'shit', 'shitty', 'slut', 'whore', 'chutiya', 'gaand',
    'gandu', 'madarchod', 'bhenchod', 'bhosdike', 'harami', 'saala', 'kamina',
  };

  // RegEx pattern matching target titles or individual name references
  // e.g. "Prof. X", "Dr. Y", "Mr. Z", "Mrs. A", "Sharma Sir", "Rao Madam", "HOD Kumar"
  static final RegExp _titlePattern = RegExp(
    r'\b(prof|professor|dr|doctor|sir|maamp?|madam|hod|principal|dean|director|chairman|mr|mrs|ms)\b',
    caseSensitive: false,
  );

  static final RegExp _nameWithTitlePattern = RegExp(
    r'\b(prof|dr|mr|mrs|ms|hod|dean|principal)\.?\s+[A-Z][a-z]+\b',
    caseSensitive: true,
  );

  static final RegExp _nameWithPostTitlePattern = RegExp(
    r'\b[A-Z][a-z]+\s+(sir|maamp?|madam|hod)\b',
    caseSensitive: false,
  );

  /// Analyzes text for profanity or specific named faculty references.
  static ReviewContentFilterResult analyzeText(String text) {
    if (text.trim().isEmpty) {
      return ReviewContentFilterResult(
        containsProfanity: false,
        targetsNamedIndividual: false,
      );
    }

    final cleanText = text.toLowerCase();
    final words = cleanText.split(RegExp(r'[\s\W]+'));

    final List<String> flaggedProfanity = [];
    for (final word in words) {
      if (_profanityList.contains(word)) {
        flaggedProfanity.add(word);
      }
    }

    bool targetsNamedIndividual = false;
    String? reason;

    if (_nameWithTitlePattern.hasMatch(text) || _nameWithPostTitlePattern.hasMatch(text)) {
      targetsNamedIndividual = true;
      reason = 'Text appears to reference a specific named faculty/staff member.';
    } else {
      // Secondary check: look for honorifics paired with review critical verbs/nouns
      if (_titlePattern.hasMatch(text)) {
        // Check if there is also proper capitalization pattern indicative of a name
        final capitalizedWords = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && w[0] == w[0].toUpperCase() && RegExp(r'^[A-Z][a-z]+$').hasMatch(w)).toList();
        if (capitalizedWords.length >= 2) {
          targetsNamedIndividual = true;
          reason = 'Comment mentions staff titles alongside potential individual names.';
        }
      }
    }

    return ReviewContentFilterResult(
      containsProfanity: flaggedProfanity.isNotEmpty,
      targetsNamedIndividual: targetsNamedIndividual,
      flaggedReason: flaggedProfanity.isNotEmpty
          ? 'Comment contains prohibited language: ${flaggedProfanity.join(', ')}'
          : reason,
      detectedWords: flaggedProfanity,
    );
  }

  /// Calculates word count of a comment.
  static int countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  /// Checks whether a comment meets the minimum length prompt requirement.
  /// If any sub-category rating is <= 3, requires at least [minWords] (default 20).
  static String? validateCommentLength(Map<String, int> subRatings, String comment, {int minWords = 20}) {
    final trimmed = comment.trim();
    if (trimmed.isEmpty) return null;
    final lowRatings = subRatings.entries.where((e) => e.value > 0 && e.value <= 2).toList();
    if (lowRatings.isNotEmpty) {
      final wordCount = countWords(comment);
      if (wordCount < minWords) {
        final categoryNames = lowRatings.map((e) => _formatCategoryName(e.key)).join(', ');
        return 'You rated $categoryNames ${lowRatings.first.value}/5★. Please explain why ($wordCount/$minWords words).';
      }
    }
    return null;
  }

  static String _formatCategoryName(String key) {
    switch (key.toLowerCase()) {
      case 'academics':
        return 'Academics';
      case 'faculty':
        return 'Faculty';
      case 'infrastructure':
        return 'Infrastructure';
      case 'placements':
        return 'Placements';
      case 'campuslife':
        return 'Campus Life';
      case 'hostel':
        return 'Hostel & Food';
      default:
        return key;
    }
  }
}
