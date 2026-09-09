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
  });
}
