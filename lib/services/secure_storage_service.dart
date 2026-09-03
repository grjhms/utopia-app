import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageService {
  static const String _rollKey = 'attendance_roll';
  static const String _passwordKey = 'attendance_pwd';
  static const String _collegeKey = 'college';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _googleAccessTokenKey = 'google_calendar_access_token';
  static const String _googleRefreshTokenKey = 'google_calendar_refresh_token';
  static const String _googleTokenExpiryKey = 'google_calendar_token_expiry';

  static Future<void> saveCredentials(
    String rollNumber,
    String password,
    String college,
  ) async {
    final cleanRoll = rollNumber.trim();
    // 1. Write to FlutterSecureStorage
    try {
      await _storage.write(key: _rollKey, value: cleanRoll);
      await _storage.write(key: _passwordKey, value: password);
      await _storage.write(key: _collegeKey, value: college);
    } catch (e) {
      debugPrint('SecureStorageService: storage write error: $e');
    }

    // 2. Hard persistence backup in SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rollKey, cleanRoll);
      await prefs.setString(_passwordKey, password);
      await prefs.setString(_collegeKey, college);
    } catch (e) {
      debugPrint('SecureStorageService: prefs write error: $e');
    }
  }

  static Future<Map<String, String>?> getCredentials() async {
    String? rollNumber;
    String? password;
    String? college;

    // 1. Try FlutterSecureStorage first
    try {
      rollNumber = await _storage.read(key: _rollKey);
      password = await _storage.read(key: _passwordKey);
      college = await _storage.read(key: _collegeKey);
    } catch (e) {
      debugPrint('SecureStorageService: storage read error: $e');
    }

    // 2. Fallback to SharedPreferences if secure storage returned null or errored
    if (rollNumber == null || password == null || rollNumber.isEmpty || password.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        rollNumber = prefs.getString(_rollKey);
        password = prefs.getString(_passwordKey);
        college = prefs.getString(_collegeKey);
      } catch (e) {
        debugPrint('SecureStorageService: prefs read error: $e');
      }
    }

    if (rollNumber == null || password == null || rollNumber.isEmpty || password.isEmpty) {
      return null;
    }

    return {
      'rollNumber': rollNumber,
      'password': password,
      'college': college ?? 'aus',
    };
  }

  static Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _rollKey);
      await _storage.delete(key: _passwordKey);
      await _storage.delete(key: _collegeKey);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_rollKey);
      await prefs.remove(_passwordKey);
      await prefs.remove(_collegeKey);
    } catch (_) {}
  }

  static Future<void> saveGoogleTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    await _storage.write(key: _googleAccessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _googleRefreshTokenKey, value: refreshToken);
    }
    if (expiry != null) {
      await _storage.write(
        key: _googleTokenExpiryKey,
        value: expiry.millisecondsSinceEpoch.toString(),
      );
    }
  }

  static Future<String?> getGoogleAccessToken() async {
    return await _storage.read(key: _googleAccessTokenKey);
  }

  static Future<String?> getGoogleRefreshToken() async {
    return await _storage.read(key: _googleRefreshTokenKey);
  }

  static Future<DateTime?> getGoogleTokenExpiry() async {
    final val = await _storage.read(key: _googleTokenExpiryKey);
    if (val == null) return null;
    final ms = int.tryParse(val);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> clearGoogleTokens() async {
    await _storage.delete(key: _googleAccessTokenKey);
    await _storage.delete(key: _googleRefreshTokenKey);
    await _storage.delete(key: _googleTokenExpiryKey);
  }
}
