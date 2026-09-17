// lib/screens/sciwordle_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../main.dart';
import '../models/sciwordle_model.dart';
import '../services/sciwordle_service.dart';
import '../services/sciwordle_dictionary_service.dart';
import '../services/notification_service.dart';
import '../widgets/utopia_loader.dart';
import '../widgets/utopia_snackbar.dart';
import 'sciwordle_leaderboard.dart';
import 'sciwordle_stats_screen.dart';
import 'how_to_play_screen.dart';

class SciwordleScreen extends StatefulWidget {
  const SciwordleScreen({super.key});

  @override
  State<SciwordleScreen> createState() => _SciwordleScreenState();
}

class _SciwordleScreenState extends State<SciwordleScreen>
    with TickerProviderStateMixin {
  static const int _maxAttempts = 6;

  final SciwordleService _service = SciwordleService();
  final SciwordleDictionaryService _dictionary = SciwordleDictionaryService();
  late ConfettiController _confettiController;
  late AnimationController _shakeController;

  SciwordleQuestion? _question;
  SciwordlePlayerScore? _playerScore;
  final List<SciwordleGuessResult> _guesses = [];
  String _currentGuess = '';
  String? _selectedDateKey;
  bool _gameOver = false;
  bool _won = false;
  int? _pointsEarned;
  bool _alreadyPlayedToday = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _loadGame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstVisitNotification();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkFirstVisitNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final prompted = prefs.getBool('sciwordle_notif_prompted') ?? false;
    if (!prompted && mounted) {
      _showFirstVisitNotificationDialog();
    }
  }

  Future<void> _showFirstVisitNotificationDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.notifications_active_rounded, color: U.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Daily Puzzle Alerts',
                style: GoogleFonts.robotoFlex(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: U.text,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SciWordle releases 3 science puzzles daily:',
              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            _buildDialogSlotBullet('🌅 Morning Edition', 'Starts 1:00 AM (Reminder 8:00 AM)'),
            const SizedBox(height: 6),
            _buildDialogSlotBullet('☀️ Afternoon Edition', 'Starts 11:00 AM'),
            const SizedBox(height: 6),
            _buildDialogSlotBullet('🌙 Evening Edition', 'Starts 4:00 PM'),
            const SizedBox(height: 14),
            Text(
              'Would you like reminders when each edition opens? You can customize these anytime in Settings.',
              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setBool('sciwordle_notif_prompted', true);
              await prefs.setBool('sciwordle_notif_enabled', false);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Not Now', style: GoogleFonts.robotoFlex(color: U.sub)),
          ),
          FilledButton(
            onPressed: () async {
              await prefs.setBool('sciwordle_notif_prompted', true);
              await NotificationService.requestNotificationPermissionOnly();
              await NotificationService.scheduleSciwordleDailyNotifications(
                morning: true,
                afternoon: true,
                evening: true,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                showUtopiaSnackBar(
                  context,
                  message: 'Daily SciWordle alerts enabled! 🔔',
                  tone: UtopiaSnackBarTone.success,
                );
              }
            },
            child: const Text('Enable Reminders'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogSlotBullet(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 16, color: U.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.robotoFlex(
                  color: U.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadGame([String? targetKey]) async {
    final activeKey = targetKey ?? _service.todayKey;
    _selectedDateKey = activeKey;
    final isCurrentSlot = activeKey == _service.todayKey;
    setState(() {
      _loading = true;
      _error = null;
      _currentGuess = '';
      _pointsEarned = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchTodaysQuestion(activeKey),
        _service.fetchPlayerScore(),
        _service.hasPlayedToday(activeKey),
        isCurrentSlot ? _service.fetchGuessProgress() : Future.value(null),
        _dictionary.init(),
      ]);

      final question = results[0] as SciwordleQuestion?;
      final playerScore = results[1] as SciwordlePlayerScore;
      final alreadyPlayed = results[2] as bool;
      final savedProgress = results[3] as SciwordleProgressData?;

      _guesses.clear();
      bool gameOver = alreadyPlayed;
      bool won = false;

      // 1. If already played, restore completed guesses so user sees actual letters!
      if (alreadyPlayed && question != null) {
        final completedHistory = await _service.fetchCompletedGameHistory(activeKey);
        if (completedHistory != null && completedHistory.guesses.isNotEmpty) {
          final restored = <SciwordleGuessResult>[];
          for (final word in completedHistory.guesses) {
            restored.add(
              _service.checkGuess(guess: word, answer: question.answer),
            );
          }
          final lastCorrect = restored.isNotEmpty &&
              restored.last.letters.every(
                (l) => l.status == LetterStatus.correct,
              );
          _guesses.addAll(restored);
          won = lastCorrect;
        }
      }

      // 2. Restore in-progress guesses if the user backed out mid-game
      if (!alreadyPlayed &&
          question != null &&
          savedProgress != null &&
          savedProgress.answer == question.answer) {
        final restoredGuesses = <SciwordleGuessResult>[];
        for (final word in savedProgress.guesses) {
          restoredGuesses.add(
            _service.checkGuess(guess: word, answer: question.answer),
          );
        }
        final lastCorrect = restoredGuesses.isNotEmpty &&
            restoredGuesses.last.letters.every(
              (l) => l.status == LetterStatus.correct,
            );
        final usedAll = restoredGuesses.length >= _maxAttempts;

        _guesses.addAll(restoredGuesses);
        if (lastCorrect || usedAll) {
          gameOver = true;
          won = lastCorrect;
        }
      }

      setState(() {
        _question = question;
        _playerScore = playerScore;
        _alreadyPlayedToday = alreadyPlayed;
        _gameOver = gameOver;
        _won = won;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _addLetter(String letter) {
    if (_question == null || _gameOver || _submitting) return;
    if (_currentGuess.length < _question!.answer.length) {
      HapticFeedback.lightImpact();
      setState(() {
        _currentGuess += letter.toLowerCase();
        _inputError = null;
      });
    }
  }

  void _removeLetter() {
    if (_currentGuess.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _currentGuess = _currentGuess.substring(0, _currentGuess.length - 1);
        _inputError = null;
      });
    }
  }

  Future<void> _submitGuess() async {
    if (_question == null || _gameOver || _submitting) return;

    if (_currentGuess.isEmpty) {
      setState(() => _inputError = 'Enter a guess');
      HapticFeedback.heavyImpact();
      _shakeCurrentRow();
      return;
    }
    if (_currentGuess.length != _question!.answer.length) {
      setState(
        () => _inputError = '${_question!.answer.length} letters needed',
      );
      HapticFeedback.heavyImpact();
      _shakeCurrentRow();
      return;
    }

    setState(() => _submitting = true);

    // Validate that the guess is a valid English word in all 6 attempts
    final isEnglishWord = await _dictionary.isValidWord(
      _currentGuess,
      targetAnswer: _question!.answer,
    );

    if (!isEnglishWord) {
      setState(() {
        _inputError = 'Not in word list';
        _submitting = false;
      });
      HapticFeedback.heavyImpact();
      _shakeCurrentRow();
      return;
    }

    final result = _service.checkGuess(
      guess: _currentGuess,
      answer: _question!.answer,
    );
    final isCorrect = result.letters.every(
      (l) => l.status == LetterStatus.correct,
    );
    final newGuesses = [..._guesses, result];
    final attemptNumber = newGuesses.length;
    final isLastAttempt = attemptNumber == _maxAttempts;
    final gameOver = isCorrect || isLastAttempt;

    int? pointsEarned;
    SciwordlePlayerScore? refreshedScore;

    if (gameOver) {
      final guessWords = newGuesses
          .map((g) => g.letters.map((l) => l.letter).join())
          .toList();
      try {
        pointsEarned = await _service.saveGameResult(
          attemptNumber: isCorrect ? attemptNumber : null,
          guesses: guessWords,
          answer: _question!.answer,
          question: _question?.question,
          category: _question?.category,
        );
        refreshedScore = await _service.fetchPlayerScore();
        await _service.clearGuessProgress();
      } catch (_) {
        pointsEarned = 0;
      }
    } else {
      final guessWords = newGuesses
          .map((g) => g.letters.map((l) => l.letter).join())
          .toList();
      await _service.saveGuessProgress(
        guesses: guessWords,
        answer: _question!.answer,
      );
    }

    setState(() {
      _guesses.clear();
      _guesses.addAll(newGuesses);
      _currentGuess = '';
      _gameOver = gameOver;
      _won = isCorrect;
      _pointsEarned = pointsEarned;
      if (refreshedScore != null) {
        _playerScore = refreshedScore;
      }
      _alreadyPlayedToday = gameOver;
      _submitting = false;
    });

    if (isCorrect) {
      HapticFeedback.mediumImpact();
      _confettiController.play();
    } else if (isLastAttempt) {
      HapticFeedback.heavyImpact();
    }
  }

  void _shakeCurrentRow() {
    _shakeController.forward(from: 0);
  }

  Map<String, LetterStatus> get _letterStatuses {
    final map = <String, LetterStatus>{};
    for (final guess in _guesses) {
      for (final letter in guess.letters) {
        final existing = map[letter.letter];
        if (existing == LetterStatus.correct) continue;
        if (existing == LetterStatus.present &&
            letter.status == LetterStatus.absent) {
          continue;
        }
        map[letter.letter] = letter.status;
      }
    }
    return map;
  }

  Future<void> _openSettingsModal() async {
    final prefs = await SharedPreferences.getInstance();
    bool masterEnabled = prefs.getBool('sciwordle_notif_enabled') ?? false;
    bool morning = prefs.getBool('sciwordle_notif_morning') ?? true;
    bool afternoon = prefs.getBool('sciwordle_notif_afternoon') ?? true;
    bool evening = prefs.getBool('sciwordle_notif_evening') ?? true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    bool showBadge = true;
    if (uid != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        showBadge = userDoc.data()?['showSciwordleBadge'] != false;
      } catch (_) {}
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: U.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: U.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: U.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.settings_rounded, color: U.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'SciWordle Settings',
                      style: GoogleFonts.robotoFlex(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: U.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Section 1: Notifications
                Text(
                  'NOTIFICATIONS',
                  style: GoogleFonts.robotoFlex(
                    color: U.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: U.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: U.outlineVariant.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text(
                          'Daily Puzzle Alerts',
                          style: GoogleFonts.robotoFlex(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: U.text,
                          ),
                        ),
                        subtitle: Text(
                          'Get notified when daily editions unlock',
                          style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
                        ),
                        value: masterEnabled,
                        activeTrackColor: U.primary,
                        onChanged: (val) async {
                          setModalState(() => masterEnabled = val);
                          await prefs.setBool('sciwordle_notif_enabled', val);
                          if (val) {
                            await NotificationService.requestNotificationPermissionOnly();
                            await NotificationService.scheduleSciwordleDailyNotifications(
                              morning: morning,
                              afternoon: afternoon,
                              evening: evening,
                            );
                          } else {
                            await NotificationService.cancelSciwordleNotifications();
                          }
                        },
                      ),
                      if (masterEnabled) ...[
                        Divider(height: 1, color: U.outlineVariant.withValues(alpha: 0.35)),
                        CheckboxListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            '🌅 Morning Edition',
                            style: GoogleFonts.robotoFlex(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: U.text,
                            ),
                          ),
                          subtitle: Text(
                            'Reminder at 8:00 AM IST',
                            style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11.5),
                          ),
                          value: morning,
                          activeColor: U.primary,
                          onChanged: (val) async {
                            final newVal = val ?? true;
                            setModalState(() => morning = newVal);
                            await prefs.setBool('sciwordle_notif_morning', newVal);
                            await NotificationService.scheduleSciwordleDailyNotifications(
                              morning: newVal,
                              afternoon: afternoon,
                              evening: evening,
                            );
                          },
                        ),
                        CheckboxListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            '☀️ Afternoon Edition',
                            style: GoogleFonts.robotoFlex(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: U.text,
                            ),
                          ),
                          subtitle: Text(
                            'Reminder at 11:00 AM IST',
                            style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11.5),
                          ),
                          value: afternoon,
                          activeColor: U.primary,
                          onChanged: (val) async {
                            final newVal = val ?? true;
                            setModalState(() => afternoon = newVal);
                            await prefs.setBool('sciwordle_notif_afternoon', newVal);
                            await NotificationService.scheduleSciwordleDailyNotifications(
                              morning: morning,
                              afternoon: newVal,
                              evening: evening,
                            );
                          },
                        ),
                        CheckboxListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            '🌙 Evening Edition',
                            style: GoogleFonts.robotoFlex(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: U.text,
                            ),
                          ),
                          subtitle: Text(
                            'Reminder at 4:00 PM IST',
                            style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 11.5),
                          ),
                          value: evening,
                          activeColor: U.primary,
                          onChanged: (val) async {
                            final newVal = val ?? true;
                            setModalState(() => evening = newVal);
                            await prefs.setBool('sciwordle_notif_evening', newVal);
                            await NotificationService.scheduleSciwordleDailyNotifications(
                              morning: morning,
                              afternoon: afternoon,
                              evening: newVal,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Section 2: Profile Badge
                Text(
                  'PROFILE BADGE',
                  style: GoogleFonts.robotoFlex(
                    color: U.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: U.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: U.outlineVariant.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(
                      'Show Badge on Profile Icon',
                      style: GoogleFonts.robotoFlex(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: U.text,
                      ),
                    ),
                    subtitle: Text(
                      'Display your elite title badge (Alpha, Prime, Fire, etc.) on your profile avatar.',
                      style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 12),
                    ),
                    value: showBadge,
                    activeTrackColor: U.primary,
                    onChanged: (val) async {
                      setModalState(() => showBadge = val);
                      await prefs.setBool('show_sciwordle_badge', val);
                      if (uid != null) {
                        try {
                          await FirebaseFirestore.instance.collection('users').doc(uid).set({
                            'showSciwordleBadge': val,
                          }, SetOptions(merge: true));
                        } catch (_) {}
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTodayEditionsBar(bool isDark) {
    final today = _service.getTodayDateIST();
    final currentKey = _service.todayKey;
    final currentSlot = SciwordleService.slotForDateKey(currentKey);

    final editions = [
      {'key': '$today-m', 'slot': 'm', 'icon': '🌅', 'label': 'Morning'},
      {'key': '$today-a', 'slot': 'a', 'icon': '☀️', 'label': 'Afternoon'},
      {'key': '$today-e', 'slot': 'e', 'icon': '🌙', 'label': 'Evening'},
    ];

    final slotOrder = {'m': 1, 'a': 2, 'e': 3};
    final currentSlotIndex = slotOrder[currentSlot] ?? 1;
    final selectedKey = _selectedDateKey ?? currentKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: U.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        children: editions.map((ed) {
          final edKey = ed['key']!;
          final edSlot = ed['slot']!;
          final edIndex = slotOrder[edSlot] ?? 1;
          final isUnlocked = edIndex <= currentSlotIndex;
          final isSelected = edKey == selectedKey;
          final isLive = edKey == currentKey;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isUnlocked) {
                  showUtopiaSnackBar(
                    context,
                    message: '${ed['label']} unlocks at ${edSlot == 'a' ? "11:00 AM" : "4:00 PM"} IST',
                    tone: UtopiaSnackBarTone.info,
                  );
                  return;
                }
                if (edKey != selectedKey) {
                  _loadGame(edKey);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? U.primary.withValues(alpha: isDark ? 0.28 : 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: U.primary.withValues(alpha: 0.6), width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(ed['icon']!, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Text(
                      ed['label']!,
                      style: GoogleFonts.robotoFlex(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? U.primary
                            : isUnlocked
                                ? U.text
                                : U.sub.withValues(alpha: 0.5),
                      ),
                    ),
                    if (!isUnlocked) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.lock_outline_rounded, size: 11, color: U.sub.withValues(alpha: 0.5)),
                    ] else if (isLive && !isSelected) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeNotifier.value.isDark;

    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.psychology_rounded, color: U.primary, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'SciWordle',
                style: GoogleFonts.robotoFlex(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: U.text,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          // How to play
          IconButton(
            icon: Icon(Icons.help_outline_rounded, color: U.sub, size: 22),
            tooltip: 'How to play',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HowToPlayScreen()),
            ),
          ),
          // Statistics
          IconButton(
            icon: Icon(Icons.bar_chart_rounded, color: U.sub, size: 22),
            tooltip: 'Statistics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SciwordleStatsScreen()),
            ).then((_) => _loadGame()),
          ),
          // Leaderboard
          IconButton(
            icon: Icon(Icons.leaderboard_rounded, color: U.primary, size: 22),
            tooltip: 'Leaderboard',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SciwordleLeaderboardScreen(),
              ),
            ),
          ),
          // Settings
          IconButton(
            icon: Icon(Icons.settings_outlined, color: U.sub, size: 22),
            tooltip: 'Settings',
            onPressed: _openSettingsModal,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: UtopiaLoader(scale: 0.8))
              : _error != null
                  ? _buildError()
                  : _question == null
                      ? _buildNoQuestion()
                      : _buildGameLayout(isDark),

          // Confetti celebratory explosion
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              particleDrag: 0.05,
              emissionFrequency: 0.06,
              numberOfParticles: 40,
              gravity: 0.25,
              shouldLoop: false,
              colors: const [
                Color(0xFF10B981),
                Color(0xFFF59E0B),
                Color(0xFF38BDF8),
                Color(0xFFA855F7),
                Color(0xFFEC4899),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: U.red, size: 52),
            const SizedBox(height: 16),
            Text(
              'Couldn\'t Load Puzzle',
              style: GoogleFonts.robotoFlex(
                color: U.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Network error. Please verify your connection.',
              textAlign: TextAlign.center,
              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _loadGame,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoQuestion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: U.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.science_outlined, color: U.dim, size: 48),
            ),
            const SizedBox(height: 18),
            Text(
              'No Puzzle Scheduled Yet',
              style: GoogleFonts.robotoFlex(
                color: U.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Next science mystery will be available at the next scheduled slot.',
              textAlign: TextAlign.center,
              style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameLayout(bool isDark) {
    final question = _question!;
    final answerLength = question.answer.length;

    return Column(
      children: [
        // Top Streak & Score Quick Banner
        if (_playerScore != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: _buildStreakBar(isDark),
          ),

        // Scrollable Question & Grid Area
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Today's 3 Editions Bar
                _buildTodayEditionsBar(isDark),

                // Science Clue Card
                _buildQuestionCard(question, isDark),

                const SizedBox(height: 16),

                // Game Finished / Already Played Card
                if (_alreadyPlayedToday && _pointsEarned == null) ...[
                  _buildAlreadyPlayedCard(isDark),
                  const SizedBox(height: 16),
                ],

                // Fresh Victory / Game Result Card
                if (_gameOver && _pointsEarned != null) ...[
                  _buildResultCard(isDark),
                  const SizedBox(height: 16),
                ],

                // 6-Row Guess Matrix
                _buildGuessGrid(answerLength, isDark),

                if (_inputError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: U.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _inputError!,
                      style: GoogleFonts.robotoFlex(
                        color: U.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Custom Keyboard (only shown when game is ongoing)
        if (!_gameOver && !_alreadyPlayedToday)
          _buildKeyboard(isDark),
      ],
    );
  }

  Widget _buildStreakBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: U.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '${_playerScore!.streak} Day Streak',
                style: GoogleFonts.robotoFlex(
                  color: const Color(0xFFFB923C),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Container(
            height: 14,
            width: 1,
            color: U.outlineVariant.withValues(alpha: 0.4),
          ),
          Text(
            '${_playerScore!.totalScore} total pts',
            style: GoogleFonts.robotoFlex(
              color: U.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(SciwordleQuestion question, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: U.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: U.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.science_rounded, color: U.primary, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      question.category.toUpperCase(),
                      style: GoogleFonts.robotoFlex(
                        color: U.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: U.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${question.answer.length} LETTERS',
                  style: GoogleFonts.robotoFlex(
                    color: U.sub,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            question.question,
            textAlign: TextAlign.center,
            style: GoogleFonts.newsreader(
              color: U.text,
              fontSize: 17.5,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyPlayedCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: U.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: U.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'Puzzle Completed!',
            style: GoogleFonts.robotoFlex(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: U.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You\'ve submitted your answer for this slot. Come back for the next mystery!',
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoFlex(fontSize: 13, color: U.sub),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.leaderboard_rounded, size: 18),
              label: const Text('Weekly Leaderboard'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SciwordleLeaderboardScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(bool isDark) {
    final word = _question?.answer.toUpperCase() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _won
              ? [
                  const Color(0xFF10B981).withValues(alpha: isDark ? 0.3 : 0.18),
                  U.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                ]
              : [
                  U.red.withValues(alpha: isDark ? 0.25 : 0.15),
                  U.surfaceContainer,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _won ? const Color(0xFF10B981).withValues(alpha: 0.5) : U.red.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _won ? '🎉' : '💡',
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 8),
              Text(
                _won ? 'Splendid Deduction!' : 'Good Effort!',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: U.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'The answer was ',
                  style: GoogleFonts.robotoFlex(color: U.sub, fontSize: 14),
                ),
                TextSpan(
                  text: word,
                  style: GoogleFonts.robotoFlex(
                    color: _won ? const Color(0xFF10B981) : U.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: U.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      '+${_pointsEarned ?? 0}',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    Text(
                      'Points Earned',
                      style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub),
                    ),
                  ],
                ),
                Container(height: 30, width: 1, color: U.outlineVariant.withValues(alpha: 0.4)),
                Column(
                  children: [
                    Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 4),
                        Text(
                          '${_playerScore?.streak ?? 1}',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFFB923C),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Day Streak',
                      style: GoogleFonts.robotoFlex(fontSize: 11, color: U.sub),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.leaderboard_rounded, size: 18),
              label: const Text('Weekly Leaderboard'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SciwordleLeaderboardScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    ).animate().scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), curve: Curves.easeOutBack);
  }

  Widget _buildGuessGrid(int wordLength, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate tile size based on available width
        // Each tile has 4px horizontal margin on each side (8px total per tile)
        final availableWidth = constraints.maxWidth;
        final totalMargin = wordLength * 8.0; // 4px margin on each side
        final maxTileSize = (availableWidth - totalMargin) / wordLength;
        final tileSize = maxTileSize.clamp(32.0, 48.0);

        return AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final shakeOffset = sin(_shakeController.value * pi * 4) * 8;
            return Column(
              children: List.generate(_maxAttempts, (rowIndex) {
                final isCurrentRow = rowIndex == _guesses.length;
                final isSubmitted = rowIndex < _guesses.length;

                return Transform.translate(
                  offset: Offset(isCurrentRow ? shakeOffset : 0, 0),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(wordLength, (colIndex) {
                        if (isSubmitted) {
                          final letterResult = _guesses[rowIndex].letters[colIndex];
                          return _buildLetterTile(
                            letter: letterResult.letter.toUpperCase(),
                            status: letterResult.status,
                            isDark: isDark,
                            tileSize: tileSize,
                          );
                        } else if (isCurrentRow) {
                          final hasChar = colIndex < _currentGuess.length;
                          final char = hasChar ? _currentGuess[colIndex].toUpperCase() : '';
                          return _buildLetterTile(
                            letter: char,
                            isActive: hasChar,
                            isDark: isDark,
                            tileSize: tileSize,
                          );
                        } else {
                          return _buildLetterTile(
                            letter: '',
                            isDark: isDark,
                            tileSize: tileSize,
                          );
                        }
                      }),
                    ),
                  ),
                );
              }),
            );
          },
        );
      },
    );
  }

  Widget _buildLetterTile({
    required String letter,
    LetterStatus? status,
    bool isActive = false,
    required bool isDark,
    double tileSize = 48,
  }) {
    Color bgColor = U.surfaceContainerLowest;
    Color borderColor = U.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4);
    Color textColor = U.text;
    List<Color>? gradientColors;

    if (status != null) {
      switch (status) {
        case LetterStatus.correct:
          gradientColors = const [Color(0xFF10B981), Color(0xFF059669)];
          borderColor = const Color(0xFF10B981);
          textColor = Colors.white;
          break;
        case LetterStatus.present:
          gradientColors = const [Color(0xFFF59E0B), Color(0xFFD97706)];
          borderColor = const Color(0xFFF59E0B);
          textColor = Colors.white;
          break;
        case LetterStatus.absent:
          bgColor = isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8);
          borderColor = Colors.transparent;
          textColor = Colors.white;
          break;
      }
    } else if (isActive) {
      borderColor = U.primary;
      bgColor = U.surfaceContainer;
    }

    final fontSize = (tileSize * 0.46).clamp(16.0, 22.0);

    return Container(
      width: tileSize,
      height: tileSize,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: gradientColors == null ? bgColor : null,
        gradient: gradientColors != null
            ? LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(tileSize > 40 ? 12 : 8),
        border: Border.all(color: borderColor, width: isActive ? 1.8 : 1.2),
        boxShadow: status == LetterStatus.correct
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.robotoFlex(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildKeyboard(bool isDark) {
    const row1 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
    const row2 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
    const row3 = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

    final statuses = _letterStatuses;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 20),
      decoration: BoxDecoration(
        color: U.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: U.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildKeyboardRow(row1, statuses, isDark),
          const SizedBox(height: 6),
          _buildKeyboardRow(row2, statuses, isDark),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ENTER Button
              _buildSpecialKey(
                icon: Icons.check_circle_rounded,
                label: 'ENTER',
                flex: 3,
                isDark: isDark,
                onTap: _submitGuess,
                color: U.primary,
              ),
              const SizedBox(width: 4),
              // Letter keys
              ...row3.map((letter) {
                return Expanded(
                  flex: 2,
                  child: _buildKeycap(
                    letter: letter,
                    status: statuses[letter.toLowerCase()],
                    isDark: isDark,
                    onTap: () => _addLetter(letter),
                  ),
                );
              }),
              const SizedBox(width: 4),
              // BACKSPACE Button
              _buildSpecialKey(
                icon: Icons.backspace_rounded,
                label: '',
                flex: 3,
                isDark: isDark,
                onTap: _removeLetter,
                color: U.sub,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardRow(
    List<String> letters,
    Map<String, LetterStatus> statuses,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters.map((letter) {
        return Expanded(
          child: _buildKeycap(
            letter: letter,
            status: statuses[letter.toLowerCase()],
            isDark: isDark,
            onTap: () => _addLetter(letter),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeycap({
    required String letter,
    LetterStatus? status,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    Color bgColor = U.surfaceContainer;
    Color textColor = U.text;

    if (status != null) {
      switch (status) {
        case LetterStatus.correct:
          bgColor = const Color(0xFF10B981);
          textColor = Colors.white;
          break;
        case LetterStatus.present:
          bgColor = const Color(0xFFF59E0B);
          textColor = Colors.white;
          break;
        case LetterStatus.absent:
          bgColor = isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8);
          textColor = Colors.white.withValues(alpha: 0.85);
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: U.outlineVariant.withValues(alpha: isDark ? 0.2 : 0.3),
                width: 0.6,
              ),
            ),
            child: Text(
              letter,
              style: GoogleFonts.robotoFlex(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey({
    required IconData icon,
    required String label,
    required int flex,
    required bool isDark,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Expanded(
      flex: flex,
      child: Material(
        color: U.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: U.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
                width: 0.6,
              ),
            ),
            child: label.isNotEmpty
                ? Text(
                    label,
                    style: GoogleFonts.robotoFlex(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: color,
                      letterSpacing: 0.5,
                    ),
                  )
                : Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
