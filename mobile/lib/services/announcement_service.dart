import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AnnouncementService {
  AnnouncementService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Announcement>> fetchAnnouncements() async {
    try {
      final response = await _client
          .from('announcements')
          .select('id,title,content,visibility,created_at')
          .inFilter('visibility', ['all', 'citizen'])
          .order('created_at', ascending: false)
          .limit(10);
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(Announcement.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching announcements: $e');
      return [];
    }
  }
}
