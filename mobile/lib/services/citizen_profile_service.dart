import 'package:supabase_flutter/supabase_flutter.dart';

class CitizenProfileService {
  CitizenProfileService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Map<String, dynamic>? _cachedCitizenProfile;

  static void clearCitizenProfileCache() {
    _cachedCitizenProfile = null;
  }

  static Future<Map<String, dynamic>> fetchMyCitizenProfile({bool force = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    if (!force && _cachedCitizenProfile != null && _cachedCitizenProfile!['auth_user_id'] == user.id) {
      return _cachedCitizenProfile!;
    }

    final response = await _client.from('citizens').select('*').eq('auth_user_id', user.id).maybeSingle();
    if (response == null) throw Exception('Citizen profile not found');
    _cachedCitizenProfile = response;
    return response;
  }

  static Future<void> updateMyCitizenProfile(Map<String, dynamic> data) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await _client.from('citizens').update(data).eq('auth_user_id', user.id);
    _cachedCitizenProfile = null;
  }
}
