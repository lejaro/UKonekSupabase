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

      final response = await _client
          .from('consultations')
          .select('*, doctor:staff!doctor_staff_id(first_name, last_name)')
          .eq('patient_citizen_id', citizenId)
          .order('consulted_at', ascending: false)
          .limit(limit);
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(Consultation.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching consultations: $e');
      return [];
    }
  }
}
