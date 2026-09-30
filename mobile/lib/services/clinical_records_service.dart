import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'citizen_profile_service.dart';

class ClinicalRecordsService {
  ClinicalRecordsService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<VitalSigns>> fetchVitalSigns({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final profile = await CitizenProfileService.fetchMyCitizenProfile();
      final citizenId = profile['id'];

      final response = await _client
          .from('vital_signs')
          .select()
          .eq('citizen_id', citizenId)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(VitalSigns.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching vital signs: $e');
      return [];
    }
  }

  static Future<List<Consultation>> fetchConsultations({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final profile = await CitizenProfileService.fetchMyCitizenProfile();
      final citizenId = profile['id'];

      // Strategy 1: Dedicated secure RPC function get_my_consultations
      try {
        final rpcRes = await _client.rpc(
          'get_my_consultations',
          params: {
            'p_limit': limit,
            'p_citizen_id': citizenId,
          },
        );
        if (rpcRes is List && rpcRes.isNotEmpty) {
          final rows = rpcRes.whereType<Map<String, dynamic>>().map(Consultation.fromMap).toList();
          if (rows.isNotEmpty) return rows;
        }
      } catch (rpcErr) {
        debugPrint('[ClinicalRecordsService] get_my_consultations RPC fallback: $rpcErr');
      }

      // Strategy 2: Query public.consultations with joined doctor details
      try {
        var query = _client
            .from('consultations')
            .select('*, doctor:staff!doctor_staff_id(first_name, last_name)');

        if (citizenId != null) {
          query = query.or('patient_citizen_id.eq.$citizenId,patient_identifier.eq.$citizenId,patient_identifier.eq.CIT-$citizenId');
        }

        final response = await query
            .order('consulted_at', ascending: false)
            .limit(limit);

        final rows = (response as List<dynamic>?) ?? const [];
        if (rows.isNotEmpty) {
          return rows.whereType<Map<String, dynamic>>().map(Consultation.fromMap).toList();
        }
      } catch (joinErr) {
        debugPrint('[ClinicalRecordsService] Joined consultation query fallback: $joinErr');
      }

      // Strategy 3: Flat table select fallback (in case doctor:staff relationship is restricted)
      try {
        var flatQuery = _client.from('consultations').select();
        if (citizenId != null) {
          flatQuery = flatQuery.or('patient_citizen_id.eq.$citizenId,patient_identifier.eq.$citizenId,patient_identifier.eq.CIT-$citizenId');
        }

        final flatResponse = await flatQuery
            .order('consulted_at', ascending: false)
            .limit(limit);

        final flatRows = (flatResponse as List<dynamic>?) ?? const [];
        return flatRows.whereType<Map<String, dynamic>>().map(Consultation.fromMap).toList();
      } catch (flatErr) {
        debugPrint('[ClinicalRecordsService] Flat consultation query fallback: $flatErr');
      }

      return [];
    } catch (e) {
      debugPrint('Error fetching consultations: $e');
      return [];
    }
  }
}
