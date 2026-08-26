import 'dart:io';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Maximum file size allowed for upload (9 MB).
const int kMaxUploadBytes = 9 * 1024 * 1024;

/// Hard limit — reject files above 15 MB outright.
const int kHardLimitBytes = 15 * 1024 * 1024;

/// Service for uploading files to Cloudinary using signed uploads.
class FileUploadService {
  static final FileUploadService _instance = FileUploadService._internal();
  factory FileUploadService() => _instance;
  FileUploadService._internal();

  String? _cachedCloudName;
  String? _cachedPublicBaseUrl;
  String? _cachedRemoteCloudName;
  String? _cachedApiKey;
  String? _cachedApiSecret;

  /// Fetch Cloudinary public configuration from Firestore.
  Future<(String?, String?)> _getStorageConfig() async {
    if (_cachedCloudName != null && _cachedPublicBaseUrl != null) {
      return (_cachedCloudName, _cachedPublicBaseUrl);
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('storage_config')
          .get();
      if (!doc.exists) return (null, null);
      final cloudName = doc.data()?['cloud_name'] as String?;
      final publicBaseUrl = doc.data()?['public_base_url'] as String?;
      if (cloudName != null && cloudName.isNotEmpty) {
        _cachedCloudName = cloudName;
      }
      if (publicBaseUrl != null && publicBaseUrl.isNotEmpty) {
        _cachedPublicBaseUrl = publicBaseUrl;
      }
      return (cloudName, publicBaseUrl);
    } catch (e) {
      debugPrint('FileUploadService: Failed to fetch storage config: $e');
      return (null, null);
    }
  }

  /// Fetch Cloudinary signed-upload credentials from Remote Config.
  Future<(String?, String?, String?)> _getCloudinarySecrets() async {
    if (_cachedApiKey != null &&
        _cachedApiSecret != null &&
        _cachedRemoteCloudName != null) {
      return (_cachedApiKey, _cachedApiSecret, _cachedRemoteCloudName);
    }

    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.fetchAndActivate();

      final apiKey = remoteConfig.getString('cloudinary_api_key');
      final apiSecret = remoteConfig.getString('cloudinary_api_secret');
      final remoteCloudName = remoteConfig.getString('cloudinary_cloud_name');

      _cachedApiKey = apiKey.isNotEmpty ? apiKey : null;
      _cachedApiSecret = apiSecret.isNotEmpty ? apiSecret : null;
      _cachedRemoteCloudName =
          remoteCloudName.isNotEmpty ? remoteCloudName : null;

      return (_cachedApiKey, _cachedApiSecret, _cachedRemoteCloudName);
    } catch (e) {
      debugPrint('FileUploadService: Failed to fetch remote config: $e');
      return (null, null, null);
    }
  }

  /// Let the user pick a file. Returns null if cancelled or file too large.
  /// Returns a tuple of (File, original filename).
  Future<(File, String)?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    if (picked.path == null) return null;
    
    final file = File(picked.path!);
    final size = await file.length();
    
    if (size > kHardLimitBytes) {
      throw FileUploadException(
        'File is too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
        'Maximum allowed is 15 MB.',
      );
    }
    if (size > kMaxUploadBytes) {
      throw FileUploadException(
        'File exceeds recommended size of 9 MB '
        '(${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
        'Please use a smaller file.',
      );
    }
    
    return (file, picked.name);
  }

  /// Upload a file to Cloudinary and return the permanent download URL.
  ///
  /// [file] — the file to upload.
  /// [originalFilename] — original name of the file.
  /// [universityId] — the university folder name for path scoping.
  /// [onProgress] — optional progress callback (0.0 to 1.0).
  Future<String> uploadFile({
    required File file,
    required String originalFilename,
    required String universityId,
    void Function(double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw FileUploadException('Not signed in.');

    final (firestoreCloudName, publicBaseUrl) = await _getStorageConfig();
    final (apiKey, apiSecret, remoteCloudName) = await _getCloudinarySecrets();

    final cloudName = (firestoreCloudName != null && firestoreCloudName.isNotEmpty)
        ? firestoreCloudName
        : remoteCloudName;

    final effectivePublicBaseUrl = (publicBaseUrl != null && publicBaseUrl.isNotEmpty)
        ? publicBaseUrl
        : (cloudName != null && cloudName.isNotEmpty ? 'https://res.cloudinary.com/$cloudName' : null);

    if (cloudName == null || cloudName.isEmpty || effectivePublicBaseUrl == null || effectivePublicBaseUrl.isEmpty) {
      throw FileUploadException(
        'Storage is not configured yet. Contact the admin.',
      );
    }
    if (apiKey == null || apiKey.isEmpty || apiSecret == null || apiSecret.isEmpty) {
      throw FileUploadException('Upload service credentials are missing.');
    }

    // Build a unique path inside Cloudinary.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = originalFilename.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final publicId = 'uploads/$universityId/${user.uid}/${timestamp}_$safeName';
    final unixTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final signedParams = <String, String>{
      'public_id': publicId,
      'timestamp': unixTs.toString(),
    };
    final sortedKeys = signedParams.keys.toList()..sort();
    final signaturePayload = [
      for (final key in sortedKeys) '$key=${signedParams[key]}',
    ].join('&') + apiSecret;
    final signature = sha1.convert(utf8.encode(signaturePayload)).toString();

    onProgress?.call(0.0);

    // Determine Cloudinary resource type (image vs raw) based on file extension
    final ext = originalFilename.split('.').last.toLowerCase();
    final isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'heif'].contains(ext);
    final resourceType = isImage ? 'image' : 'raw';

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = unixTs.toString()
      ..fields['signature'] = signature
      ..fields['public_id'] = publicId
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: originalFilename,
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'FileUploadService: Cloudinary upload failed (${response.statusCode}): ${response.body}',
      );
      throw FileUploadException('Failed to upload file. Please try again.');
    }

    onProgress?.call(1.0);

    try {
      final responseData = jsonDecode(response.body);
      final secureUrl = responseData['secure_url'] as String?;
      if (secureUrl != null && secureUrl.isNotEmpty) {
        return secureUrl;
      }
    } catch (e) {
      debugPrint('FileUploadService: Failed to parse secure_url from response: $e');
    }

    return '${effectivePublicBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/$publicId';
  }

  /// Upload a user profile avatar image to Cloudinary and return the download URL.
  Future<String> uploadProfilePhoto({
    required File file,
    String? universityId,
    void Function(double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw FileUploadException('Not signed in.');

    final ext = file.path.split('.').last.toLowerCase();
    final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final targetUni = (universityId != null && universityId.isNotEmpty)
        ? universityId
        : 'profiles';

    return uploadFile(
      file: file,
      originalFilename: filename,
      universityId: targetUni,
      onProgress: onProgress,
    );
  }

  /// Guess MIME type from filename extension.
  String? _mimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  /// Invalidate cached config values.
  void clearCache() {
    _cachedCloudName = null;
    _cachedPublicBaseUrl = null;
    _cachedRemoteCloudName = null;
    _cachedApiKey = null;
    _cachedApiSecret = null;
  }
}

class FileUploadException implements Exception {
  final String message;
  FileUploadException(this.message);
  @override
  String toString() => message;
}
