import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'attendance_cache_service.dart';

class AusAttendanceService {
  static const String _portalHost = 'info.aec.edu.in';
  static const String _aesSecret = '8701661282118308';
  static const String _prefix = '/aus';
  static const String _loginPath = '$_prefix/default.aspx';
  static const String _studentMasterPath = '$_prefix/StudentMaster.aspx';
  static const String _attendancePagePath =
      '$_prefix/Academics/studentattendance.aspx?scrid=3&showtype=SA';
  static const String _attendancePath =
      '$_prefix/Academics/studentattendance.aspx/ShowAttendance';
  static const String _ajaxJsPath = '$_prefix/JSFiles/AjaxMethods.js';

  static const Duration _timeout = Duration(seconds: 20);
  static String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; vivo I2305) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/123.0.0.0 Mobile Safari/537.36';

  static Future<String> _encryptPassword(String password) async {
    final key = encrypt.Key.fromUtf8(_aesSecret);
    final iv = encrypt.IV.fromUtf8(_aesSecret);
    final aes = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    return aes.encrypt(password, iv: iv).base64;
  }

  static Future<Map<String, String>> _loginViaWebView(
    String rollNumber,
    String password,
  ) async {
    print('[AusAttendanceService] _loginViaWebView: started for $rollNumber');
    final completer = Completer<Map<String, String>>();
    final encryptedPassword = await _encryptPassword(password);
    print('[AusAttendanceService] _loginViaWebView: password encrypted');
    
    HeadlessInAppWebView? headlessWebView;
    Timer? timeoutTimer;

    void cleanup() {
      print('[AusAttendanceService] _loginViaWebView: cleaning up...');
      timeoutTimer?.cancel();
      try {
        headlessWebView?.dispose();
        print('[AusAttendanceService] _loginViaWebView: WebView disposed.');
      } catch (e) {
        print('[AusAttendanceService] _loginViaWebView: dispose error: $e');
      }
    }

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      print('[AusAttendanceService] _loginViaWebView: 30s TIMEOUT reached!');
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Could not sign in to the college portal'),
        );
      }
    });

    print('[AusAttendanceService] _loginViaWebView: constructing HeadlessInAppWebView');
    headlessWebView = HeadlessInAppWebView(
      initialSize: const Size(360, 800),
      initialUrlRequest: URLRequest(
        url: WebUri('https://$_portalHost$_loginPath'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
      ),
      onLoadStart: (controller, url) {
        print('[AusAttendanceService] WebView LoadStart: $url');
      },
      onLoadStop: (controller, url) async {
        final currentUrl = url?.toString() ?? '';
        print('[AusAttendanceService] WebView LoadStop: $currentUrl');
        
        if (currentUrl.contains('default.aspx')) {
          print('[AusAttendanceService] WebView default.aspx detected. Waiting for DOM...');
          
          // 1. Wait for username input to be present in DOM
          bool isFormReady = false;
          for (int i = 0; i < 20; i++) {
            if (completer.isCompleted) {
              print('[AusAttendanceService] WebView: task completed/timed out during DOM check. Aborting.');
              return;
            }
            final checkForm = "document.querySelector('#txtUserId') !== null";
            final res = await controller.evaluateJavascript(source: checkForm);
            if (res == true) {
              isFormReady = true;
              break;
            }
            await Future.delayed(const Duration(milliseconds: 300));
          }
          print('[AusAttendanceService] WebView form ready: $isFormReady');
          
          if (!isFormReady) {
            print('[AusAttendanceService] WebView: Form elements not detected. Aborting.');
            return;
          }

          // 2. Check if Turnstile captcha is actually present on the page
          final checkTurnstilePresence = "document.querySelector('.cf-turnstile') !== null || document.querySelector('[class*=\"cf-\"]') !== null || document.querySelector('iframe[src*=\"cloudflare\"]') !== null || document.querySelector('[name=\"cf-turnstile-response\"]') !== null";
          final hasTurnstile = await controller.evaluateJavascript(source: checkTurnstilePresence) == true;
          print('[AusAttendanceService] WebView hasTurnstile: $hasTurnstile');

          if (hasTurnstile) {
            print('[AusAttendanceService] WebView polling for Turnstile token...');
            String turnstileToken = '';
            for (int i = 0; i < 30; i++) {
              if (completer.isCompleted) {
                print('[AusAttendanceService] WebView: task completed/timed out during Turnstile check. Aborting.');
                return;
              }
              final checkToken = "var el = document.querySelector('[name=\"cf-turnstile-response\"]'); el ? el.value : '';";
              final tokenRes = await controller.evaluateJavascript(source: checkToken);
              if (tokenRes != null && tokenRes.toString().isNotEmpty) {
                turnstileToken = tokenRes.toString();
                print('[AusAttendanceService] WebView Turnstile solved! Token length: ${turnstileToken.length}');
                break;
              }
              print('[AusAttendanceService] WebView Turnstile not solved yet (attempt ${i + 1}/30)...');
              await Future.delayed(const Duration(milliseconds: 500));
            }

            if (turnstileToken.isEmpty) {
              print('[AusAttendanceService] WebView WARNING: Turnstile token is still empty after 15s!');
            }
          } else {
            print('[AusAttendanceService] WebView: No Turnstile detected. Skipping Turnstile token polling.');
          }

          if (completer.isCompleted) {
            print('[AusAttendanceService] WebView: task completed/timed out before JS injection. Aborting.');
            return;
          }

          print('[AusAttendanceService] WebView Injecting JS credentials...');
          final jsCode = """
            (function() {
              var txtUserId = document.querySelector('#txtUserId') || document.querySelector('#txtId2') || document.querySelector('#txtid2') || document.querySelector('[id*="txtUserId"]') || document.querySelector('[id*="txtId2"]');
              var txtPassword = document.querySelector('#txtPassword') || document.querySelector('#txtPwd2') || document.querySelector('#txtpwd2') || document.querySelector('[id*="txtPassword"]') || document.querySelector('[id*="txtPwd2"]');
              var hdnpwd = document.querySelector('#hdnpwd') || document.querySelector('#hdnpwd1') || document.querySelector('#hdnpwd2') || document.querySelector('#hdnpwd3') || document.querySelector('[id*="hdnpwd"]');
              var rbtStudent = document.querySelector('#rbtStudent') || document.querySelector('#rbtStudent2') || document.querySelector('[id*="rbtStudent"]');

              if (txtUserId) txtUserId.value = '${rollNumber.trim()}';
              if (txtPassword) txtPassword.value = '$encryptedPassword';
              if (hdnpwd) hdnpwd.value = '$encryptedPassword';
              if (rbtStudent) rbtStudent.checked = true;

              // Prioritize clicking the submit button directly
              var loginBtn = document.querySelector('#btnLogin') || document.querySelector('[id*="btnLogin"]') || document.querySelector('#imgBtn2') || document.querySelector('[id*="imgBtn2"]');
              if (loginBtn) {
                loginBtn.click();
              } else if (typeof __doPostBack === 'function') {
                __doPostBack('btnLogin', '');
              } else {
                var form = document.querySelector('form');
                if (form) form.submit();
              }
            })();
          """;

          try {
            await controller.evaluateJavascript(source: jsCode);
            print('[AusAttendanceService] WebView JS credentials successfully injected and submitted.');
          } catch (e) {
            print('[AusAttendanceService] WebView JS evaluation error: $e');
          }
        } else if (currentUrl.contains('StudentMaster.aspx')) {
          if (completer.isCompleted) return;
          print('[AusAttendanceService] WebView StudentMaster.aspx detected! Extracting cookies...');
          try {
            // Extract the actual WebView User-Agent to align all subsequent HttpClient requests
            final ua = await controller.evaluateJavascript(source: "navigator.userAgent");
            if (ua != null && ua.toString().isNotEmpty) {
              _userAgent = ua.toString();
              print('[AusAttendanceService] WebView resolved native User-Agent: $_userAgent');
            }
            final cookieManager = CookieManager.instance();
            final cookiesList = await cookieManager.getCookies(
              url: WebUri(currentUrl),
            );
            final extractedCookies = <String, String>{};
            for (final cookie in cookiesList) {
              extractedCookies[cookie.name] = cookie.value.toString();
            }
            print('[AusAttendanceService] WebView extracted cookies: ${extractedCookies.keys.toList()}');

            final sessionId = extractedCookies['ASP.NET_SessionId'];
            final frmAuth = extractedCookies['frmAuth'];

            if (sessionId == null ||
                sessionId.isEmpty ||
                frmAuth == null ||
                frmAuth.isEmpty) {
              print('[AusAttendanceService] WebView error: SessionId or frmAuth missing/empty!');
              if (!completer.isCompleted) {
                completer.completeError(Exception('Invalid credentials'));
              }
            } else {
              print('[AusAttendanceService] WebView login successful! Resolving extracted cookies.');
              if (!completer.isCompleted) {
                completer.complete(extractedCookies);
              }
            }
          } catch (e) {
            print('[AusAttendanceService] WebView cookie extraction exception: $e');
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          } finally {
            cleanup();
          }
        }
      },
      onReceivedError: (controller, request, error) {
        print('[AusAttendanceService] WebView Error: ${error.description} (code: ${error.type})');
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        print('[AusAttendanceService] WebView HTTP Error: ${errorResponse.statusCode} - ${errorResponse.reasonPhrase}');
      },
      onConsoleMessage: (controller, consoleMessage) {
        print('[AusAttendanceService] WebView Console: [${consoleMessage.messageLevel}] ${consoleMessage.message}');
      },
    );

    try {
      print('[AusAttendanceService] WebView running headlessWebView...');
      await headlessWebView.run();
      print('[AusAttendanceService] WebView headless run initiated.');
    } catch (e) {
      print('[AusAttendanceService] WebView run() error: $e');
      cleanup();
      completer.completeError(e);
    }

    return completer.future;
  }

  static Future<void> _login(
    HttpClient client,
    String rollNumber,
    String password,
    Map<String, String> cookies,
  ) async {
    try {
      final webViewCookies = await _loginViaWebView(rollNumber, password);
      cookies.addAll(webViewCookies);

      final sessionId = cookies['ASP.NET_SessionId'];
      final frmAuth = cookies['frmAuth'];
      if (sessionId == null ||
          frmAuth == null ||
          sessionId.isEmpty ||
          frmAuth.isEmpty) {
        throw Exception('Invalid credentials');
      }
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
    String fromDate = '',
    String toDate = '',
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    final cookies = <String, String>{};
    try {
      await _login(client, rollNumber, password, cookies);

      await _sendRequest(
        client,
        method: 'GET',
        path: _studentMasterPath,
        cookies: cookies,
        followRedirects: true,
      );

      final profilePath = '$_prefix/Academics/StudentProfile.aspx?scrid=17';
      final profilePageResponse = await _sendRequest(
        client,
        method: 'GET',
        path: profilePath,
        cookies: cookies,
        followRedirects: true,
      );

      final rollNoMatch = RegExp(
              r'id="ctl00_CapPlaceHolder_txtRollNo"[^>]*value="([^"]+)"')
          .firstMatch(profilePageResponse.body);
      final rollNo = rollNoMatch?.group(1) ?? '';

      final authToken = cookies['AuthToken'] ?? cookies['authtoken'] ?? '';

      final showResp = await _sendRequest(
        client,
        method: 'POST',
        path: '$_prefix/Academics/studentprofile.aspx/ShowStudentProfileNew',
        cookies: cookies,
        followRedirects: false,
        contentType: 'application/json; charset=UTF-8',
        body: jsonEncode({'RollNo': rollNo, 'isImageDisplay': false}),
        extraHeaders: {
          'Origin': 'https://$_portalHost',
          HttpHeaders.refererHeader: 'https://$_portalHost$profilePath',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Auth-Token': authToken,
          'Accept': 'application/json, text/javascript, */*',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin'
        },
      );
      _debugResponse('POST ShowStudentProfileNew', showResp.statusCode, showResp.body);

      // ── Fetch Academic Marks Report (scrid=15) ──
      Map<String, dynamic>? academicInsights;
      try {
        final marksReportPath = '$_prefix/Academics/StudentMarksReport.aspx?scrid=15';
        final marksResp = await _sendRequest(
          client,
          method: 'GET',
          path: marksReportPath,
          cookies: cookies,
          followRedirects: true,
          extraHeaders: {
            HttpHeaders.refererHeader: 'https://$_portalHost$_studentMasterPath',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        );

        final authToken = cookies['AuthToken'] ?? cookies['authtoken'] ?? '';

        final marksPostResp = await _sendRequest(
          client,
          method: 'POST',
          path: '$_prefix/Academics/StudentMarksReport.aspx/ShowMarks',
          cookies: cookies,
          followRedirects: false,
          contentType: 'application/json; charset=UTF-8',
          body: jsonEncode({}),
          extraHeaders: {
            'Origin': 'https://$_portalHost',
            HttpHeaders.refererHeader: 'https://$_portalHost$marksReportPath',
            'X-Requested-With': 'XMLHttpRequest',
            'X-Auth-Token': authToken,
            'Accept': 'application/json, text/javascript, */*',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        );

        _debugResponse('POST ShowMarks', marksPostResp.statusCode, marksPostResp.body);

        String marksHtml = '';
        if (marksPostResp.statusCode == HttpStatus.ok && marksPostResp.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(marksPostResp.body);
            if (decoded is Map && decoded.containsKey('d')) {
              marksHtml = decoded['d'] as String? ?? '';
            } else {
              marksHtml = marksPostResp.body;
            }
          } catch (_) {
            marksHtml = marksPostResp.body;
          }
        }

        if (marksHtml.isNotEmpty) {
          academicInsights = _parseAcademicMarks(marksHtml);
          print('[AusAttendanceService] Academic insights parsed from ShowMarks: CGPA=${academicInsights?['cgpa']}, Semesters=${(academicInsights?['semesters'] as List?)?.length}');
        }
      } catch (marksErr) {
        print('[AusAttendanceService] Failed to fetch StudentMarksReport: $marksErr');
      }

      if (showResp.statusCode == HttpStatus.unauthorized) {
        throw Exception(
          'Attendance records not published yet. Please try again later.',
        );
      }
      if (showResp.statusCode != HttpStatus.ok) {
        throw Exception('Could not fetch attendance right now');
      }

      String profileHtml;
      try {
        final decoded = jsonDecode(showResp.body) as Map<String, dynamic>;
        profileHtml = decoded['d'] as String? ?? '';
      } catch (_) {
        profileHtml = showResp.body;
      }

      if (profileHtml.isEmpty && academicInsights == null) {
        throw Exception('No profile data in response');
      }

      int profileSectionStart = profileHtml.indexOf("<div id='divProfile_Present'>");
      if (profileSectionStart == -1) {
        profileSectionStart = profileHtml.indexOf('<div id="divProfile_Present">');
      }
      if (profileSectionStart == -1) {
        final m = RegExp(r'''<div[^>]*id=["']divProfile_Present["'][^>]*>''', caseSensitive: false).firstMatch(profileHtml);
        if (m != null) profileSectionStart = m.start;
      }

      Map<String, dynamic> parsedMap = {};
      if (profileSectionStart != -1) {
        final profileSectionEnd = profileHtml.indexOf("</div>", profileSectionStart);
        final profileSection = profileSectionEnd != -1
            ? profileHtml.substring(profileSectionStart, profileSectionEnd)
            : profileHtml.substring(profileSectionStart);

        final tableStart = profileSection.indexOf('<table');
        if (tableStart != -1) {
          final tableEnd = profileSection.indexOf('</table>', tableStart);
          final tableHtml = tableEnd != -1
              ? profileSection.substring(tableStart, tableEnd + 8)
              : profileSection.substring(tableStart);
          parsedMap = Map<String, dynamic>.from(_parseAttendanceHtml(tableHtml));
        }
      }

      final bioDataStart = profileHtml.indexOf('>Name<');
      String studentNameFromHtml = '';
      if (bioDataStart != -1) {
        final afterName = profileHtml.substring(bioDataStart);
        final nameTdMatch = RegExp(
          r"<td[^>]*colspan=['" '"' r"]?3['" '"' r"]?[^>]*>([^<]+)</td>",
          caseSensitive: false,
        ).firstMatch(afterName);
        if (nameTdMatch != null) {
          studentNameFromHtml = _cleanHtmlText(nameTdMatch.group(1) ?? '');
        }
      }

      if (studentNameFromHtml.isNotEmpty) {
        parsedMap['studentName'] = studentNameFromHtml;
      }

      if (academicInsights != null) {
        parsedMap['academicInsights'] = academicInsights;
      }

      final hasReport = parsedMap['hasReport'] as bool? ?? false;
      final subjectsList = parsedMap['subjects'] as List? ?? [];
      if (subjectsList.isEmpty && !hasReport) {
        if (academicInsights != null) {
          unawaited(AttendanceCacheService.saveAcademicInsights(
            rollNumber: rollNumber,
            academicInsights: academicInsights,
          ));

          final cached = await AttendanceCacheService.load(rollNumber);
          if (cached != null && (cached.data['subjects'] as List? ?? []).isNotEmpty) {
            final merged = Map<String, dynamic>.from(cached.data);
            merged['academicInsights'] = academicInsights;
            merged['attendanceUnavailable'] = true;
            merged['fromCache'] = true;
            return merged;
          }

          parsedMap['overallPercentage'] = 0.0;
          parsedMap['totalClasses'] = 0;
          parsedMap['totalAttended'] = 0;
          parsedMap['subjects'] = <Map<String, dynamic>>[];
          parsedMap['attendanceUnavailable'] = true;
          return parsedMap;
        }
        throw Exception('Attendance data was not found in the portal response');
      }
      return parsedMap;
    } on FormatException {
      rethrow;
    } catch (e) {
      if (e is Exception &&
          (e.toString().contains('Invalid credentials') ||
              e.toString().contains('Attendance data was not found') ||
              e.toString().contains('Could not fetch attendance') ||
              e.toString().contains('temporarily unavailable'))) {
        rethrow;
      }
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
  }) async {
    var currentUri = Uri.parse('https://$_portalHost$path');
    var currentMethod = method;
    var redirectCount = 0;

    while (true) {
      final request = await _openRequest(client, currentMethod, currentUri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-IN,en;q=0.9');
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader(cookies));
      }
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      extraHeaders?.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
      }

      final response = await request.close().timeout(_timeout);
      final responseBody = await _readResponseBody(response);
      _captureCookies(response.cookies, cookies);

      if (!followRedirects || !_isRedirect(response.statusCode)) {
        return _PortalResponse(
          statusCode: response.statusCode,
          body: responseBody,
          location: response.headers.value(HttpHeaders.locationHeader),
        );
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        return _PortalResponse(
          statusCode: response.statusCode,
          body: responseBody,
        );
      }
      if (redirectCount >= 8) {
        throw Exception('Portal redirected too many times');
      }

      currentUri = currentUri.resolve(location);
      currentMethod = 'GET';
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

  static Map<String, dynamic>? _parseAcademicMarks(String html) {
    if (html.isEmpty) return null;

    try {
      double? cgpa;
      int? passedTotal;
      int? failedTotal;
      String? creditsTotal;
      String? overallResult;

      final semesters = <Map<String, dynamic>>[];
      String? currentSemTitle;
      String? currentSemRoman;
      var currentCourses = <Map<String, dynamic>>[];

      final rowMatches = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true)
          .allMatches(html)
          .toList();

      for (final row in rowMatches) {
        final trHtml = row.group(1) ?? '';
        final trClean = _cleanHtmlText(trHtml);
        final cells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true)
            .allMatches(trHtml)
            .map((c) => _cleanHtmlText(c.group(1) ?? ''))
            .where((c) => c.isNotEmpty)
            .toList();

        if (cells.isEmpty) continue;

        // 1. Overall Summary table rows (Passed, Failed, CGPA, Credits, Result)
        if (cells.length >= 2) {
          final label = cells[0].toLowerCase().trim();
          final val = cells[1].trim();
          if (label == 'cgpa') {
            cgpa = double.tryParse(val);
          } else if (label == 'passed') {
            passedTotal = int.tryParse(val);
          } else if (label == 'failed') {
            failedTotal = int.tryParse(val);
          } else if (label == 'credits') {
            creditsTotal = val;
          } else if (label == 'result') {
            overallResult = val;
          }
        }

        // 2. Semester Title row (e.g. "I Semester", "II Semester")
        final semTitleMatch = RegExp(r'^([I|V|X\d]+)\s*Semester', caseSensitive: false)
            .firstMatch(trClean.trim());
        if (semTitleMatch != null && !trClean.contains('Summary')) {
          currentSemRoman = semTitleMatch.group(1);
          currentSemTitle = '$currentSemRoman Semester';
          currentCourses = [];
          continue;
        }

        // 3. Course row (cell 0 is numeric S.No and row has >= 7 cells)
        if (cells.length >= 7) {
          final sNo = int.tryParse(cells[0]);
          if (sNo != null) {
            final courseCode = cells[1];
            final courseName = cells[2];
            String session = '';
            String grade = '';
            String points = '';
            String credits = '';
            String result = '';

            if (cells.length >= 8) {
              session = cells[3];
              grade = cells[4];
              points = cells[5];
              credits = cells[6];
              result = cells[7];
            } else {
              grade = cells[3];
              points = cells[4];
              credits = cells[5];
              result = cells[6];
            }

            currentCourses.add({
              'sNo': sNo,
              'courseCode': courseCode,
              'courseName': courseName,
              'session': session,
              'grade': grade,
              'points': points,
              'credits': credits,
              'result': result,
            });
            continue;
          }
        }

        // 4. Semester Summary row (e.g. "I Semester Summary Passed:8, Failed:0 Result:Pass SGPA:7.89")
        if (trClean.contains('Semester Summary')) {
          final summaryMatch = RegExp(
            r'([I|V|X\d]+)\s*Semester\s*Summary.*?Passed\s*:\s*([0-9]+).*?Failed\s*:\s*([0-9]+).*?Result\s*:\s*([A-Za-z]+).*?SGPA\s*:\s*([0-9]+(\.[0-9]+)?)',
            caseSensitive: false,
          ).firstMatch(trClean);

          if (summaryMatch != null) {
            final roman = summaryMatch.group(1) ?? (currentSemRoman ?? '');
            final semPassed = int.tryParse(summaryMatch.group(2) ?? '0') ?? 0;
            final semFailed = int.tryParse(summaryMatch.group(3) ?? '0') ?? 0;
            final semRes = summaryMatch.group(4) ?? 'Pass';
            final semSgpa = double.tryParse(summaryMatch.group(5) ?? '0') ?? 0.0;

            semesters.add({
              'title': currentSemTitle ?? '$roman Semester',
              'roman': roman,
              'sgpa': semSgpa,
              'passed': semPassed,
              'failed': semFailed,
              'result': semRes,
              'courses': List<Map<String, dynamic>>.from(currentCourses),
            });
            currentCourses = [];
            currentSemTitle = null;
            currentSemRoman = null;
          }
        }
      }

      // Global clean-text fallbacks if any fields were missed
      final cleanAll = _cleanHtmlText(html);
      if (cgpa == null) {
        final m = RegExp(r'CGPA\s*[:\s]*([0-9]+\.[0-9]+|[0-9]+)', caseSensitive: false)
            .firstMatch(cleanAll);
        if (m != null) cgpa = double.tryParse(m.group(1) ?? '');
      }
      if (passedTotal == null) {
        final m = RegExp(r'Passed\s*[:\s]*([0-9]+)', caseSensitive: false).firstMatch(cleanAll);
        if (m != null) passedTotal = int.tryParse(m.group(1) ?? '');
      }
      if (failedTotal == null) {
        final m = RegExp(r'Failed\s*[:\s]*([0-9]+)', caseSensitive: false).firstMatch(cleanAll);
        if (m != null) failedTotal = int.tryParse(m.group(1) ?? '');
      }
      if (creditsTotal == null) {
        final m = RegExp(r'Credits\s*[:\s]*([0-9]+/[0-9]+|[0-9]+(\.[0-9]+)?)', caseSensitive: false)
            .firstMatch(cleanAll);
        if (m != null) creditsTotal = m.group(1);
      }
      if (overallResult == null) {
        final m = RegExp(r'Result\s*[:\s]*([A-Za-z]+)', caseSensitive: false).firstMatch(cleanAll);
        if (m != null) overallResult = m.group(1);
      }

      print('[AusAttendanceService] _parseAcademicMarks success: CGPA=$cgpa, Semesters=${semesters.length}, Passed=$passedTotal, Failed=$failedTotal');

      if (cgpa != null || semesters.isNotEmpty) {
        return {
          'cgpa': cgpa ?? (semesters.isNotEmpty ? semesters.last['sgpa'] : 0.0),
          'passed': passedTotal ?? semesters.fold<int>(0, (sum, s) => sum + (s['passed'] as int? ?? 0)),
          'failed': failedTotal ?? semesters.fold<int>(0, (sum, s) => sum + (s['failed'] as int? ?? 0)),
          'credits': creditsTotal ?? '',
          'result': overallResult ?? 'Pass',
          'semesters': semesters,
        };
      }
      return null;
    } catch (e) {
      print('[AusAttendanceService] _parseAcademicMarks error: $e');
      return null;
    }
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

  static void _debugResponse(String label, int statusCode, String body) {
    final preview = body.length <= 500 ? body : body.substring(0, 500);
    // ignore: avoid_print
    print('$label response code: $statusCode');
    // ignore: avoid_print
    print('$label response body preview: $preview');
  }
}

class _PortalResponse {
  const _PortalResponse({
    required this.statusCode,
    required this.body,
    this.location,
  });

  final int statusCode;
  final String body;
  final String? location;
}
