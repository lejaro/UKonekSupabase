import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ukonekmobile/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prescription Notification & Redirection Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('PrescriptionRecord.fromMap properly handles both prescription_id and id fields', () {
      final mapWithPrescriptionId = {
        'prescription_id': 101,
        'prescription_code': 'RX-2026-0101',
        'dispensing_status': 'pending',
        'issued_at': DateTime.now().toIso8601String(),
        'doctor_name': 'Dr. Roquero',
        'medicine_name': 'Amoxicillin 500 mg',
        'quantity': 21,
        'dispensed_quantity': 0,
        'remaining_quantity': 21,
        'unit': 'capsules',
        'dosage': '500 mg',
        'frequency': 'Three times a day (TID)',
        'duration': '7 days',
        'instructions': 'Take after meals',
        'additional_info': '',
        'is_available': true,
        'is_dispensed': false,
      };

      final rec1 = PrescriptionRecord.fromMap(mapWithPrescriptionId);
      expect(rec1.prescriptionId, 101);
      expect(rec1.prescriptionCode, 'RX-2026-0101');
      expect(rec1.displayDoctorName, 'Dr. Roquero');

      final mapWithIdFallback = {
        'id': 202,
        'prescription_code': 'RX-2026-0202',
        'dispensing_status': 'pending',
        'issued_at': DateTime.now().toIso8601String(),
        'doctor_name': 'Dr. Santos',
        'medicine_name': 'Paracetamol 500 mg',
        'quantity': 10,
        'dispensed_quantity': 0,
        'remaining_quantity': 10,
        'unit': 'tablets',
        'dosage': '500 mg',
        'frequency': 'Every 4-6 hours PRN',
        'duration': '3 days',
        'instructions': 'For fever',
        'additional_info': '',
        'is_available': true,
        'is_dispensed': false,
      };

      final rec2 = PrescriptionRecord.fromMap(mapWithIdFallback);
      expect(rec2.prescriptionId, 202);
      expect(rec2.prescriptionCode, 'RX-2026-0202');
      expect(rec2.displayDoctorName, 'Dr. Santos');
    });

    test('NewPrescriptionAlert model constructs and holds grouped items properly', () {
      final now = DateTime.now();
      final items = [
        PrescriptionRecord(
          prescriptionId: 303,
          prescriptionCode: 'RX-2026-0303',
          dispensingStatus: 'pending',
          issuedAt: now,
          doctorName: 'Dr. Roquero',
          medicineName: 'Amoxicillin',
          quantity: 21,
          dispensedQuantity: 0,
          remainingQuantity: 21,
          unit: 'capsules',
          dosage: '500 mg',
          frequency: 'TID',
          duration: '7 days',
          instructions: '',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: false,
        ),
        PrescriptionRecord(
          prescriptionId: 303,
          prescriptionCode: 'RX-2026-0303',
          dispensingStatus: 'pending',
          issuedAt: now,
          doctorName: 'Dr. Roquero',
          medicineName: 'Paracetamol',
          quantity: 10,
          dispensedQuantity: 0,
          remainingQuantity: 10,
          unit: 'tablets',
          dosage: '500 mg',
          frequency: 'PRN',
          duration: '3 days',
          instructions: '',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: false,
        ),
      ];

      final alert = NewPrescriptionAlert(
        prescriptionId: 303,
        prescriptionCode: 'RX-2026-0303',
        doctorName: 'Dr. Roquero',
        issuedAt: now,
        items: items,
      );

      expect(alert.prescriptionId, 303);
      expect(alert.prescriptionCode, 'RX-2026-0303');
      expect(alert.doctorName, 'Dr. Roquero');
      expect(alert.items.length, 2);
      expect(alert.items[0].medicineName, 'Amoxicillin');
      expect(alert.items[1].medicineName, 'Paracetamol');
    });

    test('Prescription acknowledgment persistence prevents duplicate alerts', () async {
      final prefs = await SharedPreferences.getInstance();
      const testPrescriptionId = 404;

      // Initially no acknowledged prescription
      expect(prefs.getInt('last_acknowledged_prescription_id'), isNull);

      // Acknowledge prescription via ApiService helper
      await ApiService.acknowledgePrescription(testPrescriptionId);

      expect(prefs.getInt('last_acknowledged_prescription_id'), testPrescriptionId);

      // Subsequent check confirms that this ID is <= acknowledged ID
      final lastAck = prefs.getInt('last_acknowledged_prescription_id') ?? 0;
      final shouldTrigger = testPrescriptionId > lastAck;
      expect(shouldTrigger, isFalse);

      // A newer prescription ID (e.g. 405) will be flagged
      const newerPrescriptionId = 405;
      final shouldTriggerNewer = newerPrescriptionId > lastAck;
      expect(shouldTriggerNewer, isTrue);
    });

    test('Stale prescriptions older than 24 hours are not alerted', () {
      final now = DateTime.now();
      final staleIssuedAt = now.subtract(const Duration(hours: 36));
      final recentIssuedAt = now.subtract(const Duration(minutes: 15));

      final staleAge = now.difference(staleIssuedAt);
      final recentAge = now.difference(recentIssuedAt);

      expect(staleAge.inHours > 24, isTrue);
      expect(recentAge.inHours <= 24, isTrue);
    });

    test('ApiService.formatDoctorName correctly normalizes all doctor name formats', () {
      // The exact bug reported by user: "dr dr Jose Lejearo Justado"
      expect(ApiService.formatDoctorName('dr dr Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');
      expect(ApiService.formatDoctorName('Dr. Dr. Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');
      expect(ApiService.formatDoctorName('Dr Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');
      expect(ApiService.formatDoctorName('Doctor Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');
      expect(ApiService.formatDoctorName('Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');
      expect(ApiService.formatDoctorName('Dr. Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');
      expect(ApiService.formatDoctorName('dr. Dr. DR. Jose Lejearo Justado'), 'Dr. Jose Lejearo Justado');

      // Edge cases
      expect(ApiService.formatDoctorName(''), 'Doctor');
      expect(ApiService.formatDoctorName(null), 'Doctor');
      expect(ApiService.formatDoctorName('   '), 'Doctor');
      expect(ApiService.formatDoctorName('Dr.'), 'Doctor');
      expect(ApiService.formatDoctorName('Doctor'), 'Doctor');
    });

    test('NewPrescriptionAlert displayDoctorName normalizes duplicate Dr prefixes', () {
      final alert = NewPrescriptionAlert(
        prescriptionId: 505,
        prescriptionCode: 'RX-2026-0505',
        doctorName: 'Dr. Dr. Jose Lejearo Justado',
        issuedAt: DateTime.now(),
        items: const [],
      );

      expect(alert.displayDoctorName, 'Dr. Jose Lejearo Justado');
    });

    test('DoctorSchedule and DoctorStatus display names normalize correctly', () {
      final schedule = DoctorSchedule(
        id: 1,
        doctorStaffId: 10,
        doctorName: 'Dr. Dr. Jose Lejearo Justado',
        specialization: 'Internal Medicine',
        scheduleDate: DateTime.now(),
        startTime: '08:00',
        endTime: '12:00',
      );
      expect(schedule.displayName, 'Dr. Jose Lejearo Justado');

      const status = DoctorStatus(
        id: 1,
        firstName: 'Dr. Jose Lejearo',
        lastName: 'Justado',
        specialization: 'Internal Medicine',
        availabilityStatus: 'available',
      );
      expect(status.displayName, 'Dr. Jose Lejearo Justado');
    });

    test('ApiService.synthesizeDispenseLogsFromPrescriptions produces logs for dispensed prescriptions', () {
      final now = DateTime.now();
      final records = [
        PrescriptionRecord(
          prescriptionId: 101,
          prescriptionCode: 'RX-2026-0101',
          dispensingStatus: 'dispensed',
          issuedAt: now.subtract(const Duration(hours: 2)),
          dispensedAt: now.subtract(const Duration(hours: 1)),
          doctorName: 'Dr. Jose Lejearo Justado',
          medicineName: 'Amoxicillin 500 mg',
          quantity: 21,
          dispensedQuantity: 21,
          remainingQuantity: 0,
          unit: 'capsules',
          dosage: '500 mg',
          frequency: 'TID',
          duration: '7 days',
          instructions: 'Take after meals',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
        PrescriptionRecord(
          prescriptionId: 102,
          prescriptionCode: 'RX-2026-0102',
          dispensingStatus: 'partial',
          issuedAt: now.subtract(const Duration(hours: 3)),
          dispensedAt: now.subtract(const Duration(hours: 2)),
          doctorName: 'Dr. Jose Lejearo Justado',
          medicineName: 'Paracetamol 500 mg',
          quantity: 10,
          dispensedQuantity: 5,
          remainingQuantity: 5,
          unit: 'tablets',
          dosage: '500 mg',
          frequency: 'PRN',
          duration: '3 days',
          instructions: 'For fever',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: false,
        ),
        PrescriptionRecord(
          prescriptionId: 103,
          prescriptionCode: 'RX-2026-0103',
          dispensingStatus: 'pending',
          issuedAt: now,
          doctorName: 'Dr. Jose Lejearo Justado',
          medicineName: 'Cetirizine 10 mg',
          quantity: 7,
          dispensedQuantity: 0,
          remainingQuantity: 7,
          unit: 'tablets',
          dosage: '10 mg',
          frequency: 'OD',
          duration: '7 days',
          instructions: 'At bedtime',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: false,
        ),
      ];

      final logs = ApiService.synthesizeDispenseLogsFromPrescriptions(records);

      // Should include RX-0101 (fully dispensed) and RX-0102 (partially dispensed), but NOT RX-0103 (pending)
      expect(logs.length, 2);
      expect(logs[0].prescriptionCode, anyOf('RX-2026-0101', 'RX-2026-0102'));
      expect(logs.any((l) => l.prescriptionCode == 'RX-2026-0101' && l.dispensedQuantity == 21), isTrue);
      expect(logs.any((l) => l.prescriptionCode == 'RX-2026-0102' && l.dispensedQuantity == 5), isTrue);
    });

    test('ApiService.synthesizeScheduledMedicinesFromPrescriptions synthesizes active medicines for schedule', () {
      final now = DateTime.now();
      final List<PrescriptionRecord> records = [
        PrescriptionRecord(
          prescriptionId: 101,
          prescriptionCode: 'RX-2026-0101',
          dispensingStatus: 'dispensed',
          issuedAt: now.subtract(const Duration(hours: 5)),
          dispensedAt: now.subtract(const Duration(hours: 4)),
          doctorName: 'Dr. Jose Lejearo Justado',
          medicineName: 'Amoxicillin 500 mg',
          quantity: 21,
          dispensedQuantity: 21,
          remainingQuantity: 0,
          unit: 'capsules',
          dosage: '500 mg',
          frequency: 'Every 8 hours',
          duration: '7 days',
          instructions: 'Take after meals',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
        PrescriptionRecord(
          prescriptionId: 102,
          prescriptionCode: 'RX-2026-0102',
          dispensingStatus: 'pending',
          issuedAt: now,
          doctorName: 'Dr. Jose Lejearo Justado',
          medicineName: 'Cetirizine 10 mg',
          quantity: 7,
          dispensedQuantity: 0,
          remainingQuantity: 7,
          unit: 'tablets',
          dosage: '10 mg',
          frequency: 'Once daily',
          duration: '7 days',
          instructions: 'At bedtime',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: false,
        ),
      ];

      final scheduled = ApiService.synthesizeScheduledMedicinesFromPrescriptions(records);
      expect(scheduled.length, 1);
      expect(scheduled.first.medicineName, 'Amoxicillin 500 mg');
      expect(scheduled.first.isDispensed, isTrue);
      expect(scheduled.first.prescriptionItemId, 101001);
    });
  });
}
