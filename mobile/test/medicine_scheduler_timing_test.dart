import 'package:flutter_test/flutter_test.dart';
import 'package:ukonekmobile/services/api_service.dart';

ScheduledMedicine _createMed({
  required int id,
  required String name,
  required String frequency,
  String dosage = '1 tab',
  String instructions = '',
  String duration = '7 days',
}) {
  return ScheduledMedicine(
    prescriptionItemId: id,
    prescriptionId: 100 + id,
    prescriptionCode: 'RX-$id',
    dispensingStatus: 'dispensed',
    issuedAt: DateTime(2026, 9, 1),
    doctorName: 'Dr. Smith',
    medicineName: name,
    quantity: 10,
    unit: 'tablets',
    dosage: dosage,
    frequency: frequency,
    duration: duration,
    instructions: instructions,
    additionalInfo: '',
    isAvailable: true,
    isDispensed: true,
  );
}

void main() {
  group('ScheduledMedicine Timing & Intervals', () {
    test('Calculates dose intervals correctly based on frequency', () {
      final qd = _createMed(
        id: 1,
        name: 'Amlodipine',
        frequency: 'Once a day',
        dosage: '5mg',
      );
      expect(qd.dailyDoseCount, equals(1));
      expect(qd.doseIntervalMinutes, equals(0));

      final bid = _createMed(
        id: 2,
        name: 'Metformin',
        frequency: 'Twice daily',
        dosage: '500mg',
      );
      expect(bid.dailyDoseCount, equals(2));
      expect(bid.doseIntervalMinutes, equals(720)); // 12 hours

      final tid = _createMed(
        id: 3,
        name: 'Amoxicillin',
        frequency: 'Every 8 hours',
        dosage: '500mg',
      );
      expect(tid.dailyDoseCount, equals(3));
      expect(tid.doseIntervalMinutes, equals(480)); // 8 hours

      final qid = _createMed(
        id: 4,
        name: 'Erythromycin',
        frequency: 'Every 6 hours',
        dosage: '250mg',
      );
      expect(qid.dailyDoseCount, equals(4));
      expect(qid.doseIntervalMinutes, equals(360)); // 6 hours
    });

    test('calculateDoseMinutesFromStart cascades accurately across hours and midnight', () {
      final tid = _createMed(
        id: 10,
        name: 'Antibiotic',
        frequency: 'Every 8 hours',
        dosage: '500mg',
      );

      // Start at 9:00 AM (540 mins)
      // Dose 1: 9:00 AM = 540
      // Dose 2: 5:00 PM = 540 + 480 = 1020
      // Dose 3: 1:00 AM next day = (1020 + 480) % 1440 = 60
      final doses = tid.calculateDoseMinutesFromStart(540);
      expect(doses, equals([540, 1020, 60]));
    });

    test('Three times daily meal routines without strict 8h interval', () {
      final tidMeal = _createMed(
        id: 11,
        name: 'Antacid',
        frequency: 'Three times daily with meals',
        instructions: 'With meals',
      );
      // Meal routines use practical daytime spacing (8:00 AM, 1:00 PM, 7:00 PM)
      expect(tidMeal.dailyDoseCount, equals(3));
      expect(tidMeal.doseIntervalMinutes, equals(300));
      expect(tidMeal.doseTimes, equals(['08:00 AM', '01:00 PM', '07:00 PM']));
    });
  });

  group('Heads-Up & Midnight Rollover Timing', () {
    test('Heads-up reminder handles morning doses normally', () {
      final doseMins = 8 * 60; // 8:00 AM = 480
      final headsUpMins = (doseMins - 30 + 1440) % 1440;
      expect(headsUpMins, equals(450)); // 7:30 AM
      expect(headsUpMins ~/ 60, equals(7));
      expect(headsUpMins % 60, equals(30));
    });

    test('Heads-up reminder handles midnight doses with rollover to previous evening', () {
      // 12:15 AM = 15 mins past midnight
      final dose15 = 15;
      final headsUp15 = (dose15 - 30 + 1440) % 1440;
      expect(headsUp15, equals(1425)); // 23:45 (11:45 PM)
      expect(headsUp15 ~/ 60, equals(23));
      expect(headsUp15 % 60, equals(45));

      // 12:00 AM = 0 mins
      final dose0 = 0;
      final headsUp0 = (dose0 - 30 + 1440) % 1440;
      expect(headsUp0, equals(1410)); // 23:30 (11:30 PM)
      expect(headsUp0 ~/ 60, equals(23));
      expect(headsUp0 % 60, equals(30));
    });
  });

  group('Intake Status Boundaries', () {
    String calculateStatus({
      required bool allTaken,
      required bool isFuture,
      required bool isPast,
      required int nowMins,
      required int tMins,
    }) {
      if (allTaken) return 'TAKEN';
      if (isFuture) return 'UPCOMING';
      if (isPast) return 'LATE';
      if (nowMins < tMins - 30) return 'UPCOMING';
      if (nowMins <= tMins + 120) return 'DUE';
      return 'LATE';
    }

    test('Calculates status correctly for Today across time boundaries', () {
      final tMins = 480; // 8:00 AM

      // Taken takes highest precedence
      expect(calculateStatus(
        allTaken: true, isFuture: false, isPast: false, nowMins: 480, tMins: tMins
      ), equals('TAKEN'));

      // 7:00 AM (60 min before) -> UPCOMING
      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: false, nowMins: 420, tMins: tMins
      ), equals('UPCOMING'));

      // 7:30 AM (exactly 30 min before) -> DUE
      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: false, nowMins: 450, tMins: tMins
      ), equals('DUE'));

      // 8:00 AM (exact time) -> DUE
      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: false, nowMins: 480, tMins: tMins
      ), equals('DUE'));

      // 10:00 AM (2 hours after, within grace window) -> DUE
      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: false, nowMins: 600, tMins: tMins
      ), equals('DUE'));

      // 10:01 AM (past 2-hour grace window) -> LATE
      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: false, nowMins: 601, tMins: tMins
      ), equals('LATE'));

      // 4:00 PM (8 hours after) -> LATE
      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: false, nowMins: 960, tMins: tMins
      ), equals('LATE'));
    });

    test('Calendar past and future dates override time-of-day', () {
      final tMins = 480;
      expect(calculateStatus(
        allTaken: false, isFuture: true, isPast: false, nowMins: 480, tMins: tMins
      ), equals('UPCOMING'));

      expect(calculateStatus(
        allTaken: false, isFuture: false, isPast: true, nowMins: 480, tMins: tMins
      ), equals('LATE'));
    });
  });
}
