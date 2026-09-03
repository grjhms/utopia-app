import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// IMAGE OVERLAY COLORS
/// ─────────────────────────────────────────────────────────────────────────────
/// Colors for ALL text that sits on or near the background image:
///   • title    → "Utopia" / "University" / "Semesters"
///   • subtitle → tagline below title
///   • greeting → "Good morning, Name"  (sits in gradient transition zone)
///   • quote    → motivational text below greeting
/// ─────────────────────────────────────────────────────────────────────────────

class ImageOverlayColors {
  // ── Utopia Light ── (primary-light)
  static const _primaryLight = {
    'morning':   _Quad(Color(0xFF1A1A1A), Color(0xFF4A4A4A), Color(0xFF1A1A1A), Color(0xFF4A4A4A)),
    'afternoon': _Quad(Color(0xFF1A1A1A), Color(0xFF4A4A4A), Color(0xFF1A1A1A), Color(0xFF4A4A4A)),
    'evening':   _Quad(Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0xFFFFFFFF), Color(0xDDFFFFFF)),
    'night':     _Quad(Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0xFFFFFFFF), Color(0xDDFFFFFF)),
  };

  // ── Utopia Dark ── (primary-dark)
  static const _primaryDark = {
    'morning':   _Quad(Color(0xFF121212), Color(0xFF4C4C4C), Color(0xFF121212), Color(0xFF4C4C4C)),
    'afternoon': _Quad(Color(0xFF121212), Color(0xFF4C4C4C), Color(0xFF121212), Color(0xFF4C4C4C)),
    'evening':   _Quad(Color(0xFFFBFBFA), Color(0xCCFBFBFA), Color(0xFFFBFBFA), Color(0xDDFBFBFA)),
    'night':     _Quad(Color(0xFFFBFBFA), Color(0xCCFBFBFA), Color(0xFFFBFBFA), Color(0xDDFBFBFA)),
  };

  // ── Catppuccin Latte ── (light theme)
  static const _catppuccinLatte = {
    'morning':   _Quad(Color(0xFF211047), Color(0xFF141438), Color(0xFF110826), Color(0xFF1F0F42)),
    'afternoon': _Quad(Color(0xFF211047), Color(0xFF141438), Color(0xFF110826), Color(0xFF1F0F42)),
    'evening':   _Quad(Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0xFFFFFFFF), Color(0xDDFFFFFF)),
    'night':     _Quad(Color(0xFFEFF1F5), Color(0xCCDCE0E8), Color(0xFFEFF1F5), Color(0xDDCCD0DA)),
  };

  // ── Rosé Pine Dawn ── (light theme)
  static const _rosePineDawn = {
    'morning':   _Quad(Color(0xFF8F2A43), Color(0xFF191724), Color(0xFF191724), Color(0xFF191724)),
    'afternoon': _Quad(Color(0xFF8F2A43), Color(0xFF191724), Color(0xFF191724), Color(0xFF191724)),
    'evening':   _Quad(Color(0xFFFFF4F2), Color(0xCCFFF4F2), Color(0xFFFFF4F2), Color(0xDDFFF4F2)),
    'night':     _Quad(Color(0xFFFFF4F2), Color(0xCCFFF4F2), Color(0xFFFFF4F2), Color(0xDDFFF4F2)),
  };

  // ── Mint Light ── (light theme)
  static const _mintLight = {
    'morning':   _Quad(Color(0xFF072B1F), Color(0xFF0C2B22), Color(0xFF021A12), Color(0xFF043022)),
    'afternoon': _Quad(Color(0xFF072B1F), Color(0xFF0C2B22), Color(0xFF021A12), Color(0xFF043022)),
    'evening':   _Quad(Color(0xFFE5F5ED), Color(0xCCE5F5ED), Color(0xFFE5F5ED), Color(0xDDE5F5ED)),
    'night':     _Quad(Color(0xFFE5F5ED), Color(0xCCE5F5ED), Color(0xFFE5F5ED), Color(0xDDE5F5ED)),
  };

  // ── One Light ── (light theme)
  static const _oneLight = {
    'morning':   _Quad(Color(0xFF0D2554), Color(0xFF2A2B33), Color(0xFF0A0C14), Color(0xFF2A2B33)),
    'afternoon': _Quad(Color(0xFF0D2554), Color(0xFF1F1F1F), Color(0xFF0A0C14), Color(0xFF1F1F1F)),
    'evening':   _Quad(Color(0xFFFAFAFA), Color(0xCCFAFAFA), Color(0xFFFAFAFA), Color(0xDDFAFAFA)),
    'night':     _Quad(Color(0xFFFAFAFA), Color(0xCCFAFAFA), Color(0xFFFAFAFA), Color(0xDDFAFAFA)),
  };

  // ── Orchid ── (dark theme)
  static const _orchid = {
    'morning':   _Quad(Color(0xFFECECF6), Color(0xCCB0B0CE), Color(0xFFCBA6F7), Color(0xDDECECF6)),
    'afternoon': _Quad(Color(0xFFECECF6), Color(0xCCB0B0CE), Color(0xFFCBA6F7), Color(0xDDECECF6)),
    'evening':   _Quad(Color(0xFFCBA6F7), Color(0xCCE8E8F0), Color(0xFFCBA6F7), Color(0xDDE8E8F0)),
    'night':     _Quad(Color(0xFFCBA6F7), Color(0xCCE8E8F0), Color(0xFFCBA6F7), Color(0xDDE8E8F0)),
  };

  // ── Gruvbox ── (dark theme)
  static const _gruvbox = {
    'morning':   _Quad(Color(0xFFFBF1C7), Color(0xCCD5C4A1), Color(0xFFFE8019), Color(0xDDFBF1C7)),
    'afternoon': _Quad(Color(0xFFFBF1C7), Color(0xCCD5C4A1), Color(0xFFFE8019), Color(0xDDFBF1C7)),
    'evening':   _Quad(Color(0xFFFE8019), Color(0xCCEBDBB2), Color(0xFFFE8019), Color(0xDDEBDBB2)),
    'night':     _Quad(Color(0xFFFE8019), Color(0xCCEBDBB2), Color(0xFFFE8019), Color(0xDDEBDBB2)),
  };

  // ── Everforest ── (dark theme)
  static const _everforest = {
    'morning':   _Quad(Color(0xFFE4D5B7), Color(0xCCBDC3C7), Color(0xFFA7C080), Color(0xDDE4D5B7)),
    'afternoon': _Quad(Color(0xFFE4D5B7), Color(0xCCBDC3C7), Color(0xFFA7C080), Color(0xDDE4D5B7)),
    'evening':   _Quad(Color(0xFFA7C080), Color(0xCCD5C4A1), Color(0xFFA7C080), Color(0xDDD5C4A1)),
    'night':     _Quad(Color(0xFFA7C080), Color(0xCCD5C4A1), Color(0xFFA7C080), Color(0xDDD5C4A1)),
  };

  // ── GitHub Dark ── (dark theme)
  static const _githubDark = {
    'morning':   _Quad(Color(0xFFF0F6FC), Color(0xCC8B949E), Color(0xFF58A6FF), Color(0xDDF0F6FC)),
    'afternoon': _Quad(Color(0xFFF0F6FC), Color(0xCC8B949E), Color(0xFF58A6FF), Color(0xDDF0F6FC)),
    'evening':   _Quad(Color(0xFF58A6FF), Color(0xCCC9D1D9), Color(0xFF58A6FF), Color(0xDDC9D1D9)),
    'night':     _Quad(Color(0xFF58A6FF), Color(0xCCC9D1D9), Color(0xFF58A6FF), Color(0xDDC9D1D9)),
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Lookup helpers
  // ─────────────────────────────────────────────────────────────────────────

  static const _map = {
    'primary-light':    _primaryLight,
    'primary-dark':     _primaryDark,
    'catppuccin-latte': _catppuccinLatte,
    'rose-pine-dawn':   _rosePineDawn,
    'mint-light':       _mintLight,
    'one-light':        _oneLight,
    'orchid':           _orchid,
    'gruvbox':          _gruvbox,
    'everforest':       _everforest,
    'github-dark':      _githubDark,
  };

  static String getTimeSlot() {
    final time = DateTime.now().hour + DateTime.now().minute / 60.0;
    if (time >= 5.0 && time < 11.5) {
      return 'morning';
    } else if (time >= 11.5 && time < 16.0) {
      return 'afternoon';
    } else if (time >= 16.0 && time < 20.0) {
      return 'evening';
    } else {
      return 'night';
    }
  }

  /// Title color for text overlaid on the background image.
  static Color titleColor(String themeKey, [String? timeSlot]) {
    final slot = timeSlot ?? getTimeSlot();
    return _map[themeKey]?[slot]?.title ?? const Color(0xFFFFFFFF);
  }

  /// Subtitle/tagline color for text overlaid on the background image.
  static Color subtitleColor(String themeKey, [String? timeSlot]) {
    final slot = timeSlot ?? getTimeSlot();
    return _map[themeKey]?[slot]?.subtitle ?? const Color(0xCCFFFFFF);
  }

  /// Greeting color ("Good morning, Name").
  static Color? greetingColor(String themeKey, [String? timeSlot]) {
    final slot = timeSlot ?? getTimeSlot();
    return _map[themeKey]?[slot]?.greeting;
  }

  /// Quote/motivational text color.
  static Color? quoteColor(String themeKey, [String? timeSlot]) {
    final slot = timeSlot ?? getTimeSlot();
    return _map[themeKey]?[slot]?.quote;
  }
}

/// Holds four colors: title, subtitle, greeting, quote.
class _Quad {
  final Color title;
  final Color subtitle;
  final Color? greeting;
  final Color? quote;
  const _Quad(this.title, this.subtitle, this.greeting, this.quote);
}
