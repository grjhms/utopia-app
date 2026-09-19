import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';

import 'attendance_cache_service.dart';
import 'attendance_service.dart';

class AecAttendanceService {
  static const String _portalHost = 'info.aec.edu.in';
  static const String _aesSecret = '8701661282118308';
  static String _prefix = '/acet';
  static String get _loginPath => '$_prefix/default.aspx';
  static String get _studentMasterPath => '$_prefix/StudentMaster.aspx';
  static String get _attendancePagePath =>
      '$_prefix/Academics/StudentAttendance.aspx?scrid=3&showtype=SA';
  static String get _attendancePath =>
      '$_prefix/Academics/studentattendance.aspx/ShowAttendance';
  static String get _ajaxJsPath => '$_prefix/JSFiles/AjaxMethods.js';
  static String get _authCheckPath => '$_prefix/authcheck.aspx';
  static String get _marksPath =>
      '$_prefix/Academics/StudentMarksReport.aspx?scrid=15';

  static const Duration _timeout = Duration(seconds: 20);
  static String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; vivo I2305) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/123.0.0.0 Mobile Safari/537.36';
  static const bool _isReleaseBuild = kReleaseMode;

  static String formatPortalDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day-$month-$year';
  }

  static DateTime todayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime yesterdayLocal() {
    return todayLocal().subtract(const Duration(days: 1));
  }

  static DateTime parsePortalDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]) ?? 1;
      final month = int.tryParse(parts[1]) ?? 1;
      final year = int.tryParse(parts[2]) ?? DateTime.now().year;
      return DateTime(year, month, day);
    }
    return todayLocal();
  }

  static final RegExp _hiddenInputPattern = RegExp(
    r'''<input\s+([^>]*?)>''',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _inputNameAttrPattern = RegExp(
    r'''name\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );

  static final RegExp _inputIdAttrPattern = RegExp(
    r'''id\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );

  static final RegExp _inputTypeAttrPattern = RegExp(
    r'''type\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );

  static final RegExp _inputValueAttrPattern = RegExp(
    r'''value\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );

  static final RegExp _textInputPattern = RegExp(
    r'''<input\s+[^>]*type\s*=\s*["']text["'][^>]*>''',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _passwordInputPattern = RegExp(
    r'''<input\s+[^>]*type\s*=\s*["']password["'][^>]*>''',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _loginUserFieldPattern = RegExp(
    r'''(id|name)\s*=\s*["'](txtid2|txtuserid)["']''',
  );
  static final RegExp _loginPasswordFieldPattern = RegExp(
    r'''(id|name)\s*=\s*["'](txtpwd2|txtpassword)["']''',
  );
  static final List<RegExp> _webMethodTokenPatterns = [
    RegExp(r"var\s+_tkn\s*=\s*'([^']+)'"),
    RegExp(r'var\s+_tkn\s*=\s*"([^"]+)"'),
    RegExp(r"""['"]_tkn['"]\s*:\s*'([^']+)'"""),
    RegExp(r'''['"]_tkn['"]\s*:\s*"([^"]+)"'''),
  ];

  static final List<RegExp> _genericTokenPatterns = [
    RegExp(r"var\s+token\s*=\s*'([^']+)'", caseSensitive: false),
    RegExp(r'var\s+token\s*=\s*"([^"]+)"', caseSensitive: false),
    RegExp(r'var\s+authToken\s*=\s*"([^"]+)"', caseSensitive: false),
    RegExp(r"var\s+authToken\s*=\s*'([^']+)'", caseSensitive: false),
    RegExp(r'var\s+_token\s*=\s*"([^"]+)"', caseSensitive: false),
    RegExp(r"var\s+_token\s*=\s*'([^']+)'", caseSensitive: false),
    RegExp(r'var\s+tkn\s*=\s*"([^"]+)"', caseSensitive: false),
    RegExp(r"var\s+tkn\s*=\s*'([^']+)'", caseSensitive: false),
  ];

  static final RegExp _scriptSrcPattern = RegExp(
    r'''<script[^>]+src\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  static final RegExp _hiddenInputTokenPattern = RegExp(
    r'''<input\s+[^>]*type\s*=\s*["']hidden["'][^>]*>''',
    caseSensitive: false,
    dotAll: true,
  );

  static String _generateTraceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = Random().nextInt(999).toString().padLeft(3, '0');
    return '${timestamp.substring(timestamp.length - 6)}_$random';
  }

  static String _scrubSensitive(String body) {
    var scrubbed = body;
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'__VIEWSTATE[^>]*value="([^"]{0,80})"'),
      (m) => '__VIEWSTATE value="<redacted>"',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'__VIEWSTATE[^>]*value="([^"]{80,})"'),
      (m) => '__VIEWSTATE value="<redacted>"',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'__EVENTVALIDATION[^>]*value="([^"]{0,80})"'),
      (m) => '__EVENTVALIDATION value="<redacted>"',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'__EVENTVALIDATION[^>]*value="([^"]{80,})"'),
      (m) => '__EVENTVALIDATION value="<redacted>"',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'__VIEWSTATEGENERATOR[^>]*value="([^"]{0,80})"'),
      (m) => '__VIEWSTATEGENERATOR value="<redacted>"',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'value="[^"]{80,}"'),
      (m) => 'value="<redacted>"',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'ASP\.NET_SessionId=[^;]{1,};'),
      (m) => 'ASP.NET_SessionId=<redacted>;',
    );
    scrubbed = scrubbed.replaceAllMapped(
      RegExp(r'[A-Za-z0-9+/]{100,}={0,2}'),
      (m) => '<base64-ish-redacted>',
    );
    return scrubbed;
  }

  static String _truncateLocation(String? location) {
    if (location == null || location.isEmpty) return '-';
    if (location.length <= 120) return location;
    return '${location.substring(0, 117)}...';
  }

  static Map<String, String> _parseHiddenFormFields(
    String html,
    String traceId,
  ) {
    final hiddenFields = <String, String>{};
    final matches = _hiddenInputPattern.allMatches(html);

    for (final match in matches) {
      final inputTag = match.group(1) ?? '';

      final typeMatch = _inputTypeAttrPattern.firstMatch(inputTag);
      final type = typeMatch?.group(1)?.toLowerCase() ?? 'text';

      if (type != 'hidden') continue;

      String? name;
      final nameMatch = _inputNameAttrPattern.firstMatch(inputTag);
      if (nameMatch != null) {
        name = nameMatch.group(1);
      }

      String key;
      if (name != null && name.isNotEmpty) {
        key = name;
      } else {
        final idMatch = _inputIdAttrPattern.firstMatch(inputTag);
        if (idMatch != null) {
          key = idMatch.group(1) ?? '';
        } else {
          continue;
        }
      }

      if (key.isEmpty) continue;

      final valueMatch = _inputValueAttrPattern.firstMatch(inputTag);
      final value = valueMatch?.group(1) ?? '';

      hiddenFields[key] = value;
    }

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print(
        '[$traceId][PARSE] hiddenFields: count=${hiddenFields.length} '
        'keys=[${hiddenFields.keys.join(", ")}]',
      );
    }

    return hiddenFields;
  }

  static _LoginFieldNames _detectLoginFieldNames(String html, String traceId) {
    String? userFieldName;
    String? passwordFieldName;
    String? submitButtonName;
    String? submitButtonValue;
    bool hasHdnPwd = false;

    final textInputs = _textInputPattern.allMatches(html).toList();
    for (final match in textInputs) {
      final inputTag = match.group(0) ?? '';

      String? name;
      final nameMatch = _inputNameAttrPattern.firstMatch(inputTag);
      if (nameMatch != null) name = nameMatch.group(1);

      String? id;
      final idMatch = _inputIdAttrPattern.firstMatch(inputTag);
      if (idMatch != null) id = idMatch.group(1);

      final fieldName = name ?? id ?? '';

      if (fieldName.isEmpty) continue;

      final lower = fieldName.toLowerCase();
      if (lower.contains('user') ||
          lower.contains('id') ||
          lower.contains('roll') ||
          lower.contains('login')) {
        if (userFieldName == null) {
          userFieldName = fieldName;
        }
      }
    }

    final passwordInputs = _passwordInputPattern.allMatches(html).toList();
    for (final match in passwordInputs) {
      final inputTag = match.group(0) ?? '';

      String? name;
      final nameMatch = _inputNameAttrPattern.firstMatch(inputTag);
      if (nameMatch != null) name = nameMatch.group(1);

      String? id;
      final idMatch = _inputIdAttrPattern.firstMatch(inputTag);
      if (idMatch != null) id = idMatch.group(1);

      final fieldName = name ?? id ?? '';

      if (fieldName.isEmpty) continue;

      final lower = fieldName.toLowerCase();
      if (lower.contains('pwd') ||
          lower.contains('password') ||
          lower.contains('pass')) {
        if (passwordFieldName == null) {
          passwordFieldName = fieldName;
        }
      }
    }

    final submitPattern = RegExp(
      r'''<input\s+[^>]*type\s*=\s*["']submit["'][^>]*>''',
      caseSensitive: false,
      dotAll: true,
    );
    final submitMatches = submitPattern.allMatches(html).toList();
    for (final match in submitMatches) {
      final inputTag = match.group(0) ?? '';

      final nameMatch = _inputNameAttrPattern.firstMatch(inputTag);
      if (nameMatch != null) {
        submitButtonName = nameMatch.group(1);
      }

      final valueMatch = _inputValueAttrPattern.firstMatch(inputTag);
      if (valueMatch != null) {
        submitButtonValue = valueMatch.group(1);
      }

      break;
    }

    if (html.contains('hdnpwd') || html.contains('hdnpwd')) {
      hasHdnPwd = true;
    }

    final fallbackUserField = userFieldName ?? 'txtId2';
    final fallbackPasswordField = passwordFieldName ?? 'txtPwd2';
    final fallbackButtonName = submitButtonName ?? 'btnLogin';
    final fallbackButtonValue = submitButtonValue ?? 'LOGIN';

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print(
        '[$traceId][PARSE] detectedFields: '
        'userField=$userFieldName ($fallbackUserField), '
        'passwordField=$passwordFieldName ($fallbackPasswordField), '
        'buttonName=$submitButtonName, '
        'buttonValue=$submitButtonValue, '
        'hasHdnPwd=$hasHdnPwd',
      );
    }

    return _LoginFieldNames(
      userFieldName: userFieldName,
      passwordFieldName: passwordFieldName,
      submitButtonName: submitButtonName,
      submitButtonValue: submitButtonValue,
      hasHdnPwd: hasHdnPwd,
      fallbackUserField: fallbackUserField,
      fallbackPasswordField: fallbackPasswordField,
      fallbackButtonName: fallbackButtonName,
      fallbackButtonValue: fallbackButtonValue,
    );
  }

  static const Set<String> _safeFormKeys = {
    'userType',
    'btnLogin',
    'fromDate',
    'toDate',
    'excludeothersubjects',
  };

  static const Set<String> _redactedFormKeys = {
    'txtPwd2',
    'txtPassword',
    'hdnpwd',
    '__VIEWSTATE',
    '__EVENTVALIDATION',
    '__VIEWSTATEGENERATOR',
  };

  static void _debugRequest({
    required String traceId,
    required String step,
    required String method,
    required String url,
    required String? contentType,
    required int contentLength,
    required bool followRedirects,
    required List<String> cookieKeys,
    required Map<String, String> requestHeaders,
    String? body,
  }) {
    if (_isReleaseBuild) return;

    final safeHeaders = <String, String>{};
    for (final entry in requestHeaders.entries) {
      final keyLower = entry.key.toLowerCase();
      if (keyLower == 'origin' ||
          keyLower == 'referer' ||
          keyLower == 'accept' ||
          keyLower == 'content-type' ||
          keyLower == 'x-requested-with' ||
          keyLower == 'x-auth-token' ||
          keyLower == 'user-agent' ||
          keyLower == 'cache-control' ||
          keyLower == 'pragma') {
        safeHeaders[entry.key] = entry.value;
      }
    }

    String formInfo = '';
    String redactions = '';
    if (body != null && body.isNotEmpty) {
      if (contentType != null &&
          contentType.contains('application/x-www-form-urlencoded')) {
        final params = Uri.splitQueryString(body);
        final allKeys = params.keys.toList();
        final safeKeys = <String>[];
        final redactedEntries = <String>[];

        for (final key in allKeys) {
          if (_safeFormKeys.contains(key)) {
            safeKeys.add(key);
          } else if (_redactedFormKeys.contains(key)) {
            final value = params[key] ?? '';
            if (key == '__VIEWSTATE' ||
                key == '__EVENTVALIDATION' ||
                key == '__VIEWSTATEGENERATOR') {
              redactedEntries.add('$key=len=${value.length}');
            } else {
              redactedEntries.add('$key=<redacted>');
            }
          } else {
            safeKeys.add(key);
          }
        }

        formInfo = 'formKeys=[${allKeys.join(', ')}]';
        if (redactedEntries.isNotEmpty) {
          redactions = ' redacted={${redactedEntries.join(', ')}}';
        }
      } else if (contentType != null &&
          contentType.contains('application/json')) {
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          final keys = json.keys.toList();
          final safeEntries = <String>[];
          final redactedEntries = <String>[];

          for (final key in keys) {
            final value = json[key];
            if (key == 'fromDate' || key == 'toDate') {
              safeEntries.add('$key=${value ?? "null"}');
            } else if (value is String && value.length > 50) {
              redactedEntries.add('$key=len=${value.length}');
            } else {
              safeEntries.add('$key=${value ?? "null"}');
            }
          }

          formInfo = 'jsonKeys=[${keys.join(', ')}]';
          if (safeEntries.isNotEmpty) {
            formInfo += ' values={${safeEntries.join(', ')}}';
          }
          if (redactedEntries.isNotEmpty) {
            redactions = ' redacted={${redactedEntries.join(', ')}}';
          }
        } catch (_) {
          formInfo = 'bodyLen=${body.length}';
        }
      } else {
        formInfo = 'bodyLen=${body.length}';
      }
    }

    // ignore: avoid_print
    print(
      '[$traceId][$step][REQ] method=$method url=$url '
      'contentType=${contentType ?? "-"} contentLen=$contentLength '
      'followRedirects=$followRedirects '
      'cookies=[${cookieKeys.join(', ')}] '
      '$formInfo$redactions',
    );
    if (safeHeaders.isNotEmpty) {
      final headerStr = safeHeaders.entries
          .map((e) => '${e.key}=${e.value}')
          .join(' ');
      // ignore: avoid_print
      print('[$traceId][$step][REQ] headers: $headerStr');
    }
  }

  static void _debugResponseHeaders({
    required String traceId,
    required String step,
    required int statusCode,
    required String? location,
    required List<String> setCookieNames,
    required bool hasSessionId,
    required bool hasFrmAuth,
    required bool hasViewState,
    required bool loginPage,
  }) {
    if (_isReleaseBuild) return;
    // ignore: avoid_print
    print(
      '[$traceId][$step][RES] status=$statusCode '
      'location=${_truncateLocation(location)} '
      'setCookies=[${setCookieNames.join(', ')}] '
      'hasSessionId=$hasSessionId hasFrmAuth=$hasFrmAuth '
      'hasViewState=$hasViewState loginPage=$loginPage',
    );
  }

  static void _debugBrowserParity({
    required String traceId,
    required String step,
    required int? expectedStatus,
    required String? expectedLocation,
    required bool? expectedSetsFrmAuth,
    required int gotStatus,
    required String? gotLocation,
    required bool gotSetsFrmAuth,
    required bool gotLoginPage,
  }) {
    if (_isReleaseBuild) return;
    // ignore: avoid_print
    print(
      '[$traceId][$step][PARITY] expected={status:$expectedStatus, '
      'location:$expectedLocation, setsFrmAuth:$expectedSetsFrmAuth}',
    );
    // ignore: avoid_print
    print(
      '[$traceId][$step][PARITY] got={status:$gotStatus, '
      'location:${_truncateLocation(gotLocation)}, '
      'setsFrmAuth:$gotSetsFrmAuth, loginPage:$gotLoginPage}',
    );

    final mismatches = <String>[];
    if (expectedStatus != null && gotStatus != expectedStatus) {
      mismatches.add('status:$gotStatus != $expectedStatus');
    }
    if (expectedLocation != null &&
        gotLocation != null &&
        gotLocation.contains(expectedLocation) == false) {
      mismatches.add('location mismatch');
    }
    if (expectedSetsFrmAuth != null && gotSetsFrmAuth != expectedSetsFrmAuth) {
      mismatches.add('frmAuth:$gotSetsFrmAuth != $expectedSetsFrmAuth');
    }
    if (mismatches.isNotEmpty) {
      // ignore: avoid_print
      print('[$traceId][$step][PARITY][MISMATCH] ${mismatches.join(', ')}');
    }
  }

  static void _debugPortalHop({
    required String traceId,
    required String step,
    required String method,
    required String path,
    required int statusCode,
    required String? location,
    required Map<String, String> cookies,
    required String? contentType,
    required int elapsedMs,
    required bool hasSessionId,
    required bool hasViewState,
    required bool hasEventValidation,
    required bool hasLoginPageMarkers,
    required String? bodyPreview,
  }) {
    if (_isReleaseBuild) return;
    final cookieKeys = cookies.keys.toList();
    // ignore: avoid_print
    print(
      '[$traceId][$step][${elapsedMs}ms] '
      'method=$method path=$path status=$statusCode '
      'location=${_truncateLocation(location)} '
      'contentType=${contentType ?? "-"} '
      'hasSessionId=$hasSessionId '
      'cookies=[${cookieKeys.join(", ")}] '
      'hasViewState=$hasViewState '
      'hasEventValidation=$hasEventValidation '
      'hasLoginPageMarkers=$hasLoginPageMarkers',
    );
    if (bodyPreview != null && bodyPreview.isNotEmpty) {
      // ignore: avoid_print
      print(
        '[$traceId][$step] bodyPreview: ${bodyPreview.substring(0, min(bodyPreview.length, 400))}',
      );
    }
  }

  static void _debugStep({
    required String traceId,
    required String step,
    required int elapsedMs,
    String? message,
  }) {
    if (_isReleaseBuild) return;
    // ignore: avoid_print
    print('[$traceId][$step][${elapsedMs}ms] ${message ?? "done"}');
  }

  static void _debugLoginMarkers({
    required String traceId,
    required String step,
    required String body,
  }) {
    if (_isReleaseBuild) return;
    final lower = body.toLowerCase();
    final hasUserField = _loginUserFieldPattern.hasMatch(lower);
    final hasPasswordField = _loginPasswordFieldPattern.hasMatch(lower);
    final hasLoginButton =
        lower.contains('btnlogin') || lower.contains('>login<');
    final hasLoginFormAction =
        lower.contains('default.aspx') && lower.contains('<form');
    // ignore: avoid_print
    print(
      '[$traceId][$step] loginMarkers: '
      'hasUserField=$hasUserField '
      'hasPasswordField=$hasPasswordField '
      'hasLoginButton=$hasLoginButton '
      'hasLoginFormAction=$hasLoginFormAction',
    );
  }

  static void _debugFail({
    required String traceId,
    required String step,
    required String reason,
    int? statusCode,
    bool? hasSessionId,
    bool? loginPageDetected,
    bool? hasViewState,
    bool? hasToken,
    String? location,
    List<String>? cookieKeys,
  }) {
    if (_isReleaseBuild) return;
    final parts = <String>['$traceId][$step][FAIL]'];
    parts.add('reason=$reason');
    if (statusCode != null) parts.add('status=$statusCode');
    if (hasSessionId != null) parts.add('session=$hasSessionId');
    if (loginPageDetected != null) parts.add('loginPage=$loginPageDetected');
    if (hasViewState != null) parts.add('hasViewState=$hasViewState');
    if (hasToken != null) parts.add('hasToken=$hasToken');
    if (location != null) parts.add('location=${_truncateLocation(location)}');
    if (cookieKeys != null) parts.add('cookies=[${cookieKeys.join(", ")}]');
    // ignore: avoid_print
    print('[${parts.join(' ')}');
  }

  static void _debugCookieChange({
    required String traceId,
    required String stepA,
    required String stepB,
    required String? sessionIdBefore,
    required String? sessionIdAfter,
  }) {
    if (_isReleaseBuild) return;
    if (sessionIdBefore != sessionIdAfter) {
      // ignore: avoid_print
      print('[$traceId][WARN] sessionId changed between $stepA and $stepB');
    }
  }

  static void _debugTokenExtraction({
    required String traceId,
    required String step,
    required bool hasViewState,
    required bool hasViewStateGenerator,
    required bool hasEventValidation,
    required bool allTokensPresent,
  }) {
    if (_isReleaseBuild) return;
    // ignore: avoid_print
    print(
      '[$traceId][$step] tokens: '
      'hasViewState=$hasViewState '
      'hasViewStateGenerator=$hasViewStateGenerator '
      'hasEventValidation=$hasEventValidation '
      'allPresent=$allTokensPresent',
    );
  }

  static void _debugAttendanceParsing({
    required String traceId,
    required String step,
    required int subjectCount,
    required bool hasReport,
    required bool hasStudentName,
    required String htmlLength,
  }) {
    if (_isReleaseBuild) return;
    // ignore: avoid_print
    print(
      '[$traceId][$step] parsed: '
      'subjects=$subjectCount hasReport=$hasReport '
      'hasStudentName=$hasStudentName htmlLen=$htmlLength',
    );
  }

  static Future<String> _encryptPassword(String password) async {
    final key = encrypt.Key.fromUtf8(_aesSecret);
    final iv = encrypt.IV.fromUtf8(_aesSecret);
    final aes = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    return aes.encrypt(password, iv: iv).base64;
  }

  static Future<String> _getLoginPageHtmlWithGateHandling(
    HttpClient client,
    Map<String, String> cookies,
    String traceId,
  ) async {
    final sw = Stopwatch()..start();

    final initial = await _sendRequest(
      client,
      method: 'GET',
      path: _loginPath,
      cookies: cookies,
      followRedirects: true,
      traceId: traceId,
      stepName: 'GET default.aspx (initial)',
    );
    sw.stop();

    final hasViewState = initial.body.contains('__VIEWSTATE');
    _debugPortalHop(
      traceId: traceId,
      step: 'GET default.aspx (initial)',
      method: 'GET',
      path: _loginPath,
      statusCode: initial.statusCode,
      location: initial.location,
      cookies: cookies,
      contentType: null,
      elapsedMs: sw.elapsedMilliseconds,
      hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
      hasViewState: hasViewState,
      hasEventValidation: initial.body.contains('__EVENTVALIDATION'),
      hasLoginPageMarkers: _looksLikeLoginPage(initial.body),
      bodyPreview: _scrubSensitive(initial.body),
    );
    _debugLoginMarkers(
      traceId: traceId,
      step: 'GET default.aspx (initial)',
      body: initial.body,
    );

    if (hasViewState) {
      return initial.body;
    }

    var swAuthCheck = Stopwatch()..start();
    final authCheck = await _sendRequest(
      client,
      method: 'GET',
      path: _authCheckPath,
      cookies: cookies,
      followRedirects: true,
      traceId: traceId,
      stepName: 'GET authcheck.aspx',
    );
    swAuthCheck.stop();

    _debugPortalHop(
      traceId: traceId,
      step: 'GET authcheck.aspx',
      method: 'GET',
      path: _authCheckPath,
      statusCode: authCheck.statusCode,
      location: authCheck.location,
      cookies: cookies,
      contentType: null,
      elapsedMs: swAuthCheck.elapsedMilliseconds,
      hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
      hasViewState: authCheck.body.contains('__VIEWSTATE'),
      hasEventValidation: authCheck.body.contains('__EVENTVALIDATION'),
      hasLoginPageMarkers: _looksLikeLoginPage(authCheck.body),
      bodyPreview: _scrubSensitive(authCheck.body),
    );

    final previousSessionId = cookies['ASP.NET_SessionId'];
    var swRetry = Stopwatch()..start();
    final retry = await _sendRequest(
      client,
      method: 'GET',
      path: _loginPath,
      cookies: cookies,
      followRedirects: true,
      traceId: traceId,
      stepName: 'GET default.aspx (retry)',
    );
    swRetry.stop();

    _debugCookieChange(
      traceId: traceId,
      stepA: 'GET authcheck.aspx',
      stepB: 'GET default.aspx (retry)',
      sessionIdBefore: previousSessionId,
      sessionIdAfter: cookies['ASP.NET_SessionId'],
    );
    _debugPortalHop(
      traceId: traceId,
      step: 'GET default.aspx (retry)',
      method: 'GET',
      path: _loginPath,
      statusCode: retry.statusCode,
      location: retry.location,
      cookies: cookies,
      contentType: null,
      elapsedMs: swRetry.elapsedMilliseconds,
      hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
      hasViewState: retry.body.contains('__VIEWSTATE'),
      hasEventValidation: retry.body.contains('__EVENTVALIDATION'),
      hasLoginPageMarkers: _looksLikeLoginPage(retry.body),
      bodyPreview: _scrubSensitive(retry.body),
    );
    _debugLoginMarkers(
      traceId: traceId,
      step: 'GET default.aspx (retry)',
      body: retry.body,
    );

    return retry.body;
  }

  static Future<_LoginPageData> _getLoginPageData(
    HttpClient client,
    Map<String, String> cookies,
    String traceId,
  ) async {
    var sw = Stopwatch()..start();
    final html = await _getLoginPageHtmlWithGateHandling(
      client,
      cookies,
      traceId,
    );
    sw.stop();

    final hasViewState = html.contains('__VIEWSTATE');
    final hasViewStateGenerator = html.contains('__VIEWSTATEGENERATOR');
    final hasEventValidation = html.contains('__EVENTVALIDATION');
    _debugTokenExtraction(
      traceId: traceId,
      step: 'Extract tokens',
      hasViewState: hasViewState,
      hasViewStateGenerator: hasViewStateGenerator,
      hasEventValidation: hasEventValidation,
      allTokensPresent:
          hasViewState && hasViewStateGenerator && hasEventValidation,
    );

    final hiddenFields = _parseHiddenFormFields(html, traceId);
    final fieldNames = _detectLoginFieldNames(html, traceId);

    _debugStep(
      traceId: traceId,
      step: 'Parse login page',
      elapsedMs: sw.elapsedMilliseconds,
      message:
          'hiddenFields=${hiddenFields.length}, '
          'userField=${fieldNames.fallbackUserField}, '
          'passwordField=${fieldNames.fallbackPasswordField}',
    );

    return _LoginPageData(
      hiddenFields: hiddenFields,
      fieldNames: fieldNames,
      html: html,
    );
  }

  static Future<void> _login(
    HttpClient client,
    String rollNumber,
    String password,
    Map<String, String> cookies,
    String traceId, {
    bool debugNoRedirect = false,
  }) async {
    try {
      final tokensSw = Stopwatch()..start();
      final pageData = await _getLoginPageData(client, cookies, traceId);
      tokensSw.stop();

      _debugStep(
        traceId: traceId,
        step: '_getLoginPageData',
        elapsedMs: tokensSw.elapsedMilliseconds,
      );

      final encSw = Stopwatch()..start();
      final encryptedPassword = await _encryptPassword(password);
      encSw.stop();

      _debugStep(
        traceId: traceId,
        step: 'Encrypt password',
        elapsedMs: encSw.elapsedMilliseconds,
      );

      final hiddenFields = pageData.hiddenFields;

      final formBody = <String, String>{};

      for (final entry in hiddenFields.entries) {
        formBody[entry.key] = entry.value;
      }

      final hasTabbedLogin = pageData.html.contains('txtId2');
      if (hasTabbedLogin) {
        formBody['txtId1'] = '';
        formBody['txtPwd1'] = '';
        formBody['txtId2'] = rollNumber.trim();
        formBody['txtPwd2'] = encryptedPassword;
        formBody['txtId3'] = '';
        formBody['txtPwd3'] = '';
        if (pageData.html.contains('TextBox1')) {
          formBody['TextBox1'] = '';
        }
        if (hiddenFields.containsKey('hdnpwd1')) {
          formBody['hdnpwd1'] = '';
        }
        if (hiddenFields.containsKey('hdnpwd2')) {
          formBody['hdnpwd2'] = encryptedPassword;
        }
        if (hiddenFields.containsKey('hdnpwd3')) {
          formBody['hdnpwd3'] = '';
        }
        formBody['imgBtn2.x'] = '42';
        formBody['imgBtn2.y'] = '6';
      } else {
        final userField = pageData.fieldNames.userFieldName ??
            pageData.fieldNames.fallbackUserField;
        final pwdField = pageData.fieldNames.passwordFieldName ??
            pageData.fieldNames.fallbackPasswordField;
        formBody[userField] = rollNumber.trim();
        formBody[pwdField] = encryptedPassword;
        if (hiddenFields.containsKey('hdnpwd')) {
          formBody['hdnpwd'] = encryptedPassword;
        }
        final btnName = pageData.fieldNames.submitButtonName ??
            pageData.fieldNames.fallbackButtonName;
        final btnVal = pageData.fieldNames.submitButtonValue ??
            pageData.fieldNames.fallbackButtonValue;
        if (btnName.isNotEmpty) {
          formBody[btnName] = btnVal;
        }
      }

      final formKeys = formBody.keys.toList();
      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][BUILD] formBody: keys=${formKeys.length} '
          'keys=[${formKeys.join(", ")}]',
        );
      }

      final followRedirectsLogin = !debugNoRedirect;

      final postSw = Stopwatch()..start();
      final response = await _sendRequest(
        client,
        method: 'POST',
        path: _loginPath,
        cookies: cookies,
        followRedirects: followRedirectsLogin,
        contentType: 'application/x-www-form-urlencoded',
        body: formBody.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'),
        extraHeaders: {
          'origin': 'https://$_portalHost',
          HttpHeaders.refererHeader: 'https://$_portalHost$_loginPath',
          HttpHeaders.acceptHeader:
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        traceId: traceId,
        stepName: 'POST default.aspx (login)',
      );
      postSw.stop();

      final sessionId = cookies['ASP.NET_SessionId'];
      final bodyLooksLikeLoginPage = _looksLikeLoginPage(response.body);
      final gotFrmAuth = cookies.containsKey('frmAuth');

      _debugBrowserParity(
        traceId: traceId,
        step: 'POST default.aspx (login)',
        expectedStatus: 302,
        expectedLocation: '$_prefix/StudentMaster.aspx',
        expectedSetsFrmAuth: true,
        gotStatus: response.statusCode,
        gotLocation: response.location,
        gotSetsFrmAuth: gotFrmAuth,
        gotLoginPage: bodyLooksLikeLoginPage,
      );

      _debugPortalHop(
        traceId: traceId,
        step: 'POST default.aspx (login)',
        method: 'POST',
        path: _loginPath,
        statusCode: response.statusCode,
        location: response.location,
        cookies: cookies,
        contentType: 'application/x-www-form-urlencoded',
        elapsedMs: postSw.elapsedMilliseconds,
        hasSessionId: sessionId != null && sessionId.isNotEmpty,
        hasViewState: response.body.contains('__VIEWSTATE'),
        hasEventValidation: response.body.contains('__EVENTVALIDATION'),
        hasLoginPageMarkers: bodyLooksLikeLoginPage,
        bodyPreview: _scrubSensitive(response.body),
      );
      _debugLoginMarkers(
        traceId: traceId,
        step: 'POST default.aspx (login)',
        body: response.body,
      );

      final isRedirect =
          response.statusCode == 302 ||
          response.statusCode == 301 ||
          response.statusCode == 303 ||
          response.statusCode == 307;

      final smSw = Stopwatch()..start();
      final studentMaster = await _sendRequest(
        client,
        method: 'GET',
        path: _studentMasterPath,
        cookies: cookies,
        followRedirects: true,
        extraHeaders: {
          HttpHeaders.refererHeader: 'https://$_portalHost$_loginPath',
        },
        traceId: traceId,
        stepName: 'GET StudentMaster.aspx',
      );
      smSw.stop();

      final studentMasterLoginPage = _looksLikeLoginPage(studentMaster.body);

      final loginSuccess = isRedirect || gotFrmAuth || !studentMasterLoginPage;

      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][LOGIN] successCheck: '
          'isRedirect=$isRedirect '
          'gotFrmAuth=$gotFrmAuth '
          'studentMasterLoginPage=$studentMasterLoginPage '
          '-> loginSuccess=$loginSuccess',
        );
      }

      if (!loginSuccess) {
        _debugFail(
          traceId: traceId,
          step: 'POST default.aspx (login)',
          reason: 'Invalid credentials',
          statusCode: response.statusCode,
          hasSessionId: sessionId != null && sessionId.isNotEmpty,
          loginPageDetected: bodyLooksLikeLoginPage,
          hasViewState: response.body.contains('__VIEWSTATE'),
          location: response.location,
          cookieKeys: cookies.keys.toList(),
        );
        throw Exception('Invalid credentials');
      }

      final prevSessionId = sessionId;
      _debugCookieChange(
        traceId: traceId,
        stepA: 'POST default.aspx (login)',
        stepB: 'GET StudentMaster.aspx',
        sessionIdBefore: prevSessionId,
        sessionIdAfter: cookies['ASP.NET_SessionId'],
      );
      _debugPortalHop(
        traceId: traceId,
        step: 'GET StudentMaster.aspx',
        method: 'GET',
        path: _studentMasterPath,
        statusCode: studentMaster.statusCode,
        location: studentMaster.location,
        cookies: cookies,
        contentType: null,
        elapsedMs: smSw.elapsedMilliseconds,
        hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
        hasViewState: studentMaster.body.contains('__VIEWSTATE'),
        hasEventValidation: studentMaster.body.contains('__EVENTVALIDATION'),
        hasLoginPageMarkers: studentMasterLoginPage,
        bodyPreview: _scrubSensitive(studentMaster.body),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      if (e is Exception && e.toString().contains('Invalid credentials')) {
        rethrow;
      }
      throw Exception('Could not sign in to the college portal');
    }
  }

  static Future<Map<String, dynamic>> fetchAttendance(
    String rollNumber,
    String password, {
    String college = 'acet',
    String fromDate = '',
    String toDate = '',
    AttendanceRangeMode mode = AttendanceRangeMode.period,
  }) async {
    _prefix = (college.toLowerCase() == 'aec') ? '/aec' : '/acet';
    final traceId = _generateTraceId();
    final client = HttpClient()..connectionTimeout = _timeout;
    final cookies = <String, String>{};
    final overallSw = Stopwatch()..start();

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print('[$traceId] fetchAttendance started');
    }

    try {
      final loginSw = Stopwatch()..start();
      await _login(client, rollNumber, password, cookies, traceId);
      loginSw.stop();
      _debugStep(
        traceId: traceId,
        step: '_login()',
        elapsedMs: loginSw.elapsedMilliseconds,
      );

      final sm1Sw = Stopwatch()..start();
      final sm1 = await _sendRequest(
        client,
        method: 'GET',
        path: _studentMasterPath,
        cookies: cookies,
        followRedirects: true,
        traceId: traceId,
        stepName: 'GET StudentMaster.aspx (post-login)',
      );
      sm1Sw.stop();
      _debugPortalHop(
        traceId: traceId,
        step: 'GET StudentMaster.aspx (post-login)',
        method: 'GET',
        path: _studentMasterPath,
        statusCode: sm1.statusCode,
        location: sm1.location,
        cookies: cookies,
        contentType: null,
        elapsedMs: sm1Sw.elapsedMilliseconds,
        hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
        hasViewState: sm1.body.contains('__VIEWSTATE'),
        hasEventValidation: sm1.body.contains('__EVENTVALIDATION'),
        hasLoginPageMarkers: _looksLikeLoginPage(sm1.body),
        bodyPreview: _scrubSensitive(sm1.body),
      );

      Map<String, dynamic>? academicInsights;
      try {
        academicInsights = await _fetchAndParseMarks(client, cookies, traceId);
        if (academicInsights != null) {
          unawaited(AttendanceCacheService.saveAcademicInsights(
            rollNumber: rollNumber,
            academicInsights: academicInsights,
          ));
        }
      } catch (e) {
        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print('[$traceId][MARKS] Failed to fetch/parse ACET marks: $e');
        }
      }

      final attPageSw = Stopwatch()..start();
      final attendancePageResponse = await _sendRequest(
        client,
        method: 'GET',
        path: _attendancePagePath,
        cookies: cookies,
        followRedirects: true,
        traceId: traceId,
        stepName: 'GET StudentAttendance.aspx',
      );
      attPageSw.stop();

      _debugPortalHop(
        traceId: traceId,
        step: 'GET StudentAttendance.aspx',
        method: 'GET',
        path: _attendancePagePath,
        statusCode: attendancePageResponse.statusCode,
        location: attendancePageResponse.location,
        cookies: cookies,
        contentType: null,
        elapsedMs: attPageSw.elapsedMilliseconds,
        hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
        hasViewState: attendancePageResponse.body.contains('__VIEWSTATE'),
        hasEventValidation: attendancePageResponse.body.contains(
          '__EVENTVALIDATION',
        ),
        hasLoginPageMarkers: _looksLikeLoginPage(attendancePageResponse.body),
        bodyPreview: null,
      );

      _debugTokenExtractionHints(
        traceId: traceId,
        step: 'Extract web method token',
        html: attendancePageResponse.body,
      );

      final tokenSw = Stopwatch()..start();
      final webMethodToken = await _extractTokenMultiStrategy(
        traceId: traceId,
        client: client,
        cookies: cookies,
        attendancePageHtml: attendancePageResponse.body,
      );
      tokenSw.stop();

      _debugStep(
        traceId: traceId,
        step: 'Extract token (multi-strategy)',
        elapsedMs: tokenSw.elapsedMilliseconds,
        message: 'found=${webMethodToken != null && webMethodToken.isNotEmpty}',
      );

      final hasToken =
          webMethodToken != null && webMethodToken.trim().isNotEmpty;
      if (!hasToken) {
        // ignore: avoid_print
        print('[$traceId][TOKEN] not found; proceeding without x-auth-token');
      }

      final ajaxSw = Stopwatch()..start();
      await _sendRequest(
        client,
        method: 'GET',
        path: _ajaxJsPath,
        cookies: cookies,
        followRedirects: true,
        traceId: traceId,
        stepName: 'GET AjaxMethods.js',
      );
      ajaxSw.stop();
      _debugStep(
        traceId: traceId,
        step: 'GET AjaxMethods.js',
        elapsedMs: ajaxSw.elapsedMilliseconds,
      );

      String formattedFromDate;
      String formattedToDate;

      if (mode == AttendanceRangeMode.tillNow) {
        formattedFromDate = '';
        formattedToDate = '';

        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print('[$traceId][MODE] mode=tillNow from= to= (empty for till now)');
        }
      } else {
        DateTime fromDt;
        DateTime toDt;

        if (fromDate.isEmpty || toDate.isEmpty) {
          fromDt = todayLocal();
          toDt = todayLocal();
        } else {
          fromDt = parsePortalDate(fromDate);
          toDt = parsePortalDate(toDate);
        }

        if (fromDt.isAfter(toDt)) {
          final temp = fromDt;
          fromDt = toDt;
          toDt = temp;
        }

        final today = todayLocal();
        if (toDt.isAfter(today)) {
          toDt = today;
        }

        formattedFromDate = formatPortalDate(fromDt);
        formattedToDate = formatPortalDate(toDt);

        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print(
            '[$traceId][MODE] mode=period from=$formattedFromDate to=$formattedToDate',
          );
        }
      }

      final attendanceBody = jsonEncode({
        'fromDate': formattedFromDate,
        'toDate': formattedToDate,
        'excludeothersubjects': false,
      });

      final extraHeaders = <String, String>{
        'origin': 'https://$_portalHost',
        HttpHeaders.refererHeader: 'https://$_portalHost$_attendancePagePath',
        'x-requested-with': 'XMLHttpRequest',
        HttpHeaders.acceptHeader: 'application/json, text/javascript, */*',
        'cache-control': 'no-cache',
        'pragma': 'no-cache',
      };
      if (hasToken) {
        extraHeaders['x-auth-token'] = webMethodToken;
      }

      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][BUILD] ShowAttendance headers: '
          'origin=https://$_portalHost, '
          'referer=https://$_portalHost$_attendancePagePath, '
          'x-requested-with=XMLHttpRequest, '
          'accept=application/json..., '
          'cache-control=no-cache, pragma=no-cache, '
          'x-auth-token=${hasToken ? 'sent' : 'not sent'}',
        );
      }

      final prevSessionId = cookies['ASP.NET_SessionId'];
      final showAttSw = Stopwatch()..start();
      final response = await _sendRequest(
        client,
        method: 'POST',
        path: _attendancePath,
        cookies: cookies,
        followRedirects: false,
        contentType: 'application/json; charset=UTF-8',
        body: attendanceBody,
        extraHeaders: extraHeaders,
        traceId: traceId,
        stepName: 'POST ShowAttendance',
      );
      showAttSw.stop();

      _debugCookieChange(
        traceId: traceId,
        stepA: 'GET StudentAttendance.aspx',
        stepB: 'POST ShowAttendance',
        sessionIdBefore: prevSessionId,
        sessionIdAfter: cookies['ASP.NET_SessionId'],
      );

      bool isJson = false;
      bool hasKeyD = false;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        isJson = true;
        hasKeyD = decoded.containsKey('d');
      } catch (_) {
        isJson = false;
      }

      final responseContentType = response.headers['content-type'];

      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][POST ShowAttendance][RES] '
          'status=${response.statusCode} '
          'contentType=${responseContentType ?? '-'} '
          'bodyLen=${response.body.length} '
          'isJson=$isJson hasKeyD=$hasKeyD',
        );
        if (response.statusCode != 200) {
          // ignore: avoid_print
          print(
            '[$traceId][POST ShowAttendance][RES] '
            'error preview: ${_scrubSensitive(response.body).substring(0, min(_scrubSensitive(response.body).length, 300))}',
          );
        }
      }

      if (response.statusCode != HttpStatus.ok) {
        _debugFail(
          traceId: traceId,
          step: 'POST ShowAttendance',
          reason: 'Could not fetch attendance',
          statusCode: response.statusCode,
          hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
          hasToken: true,
          location: null,
          cookieKeys: cookies.keys.toList(),
        );
        throw Exception('Could not fetch attendance right now');
      }

      String attendanceHtml;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        attendanceHtml = decoded['d'] as String? ?? '';
      } catch (_) {
        attendanceHtml = response.body;
      }

      final prevSessionId2 = cookies['ASP.NET_SessionId'];
      final parseSw = Stopwatch()..start();
      final parsed = _parseAttendanceHtml(attendanceHtml);
      parseSw.stop();

      _debugCookieChange(
        traceId: traceId,
        stepA: 'POST ShowAttendance',
        stepB: 'Parse attendance HTML',
        sessionIdBefore: prevSessionId2,
        sessionIdAfter: cookies['ASP.NET_SessionId'],
      );

      final subjectCount = (parsed['subjects'] as List).length;
      final hasReport = parsed['hasReport'] as bool? ?? false;
      final hasStudentName = parsed['studentName'] != null;
      _debugAttendanceParsing(
        traceId: traceId,
        step: 'Parse attendance HTML',
        subjectCount: subjectCount,
        hasReport: hasReport,
        hasStudentName: hasStudentName,
        htmlLength: attendanceHtml.length.toString(),
      );

      final totalAttended = parsed['totalAttended'] as int? ?? 0;
      final totalHeld = parsed['totalClasses'] as int? ?? 0;

      if (response.statusCode == 200) {
        if ((parsed['subjects'] as List).isEmpty && !hasReport) {
          if (!_isReleaseBuild) {
            // ignore: avoid_print
            print(
              '[$traceId][WARN] empty report for range '
              '$formattedFromDate to $formattedToDate: '
              'subjects=$subjectCount hasReport=$hasReport',
            );
          }
        } else if (totalAttended == 0 && totalHeld == 0 && subjectCount > 0) {
          if (!_isReleaseBuild) {
            // ignore: avoid_print
            print(
              '[$traceId][WARN] all zeros for range '
              '$formattedFromDate to $formattedToDate: '
              'attended=$totalAttended held=$totalHeld',
            );
          }
        }
      }

      if ((parsed['subjects'] as List).isEmpty && !hasReport) {
        _debugFail(
          traceId: traceId,
          step: 'Parse attendance HTML',
          reason: 'Attendance data was not found',
          statusCode: response.statusCode,
          hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
          hasToken: true,
          cookieKeys: cookies.keys.toList(),
        );
        throw Exception('Attendance data was not found in the portal response');
      }

      overallSw.stop();
      _debugStep(
        traceId: traceId,
        step: 'fetchAttendance()',
        elapsedMs: overallSw.elapsedMilliseconds,
        message: 'success',
      );

      if (academicInsights != null) {
        parsed['academicInsights'] = academicInsights;
      }

      return parsed;
    } on FormatException catch (e) {
      final msg = e.toString();
      if (msg.contains('tokens')) {
        _debugFail(
          traceId: traceId,
          step: 'Extract tokens',
          reason: 'Portal login tokens were not found',
          hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
          cookieKeys: cookies.keys.toList(),
        );
      }
      rethrow;
    } catch (e) {
      if (e is Exception &&
          (e.toString().contains('Invalid credentials') ||
              e.toString().contains('Attendance data was not found') ||
              e.toString().contains('Could not fetch attendance') ||
              e.toString().contains(
                'Failed to retrieve attendance auth token',
              ) ||
              e.toString().contains('tokens were not found'))) {
        rethrow;
      }
      _debugFail(
        traceId: traceId,
        step: 'fetchAttendance()',
        reason: 'Unable to load attendance: ${e.toString()}',
        hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
        cookieKeys: cookies.keys.toList(),
      );
      throw Exception('Unable to load attendance right now');
    } finally {
      client.close(force: true);
    }
  }

  static Future<_PortalResponse> _sendRequest(
    HttpClient client, {
    required String method,
    required String path,
    required Map<String, String> cookies,
    required bool followRedirects,
    String? body,
    String? contentType,
    Map<String, String>? extraHeaders,
    String? traceId,
    String? stepName,
  }) async {
    var currentUri = Uri.parse('https://$_portalHost$path');
    var currentMethod = method;
    var redirectCount = 0;

    while (true) {
      final request = await _openRequest(client, currentMethod, currentUri);
      request.followRedirects = false;

      final requestHeaders = <String, String>{
        'User-Agent': _userAgent,
        'Accept-Language': 'en-IN,en;q=0.9',
      };
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader(cookies));
      }
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
        requestHeaders['Content-Type'] = contentType;
      }
      if (extraHeaders != null) {
        for (final entry in extraHeaders.entries) {
          request.headers.set(entry.key, entry.value);
          requestHeaders[entry.key] = entry.value;
        }
      }
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-IN,en;q=0.9');

      if (body != null) {
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
      }

      if (traceId != null && stepName != null) {
        _debugRequest(
          traceId: traceId,
          step: stepName,
          method: currentMethod,
          url: currentUri.toString(),
          contentType: contentType,
          contentLength: body?.length ?? 0,
          followRedirects: followRedirects,
          cookieKeys: cookies.keys.toList(),
          requestHeaders: requestHeaders,
          body: body,
        );
      }

      final response = await request.close().timeout(_timeout);
      final responseBody = await _readResponseBody(response);

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          responseHeaders[name] = values.first;
        }
      });

      final previousCookies = Map<String, String>.from(cookies);
      _captureCookies(response.cookies, cookies);

      final setCookieNames = response.cookies.map((c) => c.name).toList();
      final hasNewSessionId =
          !previousCookies.containsKey('ASP.NET_SessionId') &&
          cookies.containsKey('ASP.NET_SessionId');
      final hasNewFrmAuth =
          !previousCookies.containsKey('frmAuth') &&
          cookies.containsKey('frmAuth');

      if (traceId != null && stepName != null) {
        _debugResponseHeaders(
          traceId: traceId,
          step: stepName,
          statusCode: response.statusCode,
          location: response.headers.value(HttpHeaders.locationHeader),
          setCookieNames: setCookieNames,
          hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
          hasFrmAuth: cookies.containsKey('frmAuth'),
          hasViewState: responseBody.contains('__VIEWSTATE'),
          loginPage: _looksLikeLoginPage(responseBody),
        );
        if (hasNewSessionId) {
          // ignore: avoid_print
          print('[$traceId][$stepName][NEW] ASP.NET_SessionId was set');
        }
        if (hasNewFrmAuth) {
          // ignore: avoid_print
          print('[$traceId][$stepName][NEW] frmAuth was set');
        }
      }

      if (!followRedirects || !_isRedirect(response.statusCode)) {
        return _PortalResponse(
          statusCode: response.statusCode,
          body: responseBody,
          location: response.headers.value(HttpHeaders.locationHeader),
          headers: responseHeaders,
        );
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        return _PortalResponse(
          statusCode: response.statusCode,
          body: responseBody,
          headers: responseHeaders,
        );
      }
      if (redirectCount >= 8) {
        if (traceId != null) {
          _debugFail(
            traceId: traceId,
            step: stepName ?? 'HTTP redirect',
            reason: 'Portal redirected too many times',
            statusCode: response.statusCode,
            hasSessionId: cookies.containsKey('ASP.NET_SessionId'),
            location: location,
            cookieKeys: cookies.keys.toList(),
          );
        }
        throw Exception('Portal redirected too many times');
      }

      if (traceId != null && stepName != null) {
        // ignore: avoid_print
        print(
          '[$traceId][$stepName][REDIRECT] '
          'count=$redirectCount -> ${_truncateLocation(location)}',
        );
      }

      currentUri = currentUri.resolve(location);
      currentMethod = 'GET';
      body = null;
      contentType = null;
      redirectCount += 1;
    }
  }

  static Future<HttpClientRequest> _openRequest(
    HttpClient client,
    String method,
    Uri uri,
  ) {
    switch (method.toUpperCase()) {
      case 'POST':
        return client.postUrl(uri);
      case 'GET':
        return client.getUrl(uri);
      default:
        return client.getUrl(uri);
    }
  }

  static bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.movedTemporarily ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  static void _captureCookies(
    List<Cookie> responseCookies,
    Map<String, String> cookies,
  ) {
    for (final cookie in responseCookies) {
      cookies[cookie.name] = cookie.value;
    }
  }

  static String _cookieHeader(Map<String, String> cookies) {
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static Map<String, dynamic> _parseAttendanceHtml(String html) {
    final subjects = <Map<String, dynamic>>[];
    int? totalHeldFromReport;
    int? totalAttendedFromReport;
    double? totalPercentageFromReport;
    var hasReport = false;

    String tableHtml = html;
    final tblReportMatch = RegExp(
      r'''<table[^>]*id=["']tblReport["'][^>]*>(.*?)</table>''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (tblReportMatch != null) {
      tableHtml = tblReportMatch.group(1) ?? html;
    }

    final plainText = _cleanHtmlText(tableHtml);
    final studentName = _extractLabeledValue(plainText, 'Student Name');
    final rowMatches = RegExp(
      r'<tr[^>]*>(.*?)</tr>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(tableHtml);

    int? subjectIdx;
    int? heldIdx;
    int? attendIdx;
    int? percentIdx;

    for (final row in rowMatches.toList()) {
      final rowHtml = row.group(1) ?? '';

      final isHeaderRow = RegExp(
        r'<th\b',
        caseSensitive: false,
      ).hasMatch(rowHtml);

      final cellMatches = RegExp(
        r'<t[dh][^>]*>(.*?)</t[dh]>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(rowHtml);

      final cleanedCells = cellMatches
          .map((c) => _cleanHtmlText(c.group(1) ?? ''))
          .toList();

      if (isHeaderRow) {
        for (int i = 0; i < cleanedCells.length; i++) {
          final lower = cleanedCells[i].toLowerCase().trim();
          if (lower.contains('subject') ||
              lower.contains('course') ||
              lower.contains('paper')) {
            subjectIdx = i;
          } else if (lower.contains('held')) {
            heldIdx = i;
          } else if (lower.contains('attend') &&
              !lower.contains('attendance')) {
            attendIdx = i;
          } else if (lower == '%' || lower.contains('percent')) {
            percentIdx = i;
          }
        }
        continue;
      }

      if (cleanedCells.where((c) => c.isNotEmpty).length < 3) continue;

      String? subjectName;
      int? totalClasses;
      int? attendedClasses;
      double? percentage;

      if (subjectIdx != null && heldIdx != null && attendIdx != null) {
        if (subjectIdx < cleanedCells.length) {
          final s = cleanedCells[subjectIdx].trim();
          if (s.isNotEmpty) subjectName = s;
        }
        if (heldIdx < cleanedCells.length) {
          totalClasses = int.tryParse(cleanedCells[heldIdx].trim());
        }
        if (attendIdx < cleanedCells.length) {
          attendedClasses = int.tryParse(cleanedCells[attendIdx].trim());
        }
        if (percentIdx != null && percentIdx < cleanedCells.length) {
          final raw = cleanedCells[percentIdx].trim();
          final normalized = raw.startsWith('.') ? '0$raw' : raw;
          percentage = double.tryParse(normalized);
        }
      } else {
        int subjectCellIdx = -1;
        for (int i = 0; i < cleanedCells.length; i++) {
          final cell = cleanedCells[i];
          if (cell.isNotEmpty &&
              (cell.toLowerCase().trim() == 'total' ||
                  _looksLikeSubjectCell(cell))) {
            subjectCellIdx = i;
            subjectName = cell;
            break;
          }
        }
        if (subjectCellIdx >= 0) {
          final intCellsAfterSubject = <int>[];
          for (int i = subjectCellIdx + 1; i < cleanedCells.length; i++) {
            final v = int.tryParse(cleanedCells[i].trim());
            if (v != null) intCellsAfterSubject.add(v);
          }
          if (intCellsAfterSubject.length >= 2) {
            totalClasses = intCellsAfterSubject[0];
            attendedClasses = intCellsAfterSubject[1];
          }
        }
      }

      if (percentage == null) {
        for (final cell in cleanedCells.reversed) {
          final trimmed = cell.trim();
          final normalized = trimmed.startsWith('.') ? '0$trimmed' : trimmed;
          if (normalized.contains('.')) {
            final parsed = double.tryParse(normalized);
            if (parsed != null && parsed >= 0.0 && parsed <= 100.0) {
              percentage = parsed;
              break;
            }
          }
        }
      }

      if (percentage == null &&
          totalClasses != null &&
          totalClasses > 0 &&
          attendedClasses != null) {
        percentage = (attendedClasses / totalClasses) * 100;
      }
      percentage ??= 0.0;

      if (subjectName == null) continue;
      if (totalClasses == null || attendedClasses == null) continue;

      final lowerSubject = subjectName.toLowerCase().trim();

      if (lowerSubject == 'total') {
        hasReport = true;
        totalHeldFromReport = totalClasses;
        totalAttendedFromReport = attendedClasses;
        totalPercentageFromReport = percentage;
        continue;
      }

      if (lowerSubject.contains('subject') ||
          lowerSubject.contains('sr') ||
          lowerSubject.contains('sl')) {
        continue;
      }

      subjects.add({
        'subject': subjectName,
        'totalClasses': totalClasses,
        'attendedClasses': attendedClasses,
        'percentage': percentage,
      });
    }

    final totalHeld = subjects.fold<int>(
      0,
      (sum, item) => sum + ((item['totalClasses'] as int?) ?? 0),
    );
    final totalAttended = subjects.fold<int>(
      0,
      (sum, item) => sum + ((item['attendedClasses'] as int?) ?? 0),
    );
    final overallPercentage = totalHeld == 0
        ? 0.0
        : (totalAttended / totalHeld) * 100;

    return {
      'overallPercentage': double.parse(
        (totalPercentageFromReport ?? overallPercentage).toStringAsFixed(1),
      ),
      'totalClasses': totalHeldFromReport ?? totalHeld,
      'totalAttended': totalAttendedFromReport ?? totalAttended,
      'subjects': subjects,
      'studentName': studentName,
      'hasReport': hasReport,
      'rawHtml': html,
    };
  }

  static String? _extractLabeledValue(String plainText, String label) {
    final match = RegExp(
      '$label\\s*:\\s*(.*?)\\s*(?=RollNo\\s*:|Student Name\\s*:|Course\\s*:|Branch\\s*:|Semester\\s*:|\$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(plainText);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static Future<String?> _extractTokenMultiStrategy({
    required String traceId,
    required HttpClient client,
    required Map<String, String> cookies,
    required String attendancePageHtml,
  }) async {
    String? token;

    if (_isReleaseBuild == false) {
      // ignore: avoid_print
      print(
        '[$traceId][TOKEN] Starting multi-strategy token extraction. '
        'htmlLen=${attendancePageHtml.length}',
      );
    }

    for (final pattern in _webMethodTokenPatterns) {
      final match = pattern.firstMatch(attendancePageHtml);
      final tkn = match?.group(1)?.trim();
      if (tkn != null && tkn.isNotEmpty) {
        token = tkn;
        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print('[$traceId][TOKEN] Strategy A (_tkn patterns): found');
        }
        return token;
      }
    }

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print('[$traceId][TOKEN] Strategy A (_tkn patterns): not found');
    }

    final hiddenMatches = _hiddenInputTokenPattern.allMatches(
      attendancePageHtml,
    );
    for (final hiddenMatch in hiddenMatches) {
      final inputTag = hiddenMatch.group(0) ?? '';

      String? name;
      final nameMatch = _inputNameAttrPattern.firstMatch(inputTag);
      if (nameMatch != null) name = nameMatch.group(1);

      String? id;
      final idMatch = _inputIdAttrPattern.firstMatch(inputTag);
      if (idMatch != null) id = idMatch.group(1);

      final fieldKey = (name ?? id ?? '').toLowerCase();
      if (fieldKey.contains('tkn') || fieldKey.contains('token')) {
        final valueMatch = _inputValueAttrPattern.firstMatch(inputTag);
        final value = valueMatch?.group(1)?.trim();
        if (value != null && value.isNotEmpty) {
          token = value;
          if (!_isReleaseBuild) {
            // ignore: avoid_print
            print(
              '[$traceId][TOKEN] Strategy B (hidden input): '
              'found field=$fieldKey',
            );
          }
          return token;
        }
      }
    }

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print('[$traceId][TOKEN] Strategy B (hidden input): not found');
    }

    for (final pattern in _genericTokenPatterns) {
      final match = pattern.firstMatch(attendancePageHtml);
      final tkn = match?.group(1)?.trim();
      if (tkn != null && tkn.isNotEmpty) {
        token = tkn;
        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print('[$traceId][TOKEN] Strategy C (generic patterns): found');
        }
        return token;
      }
    }

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print('[$traceId][TOKEN] Strategy C (generic patterns): not found');
    }

    final scriptMatches = _scriptSrcPattern.allMatches(attendancePageHtml);
    final jsPaths = <String>[];
    for (final match in scriptMatches) {
      final src = match.group(1) ?? '';
      if (src.contains('JSFiles') || src.contains('.js')) {
        jsPaths.add(src.split('?').first);
      }
    }

    if (!_isReleaseBuild) {
      // ignore: avoid_print
      print(
        '[$traceId][TOKEN] Strategy D (fetch JS): checking ${jsPaths.length} JS files',
      );
    }

    for (final jsPath in jsPaths) {
      if (!jsPath.contains(_portalHost)) continue;

      try {
        final jsPathOnly = jsPath.split('?').first;
        final jsResponse = await _sendRequest(
          client,
          method: 'GET',
          path: jsPathOnly,
          cookies: cookies,
          followRedirects: true,
          traceId: traceId,
          stepName: 'GET JS for token ($jsPathOnly)',
        );

        final jsBody = jsResponse.body;

        for (final pattern in _webMethodTokenPatterns) {
          final match = pattern.firstMatch(jsBody);
          final tkn = match?.group(1)?.trim();
          if (tkn != null && tkn.isNotEmpty) {
            token = tkn;
            if (!_isReleaseBuild) {
              // ignore: avoid_print
              print('[$traceId][TOKEN] Strategy D: found in $jsPathOnly');
            }
            return token;
          }
        }

        for (final pattern in _genericTokenPatterns) {
          final match = pattern.firstMatch(jsBody);
          final tkn = match?.group(1)?.trim();
          if (tkn != null && tkn.isNotEmpty) {
            token = tkn;
            if (!_isReleaseBuild) {
              // ignore: avoid_print
              print('[$traceId][TOKEN] Strategy D: found in $jsPathOnly');
            }
            return token;
          }
        }
      } catch (_) {
        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print('[$traceId][TOKEN] Strategy D: failed to fetch $jsPath');
        }
      }
    }

    if (!_isReleaseBuild) {
      final hasTkn = attendancePageHtml.contains('_tkn');
      final hasToken = attendancePageHtml.toLowerCase().contains('token');
      // ignore: avoid_print
      print(
        '[$traceId][TOKEN] All strategies failed. '
        'htmlLen=${attendancePageHtml.length}, '
        'has_tkn=$hasTkn, has_token=$hasToken, '
        'scriptSrcs=$jsPaths',
      );
    }

    return null;
  }

  static void _debugTokenExtractionHints({
    required String traceId,
    required String step,
    required String html,
  }) {
    if (_isReleaseBuild) return;

    final scriptSrcs = <String>[];
    final srcMatches = _scriptSrcPattern.allMatches(html);
    for (final match in srcMatches) {
      final src = match.group(1) ?? '';
      if (src.isNotEmpty) {
        scriptSrcs.add(src.split('?').first);
      }
    }

    // ignore: avoid_print
    print(
      '[$traceId][$step][TOKEN_DEBUG] '
      'htmlLen=${html.length} '
      'has_tkn=${html.contains('_tkn')} '
      'has_token=${html.toLowerCase().contains('token')} '
      'has_hiddenTkn=${html.toLowerCase().contains('hidden') && html.toLowerCase().contains('tkn')} '
      'scriptSrcs=[${scriptSrcs.join(', ')}]',
    );
  }

  static bool _looksLikeLoginPage(String body) {
    final lower = body.toLowerCase();
    final hasUserField = _loginUserFieldPattern.hasMatch(lower);
    final hasPasswordField = _loginPasswordFieldPattern.hasMatch(lower);
    final hasLoginButton =
        lower.contains('btnlogin') || lower.contains('>login<');
    final hasLoginFormAction =
        lower.contains('default.aspx') && lower.contains('<form');

    return hasUserField &&
        hasPasswordField &&
        (hasLoginButton || hasLoginFormAction);
  }

  static bool _looksLikeSubjectCell(String value) {
    final lower = value.toLowerCase();
    if (!RegExp(r'[a-z]').hasMatch(lower)) {
      return false;
    }
    return !lower.contains('percentage') &&
        !lower.contains('attended') &&
        !lower.contains('held') &&
        !lower.contains('total');
  }

  static String _cleanHtmlText(String input) {
    final withoutTags = input.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final decoded = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Future<String> _readResponseBody(HttpClientResponse response) async {
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<Map<String, dynamic>?> fetchMarksOnly(
    String rollNumber,
    String password, {
    String college = 'acet',
  }) async {
    _prefix = (college.toLowerCase() == 'aec') ? '/aec' : '/acet';
    final traceId = _generateTraceId();
    final client = HttpClient()..connectionTimeout = _timeout;
    final cookies = <String, String>{};

    try {
      await _login(client, rollNumber, password, cookies, traceId);
      final academicInsights = await _fetchAndParseMarks(client, cookies, traceId);
      if (academicInsights != null) {
        await AttendanceCacheService.saveAcademicInsights(
          rollNumber: rollNumber,
          academicInsights: academicInsights,
        );
      }
      return academicInsights;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _fetchAndParseMarks(
    HttpClient client,
    Map<String, String> cookies,
    String? traceId,
  ) async {
    final marksResponse = await _sendRequest(
      client,
      method: 'GET',
      path: _marksPath,
      cookies: cookies,
      followRedirects: true,
      extraHeaders: {
        HttpHeaders.refererHeader: 'https://$_portalHost$_studentMasterPath',
      },
      traceId: traceId,
      stepName: 'GET StudentMarksReport.aspx',
    );

    if (marksResponse.statusCode != 200 || marksResponse.body.isEmpty) {
      return null;
    }

    // 1. Extract AjaxPro ashx handler script path from page HTML
    final ashxMatch = RegExp(
      r'''src=["']([^"']*(?:StudentMarksReport|studentmarksreport)[^"']*\.ashx)["']''',
      caseSensitive: false,
    ).firstMatch(marksResponse.body);

    String ashxPath;
    if (ashxMatch != null) {
      final matched = ashxMatch.group(1)!;
      ashxPath = matched.startsWith('/') ? matched : '$_prefix/ajax/$matched';
    } else {
      ashxPath = '$_prefix/ajax/Academics_StudentMarksReport,App_Web_studentmarksreport.aspx.a2a1b31c.ashx';
    }

    final rpcPath = '$ashxPath?_method=ShowMarks&_session=rw';

    // 2. Call ShowMarks() via AjaxPro with exact query string from JS proxy
    var showMarksRes = await _sendRequest(
      client,
      method: 'POST',
      path: rpcPath,
      cookies: cookies,
      followRedirects: false,
      contentType: 'text/plain; charset=utf-8',
      body: '',
      extraHeaders: {
        'X-AjaxPro-Method': 'ShowMarks',
        'Ajax-Method': 'ShowMarks',
        'origin': 'https://$_portalHost',
        HttpHeaders.refererHeader: 'https://$_portalHost$_marksPath',
      },
      traceId: traceId,
      stepName: 'POST ShowMarks (AjaxPro RPC)',
    );

    // Fallback A: Try with body '{}'
    if (showMarksRes.statusCode != 200 || showMarksRes.body.startsWith('//')) {
      showMarksRes = await _sendRequest(
        client,
        method: 'POST',
        path: rpcPath,
        cookies: cookies,
        followRedirects: false,
        contentType: 'text/plain; charset=utf-8',
        body: '{}',
        extraHeaders: {
          'X-AjaxPro-Method': 'ShowMarks',
          'Ajax-Method': 'ShowMarks',
          'origin': 'https://$_portalHost',
          HttpHeaders.refererHeader: 'https://$_portalHost$_marksPath',
        },
        traceId: traceId,
        stepName: 'POST ShowMarks (AjaxPro RPC {})',
      );
    }

    // Fallback B: Try ASP.NET PageMethod
    if (showMarksRes.statusCode != 200 || showMarksRes.body.startsWith('//')) {
      showMarksRes = await _sendRequest(
        client,
        method: 'POST',
        path: '$_prefix/Academics/StudentMarksReport.aspx/ShowMarks',
        cookies: cookies,
        followRedirects: false,
        contentType: 'application/json; charset=UTF-8',
        body: '{}',
        extraHeaders: {
          'origin': 'https://$_portalHost',
          HttpHeaders.refererHeader: 'https://$_portalHost$_marksPath',
          'X-Requested-With': 'XMLHttpRequest',
        },
        traceId: traceId,
        stepName: 'POST ShowMarks (PageMethod)',
      );
    }

    if (showMarksRes.statusCode == 200 && showMarksRes.body.isNotEmpty) {
      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][MARKS] ShowMarks received raw body len=${showMarksRes.body.length}',
        );
        final raw = showMarksRes.body;
        for (int i = 0; i < raw.length; i += 800) {
          // ignore: avoid_print
          print('[$traceId][MARKS_RAW][$i]: ${raw.substring(i, min(i + 800, raw.length))}');
        }
      }

      String marksHtml = showMarksRes.body;
      try {
        var cleanJson = showMarksRes.body.trim();
        if (cleanJson.startsWith('/*json*/')) {
          cleanJson = cleanJson.substring(8).trim();
        } else if (cleanJson.startsWith(';/*json*/')) {
          cleanJson = cleanJson.substring(9).trim();
        }
        if (cleanJson.endsWith(';/*json*/')) {
          cleanJson = cleanJson.substring(0, cleanJson.length - 9).trim();
        } else if (cleanJson.endsWith(';')) {
          cleanJson = cleanJson.substring(0, cleanJson.length - 1).trim();
        }
        final decoded = jsonDecode(cleanJson);
        if (decoded is Map) {
          if (decoded.containsKey('value') && decoded['value'] != null) {
            marksHtml = decoded['value'].toString();
          } else if (decoded.containsKey('d') && decoded['d'] != null) {
            marksHtml = decoded['d'].toString();
          }
        } else if (decoded is String) {
          marksHtml = decoded;
        }
      } catch (e) {
        if (!_isReleaseBuild) {
          // ignore: avoid_print
          print('[$traceId][MARKS] jsonDecode error: $e');
        }
      }

      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][MARKS] ShowMarks unwrapped marksHtml len=${marksHtml.length}',
        );
        for (int i = 0; i < marksHtml.length; i += 800) {
          // ignore: avoid_print
          print('[$traceId][MARKS_UNWRAPPED][$i]: ${marksHtml.substring(i, min(i + 800, marksHtml.length))}');
        }
      }

      final parsed = _parseAcetAcademicMarks(marksHtml);
      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[$traceId][MARKS] parsed ACET marks: '
          'cgpa=${parsed?['cgpa']}, '
          'semesters=${(parsed?['semesters'] as List?)?.length}',
        );
      }
      return parsed;
    }

    return null;
  }

  static Map<String, dynamic>? _parseAcetAcademicMarks(String html) {
    if (html.isEmpty) return null;

    try {
      final cleanAll = _cleanHtmlText(html);

      double? cgpa;
      String? creditsTotal;
      String? percentage;
      int passedTotal = 0;
      int failedTotal = 0;

      // 1. Extract exact Summary Banner: e.g. "CGPA: 7.39 Credits:81/81 66.40 %"
      final summaryMatch = RegExp(
        r'CGPA\s*[:\s]*([0-9.]+)\s+Credits\s*[:\s]*([0-9/]+|[0-9.]+)\s+([0-9.]+)\s*%',
        caseSensitive: false,
      ).firstMatch(cleanAll);

      if (summaryMatch != null) {
        cgpa = double.tryParse(summaryMatch.group(1) ?? '');
        creditsTotal = summaryMatch.group(2);
        percentage = summaryMatch.group(3);
      } else {
        // Fallbacks
        final cgpaMatch = RegExp(r'CGPA\s*[:\s]*([0-9.]+)', caseSensitive: false).firstMatch(cleanAll);
        if (cgpaMatch != null) cgpa = double.tryParse(cgpaMatch.group(1) ?? '');

        final credMatch = RegExp(r'Credits\s*:\s*([0-9/]+|[0-9.]+)', caseSensitive: false).firstMatch(cleanAll);
        if (credMatch != null) creditsTotal = credMatch.group(1);

        final pctMatch = RegExp(r'Credits\s*:[^%]*?([0-9.]+)\s*%', caseSensitive: false).firstMatch(cleanAll);
        if (pctMatch != null) percentage = pctMatch.group(1);
      }

      // Check for Activity / AICTE points if present on portal
      final actMatch = RegExp(
        r'(?:Activity\s*Points?|AICTE\s*Points?|Activity)\s*[:\s]*([0-9.]+)',
        caseSensitive: false,
      ).firstMatch(cleanAll);
      final activityPoints = actMatch?.group(1);

      final semesters = <Map<String, dynamic>>[];

      // 2. Restrict to EXTERNAL MARKS section to prevent attendance and internal marks bleed-through
      final extStart = html.indexOf('EXTERNAL MARKS');
      final extEnd = html.indexOf('PREVIOUS SEMESTERS', extStart != -1 ? extStart : 0);
      final externalHtml = (extStart != -1 && extEnd != -1)
          ? html.substring(extStart, extEnd)
          : html;

      // 3. Match each semester block
      final semMatches = RegExp(
        r'<span[^>]*class=[^>]*reportHeading2[^>]*>([^<]*Semester[^<]*)</span>\s*<table[^>]*>(.*?)</table>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(externalHtml).toList();

      for (final m in semMatches) {
        final semTitle = _cleanHtmlText(m.group(1)!);
        final tableContent = m.group(2)!;

        final cellMatches = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true)
            .allMatches(tableContent)
            .map((c) => _cleanHtmlText(c.group(1)!))
            .toList();

        final sgpaIdx = cellMatches.indexWhere((c) => c.toUpperCase() == 'SGPA');
        if (sgpaIdx == -1) continue;

        final headers = cellMatches.sublist(1, sgpaIdx); // Skip first empty cell

        final gradeIdx = cellMatches.indexWhere((c) => c.toUpperCase() == 'GRADE');
        final credIdx = cellMatches.indexWhere((c) => c.toUpperCase() == 'CREDITS');

        if (gradeIdx == -1 || credIdx == -1) continue;

        final grades = cellMatches.sublist(gradeIdx + 1, credIdx - 1);
        final sgpa = double.tryParse(cellMatches[credIdx - 1]);

        final credits = cellMatches.sublist(credIdx + 1, credIdx + 1 + headers.length);
        final totalCreds = (credIdx + 1 + headers.length < cellMatches.length)
            ? cellMatches[credIdx + 1 + headers.length]
            : '';

        final courses = <Map<String, dynamic>>[];
        for (int i = 0; i < headers.length; i++) {
          final courseName = headers[i].trim();
          final grade = (i < grades.length) ? grades[i].trim() : '';
          final cred = (i < credits.length) ? credits[i].trim() : '';

          final isFailed = grade.toUpperCase() == 'F' || grade.toUpperCase() == 'AB';
          if (isFailed) {
            failedTotal++;
          } else if (grade.isNotEmpty && grade != '-') {
            passedTotal++;
          }

          courses.add({
            'sNo': courses.length + 1,
            'courseCode': courseName,
            'courseName': courseName,
            'grade': grade,
            'credits': cred,
            'points': _gradeToPoints(grade),
            'result': isFailed ? 'Fail' : 'Pass',
          });
        }

        final romanMatch = RegExp(r'Semester\s*[-–]\s*([I|V|X\d]+)', caseSensitive: false)
            .firstMatch(semTitle);
        final roman = romanMatch?.group(1) ??
            (semTitle.contains('Semester')
                ? semTitle.split('Semester').last.replaceAll('-', '').trim()
                : '${semesters.length + 1}');

        semesters.add({
          'title': semTitle,
          'roman': roman,
          'sgpa': sgpa ?? 0.0,
          'credits': totalCreds,
          'passed': courses.where((c) => c['result'] == 'Pass').length,
          'failed': courses.where((c) => c['result'] == 'Fail').length,
          'result': courses.any((c) => c['result'] == 'Fail') ? 'Fail' : 'Pass',
          'courses': courses,
        });
      }

      // If CGPA wasn't found in text, calculate average of semester SGPAs
      if ((cgpa == null || cgpa == 0.0) && semesters.isNotEmpty) {
        double sum = 0;
        int count = 0;
        for (final sem in semesters) {
          final sg = (sem['sgpa'] as num?)?.toDouble() ?? 0.0;
          if (sg > 0) {
            sum += sg;
            count++;
          }
        }
        if (count > 0) {
          cgpa = double.parse((sum / count).toStringAsFixed(2));
        } else {
          cgpa = (semesters.last['sgpa'] as num?)?.toDouble();
        }
      }

      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print(
          '[AecAttendanceService] _parseAcetAcademicMarks success: '
          'CGPA=$cgpa, Semesters=${semesters.length}, '
          'Passed=$passedTotal, Failed=$failedTotal, Credits=$creditsTotal, %=$percentage',
        );
      }

      return {
        'cgpa': cgpa ?? 0.0,
        'passed': passedTotal,
        'failed': failedTotal,
        'credits': creditsTotal ?? '',
        'percentage': percentage ?? '',
        'activityPoints': activityPoints ?? '',
        'result': failedTotal > 0 ? 'Fail' : 'Pass',
        'semesters': semesters,
      };
    } catch (e) {
      if (!_isReleaseBuild) {
        // ignore: avoid_print
        print('[AecAttendanceService] _parseAcetAcademicMarks error: $e');
      }
      return null;
    }
  }

  static String _gradeToPoints(String grade) {
    switch (grade.toUpperCase().trim()) {
      case 'O':
      case 'S':
        return '10';
      case 'A':
        return '9';
      case 'B':
        return '8';
      case 'C':
        return '7';
      case 'D':
        return '6';
      case 'E':
        return '5';
      case 'F':
      case 'AB':
        return '0';
      default:
        return '';
    }
  }
}

class _PortalResponse {
  const _PortalResponse({
    required this.statusCode,
    required this.body,
    this.location,
    Map<String, String>? headers,
  }) : headers = headers ?? const {};

  final int statusCode;
  final String body;
  final String? location;
  final Map<String, String> headers;
}

class _LoginFieldNames {
  const _LoginFieldNames({
    this.userFieldName,
    this.passwordFieldName,
    this.submitButtonName,
    this.submitButtonValue,
    required this.hasHdnPwd,
    required this.fallbackUserField,
    required this.fallbackPasswordField,
    required this.fallbackButtonName,
    required this.fallbackButtonValue,
  });

  final String? userFieldName;
  final String? passwordFieldName;
  final String? submitButtonName;
  final String? submitButtonValue;
  final bool hasHdnPwd;
  final String fallbackUserField;
  final String fallbackPasswordField;
  final String fallbackButtonName;
  final String fallbackButtonValue;
}

class _LoginPageData {
  const _LoginPageData({
    required this.hiddenFields,
    required this.fieldNames,
    required this.html,
  });

  final Map<String, String> hiddenFields;
  final _LoginFieldNames fieldNames;
  final String html;
}
