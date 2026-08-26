import 'dart:math';
import 'package:flutter/material.dart';

class IcebreakerCategory {
  const IcebreakerCategory({
    required this.id,
    required this.title,
    required this.emoji,
    required this.color,
    required this.starters,
  });

  final String id;
  final String title;
  final String emoji;
  final Color color;
  final List<String> starters;
}

class IcebreakerData {
  static const List<IcebreakerCategory> categories = [
    IcebreakerCategory(
      id: 'coding',
      title: 'Coding & Dev',
      emoji: '💻',
      color: Color(0xFF3B82F6),
      starters: [
        'Hey! What tech stack or framework are you building with lately?',
        'Working on any cool side projects or hackathons this semester?',
        'Are you grinding LeetCode / DSA or building real-world apps?',
        'Tabs or spaces? And what is your go-to IDE for serious coding?',
        'Hey, would love to collaborate or review each other’s GitHub projects!',
        'Any favorite open-source tools or libraries you discovered recently?',
      ],
    ),
    IcebreakerCategory(
      id: 'ai',
      title: 'AI & Agents',
      emoji: '🤖',
      color: Color(0xFF8B5CF6),
      starters: [
        'Have you experimented with building any AI agents or LLM apps recently?',
        'What is the #1 AI tool you use daily that saves you the most time?',
        'Do you think AI will replace coding or just turn us all into 10x builders?',
        'Any cool machine learning models or papers you have explored lately?',
        'Prompt engineering or fine-tuning: what is your approach?',
      ],
    ),
    IcebreakerCategory(
      id: 'study',
      title: 'Study & Grind',
      emoji: '📚',
      color: Color(0xFF10B981),
      starters: [
        'Hey! Want to team up for study sessions or share notes this semester?',
        'How is the coursework going? What is the hardest subject right now?',
        'Are you a late-night crammer or a consistent daily studier?',
        'Looking for an accountability study buddy for the upcoming exams!',
        'Best study hack that actually works for you when deadlines approach?',
      ],
    ),
    IcebreakerCategory(
      id: 'gaming',
      title: 'Gaming & Esports',
      emoji: '🎮',
      color: Color(0xFFEC4899),
      starters: [
        'What games are you currently playing? Up for a match sometime?',
        'Valorant, CS2, BGMI, Apex, or story-driven single-player games?',
        'PC master race, console, or mobile gaming?',
        'Need a squadmate for late night gaming sessions on campus!',
        'What is your all-time favorite game soundtrack or storyline?',
      ],
    ),
    IcebreakerCategory(
      id: 'chill',
      title: 'Chill & Campus',
      emoji: '☕',
      color: Color(0xFFF59E0B),
      starters: [
        'Down for a quick canteen coffee or chai break between lectures?',
        'What is your go-to spot on campus when you need to recharge?',
        'How are you surviving this week’s crazy schedule?',
        'Best spot near campus for budget-friendly food in your opinion?',
        'Free hour right now — what is everyone up to?',
      ],
    ),
    IcebreakerCategory(
      id: 'design',
      title: 'UI/UX & Design',
      emoji: '🎨',
      color: Color(0xFF06B6D4),
      starters: [
        'Figma fanatic or frontend tinkerer? What are you designing lately?',
        'What is an app whose UI/UX you genuinely admire and why?',
        'Would love your feedback on a design mockup I am working on!',
        'Dark mode minimalist or colorful vibrant design aesthetic?',
        'Favorite design system or font pairing you swear by?',
      ],
    ),
    IcebreakerCategory(
      id: 'music',
      title: 'Music & Vibes',
      emoji: '🎵',
      color: Color(0xFFA855F7),
      starters: [
        'What song is on heavy rotation in your headphones right now?',
        'Lofi beats, high-energy EDM, hip-hop, or indie for focus mode?',
        'Drop your favorite Spotify or Apple Music playlist link!',
        'Any concert, artist, or music festival you are hyped about this year?',
        'What album can you listen to with zero skips?',
      ],
    ),
    IcebreakerCategory(
      id: 'startups',
      title: 'Startups & Ideas',
      emoji: '🚀',
      color: Color(0xFFEF4444),
      starters: [
        'Got any startup ideas you have been wanting to brainstorm or ship?',
        'Are you into indie hacking/bootstrapping or building venture scale apps?',
        'Let’s bounce some product and tech ideas around if you are free!',
        'What is an unsolved problem in college life that desperately needs an app?',
        'Y Combinator style rapid MVP or highly polished launch?',
      ],
    ),
    IcebreakerCategory(
      id: 'entertainment',
      title: 'Anime & Movies',
      emoji: '🍿',
      color: Color(0xFFF97316),
      starters: [
        'Watched any good movies, anime, or series lately?',
        'What is your all-time #1 anime or TV show recommendation?',
        'Need a new show to binge-watch during study breaks — what should I watch?',
        'Sci-fi thriller, psychological mystery, or comedy sitcoms?',
        'Movie night / anime marathon over the weekend?',
      ],
    ),
    IcebreakerCategory(
      id: 'fitness',
      title: 'Fitness & Sports',
      emoji: '🏃‍♂️',
      color: Color(0xFF14B8A6),
      starters: [
        'Do you hit the campus gym or play any sports after class?',
        'Looking for a badminton, gym, or football partner on campus!',
        'Early morning workout or late-night sweat session?',
        'What is your favorite way to stay active during heavy exam weeks?',
        'Protein shakes, pre-workout, or just pure willpower?',
      ],
    ),
  ];

  /// Get all icebreaker sentences as a flat list
  static List<String> get allStarters {
    final List<String> list = [];
    for (final cat in categories) {
      list.addAll(cat.starters);
    }
    return list;
  }

  /// Get random icebreaker sentence optionally filtered by category
  static String getRandomStarter({String? categoryId}) {
    final rand = Random();
    if (categoryId != null && categoryId.isNotEmpty) {
      final cat = categories.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => categories.first,
      );
      return cat.starters[rand.nextInt(cat.starters.length)];
    }
    final all = allStarters;
    return all[rand.nextInt(all.length)];
  }

  /// Get category by ID
  static IcebreakerCategory? getCategoryById(String id) {
    try {
      return categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}
