import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'firebase_options.dart';

import 'services/cache_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'services/platform_support.dart';
import 'screens/app_shell.dart';
import 'screens/join_class_screen.dart';
import 'screens/university_selection_screen.dart';
import 'services/focus_supabase_service.dart';

import 'screens/event_details_screen.dart';
import 'services/event_service.dart';
import 'theme/m3_expressive_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final Future<AppInitializationState> appInitialization;
SupabaseClient get supabase => Supabase.instance.client;

class AppInitializationState {
  const AppInitializationState({
    required this.firebaseReady,
    this.blockingMessage,
  });

  final bool firebaseReady;
  final String? blockingMessage;
}

class AppTheme {
  const AppTheme({
    required this.key,
    required this.label,
    required this.description,
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.card,
    required this.border,
    required this.text,
    required this.sub,
    required this.dim,
    required this.primary,
    required this.teal,
    required this.red,
    required this.green,
    required this.peach,
    required this.blue,
    required this.gold,
    required this.sky,
    required this.lavender,
    required this.gray,
    required this.mdH1,
    required this.mdH2,
    required this.mdH3,
    required this.mdBold,
    required this.mdItalic,
    required this.mdCode,
    required this.mdLink,
    required this.mdBlockquote,
    required this.mdDel,
    required this.mermaidPrimary,
    required this.mermaidBackground,
    required this.mermaidLine,
  });

  final String key;
  final String label;
  final String description;
  final bool isDark;
  final Color bg;
  final Color surface;
  final Color card;
  final Color border;
  final Color text;
  final Color sub;
  final Color dim;
  final Color primary;
  final Color teal;
  final Color red;
  final Color green;
  final Color peach;
  final Color blue;
  final Color gold;
  final Color sky;
  final Color lavender;
  final Color gray;
  final Color mdH1;
  final Color mdH2;
  final Color mdH3;
  final Color mdBold;
  final Color mdItalic;
  final Color mdCode;
  final Color mdLink;
  final Color mdBlockquote;
  final Color mdDel;
  final String mermaidPrimary;
  final String mermaidBackground;
  final String mermaidLine;

  ColorScheme get colorScheme {
    return M3ThemeFactory.createColorScheme(
      seedColor: primary,
      isDark: isDark,
      surfaceBackground: bg,
      customSurface: surface,
      customCard: card,
      customPrimary: primary,
      customSecondary: teal,
      customText: text,
      customSub: sub,
    );
  }
}

const _primaryLightTheme = AppTheme(
  key: 'primary-light',
  label: 'Utopia Light',
  description: 'Sage green Material 3 Expressive daylight',
  isDark: false,
  bg: Color(0xFFFAF9F6),
  surface: Color(0xFFF2F1EC),
  card: Color(0xFFFFFFFF),
  border: Color(0xFFE2DFD6),
  text: Color(0xFF191C16),
  sub: Color(0xFF44483E),
  dim: Color(0xFF656B5D),
  primary: Color(0xFF435E32),
  teal: Color(0xFF336055),
  red: Color(0xFFBA1A1A),
  green: Color(0xFF2C6B38),
  peach: Color(0xFF8C5312),
  blue: Color(0xFF1F5F8B),
  gold: Color(0xFF7A5900),
  sky: Color(0xFF146A80),
  lavender: Color(0xFF5B5480),
  gray: Color(0xFF5F6559),
  mdH1: Color(0xFF191C16),
  mdH2: Color(0xFF191C16),
  mdH3: Color(0xFF435E32),
  mdBold: Color(0xFF191C16),
  mdItalic: Color(0xFF44483E),
  mdCode: Color(0xFF435E32),
  mdLink: Color(0xFF1F5F8B),
  mdBlockquote: Color(0xFF44483E),
  mdDel: Color(0xFF656B5D),
  mermaidPrimary: '#435E32',
  mermaidBackground: '#F2F1EC',
  mermaidLine: '#191C16',
);

const _primaryDarkTheme = AppTheme(
  key: 'primary-dark',
  label: 'Utopia Dark',
  description: 'Deep sage velvet midnight',
  isDark: true,
  bg: Color(0xFF11140E),
  surface: Color(0xFF191C16),
  card: Color(0xFF20241C),
  border: Color(0xFF383D32),
  text: Color(0xFFE2E3D8),
  sub: Color(0xFFC4C8BA),
  dim: Color(0xFF9AA090),
  primary: Color(0xFFB2D097),
  teal: Color(0xFF9ED0C5),
  red: Color(0xFFFFB4AB),
  green: Color(0xFFB2D097),
  peach: Color(0xFFFFB870),
  blue: Color(0xFFA0D0CF),
  gold: Color(0xFFE8D068),
  sky: Color(0xFFA0D0CF),
  lavender: Color(0xFFCCC5F5),
  gray: Color(0xFF9AA090),
  mdH1: Color(0xFFE2E3D8),
  mdH2: Color(0xFFE2E3D8),
  mdH3: Color(0xFFC4C8BA),
  mdBold: Color(0xFFE2E3D8),
  mdItalic: Color(0xFFC4C8BA),
  mdCode: Color(0xFFB2D097),
  mdLink: Color(0xFFB2D097),
  mdBlockquote: Color(0xFFC4C8BA),
  mdDel: Color(0xFF9AA090),
  mermaidPrimary: '#B2D097',
  mermaidBackground: '#20241C',
  mermaidLine: '#E2E3D8',
);

const _mintLightTheme = AppTheme(
  key: 'mint-light',
  label: 'Mint Light',
  description: 'Crisp and refreshing minty whites',
  isDark: false,
  bg: Color(0xFFF2FBF7),
  surface: Color(0xFFE4F4EC),
  card: Color(0xFFFFFFFF),
  border: Color(0xFFBEE0D0),
  text: Color(0xFF163828),
  sub: Color(0xFF355C47),
  dim: Color(0xFF527A64),
  primary: Color(0xFF0F7655),
  teal: Color(0xFF0D6B58),
  red: Color(0xFFC52828),
  green: Color(0xFF1B7A38),
  peach: Color(0xFFB04D08),
  blue: Color(0xFF165F9E),
  gold: Color(0xFF8A5D00),
  sky: Color(0xFF0F6880),
  lavender: Color(0xFF654999),
  gray: Color(0xFF52685C),
  mdH1: Color(0xFF0F7655),
  mdH2: Color(0xFF0D6B58),
  mdH3: Color(0xFF654999),
  mdBold: Color(0xFFB04D08),
  mdItalic: Color(0xFF1B7A38),
  mdCode: Color(0xFFC52828),
  mdLink: Color(0xFF165F9E),
  mdBlockquote: Color(0xFF355C47),
  mdDel: Color(0xFF527A64),
  mermaidPrimary: '#0F7655',
  mermaidBackground: '#E4F4EC',
  mermaidLine: '#163828',
);

const _orchidTheme = AppTheme(
  key: 'orchid',
  label: 'Orchid',
  description: 'Soft purple with warm undertones',
  isDark: true,
  bg: Color(0xFF0F0F17),
  surface: Color(0xFF1A1A27),
  card: Color(0xFF222234),
  border: Color(0xFF32324D),
  text: Color(0xFFECECF6),
  sub: Color(0xFFB0B0CE),
  dim: Color(0xFF8888AA),
  primary: Color(0xFFCBA6F7),
  teal: Color(0xFF94E2D5),
  red: Color(0xFFF38BA8),
  green: Color(0xFFA6E3A1),
  peach: Color(0xFFFAB387),
  blue: Color(0xFF89B4FA),
  gold: Color(0xFFF9E2AF),
  sky: Color(0xFF89DCEB),
  lavender: Color(0xFFB4BEFE),
  gray: Color(0xFFA6ADC8),
  mdH1: Color(0xFFCBA6F7),
  mdH2: Color(0xFF94E2D5),
  mdH3: Color(0xFFB4BEFE),
  mdBold: Color(0xFFFAB387),
  mdItalic: Color(0xFFA6E3A1),
  mdCode: Color(0xFFF38BA8),
  mdLink: Color(0xFF89B4FA),
  mdBlockquote: Color(0xFFCBA6F7),
  mdDel: Color(0xFF8888AA),
  mermaidPrimary: '#CBA6F7',
  mermaidBackground: '#222234',
  mermaidLine: '#ECECF6',
);

const _oneLightTheme = AppTheme(
  key: 'one-light',
  label: 'One Light',
  description: 'Atom inspired daylight',
  isDark: false,
  bg: Color(0xFFFAFAFA),
  surface: Color(0xFFF0F0F1),
  card: Color(0xFFFFFFFF),
  border: Color(0xFFDCDCE0),
  text: Color(0xFF24272E),
  sub: Color(0xFF4F525D),
  dim: Color(0xFF6B6E7B),
  primary: Color(0xFF2F65E2),
  teal: Color(0xFF0075A8),
  red: Color(0xFFCA2518),
  green: Color(0xFF2C7D2B),
  peach: Color(0xFFAC5B00),
  blue: Color(0xFF2F65E2),
  gold: Color(0xFF8E5C00),
  sky: Color(0xFF0075A8),
  lavender: Color(0xFF8B1989),
  gray: Color(0xFF5C5F6C),
  mdH1: Color(0xFF2F65E2),
  mdH2: Color(0xFF0075A8),
  mdH3: Color(0xFF8B1989),
  mdBold: Color(0xFFAC5B00),
  mdItalic: Color(0xFF2C7D2B),
  mdCode: Color(0xFFCA2518),
  mdLink: Color(0xFF2F65E2),
  mdBlockquote: Color(0xFF4F525D),
  mdDel: Color(0xFF6B6E7B),
  mermaidPrimary: '#2F65E2',
  mermaidBackground: '#F0F0F1',
  mermaidLine: '#24272E',
);

const _gruvboxTheme = AppTheme(
  key: 'gruvbox',
  label: 'Gruvbox',
  description: 'Retro warmth with dark background',
  isDark: true,
  bg: Color(0xFF1D2021),
  surface: Color(0xFF282828),
  card: Color(0xFF32302F),
  border: Color(0xFF49433F),
  text: Color(0xFFFBF1C7),
  sub: Color(0xFFD5C4A1),
  dim: Color(0xFFA89984),
  primary: Color(0xFFFE8019),
  teal: Color(0xFF8EC07C),
  red: Color(0xFFFB4934),
  green: Color(0xFFB8BB26),
  peach: Color(0xFFFE8019),
  blue: Color(0xFF83A598),
  gold: Color(0xFFFABD2F),
  sky: Color(0xFF8EC07C),
  lavender: Color(0xFFD3869B),
  gray: Color(0xFFA89984),
  mdH1: Color(0xFFFE8019),
  mdH2: Color(0xFF8EC07C),
  mdH3: Color(0xFF83A598),
  mdBold: Color(0xFFFABD2F),
  mdItalic: Color(0xFFB8BB26),
  mdCode: Color(0xFFFB4934),
  mdLink: Color(0xFF83A598),
  mdBlockquote: Color(0xFFFE8019),
  mdDel: Color(0xFFA89984),
  mermaidPrimary: '#FE8019',
  mermaidBackground: '#32302F',
  mermaidLine: '#FBF1C7',
);

const _catppuccinLatteTheme = AppTheme(
  key: 'catppuccin-latte',
  label: 'Catppuccin Latte',
  description: 'Soft daylight with balanced contrast',
  isDark: false,
  bg: Color(0xFFF4F6FA),
  surface: Color(0xFFE9ECF2),
  card: Color(0xFFFFFFFF),
  border: Color(0xFFD0D5E0),
  text: Color(0xFF303446),
  sub: Color(0xFF51576D),
  dim: Color(0xFF6C7086),
  primary: Color(0xFF721DE0),
  teal: Color(0xFF0B7075),
  red: Color(0xFFB80B2E),
  green: Color(0xFF287C17),
  peach: Color(0xFFB84500),
  blue: Color(0xFF1453C9),
  gold: Color(0xFF8F5800),
  sky: Color(0xFF0072A3),
  lavender: Color(0xFF4F5FD4),
  gray: Color(0xFF6C7086),
  mdH1: Color(0xFF721DE0),
  mdH2: Color(0xFF0B7075),
  mdH3: Color(0xFF4F5FD4),
  mdBold: Color(0xFFB84500),
  mdItalic: Color(0xFF287C17),
  mdCode: Color(0xFFB80B2E),
  mdLink: Color(0xFF1453C9),
  mdBlockquote: Color(0xFF51576D),
  mdDel: Color(0xFF6C7086),
  mermaidPrimary: '#721DE0',
  mermaidBackground: '#E9ECF2',
  mermaidLine: '#303446',
);

const _everforestTheme = AppTheme(
  key: 'everforest',
  label: 'Everforest',
  description: 'Low contrast forest theme',
  isDark: true,
  bg: Color(0xFF1E2326),
  surface: Color(0xFF272E33),
  card: Color(0xFF323B40),
  border: Color(0xFF465259),
  text: Color(0xFFE4D5B7),
  sub: Color(0xFFBDC3C7),
  dim: Color(0xFF909D96),
  primary: Color(0xFFA7C080),
  teal: Color(0xFF83C092),
  red: Color(0xFFE67E80),
  green: Color(0xFFA7C080),
  peach: Color(0xFFE69875),
  blue: Color(0xFF7FBBB3),
  gold: Color(0xFFDBBC7F),
  sky: Color(0xFF7FBBB3),
  lavender: Color(0xFFD699B6),
  gray: Color(0xFF909D96),
  mdH1: Color(0xFFA7C080),
  mdH2: Color(0xFF83C092),
  mdH3: Color(0xFF7FBBB3),
  mdBold: Color(0xFFE69875),
  mdItalic: Color(0xFFA7C080),
  mdCode: Color(0xFFE67E80),
  mdLink: Color(0xFF7FBBB3),
  mdBlockquote: Color(0xFFA7C080),
  mdDel: Color(0xFF909D96),
  mermaidPrimary: '#A7C080',
  mermaidBackground: '#323B40',
  mermaidLine: '#E4D5B7',
);

const _rosePineDawnTheme = AppTheme(
  key: 'rose-pine-dawn',
  label: 'Rosé Pine Dawn',
  description: 'Warm pastel light theme',
  isDark: false,
  bg: Color(0xFFFAF4ED),
  surface: Color(0xFFF2E9E1),
  card: Color(0xFFFFFFFF),
  border: Color(0xFFDECFC2),
  text: Color(0xFF3F3B59),
  sub: Color(0xFF575279),
  dim: Color(0xFF6E6A86),
  primary: Color(0xFF9E3853),
  teal: Color(0xFF1D5A72),
  red: Color(0xFF9E3853),
  green: Color(0xFF1D5A72),
  peach: Color(0xFFA15900),
  blue: Color(0xFF1D5A72),
  gold: Color(0xFFA15900),
  sky: Color(0xFF1E6C7A),
  lavender: Color(0xFF664F82),
  gray: Color(0xFF6E6A86),
  mdH1: Color(0xFF9E3853),
  mdH2: Color(0xFF1E6C7A),
  mdH3: Color(0xFF664F82),
  mdBold: Color(0xFFA15900),
  mdItalic: Color(0xFF1D5A72),
  mdCode: Color(0xFF9E3853),
  mdLink: Color(0xFF1E6C7A),
  mdBlockquote: Color(0xFF575279),
  mdDel: Color(0xFF6E6A86),
  mermaidPrimary: '#9E3853',
  mermaidBackground: '#F2E9E1',
  mermaidLine: '#3F3B59',
);

const _githubDarkTheme = AppTheme(
  key: 'github-dark',
  label: 'GitHub Dark',
  description: 'GitHub dark mode inspired',
  isDark: true,
  bg: Color(0xFF0D1117),
  surface: Color(0xFF161B22),
  card: Color(0xFF21262D),
  border: Color(0xFF363C45),
  text: Color(0xFFF0F6FC),
  sub: Color(0xFF8B949E),
  dim: Color(0xFF6E7681),
  primary: Color(0xFF58A6FF),
  teal: Color(0xFF3FB950),
  red: Color(0xFFF85149),
  green: Color(0xFF56D364),
  peach: Color(0xFFF0883E),
  blue: Color(0xFF58A6FF),
  gold: Color(0xFFE3B341),
  sky: Color(0xFF79C0FF),
  lavender: Color(0xFFBC8CFF),
  gray: Color(0xFF8B949E),
  mdH1: Color(0xFF58A6FF),
  mdH2: Color(0xFF3FB950),
  mdH3: Color(0xFFBC8CFF),
  mdBold: Color(0xFFF0883E),
  mdItalic: Color(0xFF56D364),
  mdCode: Color(0xFFF85149),
  mdLink: Color(0xFF58A6FF),
  mdBlockquote: Color(0xFF8B949E),
  mdDel: Color(0xFF6E7681),
  mermaidPrimary: '#58A6FF',
  mermaidBackground: '#21262D',
  mermaidLine: '#F0F6FC',
);

const appThemes = [
  _primaryLightTheme,
  _primaryDarkTheme,
  _mintLightTheme,
  _orchidTheme,
  _oneLightTheme,
  _gruvboxTheme,
  _catppuccinLatteTheme,
  _everforestTheme,
  _rosePineDawnTheme,
  _githubDarkTheme,
];

final ValueNotifier<AppTheme> appThemeNotifier = ValueNotifier<AppTheme>(
  _primaryLightTheme,
);


final ValueNotifier<bool> morningNotifEnabledNotifier = ValueNotifier<bool>(true);
final ValueNotifier<int> appLoadingCounter = ValueNotifier<int>(0);

void _applySystemUiForTheme(AppTheme theme) {
  final usesLightIcons = theme.isDark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          usesLightIcons ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          usesLightIcons ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: theme.surface,
      systemNavigationBarIconBrightness:
          usesLightIcons ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}

void showAppLoading() {
  appLoadingCounter.value = appLoadingCounter.value + 1;
}

void hideAppLoading() {
  if (appLoadingCounter.value > 0) {
    appLoadingCounter.value = appLoadingCounter.value - 1;
  }
}

class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appLoadingCounter,
      builder: (context, count, _) {
        return Stack(
          children: [
            child,
            if (count > 0)
              Positioned.fill(
                child: Container(
                  color: U.bg.withValues(alpha: 0.85),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: U.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: U.border),
                        boxShadow: [
                          BoxShadow(
                            color: U.primary.withValues(alpha: 0.15),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: U.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading...',
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AppAccentStyle {
  const AppAccentStyle({
    required this.key,
    required this.label,
    required this.primary,
  });

  final String key;
  final String label;
  final Color primary;
}

Future<AppInitializationState> _initializeApp() async {
  if (PlatformSupport.isWindows) {
    return const AppInitializationState(
      firebaseReady: false,
      blockingMessage:
          'Windows support is only partially configured. Add a Windows Firebase app and a desktop authentication flow before signing in on Windows.',
    );
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (PlatformSupport.supportsNotifications) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      unawaited(NotificationService.initialize());
    }

    // Initialize global Supabase in the background (used by notes, events, etc.)
    unawaited(() async {
      try {
        final doc = await FirebaseFirestore.instance.collection('config').doc('supabase').get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final url = data['url'] as String?;
          final anonKey = data['anon_key'] as String?;
          if (url != null && anonKey != null) {
            await Supabase.initialize(url: url, anonKey: anonKey);
            debugPrint('Supabase Init: Initialized global Supabase with URL: $url');
          } else {
            debugPrint('Supabase config missing url or anon_key');
          }
        } else {
          debugPrint('Supabase config document not found');
        }
      } catch (e) {
        debugPrint('Failed to initialize Supabase: $e');
      }
    }());

    // Initialize Focus Supabase in the background
    unawaited(FocusSupabaseService().initialize());

    return const AppInitializationState(firebaseReady: true);
  } catch (e) {
    return AppInitializationState(
      firebaseReady: false,
      blockingMessage:
          'Firebase failed to initialize on this platform. Check the desktop Firebase configuration before building for Windows.',
    );
  }
}

String? _initialAccentKey;

Future<String?> _loadInitialAccent() async {
  final cached = await CacheService().getAppSetting('theme_accent');
  return cached;
}

Future<void> _loadAppToggleSettings() async {

  final cachedMorning = await CacheService().getAppSetting('morning_notif_enabled');
  if (cachedMorning != null) {
    morningNotifEnabledNotifier.value = cachedMorning == 'true';
  }

  final cachedUniId = await CacheService().getAppSetting('cached_university_id');
  if (cachedUniId != null) {
    U.cachedUniversityId = cachedUniId;
  }
  final cachedUniName = await CacheService().getAppSetting('cached_university_name');
  if (cachedUniName != null) {
    U.cachedUniversityName = cachedUniName;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  _initialAccentKey = await _loadInitialAccent();
  U.applyTheme(_initialAccentKey);
  await _loadAppToggleSettings();
  appInitialization = _initializeApp();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _applySystemUiForTheme(appThemeNotifier.value);
  runApp(const UtopiaApp());
}

class U {
  static String cachedUniversityId = '';
  static String cachedUniversityName = '';

  static ColorScheme get colorScheme => appThemeNotifier.value.colorScheme;
  static ColorScheme scheme(BuildContext context) => Theme.of(context).colorScheme;

  static Color get bg => appThemeNotifier.value.bg;
  static Color get surface => appThemeNotifier.value.surface;
  static Color get card => appThemeNotifier.value.card;
  static Color get border => appThemeNotifier.value.border;
  static Color get text => appThemeNotifier.value.text;
  static Color get sub => appThemeNotifier.value.sub;
  static Color get dim => appThemeNotifier.value.dim;
  static Color get primary => appThemeNotifier.value.primary;
  static Color get teal => appThemeNotifier.value.teal;
  static Color get red => appThemeNotifier.value.red;
  static Color get green => appThemeNotifier.value.green;
  static Color get peach => appThemeNotifier.value.peach;
  static Color get blue => appThemeNotifier.value.blue;
  static Color get gold => appThemeNotifier.value.gold;
  static Color get sky => appThemeNotifier.value.sky;
  static Color get lavender => appThemeNotifier.value.lavender;
  static Color get gray => appThemeNotifier.value.gray;

  static Color get surfaceContainerLowest => appThemeNotifier.value.colorScheme.surfaceContainerLowest;
  static Color get surfaceContainerLow => appThemeNotifier.value.surface;
  static Color get surfaceContainer => appThemeNotifier.value.card;
  static Color get surfaceContainerHigh => appThemeNotifier.value.colorScheme.surfaceContainerHigh;
  static Color get surfaceContainerHighest => appThemeNotifier.value.colorScheme.surfaceContainerHighest;
  static Color get primaryContainer => appThemeNotifier.value.colorScheme.primaryContainer;
  static Color get onPrimaryContainer => appThemeNotifier.value.colorScheme.onPrimaryContainer;
  static Color get secondaryContainer => appThemeNotifier.value.colorScheme.secondaryContainer;
  static Color get onSecondaryContainer => appThemeNotifier.value.colorScheme.onSecondaryContainer;
  static Color get outlineVariant => appThemeNotifier.value.border;

  static Color getContrastColor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF11140E);
  }

  static Color get mdH1 => appThemeNotifier.value.mdH1;
  static Color get mdH2 => appThemeNotifier.value.mdH2;
  static Color get mdH3 => appThemeNotifier.value.mdH3;
  static Color get mdBold => appThemeNotifier.value.mdBold;
  static Color get mdItalic => appThemeNotifier.value.mdItalic;
  static Color get mdCode => appThemeNotifier.value.mdCode;
  static Color get mdLink => appThemeNotifier.value.mdLink;
  static Color get mdBlockquote => appThemeNotifier.value.mdBlockquote;
  static Color get mdDel => appThemeNotifier.value.mdDel;

  static String get mermaidPrimary => appThemeNotifier.value.mermaidPrimary;
  static String get mermaidBackground =>
      appThemeNotifier.value.mermaidBackground;
  static String get mermaidLine => appThemeNotifier.value.mermaidLine;

  static String get currentThemeKey => appThemeNotifier.value.key;


  static bool get morningNotifEnabled => morningNotifEnabledNotifier.value;
  static AppTheme themeForKey(String? key) {
    for (final theme in appThemes) {
      if (theme.key == key) {
        return theme;
      }
    }
    return _primaryLightTheme;
  }

  static void applyTheme(String? key) {
    final next = themeForKey(key);
    if (appThemeNotifier.value.key == next.key) {
      return;
    }
    appThemeNotifier.value = next;
  }

  static String sanitizeDisplayName(String? name) {
    var clean = (name ?? '').trim();
    if (clean.isEmpty) return 'Student';
    if (clean.contains('@')) {
      final prefix = clean.split('@').first.trim();
      if (prefix.isEmpty) return 'Student';
      clean = prefix.replaceAll('.', ' ').replaceAll('_', ' ');
    }

    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'Student';

    // Deduplicate identical consecutive words (e.g. "25B11CE107 25B11CE107" -> "25B11CE107")
    final deduplicated = <String>[];
    for (final word in words) {
      if (deduplicated.isEmpty || deduplicated.last.toLowerCase() != word.toLowerCase()) {
        deduplicated.add(word);
      }
    }

    return deduplicated.map((word) {
      if (word.length <= 1) return word.toUpperCase();
      // If it looks like a roll number / alphanumeric ID (e.g. 25B11CE107), keep uppercase
      if (RegExp(r'^\d+[a-zA-Z]+\d+').hasMatch(word)) return word.toUpperCase();
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  static void showSnackBar(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle_rounded,
    Color? iconColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E222B).withValues(alpha: 0.94)
                    : const Color(0xFFFFFFFF).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: iconColor ?? (isDark ? const Color(0xFF08BB68) : const Color(0xFF059669)),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : const Color(0xFF191C16),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String sanitizeDisplayName(String? name) => U.sanitizeDisplayName(name);

class UtopiaApp extends StatelessWidget {
  const UtopiaApp({super.key});

  static String sanitizeDisplayName(String? name) => U.sanitizeDisplayName(name);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, _) {
        final colorScheme = theme.colorScheme;
        final m3Theme = M3ThemeFactory.createThemeData(
          colorScheme: colorScheme,
          text: theme.text,
          sub: theme.sub,
          border: theme.border,
        );

        return MaterialApp(
          title: 'UTOPIA',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: m3Theme,
          home: const AppLoadingOverlay(child: AuthGate()),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final Future<AppInitializationState> _appInit = appInitialization;
  bool _greetingCyclePassed = false;

  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.setAppForeground(true);

    _initDeepLinks();
    Future.delayed(SplashScreen.minimumDisplayDuration, () {
      if (mounted) {
        setState(() => _greetingCyclePassed = true);
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.setAppForeground(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationService.setAppForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      unawaited(() async {
        final init = await _appInit;
        if (init.firebaseReady) {
          await ChatService().touchPresence();
        }
      }());
      if (PlatformSupport.supportsNotifications) {
        unawaited(NotificationService.refreshTokenRegistration());
      }
    }
  }



  void _initDeepLinks() {
    final appLinks = AppLinks();
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });
    _linkSub = appLinks.uriLinkStream.listen(_handleLink);
  }

  void _handleLink(Uri uri) {
    String? classCode;
    String? eventId;

    // Handle class join links: https://classes.inferalis.space/join/CODE or utopia://join/CODE
    if (uri.path.startsWith('/join/')) {
      classCode = uri.pathSegments.last;
    } else if (uri.scheme == 'utopia' && uri.host == 'join') {
      classCode = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }

    // Handle event links: https://events.inferalis.space/eventID or utopia://event/eventID
    if (uri.host == 'events.inferalis.space' || uri.path.startsWith('/event/')) {
      eventId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
    } else if (uri.scheme == 'utopia' && uri.host == 'event') {
      eventId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (uri.host == 'events.inferalis.space' && uri.path.isNotEmpty) {
      eventId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }

    if (classCode != null && classCode.isNotEmpty) {
      // Wait for navigator to be ready, then push the join screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => JoinClassScreen(classCode: classCode!),
            ),
          );
        }
      });
    } else if (eventId != null && eventId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final nav = navigatorKey.currentState;
        if (nav != null) {
          try {
            // Show dynamic feedback/dialog or direct navigation
            final event = await EventService.instance.getEvent(eventId!);
            if (event != null) {
              nav.push(
                MaterialPageRoute(
                  builder: (_) => EventDetailsScreen(event: event),
                ),
              );
            }
          } catch (e) {
            debugPrint('Failed to load deep-linked event: $e');
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppInitializationState>(
      future: _appInit,
      builder: (context, initSnapshot) {
        if (initSnapshot.connectionState != ConnectionState.done ||
            !_greetingCyclePassed) {
          return const SplashScreen();
        }
        final initState =
            initSnapshot.data ??
            const AppInitializationState(firebaseReady: false);
        if (!initState.firebaseReady) {
          return _PlatformSetupScreen(
            message:
                initState.blockingMessage ??
                'This platform is not configured for UTOPIA yet.',
          );
        }


        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SplashScreen();
            }
            if (snapshot.hasData) {
              unawaited(ChatService().touchPresence());
              if (PlatformSupport.supportsNotifications) {

              }
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(snapshot.data!.uid)
                    .snapshots(),
                builder: (context, userSnapshot) {
                  final themeAccent =
                      userSnapshot.data?.data()?['themeAccent'] as String?;
                  if (themeAccent != null) {
                    unawaited(
                      CacheService().saveAppSetting(
                        'theme_accent',
                        themeAccent,
                      ),
                    );
                  }

                  final selectedUniversityId = 
                      userSnapshot.data?.data()?['selectedUniversityId'] as String?;

                  if (userSnapshot.connectionState == ConnectionState.active && 
                      selectedUniversityId == null) {
                    return const UniversitySelectionScreen();
                  }

                  if (selectedUniversityId != null && selectedUniversityId.isNotEmpty) {
                    U.cachedUniversityId = selectedUniversityId;
                    unawaited(
                      CacheService().saveAppSetting(
                        'cached_university_id',
                        selectedUniversityId,
                      ),
                    );
                  }

                  return const AppShell();
                },
              );
            }
            U.applyTheme(null);
            return const LoginScreen();
          },
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const greetings = ['Hello', 'నమస్కారం', 'नमस्ते', 'こんにちは', '안녕하세요'];
  static const greetingStepDelay = Duration(milliseconds: 65);
  static const greetingAnimDuration = Duration(milliseconds: 45);
  static Duration get minimumDisplayDuration {
    final transitions = greetings.length - 1;
    final perTransition =
        greetingStepDelay.inMilliseconds +
        (greetingAnimDuration.inMilliseconds * 2);
    return Duration(milliseconds: transitions * perTransition);
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  int _idx = 0;
  late AnimationController _ac;
  late Animation<double> _fade;
  late Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: SplashScreen.greetingAnimDuration,
    );
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeInOut);
    _slide = Tween<double>(
      begin: 6,
      end: 0,
    ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ac.forward();
    _cycle();
  }

  Future<void> _cycle() async {
    for (int i = 1; i < SplashScreen.greetings.length; i++) {
      await Future.delayed(SplashScreen.greetingStepDelay);
      if (!mounted) return;
      await _ac.reverse();
      setState(() => _idx = i);
      await _ac.forward();
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      body: Stack(
        children: [
          // ── Content ──
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _ac,
                  builder: (context, _) => Opacity(
                    opacity: _fade.value,
                    child: Transform.translate(
                      offset: Offset(0, _slide.value),
                      child: Text(
                        SplashScreen.greetings[_idx],
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 42,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          color: U.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'UTOPIA',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: U.sub,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 48),
                AnimatedBuilder(
                  animation: _ac,
                  builder: (context, _) {
                    return Container(
                      width: 4 + (20 * _fade.value),
                      height: 4,
                      decoration: BoxDecoration(
                        color: U.primary.withValues(alpha: 0.5 + (0.5 * _fade.value)),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  Future<void> _signIn() async {
    if (!PlatformSupport.supportsGoogleSignIn) {
      setState(() {
        _error =
            'Google sign-in is not available on Windows in this build. Add a desktop auth flow before shipping the Windows app.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '402670858978-94eqn0qvvrtv59ijne3hn1g5flr4ahve.apps.googleusercontent.com',
      );
      final user = await GoogleSignIn.instance.authenticate();
      final auth = user.authentication;
      final cred = GoogleAuthProvider.credential(idToken: auth.idToken);
      final credential = await FirebaseAuth.instance.signInWithCredential(cred);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user?.uid)
          .set({
            'displayName': credential.user?.displayName ?? '',
            'email': credential.user?.email ?? '',
            'photoUrl': credential.user?.photoURL,
            'lastSeen': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      setState(() {
        _error = 'Sign-in failed. Please try again.';
        _loading = false;
      });
    }
  }

  void _showAdminLoginDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool dialogLoading = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: !_loading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: U.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Admin Login',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: U.text,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter administrator email and password to log in.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: U.sub,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: U.text),
                    decoration: InputDecoration(
                      hintText: 'Admin Email',
                      hintStyle: TextStyle(color: U.dim),
                      filled: true,
                      fillColor: U.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: U.border, width: 0.8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: U.border, width: 0.8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: U.primary, width: 1.2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: TextStyle(color: U.text),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: TextStyle(color: U.dim),
                      filled: true,
                      fillColor: U.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: U.border, width: 0.8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: U.border, width: 0.8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: U.primary, width: 1.2),
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: GoogleFonts.outfit(
                        color: U.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.outfit(
                      color: U.sub,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: dialogLoading
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          final password = passwordController.text.trim();
                          if (email.isEmpty || password.isEmpty) {
                            setDialogState(() {
                              dialogError = 'Email and password cannot be empty.';
                            });
                            return;
                          }
                          setDialogState(() {
                            dialogLoading = true;
                            dialogError = null;
                          });
                          try {
                            final credential = await FirebaseAuth.instance
                                .signInWithEmailAndPassword(
                              email: email,
                              password: password,
                            );
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(credential.user?.uid)
                                .set({
                              'displayName': credential.user?.displayName ?? email.split('@')[0],
                              'email': credential.user?.email ?? email,
                              'photoUrl': credential.user?.photoURL,
                              'lastSeen': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() {
                                dialogLoading = false;
                                dialogError = 'Login failed: ${e.toString().split(']').last.trim()}';
                              });
                            }
                          }
                        },
                  child: dialogLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: U.primary,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Login',
                          style: GoogleFonts.outfit(
                            color: U.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 4),
              GestureDetector(
                onTap: () {
                  final now = DateTime.now();
                  if (_lastLogoTap == null || now.difference(_lastLogoTap!) < const Duration(seconds: 2)) {
                    _logoTapCount++;
                  } else {
                    _logoTapCount = 1;
                  }
                  _lastLogoTap = now;

                  if (_logoTapCount >= 5) {
                    _logoTapCount = 0;
                    _showAdminLoginDialog();
                  }
                },
                child: Text(
                  'UTOPIA',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    color: U.primary,
                    fontStyle: FontStyle.italic,
                    height: 1,
                    letterSpacing: -1,
                    shadows: [
                      Shadow(
                        color: U.primary.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.15, end: 0, duration: 600.ms, curve: Curves.easeOut),
              const SizedBox(height: 10),
              Text(
                'The Productivity Platform',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: U.sub,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 600.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.15, end: 0, delay: 200.ms, duration: 600.ms, curve: Curves.easeOut),
              const Spacer(flex: 3),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: U.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: U.red.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.outfit(
                      color: U.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Animated container for the button state
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: U.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _loading || !PlatformSupport.supportsGoogleSignIn
                      ? null
                      : _signIn,
                  child: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: U.bg,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _GoogleIcon(),
                            const SizedBox(width: 12),
                            Text(
                              PlatformSupport.supportsGoogleSignIn
                                  ? 'Continue with Google'
                                  : 'Google sign-in unavailable',
                            ),
                          ],
                        ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 600.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.15, end: 0, delay: 400.ms, duration: 600.ms, curve: Curves.easeOut),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Designed by Inferno',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: U.dim,
                    letterSpacing: 0.5,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 600.ms, duration: 600.ms),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformSetupScreen extends StatelessWidget {
  const _PlatformSetupScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: U.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: U.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Windows Setup Needed',
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: GoogleFonts.outfit(
                        color: U.sub,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Current blockers: Firebase desktop config, desktop login, and push notifications.',
                      style: GoogleFonts.outfit(
                        color: U.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0; // scale factor from 24x24 viewBox

    // Blue
    final bluePath = Path()
      ..moveTo(22.56 * s, 12.25 * s)
      ..cubicTo(22.56 * s, 11.47 * s, 22.49 * s, 10.72 * s, 22.36 * s, 10.0 * s)
      ..lineTo(12.0 * s, 10.0 * s)
      ..lineTo(12.0 * s, 14.26 * s)
      ..lineTo(17.92 * s, 14.26 * s)
      ..cubicTo(17.66 * s, 15.63 * s, 16.88 * s, 16.79 * s, 15.71 * s, 17.57 * s)
      ..lineTo(15.71 * s, 20.34 * s)
      ..lineTo(19.28 * s, 20.34 * s)
      ..cubicTo(21.36 * s, 18.42 * s, 22.56 * s, 15.6 * s, 22.56 * s, 12.25 * s)
      ..close();
    canvas.drawPath(bluePath, Paint()..color = const Color(0xFF4285F4));

    // Green
    final greenPath = Path()
      ..moveTo(12.0 * s, 23.0 * s)
      ..cubicTo(14.97 * s, 23.0 * s, 17.46 * s, 22.02 * s, 19.28 * s, 20.34 * s)
      ..lineTo(15.71 * s, 17.57 * s)
      ..cubicTo(14.73 * s, 18.23 * s, 13.48 * s, 18.63 * s, 12.0 * s, 18.63 * s)
      ..cubicTo(9.14 * s, 18.63 * s, 6.71 * s, 16.69 * s, 5.84 * s, 14.09 * s)
      ..lineTo(2.18 * s, 14.09 * s)
      ..lineTo(2.18 * s, 16.94 * s)
      ..cubicTo(3.99 * s, 20.53 * s, 7.7 * s, 23.0 * s, 12.0 * s, 23.0 * s)
      ..close();
    canvas.drawPath(greenPath, Paint()..color = const Color(0xFF34A853));

    // Yellow
    final yellowPath = Path()
      ..moveTo(5.84 * s, 14.09 * s)
      ..cubicTo(5.62 * s, 13.43 * s, 5.49 * s, 12.73 * s, 5.49 * s, 12.0 * s)
      ..cubicTo(5.49 * s, 11.27 * s, 5.62 * s, 10.57 * s, 5.84 * s, 9.91 * s)
      ..lineTo(5.84 * s, 7.06 * s)
      ..lineTo(2.18 * s, 7.06 * s)
      ..cubicTo(1.43 * s, 8.55 * s, 1.0 * s, 10.22 * s, 1.0 * s, 12.0 * s)
      ..cubicTo(1.0 * s, 13.78 * s, 1.43 * s, 15.45 * s, 2.18 * s, 16.94 * s)
      ..lineTo(5.84 * s, 14.09 * s)
      ..close();
    canvas.drawPath(yellowPath, Paint()..color = const Color(0xFFFBBC05));

    // Red
    final redPath = Path()
      ..moveTo(12.0 * s, 5.38 * s)
      ..cubicTo(13.62 * s, 5.38 * s, 15.06 * s, 5.94 * s, 16.21 * s, 7.02 * s)
      ..lineTo(19.36 * s, 3.87 * s)
      ..cubicTo(17.45 * s, 2.09 * s, 14.97 * s, 1.0 * s, 12.0 * s, 1.0 * s)
      ..cubicTo(7.7 * s, 1.0 * s, 3.99 * s, 3.47 * s, 2.18 * s, 7.06 * s)
      ..lineTo(5.84 * s, 9.91 * s)
      ..cubicTo(6.71 * s, 7.31 * s, 9.14 * s, 5.38 * s, 12.0 * s, 5.38 * s)
      ..close();
    canvas.drawPath(redPath, Paint()..color = const Color(0xFFEA4335));
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;
}
