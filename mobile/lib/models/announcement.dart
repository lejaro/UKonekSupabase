class Announcement {
  final int id;
  final String title;
  final String content;
  final String visibility;
  final String? imageUrl;
  final DateTime createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.visibility,
    this.imageUrl,
    required this.createdAt,
  });

  factory Announcement.fromMap(Map<String, dynamic> map) {
    final rawImg = map['image_url'] as String?;
    return Announcement(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: (map['title'] as String?)?.trim() ?? '',
      content: (map['content'] as String?)?.trim() ?? '',
      visibility: (map['visibility'] as String?)?.trim() ?? 'all',
      imageUrl: (rawImg != null && rawImg.trim().isNotEmpty) ? rawImg.trim() : null,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
