import 'package:flutter_test/flutter_test.dart';
import 'package:ukonekmobile/models/models.dart';
import 'package:ukonekmobile/services/prescription_service.dart';

void main() {
  group('Medicine Scheduler Deduplication & Synthesis Tests', () {
    test('Deduplicates remote schedule items and synthesized prescription items cleanly', () {
      final remoteMeds = [
        ScheduledMedicine(
          prescriptionItemId: 42,
          prescriptionId: 10,
          prescriptionCode: 'RX-1001',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 10, 8, 0),
          dispensedAt: DateTime(2026, 9, 10, 9, 0),
          doctorName: 'Dr. Cruz',
          medicineName: 'Amoxicillin 500mg',
          quantity: 21,
          unit: 'capsules',
          dosage: '500mg',
          frequency: 'TID',
          duration: '7 days',
          instructions: 'After meals',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
      ];

      final prescriptions = [
        PrescriptionRecord(
          prescriptionId: 10,
          prescriptionItemId: 42,
          prescriptionCode: 'RX-1001',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 10, 8, 0),
          dispensedAt: DateTime(2026, 9, 10, 9, 0),
          doctorName: 'Dr. Cruz',
          medicineName: 'Amoxicillin 500mg',
          quantity: 21,
          dispensedQuantity: 21,
          remainingQuantity: 0,
          unit: 'capsules',
          dosage: '500mg',
          frequency: 'TID',
          duration: '7 days',
          instructions: 'After meals',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
      ];

      final synthesized = PrescriptionService.synthesizeScheduledMedicinesFromPrescriptions(prescriptions);
      expect(synthesized.length, equals(1));

      // Even if synthesized had a different ID (e.g. synthetic fallback)
      final synthesizedFallback = [
        ScheduledMedicine(
          prescriptionItemId: 10001,
          prescriptionId: 10,
          prescriptionCode: 'RX-1001',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 10, 8, 0),
          dispensedAt: DateTime(2026, 9, 10, 9, 0),
          doctorName: 'Dr. Cruz',
          medicineName: 'Amoxicillin 500mg',
          quantity: 21,
          unit: 'capsules',
          dosage: '500mg',
          frequency: 'TID',
          duration: '7 days',
          instructions: 'After meals',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
      ];

      final merged = PrescriptionService.deduplicateMedicines(remoteMeds, synthesizedFallback);

      // Must be EXACTLY ONE item - NO DUPLICATION
      expect(merged.length, equals(1));
      expect(merged.first.prescriptionItemId, equals(42));
      expect(merged.first.medicineName, equals('Amoxicillin 500mg'));
    });

    test('Preserves multiple distinct medicines on the same prescription without collision', () {
      final prescriptions = [
        PrescriptionRecord(
          prescriptionId: 15,
          prescriptionItemId: 101,
          prescriptionCode: 'RX-2002',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 11),
          doctorName: 'Dr. Santos',
          medicineName: 'Amoxicillin 500mg',
          quantity: 21,
          dispensedQuantity: 21,
          remainingQuantity: 0,
          unit: 'capsules',
          dosage: '500mg',
          frequency: 'TID',
          duration: '7 days',
          instructions: '',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
        PrescriptionRecord(
          prescriptionId: 15,
          prescriptionItemId: 102,
          prescriptionCode: 'RX-2002',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 11),
          doctorName: 'Dr. Santos',
          medicineName: 'Paracetamol 500mg',
          quantity: 10,
          dispensedQuantity: 10,
          remainingQuantity: 0,
          unit: 'tablets',
          dosage: '500mg',
          frequency: 'PRN',
          duration: '5 days',
          instructions: 'For fever',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
      ];

      final synthesized = PrescriptionService.synthesizeScheduledMedicinesFromPrescriptions(prescriptions);
      expect(synthesized.length, equals(2));
      expect(synthesized[0].prescriptionItemId, isNot(equals(synthesized[1].prescriptionItemId)));

      final deduplicated = PrescriptionService.deduplicateMedicines(synthesized);
      expect(deduplicated.length, equals(2));
      expect(deduplicated.map((m) => m.medicineName), containsAll(['Amoxicillin 500mg', 'Paracetamol 500mg']));
    });

    test('Synthesis cleanly fills in a newly dispensed Rx missing from remote schedule', () {
      final remoteMeds = [
        ScheduledMedicine(
          prescriptionItemId: 1,
          prescriptionId: 5,
          prescriptionCode: 'RX-001',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 1),
          doctorName: 'Dr. Lee',
          medicineName: 'Cetirizine 10mg',
          quantity: 7,
          unit: 'tablets',
          dosage: '10mg',
          frequency: 'OD',
          duration: '7 days',
          instructions: '',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
      ];

      final newlyDispensed = [
        PrescriptionRecord(
          prescriptionId: 6,
          prescriptionItemId: 55,
          prescriptionCode: 'RX-002',
          dispensingStatus: 'dispensed',
          issuedAt: DateTime(2026, 9, 12),
          doctorName: 'Dr. Lee',
          medicineName: 'Ibuprofen 400mg',
          quantity: 6,
          dispensedQuantity: 6,
          remainingQuantity: 0,
          unit: 'tablets',
          dosage: '400mg',
          frequency: 'BID',
          duration: '3 days',
          instructions: '',
          additionalInfo: '',
          isAvailable: true,
          isDispensed: true,
        ),
      ];

      final synthesized = PrescriptionService.synthesizeScheduledMedicinesFromPrescriptions(newlyDispensed);
      final merged = PrescriptionService.deduplicateMedicines(remoteMeds, synthesized);

      expect(merged.length, equals(2));
      expect(merged.any((m) => m.medicineName == 'Cetirizine 10mg'), isTrue);
      expect(merged.any((m) => m.medicineName == 'Ibuprofen 400mg'), isTrue);
    });
  });

  group('Liquid & Container Packaging Dose Calculations', () {
    test('Liquid suspension with quantity 1 and 7-day duration produces 21 doses, NOT 1', () {
      final liquidMed = ScheduledMedicine(
        prescriptionItemId: 200,
        prescriptionId: 50,
        prescriptionCode: 'RX-50',
        dispensingStatus: 'dispensed',
        issuedAt: DateTime(2026, 9, 10, 8, 0),
        dispensedAt: DateTime(2026, 9, 10, 9, 0),
        doctorName: 'Dr. Cruz',
        medicineName: 'Amoxicillin Suspension 60ml',
        quantity: 1, // 1 bottle dispensed
        unit: 'bottle',
        dosage: '250mg/5ml',
        frequency: 'TID', // 3 times daily
        duration: '7 days',
        instructions: 'Take 5ml after meals',
        additionalInfo: '',
        isAvailable: true,
        isDispensed: true,
      );

      expect(liquidMed.isDiscreteUnit, isFalse);
      expect(liquidMed.dailyDoseCount, equals(3));
      expect(liquidMed.durationDays, equals(7));
      expect(liquidMed.totalPrescribedDoses, equals(21)); // 7 days * 3 doses = 21 doses!

      // Verify it remains active on day 2, day 5, and day 7
      expect(liquidMed.isActiveOn(DateTime(2026, 9, 10)), isTrue);
      expect(liquidMed.isActiveOn(DateTime(2026, 9, 11)), isTrue);
      expect(liquidMed.isActiveOn(DateTime(2026, 9, 14)), isTrue);
      expect(liquidMed.isActiveOn(DateTime(2026, 9, 16)), isTrue);
    });

    test('Liquid bottle with no duration specified defaults to 30 active days, NOT 1 day', () {
      final syrupMed = ScheduledMedicine(
        prescriptionItemId: 201,
        prescriptionId: 51,
        prescriptionCode: 'RX-51',
        dispensingStatus: 'dispensed',
        issuedAt: DateTime(2026, 9, 10),
        doctorName: 'Dr. Cruz',
        medicineName: 'Cough Syrup 120ml',
        quantity: 1,
        unit: 'syrup',
        dosage: '10ml',
        frequency: 'BID',
        duration: '',
        instructions: '',
        additionalInfo: '',
        isAvailable: true,
        isDispensed: true,
      );

      expect(syrupMed.isDiscreteUnit, isFalse);
      expect(syrupMed.dailyDoseCount, equals(2));
      expect(syrupMed.durationDays, equals(30));
      expect(syrupMed.totalPrescribedDoses, equals(60)); // 30 days * 2 = 60 doses
      expect(syrupMed.isActiveOn(DateTime(2026, 9, 20)), isTrue);
    });

    test('Discrete tablets partial dispense respects smaller quantity', () {
      final partialTabs = ScheduledMedicine(
        prescriptionItemId: 202,
        prescriptionId: 52,
        prescriptionCode: 'RX-52',
        dispensingStatus: 'partial',
        issuedAt: DateTime(2026, 9, 10),
        doctorName: 'Dr. Cruz',
        medicineName: 'Amoxicillin 500mg',
        quantity: 6, // only 6 tablets received
        unit: 'tablets',
        dosage: '500mg',
        frequency: 'TID',
        duration: '7 days', // prescribed for 7 days (21 doses)
        instructions: '',
        additionalInfo: '',
        isAvailable: true,
        isDispensed: true,
      );

      expect(partialTabs.isDiscreteUnit, isTrue);
      expect(partialTabs.dailyDoseCount, equals(3));
      // Clamped to 6 actual dispensed units
      expect(partialTabs.totalPrescribedDoses, equals(6));
    });
  });
}
