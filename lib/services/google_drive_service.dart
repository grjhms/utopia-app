import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage_service.dart';
import '../models/drive_notebook_model.dart';

/// An HTTP Client that attaches an OAuth Bearer token to each request.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  static const String serverClientId =
      '402670858978-94eqn0qvvrtv59ijne3hn1g5flr4ahve.apps.googleusercontent.com';

  /// Default scope: drive.readonly is required to browse folders shared via pasted URLs.
  static const String driveReadOnlyScope = drive.DriveApi.driveReadonlyScope;

  static const String _prefKeyNotebooks = 'utopia_drive_connected_notebooks';

  drive.DriveApi? _driveApi;
  String? _currentAccessToken;
  String? _connectedEmail;
  GoogleSignInAccount? _account;

  String? get connectedEmail => _connectedEmail;
  bool get isConnected => _currentAccessToken != null && _currentAccessToken!.isNotEmpty;
  drive.DriveApi? get driveApi => _driveApi;

  /// Restores connection from SecureStorage if token exists.
  Future<bool> initialize() async {
    try {
      final isConnectedStored = await SecureStorageService.isGoogleDriveConnected();
      final token = await SecureStorageService.getGoogleDriveAccessToken();
      final email = await SecureStorageService.getGoogleDriveEmail();

      if (isConnectedStored && token != null && token.isNotEmpty) {
        _currentAccessToken = token;
        _connectedEmail = email;
        _setupDriveClient(token);
        return true;
      }
    } catch (e) {
      debugPrint('GoogleDriveService.initialize error: $e');
    }
    return false;
  }

  void _setupDriveClient(String accessToken) {
    final client = _GoogleAuthClient({
      'Authorization': 'Bearer $accessToken',
    });
    _driveApi = drive.DriveApi(client);
  }

  /// Prompts user to connect Google Drive with drive.readonly scope.
  Future<bool> connect() async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: serverClientId,
      );

      final account = await GoogleSignIn.instance.authenticate();
      _account = account;
      _connectedEmail = account.email;

      final authClient = account.authorizationClient;
      final headers = await authClient.authorizationHeaders(
        [driveReadOnlyScope],
        promptIfNecessary: true,
      );

      final authHeader = headers?['Authorization'] ?? headers?['authorization'];
      if (authHeader == null || authHeader.isEmpty) {
        debugPrint('GoogleDriveService: No Authorization header returned.');
        return false;
      }

      final token = authHeader.startsWith('Bearer ')
          ? authHeader.substring(7).trim()
          : authHeader.trim();

      _currentAccessToken = token;
      await SecureStorageService.saveGoogleDriveAuth(
        accessToken: token,
        email: _connectedEmail ?? '',
      );

      _setupDriveClient(token);
      return true;
    } catch (e) {
      debugPrint('GoogleDriveService.connect error: $e');
      return false;
    }
  }

  /// Attempts to refresh the access token silently via GoogleSignIn authorization client.
  Future<bool> refreshToken() async {
    try {
      if (_account == null) {
        await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
        _account = await GoogleSignIn.instance.authenticate();
      }

      final authClient = _account?.authorizationClient;
      if (authClient == null) return false;

      final headers = await authClient.authorizationHeaders(
        [driveReadOnlyScope],
        promptIfNecessary: false,
      );

      final authHeader = headers?['Authorization'] ?? headers?['authorization'];
      if (authHeader != null && authHeader.isNotEmpty) {
        final token = authHeader.startsWith('Bearer ')
            ? authHeader.substring(7).trim()
            : authHeader.trim();

        _currentAccessToken = token;
        await SecureStorageService.saveGoogleDriveAuth(
          accessToken: token,
          email: _connectedEmail ?? '',
        );
        _setupDriveClient(token);
        return true;
      }
    } catch (e) {
      debugPrint('GoogleDriveService.refreshToken error: $e');
    }
    return false;
  }

  /// Disconnects Google Drive and clears saved tokens and local session.
  Future<void> disconnect() async {
    _currentAccessToken = null;
    _connectedEmail = null;
    _driveApi = null;
    _account = null;
    await SecureStorageService.clearGoogleDriveAuth();
  }

  // ─────────────────────────────────────────────────────────
  // Notebooks Persistence (Local storage)
  // ─────────────────────────────────────────────────────────

  Future<List<DriveNotebook>> getSavedNotebooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKeyNotebooks) ?? [];
      return list
          .map((item) => DriveNotebook.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('GoogleDriveService.getSavedNotebooks error: $e');
      return [];
    }
  }

  Future<void> saveNotebook(DriveNotebook notebook) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getSavedNotebooks();
      final index = current.indexWhere((n) => n.folderId == notebook.folderId);
      if (index != -1) {
        current[index] = notebook;
      } else {
        current.insert(0, notebook);
      }
      final jsonList = current.map((n) => n.toJson()).toList();
      await prefs.setStringList(_prefKeyNotebooks, jsonList);
    } catch (e) {
      debugPrint('GoogleDriveService.saveNotebook error: $e');
    }
  }

  Future<void> removeNotebook(String folderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getSavedNotebooks();
      current.removeWhere((n) => n.folderId == folderId);
      final jsonList = current.map((n) => n.toJson()).toList();
      await prefs.setStringList(_prefKeyNotebooks, jsonList);
    } catch (e) {
      debugPrint('GoogleDriveService.removeNotebook error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // Drive API Helpers
  // ─────────────────────────────────────────────────────────

  /// Extracts Google Drive Folder ID from a URL or raw ID string.
  static String? extractFolderId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Direct folder ID (typically 28-33 alphanumeric and hyphen/underscore characters)
    if (!trimmed.contains('/') && !trimmed.contains('.')) {
      return trimmed;
    }

    // Pattern 1: https://drive.google.com/drive/folders/{folderId}
    final regex1 = RegExp(r'drive\.google\.com/(?:drive/)?(?:u/\d+/)?folders/([a-zA-Z0-9_-]+)');
    final match1 = regex1.firstMatch(trimmed);
    if (match1 != null) {
      return match1.group(1);
    }

    // Pattern 2: https://drive.google.com/open?id={folderId} or uc?id={folderId}
    final regex2 = RegExp(r'id=([a-zA-Z0-9_-]+)');
    final match2 = regex2.firstMatch(trimmed);
    if (match2 != null) {
      return match2.group(1);
    }

    return null;
  }

  /// Verifies access to a Drive folder and retrieves its metadata.
  Future<DriveNotebook?> verifyAndFetchFolder(String folderIdOrUrl, {required String ownerUid}) async {
    final folderId = extractFolderId(folderIdOrUrl);
    if (folderId == null) {
      throw const FormatException('Invalid Google Drive folder link or ID');
    }

    if (_driveApi == null) {
      final inited = await initialize();
      if (!inited) {
        throw StateError('Google Drive is not connected. Please connect your Google account first.');
      }
    }

    try {
      final file = await _driveApi!.files.get(
        folderId,
        $fields: 'id, name, mimeType, trashed',
      ) as drive.File;

      if (file.trashed == true) {
        throw StateError('This Google Drive folder is in trash.');
      }

      if (file.mimeType != 'application/vnd.google-apps.folder') {
        throw StateError('The provided link is not a Google Drive folder.');
      }

      return DriveNotebook(
        id: folderId,
        folderId: folderId,
        name: file.name ?? 'Drive Folder',
        ownerEmail: _connectedEmail ?? '',
        ownerUid: ownerUid,
        createdAt: DateTime.now(),
      );
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 403 || e.status == 404) {
        throw StateError(
          'Access denied. Please ensure your Google account has permission to view this folder.',
        );
      }
      rethrow;
    }
  }

  /// Lists files and subfolders inside a given folder ID.
  Future<({List<DriveFileItem> items, String? nextPageToken})> listFolderContents(
    String folderId, {
    String? pageToken,
    int pageSize = 100,
  }) async {
    if (_driveApi == null) {
      final inited = await initialize();
      if (!inited) {
        throw StateError('Google Drive is not connected.');
      }
    }

    try {
      final fileList = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime)',
        pageSize: pageSize,
        pageToken: pageToken,
        orderBy: 'folder, name',
      );

      final files = (fileList.files ?? []).map((f) {
        return DriveFileItem(
          id: f.id ?? '',
          folderId: folderId,
          name: f.name ?? 'Untitled',
          mimeType: f.mimeType ?? 'application/octet-stream',
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
          modifiedTime: f.modifiedTime ?? DateTime.now(),
        );
      }).toList();

      return (items: files, nextPageToken: fileList.nextPageToken);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        final refreshed = await refreshToken();
        if (refreshed) {
          return listFolderContents(folderId, pageToken: pageToken, pageSize: pageSize);
        }
      }
      rethrow;
    }
  }

  /// Downloads a Drive file to the local target file path with progress reporting.
  Future<File> downloadFile({
    required String fileId,
    required String targetPath,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (_driveApi == null) {
      final inited = await initialize();
      if (!inited) {
        throw StateError('Google Drive is not connected.');
      }
    }

    final targetFile = File(targetPath);
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }

    final media = await _driveApi!.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final totalBytes = media.length ?? 0;
    int receivedBytes = 0;
    final sink = targetFile.openWrite();

    try {
      await for (final chunk in media.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null) {
          onProgress(receivedBytes, totalBytes);
        }
      }
      await sink.flush();
      return targetFile;
    } catch (e) {
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await sink.close();
    }
  }
}
