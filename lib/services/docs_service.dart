import 'package:cloud_firestore/cloud_firestore.dart';

class UniversityDoc {
  final String id;
  final String title;
  final String url;
  final String universityId;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  const UniversityDoc({
    required this.id,
    required this.title,
    required this.url,
    required this.universityId,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
  });

  factory UniversityDoc.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UniversityDoc(
      id: doc.id,
      title: data['title'] as String? ?? 'Untitled',
      url: data['url'] as String? ?? '',
      universityId: data['universityId'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      createdByName: data['createdByName'] as String? ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'url': url,
        'universityId': universityId,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class DocsService {
  static final DocsService instance = DocsService._();
  DocsService._();

  final _db = FirebaseFirestore.instance;

  Stream<List<UniversityDoc>> watchDocs(String universityId) {
    return _db
        .collection('university_docs')
        .where('universityId', isEqualTo: universityId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .where((doc) => doc.data()['createdAt'] != null)
            .map(UniversityDoc.fromFirestore)
            .toList());
  }

  Future<void> addDoc({
    required String title,
    required String url,
    required String universityId,
    required String createdBy,
    required String createdByName,
  }) async {
    await _db.collection('university_docs').add({
      'title': title,
      'url': url,
      'universityId': universityId,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDoc({
    required String docId,
    required String title,
    required String url,
  }) async {
    await _db.collection('university_docs').doc(docId).update({
      'title': title,
      'url': url,
    });
  }

  Future<void> deleteDoc(String docId) async {
    await _db.collection('university_docs').doc(docId).delete();
  }

  /// Converts any Google Drive share URL to an embeddable preview URL.
  static String toPreviewUrl(String url) {
    // https://drive.google.com/file/d/FILE_ID/view?... → preview
    final fileRegex = RegExp(r'drive\.google\.com/file/d/([^/?]+)');
    final fileMatch = fileRegex.firstMatch(url);
    if (fileMatch != null) {
      final id = fileMatch.group(1)!;
      return 'https://drive.google.com/file/d/$id/preview';
    }
    // https://drive.google.com/open?id=FILE_ID
    final openRegex = RegExp(r'drive\.google\.com/open\?id=([^&]+)');
    final openMatch = openRegex.firstMatch(url);
    if (openMatch != null) {
      final id = openMatch.group(1)!;
      return 'https://drive.google.com/file/d/$id/preview';
    }
    // Already a preview / not a drive link — return as-is
    return url;
  }

  /// Returns a direct download URL for Google Drive and Google Docs files.
  static String toDownloadUrl(String url) {
    // Google drive file
    final fileRegex = RegExp(r'drive\.google\.com/file/d/([^/?]+)');
    final fileMatch = fileRegex.firstMatch(url);
    if (fileMatch != null) {
      final id = fileMatch.group(1)!;
      return 'https://drive.google.com/uc?export=download&id=$id';
    }
    // Google drive open?id= or uc?id=
    final openRegex = RegExp(r'drive\.google\.com/(?:open|uc)\?.*id=([^&]+)');
    final openMatch = openRegex.firstMatch(url);
    if (openMatch != null) {
      final id = openMatch.group(1)!;
      return 'https://drive.google.com/uc?export=download&id=$id';
    }
    // Google Docs/Sheets/Slides export as PDF
    final docsRegex = RegExp(r'docs\.google\.com/(document|presentation|spreadsheets)/d/([^/?]+)');
    final docsMatch = docsRegex.firstMatch(url);
    if (docsMatch != null) {
      final type = docsMatch.group(1)!;
      final id = docsMatch.group(2)!;
      if (type == 'document') {
        return 'https://docs.google.com/document/d/$id/export?format=pdf';
      } else if (type == 'presentation') {
        return 'https://docs.google.com/presentation/d/$id/export/pdf';
      } else if (type == 'spreadsheets') {
        return 'https://docs.google.com/spreadsheets/d/$id/export?format=pdf';
      }
    }
    return url;
  }

  static bool isGoogleDriveUrl(String url) {
    return url.contains('drive.google.com') || url.contains('docs.google.com');
  }
}
