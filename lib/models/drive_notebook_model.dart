import 'dart:convert';

/// Represents a Google Drive folder connected as a notebook in UTOPIA.
class DriveNotebook {
  final String id;
  final String folderId;
  final String name;
  final String ownerEmail;
  final String ownerUid;
  final DateTime createdAt;
  final DateTime? lastSyncedAt;
  final bool isOffline;
  final String? shareCode;
  final int itemCount;
  final int totalSizeBytes;

  const DriveNotebook({
    required this.id,
    required this.folderId,
    required this.name,
    required this.ownerEmail,
    required this.ownerUid,
    required this.createdAt,
    this.lastSyncedAt,
    this.isOffline = false,
    this.shareCode,
    this.itemCount = 0,
    this.totalSizeBytes = 0,
  });

  DriveNotebook copyWith({
    String? id,
    String? folderId,
    String? name,
    String? ownerEmail,
    String? ownerUid,
    DateTime? createdAt,
    DateTime? lastSyncedAt,
    bool? isOffline,
    String? shareCode,
    int? itemCount,
    int? totalSizeBytes,
  }) {
    return DriveNotebook(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerUid: ownerUid ?? this.ownerUid,
      createdAt: createdAt ?? this.createdAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isOffline: isOffline ?? this.isOffline,
      shareCode: shareCode ?? this.shareCode,
      itemCount: itemCount ?? this.itemCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'folderId': folderId,
      'name': name,
      'ownerEmail': ownerEmail,
      'ownerUid': ownerUid,
      'createdAt': createdAt.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'isOffline': isOffline ? 1 : 0,
      'shareCode': shareCode,
      'itemCount': itemCount,
      'totalSizeBytes': totalSizeBytes,
    };
  }

  factory DriveNotebook.fromMap(Map<String, dynamic> map) {
    return DriveNotebook(
      id: map['id'] as String? ?? '',
      folderId: map['folderId'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled Folder',
      ownerEmail: map['ownerEmail'] as String? ?? '',
      ownerUid: map['ownerUid'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'] as String)
          : null,
      isOffline: (map['isOffline'] is int)
          ? (map['isOffline'] as int) == 1
          : (map['isOffline'] as bool? ?? false),
      shareCode: map['shareCode'] as String?,
      itemCount: (map['itemCount'] as num?)?.toInt() ?? 0,
      totalSizeBytes: (map['totalSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory DriveNotebook.fromJson(String source) =>
      DriveNotebook.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// Represents a file or folder inside a connected Google Drive folder.
class DriveFileItem {
  final String id;
  final String folderId;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final DateTime modifiedTime;
  final String? localPath;
  final bool isDownloaded;

  const DriveFileItem({
    required this.id,
    required this.folderId,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedTime,
    this.localPath,
    this.isDownloaded = false,
  });

  bool get isFolder =>
      mimeType == 'application/vnd.google-apps.folder';

  bool get isGoogleDoc =>
      mimeType.startsWith('application/vnd.google-apps.');

  DriveFileItem copyWith({
    String? id,
    String? folderId,
    String? name,
    String? mimeType,
    int? sizeBytes,
    DateTime? modifiedTime,
    String? localPath,
    bool? isDownloaded,
  }) {
    return DriveFileItem(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'folderId': folderId,
      'name': name,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'modifiedTime': modifiedTime.toIso8601String(),
      'localPath': localPath,
      'isDownloaded': isDownloaded ? 1 : 0,
    };
  }

  factory DriveFileItem.fromMap(Map<String, dynamic> map) {
    return DriveFileItem(
      id: map['id'] as String? ?? '',
      folderId: map['folderId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedTime: map['modifiedTime'] != null
          ? DateTime.tryParse(map['modifiedTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      localPath: map['localPath'] as String?,
      isDownloaded: (map['isDownloaded'] is int)
          ? (map['isDownloaded'] as int) == 1
          : (map['isDownloaded'] as bool? ?? false),
    );
  }
}
