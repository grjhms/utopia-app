class UniversityModel {
  final String id;
  final String name;
  final String shortName;
  final bool isActive;

  UniversityModel({
    required this.id,
    required this.name,
    required this.shortName,
    this.isActive = true,
  });

  factory UniversityModel.fromMap(Map<String, dynamic> data, String documentId) {
    final String resolvedId = (data['id'] as String?)?.trim().isNotEmpty == true
        ? (data['id'] as String).trim()
        : documentId.trim();

    final String name = (data['name'] ?? data['title'] ?? data['universityName'] ?? resolvedId)
        .toString()
        .trim();

    String shortName = (data['shortName'] ?? data['code'] ?? data['abbr'] ?? data['short_name'] ?? '')
        .toString()
        .trim();

    if (shortName.isEmpty && name.isNotEmpty) {
      final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length > 1) {
        shortName = words.take(4).map((w) => w[0].toUpperCase()).join('');
      } else if (name.length <= 4) {
        shortName = name.toUpperCase();
      } else {
        shortName = name.substring(0, 3).toUpperCase();
      }
    }

    final bool isActive = data['isActive'] != false && data['enabled'] != false;

    return UniversityModel(
      id: resolvedId,
      name: name,
      shortName: shortName,
      isActive: isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName,
      'isActive': isActive,
    };
  }
}
