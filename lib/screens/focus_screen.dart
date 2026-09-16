import 'dart:convert';
import 'dart:math';
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
import 'friends_screen.dart';
import 'event_notifications_screen.dart';
import 'sciwordle_screen.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/minimal_news_pill.dart';
import '../theme/m3_expressive_theme.dart';
import '../services/focus_supabase_service.dart';
import '../services/cache_service.dart';
import '../services/secure_storage_service.dart';
import '../services/attendance_cache_service.dart';
import '../services/uni_chat_service.dart';
import '../widgets/dynamic_attendance_card.dart';
import '../utils/responsive_scale.dart';

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
  bool _isAttendanceConnected = false;
  DateTime? _lastAttendanceFetched;

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
      final dismissedIds = await NotificationService.getDismissedNotificationIds();
      final lastClearedAt = await NotificationService.getLastNotificationsClearedAt();

      int socialCount = 0;
      if (uid.isNotEmpty) {
        try {
          final pendingReqs = await FirebaseFirestore.instance
              .collection('follows')
              .where('followingId', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
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

          final validReqs = pendingReqs.docs.where((d) => !NotificationService.isNotificationDismissed(
                d.id,
                dismissedIds: dismissedIds,
                lastClearedAt: lastClearedAt,
              )).length;

          final validWaves = unseenWaves.docs.where((d) {
            final createdAt = (d.data()['createdAt'] as Timestamp?)?.toDate();
            return !NotificationService.isNotificationDismissed(
              d.id,
              dismissedIds: dismissedIds,
              lastClearedAt: lastClearedAt,
              createdAt: createdAt,
            );
          }).length;

          final validNotifs = unreadNotifs.docs.where((d) {
            final createdAt = (d.data()['createdAt'] as Timestamp?)?.toDate();
            return !NotificationService.isNotificationDismissed(
              d.id,
              dismissedIds: dismissedIds,
              lastClearedAt: lastClearedAt,
              createdAt: createdAt,
            );
          }).length;

          socialCount = validReqs + validWaves + validNotifs;
        } catch (_) {}
      }

      final results = await Future.wait([
        EventService.instance.getEndingSoonEvents(limit: 5),
        EventService.instance.getUpcomingEvents(limit: 5),
        EventService.instance.getMyCertificates(),
      ]);

      final endingSoon = (results[0] as List<EventModel>).where((e) => !NotificationService.isNotificationDismissed(
            e.id,
            dismissedIds: dismissedIds,
            lastClearedAt: lastClearedAt,
            createdAt: e.createdAt ?? e.date,
          )).toList();
      final newEvents = (results[1] as List<EventModel>).where((e) => !NotificationService.isNotificationDismissed(
            e.id,
            dismissedIds: dismissedIds,
            lastClearedAt: lastClearedAt,
            createdAt: e.createdAt ?? e.date,
          )).toList();
      final certificates = (results[2] as List<EventCertificate>).where((c) => !NotificationService.isNotificationDismissed(
            c.id,
            dismissedIds: dismissedIds,
            lastClearedAt: lastClearedAt,
            createdAt: c.issuedAt,
          )).toList();

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
      bool isConnected = false;
      DateTime? lastFetched;
      try {
        final credentials = await SecureStorageService.getCredentials();
        if (credentials != null) {
          isConnected = true;
          final roll = credentials['rollNumber'];
          if (roll != null) {
            final cachedAttendance = await AttendanceCacheService.load(roll);
            if (cachedAttendance != null) {
              attendancePct = (cachedAttendance.data['overallPercentage'] as num?)?.toDouble();
              studentName = (cachedAttendance.data['studentName'] as String? ?? '').trim();
              lastFetched = cachedAttendance.cachedAt;
            } else {
              final prefs = await SharedPreferences.getInstance();
              final currJson = prefs.getString('attendance_history_curr_${roll.trim().toUpperCase()}');
              if (currJson != null) {
                try {
                  final Map<String, dynamic> currMap = jsonDecode(currJson);
                  final tsStr = currMap['timestamp'] as String?;
                  if (tsStr != null) {
                    lastFetched = DateTime.tryParse(tsStr);
                  }
                  attendancePct ??= (currMap['overallPercentage'] as num?)?.toDouble();
                } catch (_) {}
              }
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
          _isAttendanceConnected = isConnected;
          _lastAttendanceFetched = lastFetched;
        });
      }
    } catch (_) {}
  }

  Widget _buildQuickPill({
    required String label,
    required IconData icon,
    required Color color,
    ResponsiveScale? rs,
    VoidCallback? onTap,
  }) {
    return M3Pressable(
      onTap: onTap,
      scaleFactor: 0.94,
      borderRadius: M3Shapes.fullRadius,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: rs?.s(16, min: 12, max: 20) ?? 16,
          vertical: rs?.s(10, min: 8, max: 13) ?? 10,
        ),
        decoration: BoxDecoration(
          color: U.surfaceContainerHigh,
          borderRadius: M3Shapes.fullRadius,
          border: Border.all(
            color: U.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: rs?.s(15, min: 13, max: 18) ?? 15,
              color: color,
            ),
            SizedBox(width: rs?.s(8, min: 6, max: 10) ?? 8),
            Text(
              label,
              style: GoogleFonts.robotoFlex(
                fontSize: rs?.font(12, min: 10.5, max: 14) ?? 12,
                fontWeight: FontWeight.w700,
                color: U.text,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = appThemeNotifier.value.isDark;
    final rs = ResponsiveScale.of(context);
    final padH = rs.horizontalPadding;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: rs.vs(20, min: 14, max: 26)),

                  // ── Header: Utopia brand identity & Notifications ──
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH),
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
                                    fontSize: rs.font(38, min: 32, max: 46),
                                    fontWeight: FontWeight.w700,
                                    color: U.text,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                SizedBox(width: rs.s(4, min: 3, max: 6)),
                                Padding(
                                  padding: EdgeInsets.only(top: rs.s(8, min: 6, max: 10)),
                                  child: Transform.rotate(
                                    angle: 30 * 3.1415926535 / 180,
                                    child: Transform.scale(
                                      scaleX: -1,
                                      child: Image.asset(
                                        'assets/focus screen/leaves.png',
                                        width: rs.s(22, min: 18, max: 28),
                                        height: rs.s(22, min: 18, max: 28),
                                        fit: BoxFit.contain,
                                        color: U.primary,
                                        colorBlendMode: BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            M3Pressable(
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
                                    width: rs.s(42, min: 36, max: 48),
                                    height: rs.s(42, min: 36, max: 48),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDarkTheme
                                          ? U.surfaceContainerHighest.withValues(alpha: 0.6)
                                          : U.surfaceContainerHighest.withValues(alpha: 0.8),
                                      border: Border.all(
                                        color: U.outlineVariant.withValues(alpha: isDarkTheme ? 0.3 : 0.5),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.notifications_none_rounded,
                                      color: U.text,
                                      size: rs.s(20, min: 17, max: 24),
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
                                            style: GoogleFonts.robotoFlex(
                                              color: U.getContrastColor(U.primary),
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
                        SizedBox(height: rs.vs(12, min: 8, max: 16)),
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
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: rs.font(22, min: 18, max: 26),
                                      fontWeight: FontWeight.w300,
                                      color: U.text,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  TextSpan(
                                    text: namePart,
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: rs.font(23, min: 19, max: 27),
                                      fontWeight: FontWeight.w700,
                                      color: U.text,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            return Text(
                              _greetingText,
                              style: GoogleFonts.robotoFlex(
                                fontSize: rs.font(22, min: 18, max: 26),
                                fontWeight: FontWeight.w400,
                                color: U.text,
                                letterSpacing: -0.3,
                              ),
                            );
                          }
                        })(),
                        if (_quote.isNotEmpty) ...[
                          SizedBox(height: rs.vs(12, min: 8, max: 16)),
                          Container(
                            padding: EdgeInsets.only(left: rs.s(12, min: 9, max: 16)),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: U.primary.withValues(alpha: 0.4),
                                  width: 2.0,
                                ),
                              ),
                            ),
                            child: Text(
                              _quote,
                              style: GoogleFonts.newsreader(
                                fontSize: rs.font(14.5, min: 12.5, max: 17),
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

                  SizedBox(height: rs.vs(18, min: 12, max: 24)),

                  // ── Inline Metric Quick Bar ──
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          const MinimalNewsPill(),
                          SizedBox(width: rs.s(8, min: 6, max: 12)),
                          _buildQuickPill(
                            label: _weatherTemp != null
                                ? '${_weatherTemp!.toStringAsFixed(0)}°C $_weatherCity'
                                : 'Set Location',
                            icon: _getWeatherIcon(_weatherCode),
                            color: U.lavender,
                            rs: rs,
                            onTap: _showWeatherCityPicker,
                          ),
                          SizedBox(width: rs.s(8, min: 6, max: 12)),
                          _buildQuickPill(
                            label: 'SciWordle',
                            icon: Icons.psychology_rounded,
                            color: const Color(0xFF10B981),
                            rs: rs,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SciwordleScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ).animate()
                      .fadeIn(delay: 150.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0, delay: 150.ms, duration: 400.ms, curve: Curves.easeOutCubic),

                  SizedBox(height: rs.vs(20, min: 14, max: 26)),

                  // ── Dynamic Motion Attendance Hero Card (Always in Motion) ──
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH),
                    child: DynamicMotionAttendanceCard(
                      isConnected: _isAttendanceConnected,
                      attendancePct: _attendancePct,
                      studentName: _studentName,
                      lastFetched: _lastAttendanceFetched,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AttendanceScreen()),
                      ).then((_) => _loadData()),
                    ),
                  ).animate()
                      .fadeIn(delay: 250.ms, duration: 500.ms)
                      .slideY(begin: 0.1, end: 0, delay: 250.ms, duration: 500.ms, curve: Curves.easeOutCubic),

                  SizedBox(height: rs.vs(16, min: 12, max: 22)),

                  // ── People & Chat to Utopia Square Cards ──
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // SciWord Game Card
                          Expanded(
                            child: M3Pressable(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  buildForwardRoute(const SciwordleScreen()),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.all(rs.s(18, min: 14, max: 22)),
                                decoration: BoxDecoration(
                                  color: U.surfaceContainer,
                                  borderRadius: BorderRadius.circular(rs.s(26, min: 20, max: 30)),
                                  border: Border.all(
                                    color: U.outlineVariant.withValues(alpha: isDarkTheme ? 0.3 : 0.45),
                                    width: 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      width: rs.s(48, min: 40, max: 56),
                                      height: rs.s(48, min: 40, max: 56),
                                      decoration: BoxDecoration(
                                        color: U.primaryContainer,
                                        borderRadius: BorderRadius.circular(rs.s(16, min: 13, max: 19)),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.extension_rounded,
                                          color: U.onPrimaryContainer,
                                          size: rs.s(24, min: 20, max: 28),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: rs.vs(16, min: 10, max: 20)),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'SciWord',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.robotoFlex(
                                            color: U.text,
                                            fontSize: rs.font(16.5, min: 14.5, max: 19),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Daily word game',
                                          style: GoogleFonts.robotoFlex(
                                            fontSize: rs.font(12, min: 10.5, max: 13.5),
                                            color: U.sub,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: rs.s(12, min: 8, max: 16)),
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
                                        return M3Pressable(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => UniChatScreen(universityId: uniId)),
                                            );
                                          },
                                          child: Container(
                                            padding: EdgeInsets.all(rs.s(18, min: 14, max: 22)),
                                            decoration: BoxDecoration(
                                              color: U.surfaceContainer,
                                              borderRadius: BorderRadius.circular(rs.s(26, min: 20, max: 30)),
                                              border: Border.all(
                                                color: U.outlineVariant.withValues(alpha: isDarkTheme ? 0.3 : 0.45),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Container(
                                                  width: rs.s(48, min: 40, max: 56),
                                                  height: rs.s(48, min: 40, max: 56),
                                                  decoration: BoxDecoration(
                                                    color: U.secondaryContainer,
                                                    borderRadius: BorderRadius.circular(rs.s(16, min: 13, max: 19)),
                                                  ),
                                                  child: Center(
                                                    child: Stack(
                                                      alignment: Alignment.topRight,
                                                      children: [
                                                        Icon(
                                                          Icons.forum_rounded,
                                                          color: U.onSecondaryContainer,
                                                          size: rs.s(24, min: 20, max: 28),
                                                        ),
                                                        if (hasUnread)
                                                          Container(
                                                            width: rs.s(7, min: 5, max: 9),
                                                            height: rs.s(7, min: 5, max: 9),
                                                            decoration: const BoxDecoration(
                                                              color: Colors.redAccent,
                                                              shape: BoxShape.circle,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: rs.vs(16, min: 10, max: 20)),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Chat to Utopia',
                                                      style: GoogleFonts.robotoFlex(
                                                        color: U.text,
                                                        fontSize: rs.font(16.5, min: 14.5, max: 19),
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Campus chat',
                                                      style: GoogleFonts.robotoFlex(
                                                        fontSize: rs.font(12, min: 10.5, max: 13.5),
                                                        color: U.sub,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
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
                    ),
                  ).animate()
                      .fadeIn(delay: 300.ms, duration: 500.ms)
                      .slideY(begin: 0.1, end: 0, delay: 300.ms, duration: 500.ms, curve: Curves.easeOutCubic),

                  SizedBox(height: rs.vs(16, min: 12, max: 22)),

                  // ── Friends Card (Rectangle) ──
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH),
                    child: M3Pressable(
                      onTap: () {
                        Navigator.push(
                          context,
                          buildForwardRoute(const FriendsScreen()),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.all(rs.s(20, min: 16, max: 24)),
                        decoration: BoxDecoration(
                          color: U.surfaceContainer,
                          borderRadius: BorderRadius.circular(rs.s(26, min: 20, max: 30)),
                          border: Border.all(
                            color: U.outlineVariant.withValues(alpha: isDarkTheme ? 0.3 : 0.45),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: rs.s(50, min: 42, max: 58),
                              height: rs.s(50, min: 42, max: 58),
                              decoration: BoxDecoration(
                                color: U.secondaryContainer,
                                borderRadius: BorderRadius.circular(rs.s(16, min: 13, max: 19)),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.people_rounded,
                                  color: U.onSecondaryContainer,
                                  size: rs.s(25, min: 21, max: 29),
                                ),
                              ),
                            ),
                            SizedBox(width: rs.s(16, min: 12, max: 20)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Friends',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.robotoFlex(
                                      color: U.text,
                                      fontSize: rs.font(16.5, min: 14.5, max: 19),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Chat with friends',
                                    style: GoogleFonts.robotoFlex(
                                      fontSize: rs.font(12, min: 10.5, max: 13.5),
                                      color: U.sub,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: rs.s(12, min: 8, max: 16)),
                            Container(
                              width: rs.s(36, min: 30, max: 42),
                              height: rs.s(36, min: 30, max: 42),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: U.surfaceContainerHighest,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: U.sub,
                                  size: rs.s(14, min: 12, max: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate()
                      .fadeIn(delay: 350.ms, duration: 500.ms)
                      .slideY(begin: 0.1, end: 0, delay: 350.ms, duration: 500.ms, curve: Curves.easeOutCubic),

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
                        padding: EdgeInsets.only(top: rs.vs(20, min: 14, max: 26), left: padH, right: padH),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(rs.s(20, min: 16, max: 24)),
                          decoration: BoxDecoration(
                            color: U.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(rs.s(24, min: 18, max: 28)),
                            border: Border.all(
                              color: U.outlineVariant.withValues(alpha: isDarkTheme ? 0.3 : 0.45),
                              width: 0.8,
                            ),
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
                                      // Tonal tag
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: U.primary.withValues(alpha: 0.12),
                                          borderRadius: M3Shapes.smallRadius,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.newspaper_rounded,
                                              size: 12,
                                              color: U.primary,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'NEWS',
                                              style: GoogleFonts.robotoFlex(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.2,
                                                color: U.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: rs.vs(12, min: 8, max: 16)),
                                  Text(
                                    title,
                                    style: GoogleFonts.newsreader(
                                      fontSize: rs.font(18, min: 15, max: 22),
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
                                      style: GoogleFonts.robotoFlex(
                                        fontSize: rs.font(13, min: 11, max: 15),
                                        color: U.sub,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ).animate()
                          .fadeIn(delay: 500.ms, duration: 500.ms)
                          .slideY(begin: 0.1, end: 0, delay: 500.ms, duration: 500.ms, curve: Curves.easeOutCubic);
                    },
                  ),

                  SizedBox(height: rs.vs(120, min: 90, max: 140)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PressableCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;

  const PressableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.965,
  });

  @override
  Widget build(BuildContext context) {
    return M3Pressable(
      onTap: onTap,
      scaleFactor: scaleFactor,
      child: child,
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
      builder: (context, _) {
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
