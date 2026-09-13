import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../core/network/api_cache.dart';
import '../utils/formatters.dart';

class DoctorScheduleService {
  DoctorScheduleService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static void invalidateDoctorCache() {
    ApiCache.remove('doctor_status_list');
    ApiCache.removeWhere((key) => key.startsWith('doctor_schedules_'));
  }

  static Future<List<DoctorStatus>> listDoctorStatus({bool forceRefresh = false}) async {
    const cacheKey = 'doctor_status_list';
    if (!forceRefresh) {
      final cached = ApiCache.get<List<DoctorStatus>>(cacheKey);
      if (cached != null) return cached;
    }

    final response = await _client.rpc('list_staff_accounts');
    final rows = (response as List<dynamic>?) ?? const [];
    final result = rows
        .whereType<Map<String, dynamic>>()
        .where((row) => (row['role']?.toString().toLowerCase() ?? '') == 'doctor')
        .map(DoctorStatus.fromMap)
        .toList(growable: false);
    ApiCache.set(cacheKey, result, const Duration(minutes: 5));
    return result;
  }

  static Future<List<DoctorSchedule>> listAvailableDoctorSchedules({
    DateTime? from,
    DateTime? to,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final dateFrom = DateTime(now.year, now.month, now.day);
    final dateTo = to ?? dateFrom.add(const Duration(days: 30));
    final cacheKey = 'doctor_schedules_${formatDateIso(from ?? dateFrom)}_${formatDateIso(dateTo)}';

    if (!forceRefresh) {
      final cached = ApiCache.get<List<DoctorSchedule>>(cacheKey);
      if (cached != null) return cached;
    }

    final response = await _client.rpc(
      'list_available_doctor_schedules',
      params: {
        'p_date_from': formatDateIso(from ?? dateFrom),
        'p_date_to': formatDateIso(dateTo),
      },
    );

    final rows = (response as List<dynamic>?) ?? const [];
    final result = rows.whereType<Map<String, dynamic>>().map(DoctorSchedule.fromMap).toList(growable: false);
    ApiCache.set(cacheKey, result, const Duration(minutes: 5));
    return result;
  }
}
