import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../theme/image_overlay_colors.dart';
import 'attendance_screen.dart';
import 'university_screen.dart';
import 'uni_chat_screen.dart';
import 'community_notes_screen.dart';
import 'event_notifications_screen.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/minimal_news_pill.dart';
import '../services/focus_supabase_service.dart';
import '../services/cache_service.dart';
import '../services/secure_storage_service.dart';
import '../services/attendance_cache_service.dart';
import '../services/uni_chat_service.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  final _service = FocusSupabaseService();
  String _quote = '';
  String _greetingText = '';
  double? _attendancePct;
  String _studentName = '';
  int _belowTargetCount = 0;
  bool _isAttendanceConnected = false;

  String _weatherCity = '';
  double? _weatherTemp;
  int? _weatherCode;
  int _notificationCount = 0;

  String get _userName {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final name = user.displayName;
    if (name == null || name.isEmpty) return '';
    return name.split(' ')[0];
  }

  String _generateRandomGreeting(String slot) {
    final List<String> variants;
    if (slot == 'morning') {
      variants = const [
        'Good morning',
        'Top of the morning',
        'Have a beautiful morning',
        'Wishing you a bright morning',
        'Wake up and conquer',
        'Hello, early bird',
        'A fresh start today',
        'Time to shine',
        'Good morning, champion',
        'Hope your day starts great',
        'Good morning, legend',
        'Start with a smile',
        'Embrace the fresh day',
        'Morning, superstar',
        'Ready for a great day?',
        'A beautiful morning to you',
        'Make today count',
        'Rise up and thrive',
        'Hello there, sunshine',
      ];
    } else if (slot == 'afternoon') {
      variants = const [
        'Good afternoon',
        'Hope your afternoon is great',
        'Good afternoon, legend',
        'Happy midday',
        'Keep going strong',
        'Crushing your day?',
        'Stay focused this afternoon',
        'A wonderful afternoon to you',
        'Enjoy this beautiful afternoon',
        'Afternoon, superstar',
        'Halfway to your goals',
        'Keep up the great momentum',
        'Midday motivation is here',
        'Hope your day is productive',
        'Taking a breath?',
        'Good afternoon, champion',
        'Stay energized',
        'Make the rest of the day count',
        'Afternoon, early achiever',
        'Doing amazing things today',
      ];
    } else if (slot == 'evening') {
      variants = const [
        'Good evening',
        'Hope you had a great day',
        'Good evening, legend',
        'Unwind and relax',
        'Time to ease into the evening',
        'A peaceful evening to you',
        'Evening, superstar',
        'Reflect on today\'s wins',
        'Relax and recharge',
        'Good evening, champion',
        'You made it through the day',
        'Rest up for tomorrow',
        'Evening calm is here',
        'Proud of your effort today',
        'Time to slow down',
        'Evening, early achiever',
        'Cherish the quiet moments',
        'Hope your evening is restful',
        'Wrap up and relax',
      ];
    } else {
      variants = const [
        'Welcome back',
        'Great to see you',
        'Ready to dive in?',
        'Let\'s get things done',
        'Stay inspired today',
        'Keep up the great work',
        'Your journey continues',
        'Focus and achieve',
        'Make today amazing',
        'Step by step forward',
        'Believe in your progress',
        'Every moment counts',
        'Keep reaching higher',
        'You\'ve got this',
        'Stay curious and bold',
        'Embrace every challenge',
        'Small steps, big results',
        'Create something great',
        'Keep moving forward',
      ];
    }
    final now = DateTime.now();
    final dayIndex = now.difference(DateTime(now.year)).inDays;
    final seed = dayIndex + now.hour;
    final index = seed % variants.length;
    return variants[index];
  }

  @override
  void initState() {
    super.initState();
    final timeSlot = ImageOverlayColors.getTimeSlot();
    final greetingText = _generateRandomGreeting(timeSlot);
    final userNameStr = _userName;
    _greetingText = userNameStr.isEmpty ? greetingText : '$greetingText, $userNameStr';
    _loadCachedWeather();
    _loadData();
    _loadQuote();
    _loadNotificationCount();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final prefs = await SharedPreferences.getInstance();
      final dismissedIds = prefs.getStringList('dismissed_notifications') ?? [];

      int socialCount = 0;
      if (uid.isNotEmpty) {
        try {
          final pendingReqs = await FirebaseFirestore.instance
              .collection('follows')
              .where('followingId', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .count()
              .get();
          final unseenWaves = await FirebaseFirestore.instance
              .collection('waves')
              .where('receiverId', isEqualTo: uid)
              .limit(10)
              .get();
          final unreadNotifs = await FirebaseFirestore.instance
              .collection('notifications')
              .where('recipientId', isEqualTo: uid)
              .limit(10)
              .get();

          final validWaves = unseenWaves.docs.where((d) => !dismissedIds.contains(d.id)).length;
          final validNotifs = unreadNotifs.docs.where((d) => !dismissedIds.contains(d.id)).length;

          socialCount = (pendingReqs.count ?? 0) + validWaves + validNotifs;
        } catch (_) {}
      }

      final results = await Future.wait([
        EventService.instance.getEndingSoonEvents(limit: 5),
        EventService.instance.getUpcomingEvents(limit: 5),
        EventService.instance.getMyCertificates(),
      ]);

      final endingSoon = (results[0] as List<EventModel>).where((e) => !dismissedIds.contains(e.id)).toList();
      final newEvents = (results[1] as List<EventModel>).where((e) => !dismissedIds.contains(e.id)).toList();
      final certificates = (results[2] as List<EventCertificate>).where((c) => !dismissedIds.contains(c.id)).toList();

      if (mounted) {
        setState(() {
          _notificationCount = socialCount + endingSoon.length + newEvents.length + certificates.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCachedWeather() async {
    try {
      final city = await CacheService().getAppSetting('weather_city');
      final tempStr = await CacheService().getAppSetting('weather_temp');
      final codeStr = await CacheService().getAppSetting('weather_code');
      if (mounted) {
        setState(() {
          _weatherCity = city ?? (U.cachedUniversityName.isNotEmpty ? U.cachedUniversityName : 'Kakinada');
          if (tempStr != null) _weatherTemp = double.tryParse(tempStr);
          if (codeStr != null) _weatherCode = int.tryParse(codeStr);
        });
      }
    } catch (e) {
      debugPrint('Error loading cached weather: $e');
    }
  }

  Future<void> _fetchWeather() async {
    if (_weatherCity.isEmpty) return;
    try {
      final geoUrl = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(_weatherCity)}&count=1&language=en&format=json',
      );
      final geoRes = await http.get(geoUrl);
      if (geoRes.statusCode == 200) {
        final geoData = jsonDecode(geoRes.body);
        final results = geoData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first;
          final lat = first['latitude'];
          final lon = first['longitude'];
          final name = first['name'] as String? ?? _weatherCity;

          final weatherUrl = Uri.parse(
            'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true',
          );
          final weatherRes = await http.get(weatherUrl);
          if (weatherRes.statusCode == 200) {
            final weatherData = jsonDecode(weatherRes.body);
            final current = weatherData['current_weather'];
            if (current != null) {
              final temp = (current['temperature'] as num?)?.toDouble();
              final code = current['weathercode'] as int?;

              if (mounted) {
                setState(() {
                  _weatherTemp = temp;
                  _weatherCode = code;
                  _weatherCity = name;
                });
              }

              await CacheService().saveAppSetting('weather_city', name);
              if (temp != null) {
                await CacheService().saveAppSetting('weather_temp', temp.toString());
              }
              if (code != null) {
                await CacheService().saveAppSetting('weather_code', code.toString());
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching weather: $e');
    }
  }

  IconData _getWeatherIcon(int? code) {
    if (code == null) return Icons.thermostat_rounded;
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code >= 1 && code <= 3) return Icons.wb_cloudy_rounded;
    if (code == 45 || code == 48) return Icons.cloud_rounded;
    if (code >= 51 && code <= 55) return Icons.grain_rounded;
    if (code >= 61 && code <= 65) return Icons.umbrella_rounded;
    if (code >= 71 && code <= 75) return Icons.ac_unit_rounded;
    if (code >= 80 && code <= 82) return Icons.umbrella_rounded;
    if (code >= 95 && code <= 99) return Icons.thunderstorm_rounded;
    return Icons.thermostat_rounded;
  }

  void _showWeatherCityPicker() {
    final controller = TextEditingController(text: _weatherCity);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: U.border, width: 0.5),
        ),
        title: Text(
          'Set Weather Location',
          style: GoogleFonts.outfit(
            color: U.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          style: GoogleFonts.plusJakartaSans(color: U.text),
          decoration: InputDecoration(
            labelText: 'City Name',
            labelStyle: GoogleFonts.plusJakartaSans(color: U.sub),
            hintText: 'e.g. Kakinada, Surampalem',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(color: U.sub),
            ),
          ),
          FilledButton(
            onPressed: () async {
              final newCity = controller.text.trim();
              if (newCity.isNotEmpty) {
                setState(() {
                  _weatherCity = newCity;
                });
                Navigator.pop(ctx);
                await CacheService().saveAppSetting('weather_city', newCity);
                _fetchWeather();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: U.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Save',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    try {
      await _service.initialize();
      // Start download sync in background to update local SQLite
      _service.syncDownAllData().then((_) {
        _loadStats();
        _fetchWeather();
      });
      _loadStats();
      _fetchWeather();
    } catch (_) {}
  }

  Future<void> _loadQuote() async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedQuote = prefs.getString('daily_quote_text');
      final cachedAuthor = prefs.getString('daily_quote_author');
      final cachedDate = prefs.getString('daily_quote_date');

      if (cachedQuote != null && cachedAuthor != null && cachedDate == todayStr) {
        // Today's quote is already cached. Show it immediately and skip fetching.
        if (mounted) {
          setState(() {
            _quote = '"$cachedQuote" — $cachedAuthor';
          });
        }
        return;
      }

      // If a cache exists from a previous day, show it immediately before fetching
      if (cachedQuote != null && cachedAuthor != null) {
        if (mounted) {
          setState(() {
            _quote = '"$cachedQuote" — $cachedAuthor';
          });
        }
      } else {
        // Otherwise show nothing until fetched
        if (mounted) {
          setState(() {
            _quote = '';
          });
        }
      }

      // Fetch fresh quote from ZenQuotes API
      final response = await http.get(Uri.parse('https://zenquotes.io/api/today')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty && data[0] is Map) {
          final q = data[0]['q'] as String?;
          final a = data[0]['a'] as String?;
          if (q != null && a != null && q.isNotEmpty && a.isNotEmpty) {
            // Cache the fresh quote, author, and date
            await prefs.setString('daily_quote_text', q);
            await prefs.setString('daily_quote_author', a);
            await prefs.setString('daily_quote_date', todayStr);

            if (mounted) {
              setState(() {
                _quote = '"$q" — $a';
              });
            }
            return;
          }
        }
      }

      // If API fails and no cache exists at all, show hardcoded fallback
      if (cachedQuote == null || cachedAuthor == null) {
        if (mounted) {
          setState(() {
            _quote = '"Focus on progress, not perfection." — Unknown';
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching/loading daily quote: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedQuote = prefs.getString('daily_quote_text');
        final cachedAuthor = prefs.getString('daily_quote_author');
        if (cachedQuote == null || cachedAuthor == null) {
          if (mounted) {
            setState(() {
              _quote = '"Focus on progress, not perfection." — Unknown';
            });
          }
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _quote = '"Focus on progress, not perfection." — Unknown';
          });
        }
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      double? attendancePct;
      String studentName = '';
      int belowTargetCount = 0;
      bool isConnected = false;
      try {
        final credentials = await SecureStorageService.getCredentials();
        if (credentials != null) {
          isConnected = true;
          final roll = credentials['rollNumber'];
          if (roll != null) {
            final cachedAttendance = await AttendanceCacheService.load(roll);
            if (cachedAttendance != null) {
              attendancePct = cachedAttendance.data['overallPercentage'] as double?;
              studentName = (cachedAttendance.data['studentName'] as String? ?? '').trim();
              final subjects = (cachedAttendance.data['subjects'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>();
              belowTargetCount = subjects.where((subject) {
                final percentage = (subject['percentage'] as num?)?.toDouble() ?? 0;
                return percentage < 75.0;
              }).length;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading cached attendance: $e');
      }

      if (mounted) {
        setState(() {
          _attendancePct = attendancePct;
          _studentName = studentName;
          _belowTargetCount = belowTargetCount;
          _isAttendanceConnected = isConnected;
        });
      }
    } catch (_) {}
  }

  Widget _buildQuickPill({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDark = appThemeNotifier.value.isDark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? color.withValues(alpha: 0.06)
                  : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? color.withValues(alpha: 0.2)
                    : color.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isDark ? color.withValues(alpha: 0.95) : color.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isDark ? color.withValues(alpha: 0.95) : color.withValues(alpha: 0.85),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = appThemeNotifier.value.isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Header: Utopia brand identity & Notifications ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Utopia',
                              style: TextStyle(
                                fontFamily: 'OrangeAvenue',
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                                color: U.text,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Transform.rotate(
                                angle: 30 * 3.1415926535 / 180,
                                child: Transform.scale(
                                  scaleX: -1,
                                  child: Image.asset(
                                    'assets/focus screen/leaves.png',
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.contain,
                                    color: U.primary,
                                    colorBlendMode: BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EventNotificationsScreen(),
                              ),
                            );
                            _loadNotificationCount();
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDarkTheme
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: isDarkTheme
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.05),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.notifications_none_rounded,
                                  color: U.text,
                                  size: 20,
                                ),
                              ),
                              if (_notificationCount > 0)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: U.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: U.bg,
                                        width: 1.5,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Center(
                                      child: Text(
                                        _notificationCount > 9 ? '9+' : _notificationCount.toString(),
                                        style: GoogleFonts.plusJakartaSans(
                                          color: isDarkTheme ? Colors.black : Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Greeting text
                    (() {
                      final commaIndex = _greetingText.indexOf(',');
                      if (commaIndex != -1) {
                        final greetingPart = _greetingText.substring(0, commaIndex);
                        final namePart = _greetingText.substring(commaIndex + 1).trim();
                        return RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '$greetingPart, ',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w300,
                                  color: U.text,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              TextSpan(
                                text: namePart,
                                style: GoogleFonts.outfit(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  color: U.text,
                                  letterSpacing: -0.6,
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Text(
                          _greetingText,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: U.text,
                            letterSpacing: -0.4,
                          ),
                        );
                      }
                    })(),
                    if (_quote.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: U.primary.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Text(
                          _quote,
                          style: GoogleFonts.newsreader(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.italic,
                            color: U.sub,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ).animate()
                  .fadeIn(duration: 500.ms, curve: Curves.easeOutCubic)
                  .slideY(begin: 0.1, end: 0, duration: 500.ms, curve: Curves.easeOutCubic),

              const SizedBox(height: 18),

              // ── Inline Metric Quick Bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      const MinimalNewsPill(),
                      const SizedBox(width: 8),
                      _buildQuickPill(
                        label: _weatherTemp != null
                            ? '${_weatherTemp!.toStringAsFixed(0)}°C $_weatherCity'
                            : 'Set Location',
                        icon: _getWeatherIcon(_weatherCode),
                        color: U.lavender,
                        onTap: _showWeatherCityPicker,
                      ),
                    ],
                  ),
                ),
              ).animate()
                  .fadeIn(delay: 150.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0, delay: 150.ms, duration: 400.ms, curve: Curves.easeOutCubic),

              const SizedBox(height: 20),

              // ── Attendance Tracker Hero Card (Wide) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: PressableCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AttendanceScreen()),
                  ).then((_) => _loadData()),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDarkTheme
                            ? [
                                U.card.withValues(alpha: 0.95),
                                U.card.withValues(alpha: 0.8),
                              ]
                            : [
                                Colors.white,
                                U.card.withValues(alpha: 0.95),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDarkTheme
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.5),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDarkTheme ? 0.45 : 0.12,
                          ),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          spreadRadius: -2,
                        ),
                        BoxShadow(
                          color: isDarkTheme
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Neumorphic icon container
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isDarkTheme
                                            ? [
                                                U.card,
                                                U.card.withValues(alpha: 0.7),
                                              ]
                                            : [
                                                Colors.white,
                                                U.card.withValues(alpha: 0.9),
                                              ],
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDarkTheme ? 0.25 : 0.05),
                                          blurRadius: 4,
                                          offset: const Offset(2, 2),
                                        ),
                                        BoxShadow(
                                          color: isDarkTheme 
                                              ? Colors.white.withValues(alpha: 0.02) 
                                              : Colors.white,
                                          blurRadius: 4,
                                          offset: const Offset(-2, -2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.school_rounded,
                                      color: _attendancePct != null && _attendancePct! >= 75
                                          ? U.green
                                          : _attendancePct != null && _attendancePct! >= 65
                                              ? U.peach
                                              : U.red,
                                      size: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'ACADEMIC PROFILE',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        color: (_attendancePct != null && _attendancePct! >= 75
                                                ? U.green
                                                : _attendancePct != null && _attendancePct! >= 65
                                                    ? U.peach
                                                    : U.red)
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _isAttendanceConnected ? 'Attendance Report' : 'Connect Attendance',
                                style: GoogleFonts.newsreader(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                  color: U.text,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (!_isAttendanceConnected)
                                Text(
                                  'Tap to link your college portal & track progress',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: U.sub,
                                  ),
                                )
                              else if (_attendancePct == null)
                                Text(
                                  'Connected',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: U.sub,
                                  ),
                                )
                              else ...[
                                if (_studentName.isNotEmpty) ...[
                                  Text(
                                    _studentName.toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: U.sub,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                ],
                                Text(
                                  _belowTargetCount > 0
                                      ? '$_belowTargetCount subject${_belowTargetCount == 1 ? '' : 's'} need attention'
                                      : 'All subjects on track',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: U.sub,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: U.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: U.border.withValues(alpha: 0.3), width: 0.5),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _attendancePct != null ? (_attendancePct! / 100).clamp(0.0, 1.0) : 0.0,
                                    backgroundColor: Colors.transparent,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _attendancePct != null && _attendancePct! >= 75
                                          ? U.green
                                          : _attendancePct != null && _attendancePct! >= 65
                                              ? U.peach
                                              : U.red,
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        (() {
                          final pctValue = _attendancePct != null ? _attendancePct! / 100 : 0.0;
                          return SizedBox(
                            width: 76,
                            height: 76,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer Neumorphic circular track/plate (complementary concave depth)
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isDarkTheme
                                          ? [
                                              U.card.withValues(alpha: 0.8),
                                              U.card,
                                            ]
                                          : [
                                              U.card.withValues(alpha: 0.9),
                                              Colors.white,
                                            ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDarkTheme ? 0.25 : 0.04),
                                        blurRadius: 6,
                                        offset: const Offset(3, 3),
                                      ),
                                      BoxShadow(
                                        color: isDarkTheme 
                                            ? Colors.white.withValues(alpha: 0.02) 
                                            : Colors.white.withValues(alpha: 0.8),
                                        blurRadius: 6,
                                        offset: const Offset(-3, -3),
                                      ),
                                    ],
                                  ),
                                ),
                                // Circular Progress ring
                                SizedBox(
                                  width: 70,
                                  height: 70,
                                  child: CircularProgressIndicator(
                                    value: pctValue,
                                    backgroundColor: U.surface,
                                    color: _attendancePct != null && _attendancePct! >= 75
                                        ? U.green
                                        : _attendancePct != null && _attendancePct! >= 65
                                            ? U.peach
                                            : U.red,
                                    strokeWidth: 6,
                                    strokeCap: StrokeCap.round,
                                  ),
                                ),
                                // Inner Neumorphic raised circular button (raised convex dome)
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isDarkTheme
                                          ? [
                                              U.card,
                                              U.card.withValues(alpha: 0.7),
                                            ]
                                          : [
                                              Colors.white,
                                              U.card.withValues(alpha: 0.9),
                                            ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDarkTheme ? 0.3 : 0.06),
                                        blurRadius: 5,
                                        offset: const Offset(2, 2),
                                      ),
                                      BoxShadow(
                                        color: isDarkTheme 
                                            ? Colors.white.withValues(alpha: 0.03) 
                                            : Colors.white,
                                        blurRadius: 5,
                                        offset: const Offset(-2, -2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _isAttendanceConnected
                                        ? Text(
                                            '${(pctValue * 100).toInt()}%',
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: U.text,
                                            ),
                                          )
                                        : Icon(
                                            Icons.sync_lock_rounded,
                                            color: U.sub,
                                            size: 16,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          );
                      })(),
                    ],
                  ),
                ),
              ),
            ).animate()
                .fadeIn(delay: 250.ms, duration: 500.ms)
                .slideY(begin: 0.1, end: 0, delay: 250.ms, duration: 500.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: 16),

            // ── People & Chat to Utopia Square Cards ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  // University Card
                  Expanded(
                    child: PressableCard(
                      onTap: () {
                        Navigator.push(
                          context,
                          buildForwardRoute(const UniversityScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDarkTheme
                                ? [
                                    U.card.withValues(alpha: 0.95),
                                    U.card.withValues(alpha: 0.8),
                                  ]
                                : [
                                    Colors.white,
                                    U.card.withValues(alpha: 0.95),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDarkTheme
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white.withValues(alpha: 0.5),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDarkTheme ? 0.45 : 0.12,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                              spreadRadius: -2,
                            ),
                            BoxShadow(
                              color: isDarkTheme
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isDarkTheme
                                          ? [
                                              U.card,
                                              U.card.withValues(alpha: 0.7),
                                            ]
                                          : [
                                              Colors.white,
                                              U.card.withValues(alpha: 0.9),
                                            ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDarkTheme ? 0.25 : 0.08),
                                        blurRadius: 6,
                                        offset: const Offset(2, 3),
                                      ),
                                      BoxShadow(
                                        color: isDarkTheme
                                            ? Colors.white.withValues(alpha: 0.02)
                                            : Colors.white,
                                        blurRadius: 4,
                                        offset: const Offset(-2, -2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.school_rounded,
                                      color: U.primary,
                                      size: 19,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: U.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Campus',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: U.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'University',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: U.text,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Events, docs & hub',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: U.sub,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Chat to Utopia Card
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: currentUid.isNotEmpty
                              ? FirebaseFirestore.instance.collection('users').doc(currentUid).snapshots()
                              : const Stream.empty(),
                          builder: (context, userSnap) {
                            final liveUniId = userSnap.data?.data()?['selectedUniversityId'] as String?;
                            final uniId = (liveUniId != null && liveUniId.isNotEmpty)
                                ? liveUniId
                                : (U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'support');
                            if (liveUniId != null && liveUniId.isNotEmpty && liveUniId != U.cachedUniversityId) {
                              U.cachedUniversityId = liveUniId;
                            }

                            return StreamBuilder<bool>(
                              stream: UniChatService().unreadStatusStream(uniId),
                              initialData: false,
                              builder: (context, snapshot) {
                                final hasUnread = snapshot.data ?? false;
                                return PressableCard(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => UniChatScreen(universityId: uniId)),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isDarkTheme
                                            ? [
                                                U.card.withValues(alpha: 0.95),
                                                U.card.withValues(alpha: 0.8),
                                              ]
                                            : [
                                                Colors.white,
                                                U.card.withValues(alpha: 0.95),
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: isDarkTheme
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.white.withValues(alpha: 0.5),
                                        width: 1.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: isDarkTheme ? 0.45 : 0.12,
                                          ),
                                          blurRadius: 20,
                                          offset: const Offset(0, 8),
                                          spreadRadius: -2,
                                        ),
                                        BoxShadow(
                                          color: isDarkTheme
                                              ? Colors.white.withValues(alpha: 0.03)
                                              : Colors.black.withValues(alpha: 0.04),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                          spreadRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: isDarkTheme
                                                      ? [
                                                          U.card,
                                                          U.card.withValues(alpha: 0.7),
                                                        ]
                                                      : [
                                                          Colors.white,
                                                          U.card.withValues(alpha: 0.9),
                                                        ],
                                                ),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: isDarkTheme ? 0.25 : 0.08),
                                                    blurRadius: 6,
                                                    offset: const Offset(2, 3),
                                                  ),
                                                  BoxShadow(
                                                    color: isDarkTheme
                                                        ? Colors.white.withValues(alpha: 0.02)
                                                        : Colors.white,
                                                    blurRadius: 4,
                                                    offset: const Offset(-2, -2),
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Stack(
                                                  alignment: Alignment.topRight,
                                                  children: [
                                                    Icon(
                                                      Icons.forum_rounded,
                                                      color: U.teal,
                                                      size: 19,
                                                    ),
                                                    if (hasUnread)
                                                      Container(
                                                        width: 5,
                                                        height: 5,
                                                        decoration: const BoxDecoration(
                                                          color: Colors.redAccent,
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: U.teal.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Chat',
                                                style: GoogleFonts.outfit(
                                                  color: U.teal,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          'Chat to Utopia',
                                          style: GoogleFonts.outfit(
                                            color: U.text,
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Campus chat',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: U.sub,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
                ],
              ),
            ).animate()
                .fadeIn(delay: 300.ms, duration: 500.ms)
                .slideY(begin: 0.1, end: 0, delay: 300.ms, duration: 500.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: 16),

            // ── Community Notes Card (Rectangle) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PressableCard(
                onTap: () {
                  final uniId = U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'support';
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CommunityNotesScreen(universityFolderName: uniId)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDarkTheme
                          ? [
                              U.card.withValues(alpha: 0.95),
                              U.card.withValues(alpha: 0.8),
                            ]
                          : [
                              Colors.white,
                              U.card.withValues(alpha: 0.95),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDarkTheme
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDarkTheme ? 0.45 : 0.12,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                        spreadRadius: -2,
                      ),
                      BoxShadow(
                        color: isDarkTheme
                            ? Colors.white.withValues(alpha: 0.03)
                            : Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDarkTheme
                                ? [
                                    U.card,
                                    U.card.withValues(alpha: 0.7),
                                  ]
                                : [
                                    Colors.white,
                                    U.card.withValues(alpha: 0.9),
                                  ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDarkTheme ? 0.25 : 0.08),
                              blurRadius: 6,
                              offset: const Offset(2, 3),
                            ),
                            BoxShadow(
                              color: isDarkTheme
                                  ? Colors.white.withValues(alpha: 0.02)
                                  : Colors.white,
                              blurRadius: 4,
                              offset: const Offset(-2, -2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: U.blue,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Community Notes',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      color: U.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: U.blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Academics',
                                    style: GoogleFonts.outfit(
                                      color: U.blue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Campus notes & study materials',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: U.sub,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: U.sub,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ).animate()
                .fadeIn(delay: 350.ms, duration: 500.ms)
                .slideY(begin: 0.1, end: 0, delay: 350.ms, duration: 500.ms, curve: Curves.easeOutCubic),

              // ── Community Notes & Classes cards hidden ──

              // ── Dynamic Online News Card ──
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('config')
                    .doc('app_config')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
                    return const SizedBox.shrink();
                  }

                  final data = snapshot.data!.data();
                  if (data == null) return const SizedBox.shrink();

                  final bool isEnabled = data['news_enabled'] as bool? ?? false;
                  final String title = (data['news_title'] as String? ?? '').trim();
                  final String description = (data['news_description'] as String? ?? '').trim();

                  if (!isEnabled || title.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDarkTheme
                              ? [
                                  U.card.withValues(alpha: 0.95),
                                  U.card.withValues(alpha: 0.8),
                                ]
                              : [
                                  Colors.white,
                                  U.card.withValues(alpha: 0.95),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDarkTheme
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.white.withValues(alpha: 0.5),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDarkTheme ? 0.45 : 0.12,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                            spreadRadius: -2,
                          ),
                          BoxShadow(
                            color: isDarkTheme
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Accent edge
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    U.primary.withValues(alpha: 0.0),
                                    U.primary,
                                    U.primary.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Neumorphic pill tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isDarkTheme
                                            ? [
                                                U.card,
                                                U.card.withValues(alpha: 0.7),
                                              ]
                                            : [
                                                Colors.white,
                                                U.card.withValues(alpha: 0.9),
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDarkTheme ? 0.20 : 0.04),
                                          blurRadius: 4,
                                          offset: const Offset(2, 2),
                                        ),
                                        BoxShadow(
                                          color: isDarkTheme
                                              ? Colors.white.withValues(alpha: 0.02)
                                              : Colors.white,
                                          blurRadius: 4,
                                          offset: const Offset(-2, -2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.newspaper_rounded,
                                          size: 12,
                                          color: U.primary.withValues(alpha: 0.85),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'NEWS',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                            color: U.primary.withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                title,
                                style: GoogleFonts.newsreader(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                  color: U.text,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: U.sub,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ).animate()
                        .fadeIn(delay: 500.ms, duration: 500.ms)
                        .slideY(begin: 0.1, end: 0, delay: 500.ms, duration: 500.ms, curve: Curves.easeOutCubic),
                  );
                },
              ),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;

  const PressableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.97,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class AnimatedWaveform extends StatefulWidget {
  final Color color;
  const AnimatedWaveform({super.key, required this.color});

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final heights = [0.35, 0.75, 0.5, 0.95, 0.65, 0.45, 0.25];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(7, (index) {
            final animatedVal = _controller.value;
            final shift = sin((animatedVal * 2 * pi) + (index * 0.8));
            final currentHeight = 10.0 + 18.0 * heights[index] * (shift + 1.2);
            return Container(
              width: 3.5,
              height: currentHeight.clamp(4.0, 32.0),
              margin: const EdgeInsets.symmetric(horizontal: 1.8),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
