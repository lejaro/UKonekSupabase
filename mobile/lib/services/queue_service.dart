import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../core/network/api_cache.dart';
import '../utils/formatters.dart';
import 'citizen_profile_service.dart';

class QueueService {
  QueueService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<QueueServiceOption>> listAvailableQueueServices({DateTime? date}) async {
    final normalizedDate = date ?? DateTime.now();
    final cacheKey = 'queue_services_${formatDateIso(normalizedDate)}';

    final cached = ApiCache.get<List<QueueServiceOption>>(cacheKey);
    if (cached != null) return cached;

    final response = await _client.rpc(
      'list_available_queue_services',
      params: {'p_date': formatDateIso(normalizedDate)},
    );

    final rows = (response as List<dynamic>?) ?? const [];
    final result = rows
        .whereType<Map<String, dynamic>>()
        .map(QueueServiceOption.fromMap)
        .where((entry) => entry.serviceKey.isNotEmpty && entry.serviceLabel.isNotEmpty)
        .toList(growable: false);
    ApiCache.set(cacheKey, result, const Duration(minutes: 5));
    return result;
  }

  static Future<QueueTicket> joinQueue(QueueJoinRequest request) async {
    final citizenType = request.citizenType.trim().toLowerCase();
    if (request.serviceKey.trim().isEmpty || request.serviceLabel.trim().isEmpty) {
      throw Exception('Please select a healthcare service.');
    }
    if (!const {'regular', 'pwd', 'pregnant'}.contains(citizenType)) {
      throw Exception('Please select a valid citizen type.');
    }

    dynamic response;
    try {
      response = await _client.rpc(
        'create_queue_ticket',
        params: {
          'p_service_key': request.serviceKey.trim(),
          'p_service_label': request.serviceLabel.trim(),
          'p_citizen_type': citizenType,
          'p_reason': request.reason.trim(),
          'p_symptoms': request.symptoms.trim(),
        },
      );
    } on PostgrestException catch (error) {
      final rawMessage = error.message.toLowerCase();
      if (rawMessage.contains('citizen profile not found')) {
        throw Exception('Your account is missing a citizen profile. Please contact the health center admin for account setup.');
      }
      rethrow;
    }

    final rows = (response as List<dynamic>?) ?? const [];
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) {
      throw Exception('Failed to create queue ticket. Please try again.');
    }

    return QueueTicket.fromMap(rows.first as Map<String, dynamic>);
  }

  static Future<QueueDashboardSnapshot> getMyQueueDashboard() async {
    final response = await _client.rpc('get_my_queue_dashboard');
    final rows = (response as List<dynamic>?) ?? const [];
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) return QueueDashboardSnapshot.empty;
    final map = rows.first as Map<String, dynamic>;
    final hasVitals = map['has_vitals'] == true;
    return QueueDashboardSnapshot.fromMap(map, hasVitals: hasVitals);
  }

  static Future<QueueLimiterStatus> getQueueLimiterStatus() async {
    const cacheKey = 'queue_limiter_status';
    final cached = ApiCache.get<QueueLimiterStatus>(cacheKey);
    if (cached != null) return cached;

    final response = await _client.rpc('get_queue_limiter_status');
    final rows = (response as List<dynamic>?) ?? const [];
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) return QueueLimiterStatus.disabled();
    final result = QueueLimiterStatus.fromMap(rows.first as Map<String, dynamic>);
    ApiCache.set(cacheKey, result, const Duration(seconds: 30));
    return result;
  }

  static Future<bool> cancelMyQueue() async {
    final response = await _client.rpc('cancel_my_queue_ticket');
    return response == true;
  }

  static Future<Map<String, dynamic>?> getTicketStatus(int ticketId) async {
    try {
      final response = await _client
          .from('queue_tickets')
          .select('id, status, service_label, queue_number, ticket_code, completed_at')
          .eq('id', ticketId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error getting ticket status: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getCompletedQueueTicket({int? ticketId}) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await CitizenProfileService.fetchMyCitizenProfile();
      final citizenId = profile['id'];

      var query = _client
          .from('queue_tickets')
          .select('id, status, service_label, queue_number, ticket_code, completed_at, queue_date')
          .eq('citizen_id', citizenId)
          .eq('status', 'completed');

      if (ticketId != null) {
        query = query.eq('id', ticketId);
      }

      final response = await query
          .order('completed_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error getting completed queue ticket: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> getTvQueueDisplay() async {
    try {
      final response = await _client.rpc('get_tv_queue_display');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {};
    } catch (e) {
      debugPrint('Error fetching TV display: $e');
      return {};
    }
  }
}
