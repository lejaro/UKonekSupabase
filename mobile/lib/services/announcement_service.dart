import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../core/network/api_cache.dart';

class AnnouncementService {
  AnnouncementService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static const String _cacheKey = 'active_announcements_list';

  static void invalidateCache() {
    ApiCache.remove(_cacheKey);
  }

  static Future<List<Announcement>> fetchAnnouncements({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = ApiCache.get<List<Announcement>>(_cacheKey);
      if (cached != null) return cached;
    }

    try {
      final response = await _client
          .from('announcements')
          .select('id,title,content,visibility,image_url,created_at')
          .inFilter('visibility', ['all', 'citizen'])
          .order('created_at', ascending: false)
          .limit(10);
      final rows = (response as List<dynamic>?) ?? const [];
      final list = rows.whereType<Map<String, dynamic>>().map(Announcement.fromMap).toList();
      ApiCache.set(_cacheKey, list, const Duration(minutes: 15));
      return list;
    } catch (e) {
      debugPrint('Error fetching announcements: $e');
      return [];
    }
  }
}
