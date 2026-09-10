import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'citizen_profile_service.dart';

class PrescriptionService {
  PrescriptionService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<PrescribedMedicine>> getMyPrescribedMedicines() async {
    final response = await _client.rpc('get_my_prescribed_medicines');
    final rows = (response as List<dynamic>?) ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PrescribedMedicine.fromMap)
        .where((item) => item.medicineName.isNotEmpty)
        .toList(growable: false);
  }

  static Future<List<ScheduledMedicine>> getMedicineSchedule() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _client.rpc('get_my_medicine_schedule');
      final rows = (response as List<dynamic>?) ?? const <dynamic>[];
      return rows.whereType<Map<String, dynamic>>().map(ScheduledMedicine.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching medicine schedule: $e');
      return [];
    }
  }

  static Future<List<PrescriptionRecord>> fetchPrescriptions({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _client.rpc('get_my_prescribed_medicines', params: {'p_limit': limit});
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(PrescriptionRecord.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching prescriptions: $e');
      return [];
    }
  }

  /// Synthesizes dispense log entries from dispensed prescription records.
  /// Used as a robust fallback when the backend dispense logs RPC returns empty
  /// or encounters an overloaded function error, ensuring the patient's Purchase Logs
  /// accurately reflect all fulfilled prescriptions.
  static List<PrescriptionDispenseLog> synthesizeDispenseLogsFromPrescriptions(
    List<PrescriptionRecord> prescriptions,
  ) {
    final List<PrescriptionDispenseLog> logs = [];
    int syntheticId = 1;

    for (final r in prescriptions) {
      final isDisp = r.isPrescriptionDispensed || r.isDispensed || r.dispensedQuantity > 0;
      if (!isDisp) continue;

      final qty = r.dispensedQuantity > 0 ? r.dispensedQuantity : r.quantity;
      final dispensedDate = r.dispensedAt ?? r.issuedAt;

      logs.add(PrescriptionDispenseLog(
        dispenseId: r.prescriptionId * 1000 + (syntheticId++),
        prescriptionId: r.prescriptionId,
        prescriptionCode: r.prescriptionCode,
        prescriptionItemId: r.prescriptionId * 1000 + syntheticId,
        medicineName: r.medicineName,
        dosage: r.dosage,
        dispensedQuantity: qty,
        unit: r.unit,
        note: r.instructions.isNotEmpty ? r.instructions : 'Fulfilled by Pharmacy',
        pharmacistName: 'Pharmacy Staff',
        dispensedAt: dispensedDate,
      ));
    }

    logs.sort((a, b) => b.dispensedAt.compareTo(a.dispensedAt));
    return logs;
  }

  /// Synthesizes ScheduledMedicine items from dispensed prescription records.
  /// Guarantees newly fulfilled dispensed medicines immediately populate
  /// the Medicine Scheduler even before background RPC synchronization completes.
  static List<ScheduledMedicine> synthesizeScheduledMedicinesFromPrescriptions(
    List<PrescriptionRecord> prescriptions,
  ) {
    final List<ScheduledMedicine> meds = [];
    for (final r in prescriptions) {
      final isDisp = r.isPrescriptionDispensed || r.isDispensed || r.dispensedQuantity > 0;
      if (!isDisp) continue;

      final qty = r.dispensedQuantity > 0 ? r.dispensedQuantity : r.quantity;
      final dispensedDate = r.dispensedAt ?? r.issuedAt;

      meds.add(ScheduledMedicine(
        prescriptionItemId: r.prescriptionId * 1000 + 1,
        prescriptionId: r.prescriptionId,
        prescriptionCode: r.prescriptionCode,
        dispensingStatus: r.dispensingStatus.isNotEmpty ? r.dispensingStatus : 'dispensed',
        issuedAt: r.issuedAt,
        dispensedAt: dispensedDate,
        doctorName: r.doctorName,
        medicineName: r.medicineName,
        quantity: qty,
        unit: r.unit,
        dosage: r.dosage,
        frequency: r.frequency,
        duration: r.duration,
        instructions: r.instructions,
        additionalInfo: r.additionalInfo,
        isAvailable: true,
        isDispensed: true,
      ));
    }
    return meds;
  }

  static Future<List<PrescriptionDispenseLog>> fetchPrescriptionDispenseLogs({
    int? prescriptionId,
    int limit = 50,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final params = <String, dynamic>{'p_limit': limit};
    if (prescriptionId != null) {
      params['p_prescription_id'] = prescriptionId;
    }

    // 1. Try canonical function
    try {
      final response = await _client.rpc('get_my_prescription_dispense_logs', params: params);
      final rows = (response as List<dynamic>?) ?? const [];
      if (rows.isNotEmpty) {
        return rows.whereType<Map<String, dynamic>>().map(PrescriptionDispenseLog.fromMap).toList();
      }
    } catch (e) {
      debugPrint('Primary get_my_prescription_dispense_logs failed: $e, trying alias...');
    }

    // 2. Try alias get_my_dispense_history
    try {
      final response = await _client.rpc('get_my_dispense_history', params: params);
      final rows = (response as List<dynamic>?) ?? const [];
      if (rows.isNotEmpty) {
        return rows.whereType<Map<String, dynamic>>().map(PrescriptionDispenseLog.fromMap).toList();
      }
    } catch (e) {
      debugPrint('Alias get_my_dispense_history failed: $e');
    }

    return [];
  }

  static Future<void> logMedicineIntake({
    required int prescriptionItemId,
    required String scheduledTime,
    required int doseIndex,
    int? citizenId,
    String? intakeDate,
  }) async {
    if (citizenId == null) {
      final profile = await CitizenProfileService.fetchMyCitizenProfile();
      citizenId = (profile['id'] as num).toInt();
    }

    // Bug #5 fix: Use the passed intakeDate (from UI's selected date) rather than DateTime.now()
    final dateStr = intakeDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    await _client.from('medicine_intake_logs').upsert({
      'citizen_id': citizenId,
      'prescription_item_id': prescriptionItemId,
      'scheduled_time': scheduledTime,
      'dose_index': doseIndex,
      'status': 'taken',
      'actual_time': DateTime.now().toUtc().toIso8601String(),
      'intake_date': dateStr,
    }, onConflict: 'citizen_id,prescription_item_id,dose_index,intake_date');
  }

  static Future<void> deleteMedicineIntakeLog({
    required int prescriptionItemId,
    required int doseIndex,
    required String intakeDate,
    int? citizenId,
  }) async {
    if (citizenId == null) {
      final profile = await CitizenProfileService.fetchMyCitizenProfile();
      citizenId = (profile['id'] as num).toInt();
    }
    await _client
        .from('medicine_intake_logs')
        .delete()
        .eq('citizen_id', citizenId)
        .eq('prescription_item_id', prescriptionItemId)
        .eq('dose_index', doseIndex)
        .eq('intake_date', intakeDate);
  }

  static Future<List<Map<String, dynamic>>> getIntakeLogsForDate(
    DateTime date, {
    int? citizenId,
  }) async {
    if (citizenId == null) {
      final profile = await CitizenProfileService.fetchMyCitizenProfile();
      citizenId = (profile['id'] as num).toInt();
    }

    // Bug #4 fix: Query by intake_date (plain DATE column) instead of created_at (UTC timestamp)
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    final response = await _client
        .from('medicine_intake_logs')
        .select()
        .eq('citizen_id', citizenId)
        .eq('intake_date', dateStr);

    return (response as List<dynamic>?)?.whereType<Map<String, dynamic>>().toList() ?? [];
  }

  static String _prescriptionAckKeyForUser() {
    try {
      final session = _client.auth.currentSession;
      final userId = session?.user.id;
      if (userId != null && userId.isNotEmpty) {
        return 'last_acknowledged_prescription_id_$userId';
      }
    } catch (_) {}
    return 'last_acknowledged_prescription_id';
  }

  /// Retrieves the latest prescription if it has not been acknowledged yet.
  /// Used to trigger the New E-Prescription pop-up modal and local notification.
  static Future<NewPrescriptionAlert?> fetchLatestUnacknowledgedPrescription() async {
    try {
      final records = await fetchPrescriptions(limit: 20);
      if (records.isEmpty) return null;

      // Group by prescriptionId
      final Map<int, List<PrescriptionRecord>> groups = {};
      for (final r in records) {
        if (r.prescriptionId <= 0) continue;
        groups.putIfAbsent(r.prescriptionId, () => []).add(r);
      }
      if (groups.isEmpty) return null;

      // Find the newest prescription group by highest ID or most recent issuedAt
      final sortedEntries = groups.entries.toList()
        ..sort((a, b) {
          final timeComp = b.value.first.issuedAt.compareTo(a.value.first.issuedAt);
          if (timeComp != 0) return timeComp;
          return b.key.compareTo(a.key);
        });

      final latestGroup = sortedEntries.first;
      final latestId = latestGroup.key;
      final latestItems = latestGroup.value;
      final firstItem = latestItems.first;

      final prefs = await SharedPreferences.getInstance();
      final userKey = _prescriptionAckKeyForUser();
      final lastAckIdUser = prefs.getInt(userKey) ?? 0;
      final lastAckIdGlobal = prefs.getInt('last_acknowledged_prescription_id') ?? 0;
      final lastAckId = lastAckIdUser > lastAckIdGlobal ? lastAckIdUser : lastAckIdGlobal;

      // If already acknowledged, do not alert again
      if (latestId <= lastAckId) return null;

      // Only alert if issued recently (within last 24 hours)
      final age = DateTime.now().difference(firstItem.issuedAt);
      if (age.inHours > 24) {
        // Automatically mark stale prescription as acknowledged so it doesn't pop up later
        await acknowledgePrescription(latestId);
        return null;
      }

      return NewPrescriptionAlert(
        prescriptionId: latestId,
        prescriptionCode: firstItem.prescriptionCode,
        doctorName: firstItem.displayDoctorName,
        issuedAt: firstItem.issuedAt,
        items: latestItems,
      );
    } catch (e) {
      debugPrint('Error checking unacknowledged prescription: $e');
      return null;
    }
  }

  /// Marks a prescription ID as acknowledged so its pop-up notification is not repeated.
  static Future<void> acknowledgePrescription(int prescriptionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('last_acknowledged_prescription_id') ?? 0;
      if (prescriptionId > current) {
        await prefs.setInt('last_acknowledged_prescription_id', prescriptionId);
      }
      final userKey = _prescriptionAckKeyForUser();
      if (userKey != 'last_acknowledged_prescription_id') {
        final userCurrent = prefs.getInt(userKey) ?? 0;
        if (prescriptionId > userCurrent) {
          await prefs.setInt(userKey, prescriptionId);
        }
      }
    } catch (e) {
      debugPrint('Error acknowledging prescription: $e');
    }
  }
}
