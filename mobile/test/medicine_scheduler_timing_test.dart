import 'package:flutter_test/flutter_test.dart';
import 'package:ukonekmobile/services/api_service.dart';

ScheduledMedicine _createMed({
  required int id,
  required String name,
  required String frequency,
  String dosage = '1 tab',
  String instructions = '',
  String duration = '7 days',
  int? quantity,
  DateTime? issuedAt,
  DateTime? dispensedAt,
}) {
  return ScheduledMedicine(
    prescriptionItemId: id,
    prescriptionId: 100 + id,
    prescriptionCode: 'RX-$id',
    dispensingStatus: 'dispensed',
    issuedAt: issuedAt ?? DateTime(2026, 9, 1),
    dispensedAt: dispensedAt,
    doctorName: 'Dr. Smith',
    medicineName: name,
    quantity: quantity ?? 10,
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

int _parseTime(String t) {
  try {
    final clean = t.trim().replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
    final match = RegExp(r'(\d{1,2}):(\d{2})(?:\s*([AP]M?|[ap]m?))?', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      int h = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      final period = match.group(3)?.toUpperCase().replaceAll('.', '');
      if (period == 'PM' || period == 'P') {
        if (h != 12) h += 12;
      } else if (period == 'AM' || period == 'A') {
        if (h == 12) h = 0;
      }
      return (h % 24) * 60 + m;
    }
    final simpleMatch = RegExp(r'(\d{1,2})\s*([AP]M?|[ap]m?)', caseSensitive: false).firstMatch(clean);
    if (simpleMatch != null) {
      int h = int.parse(simpleMatch.group(1)!);
      final period = simpleMatch.group(2)!.toUpperCase().replaceAll('.', '');
      if ((period == 'PM' || period == 'P') && h != 12) h += 12;
      if ((period == 'AM' || period == 'A') && h == 12) h = 0;
      return (h % 24) * 60;
    }
    return 0;
  } catch (_) {
    return 0;
  }
}

String _getIntakeStatus({
  required String timeStr,
  required bool allTaken,
  required bool isToday,
  required bool isFuture,
  required bool isPast,
  required int nowMins,
}) {
  if (allTaken) return 'TAKEN';
  if (isFuture) return 'UPCOMING';
  if (isPast) return 'LATE';

  int tMins = _parseTime(timeStr);
  if (tMins == 0 && (timeStr.startsWith('12') || timeStr.contains('12:00'))) {
    tMins = 1440;
  }

  int diff;
  if (tMins == 1440 && nowMins < 240) {
    diff = 1440 - (1440 + nowMins);
  } else {
    diff = tMins - nowMins;
  }

  if (diff <= 30 && diff >= -120) {
    return 'DUE';
  } else if (diff > 30) {
    return 'UPCOMING';
  } else {
    return 'LATE';
  }
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
      // Outpatient waking-hour schedule (6 AM, 2 PM, 10 PM)
      expect(tid.doseTimes, equals(['06:00 AM', '02:00 PM', '10:00 PM']));

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
      expect(tidMeal.dailyDoseCount, equals(3));
      expect(tidMeal.doseIntervalMinutes, equals(300));
      expect(tidMeal.doseTimes, equals(['08:00 AM', '01:00 PM', '07:00 PM']));
    });

    test('English preposition "on" is not confused with Latin omni nocte (o.n.)', () {
      final medPreposition = _createMed(
        id: 12,
        name: 'Omeprazole',
        frequency: 'Take 1 capsule on an empty stomach daily',
      );
      expect(medPreposition.dailyDoseCount, equals(1));
      // Must NOT default to 08:00 PM (nightly)! Should be morning 08:00 AM.
      expect(medPreposition.doseTimes, equals(['08:00 AM']));

      final medNight = _createMed(
        id: 13,
        name: 'Simvastatin',
        frequency: 'Take 1 tablet every night at bedtime',
      );
      expect(medNight.dailyDoseCount, equals(1));
      expect(medNight.doseTimes, equals(['09:00 PM']));
    });
  });

  group('Dispense-Day Retrospective Overdue Prevention', () {
    test('Doses before dispense time on day 1 are not considered active', () {
      final today = DateTime(2026, 9, 9);
      // Dispensed today at 4:30 PM (16:30 = 990 mins)
      final dispensedTime = DateTime(2026, 9, 9, 16, 30);
      final med = _createMed(
        id: 20,
        name: 'Antibiotic',
        frequency: 'Three times daily',
        issuedAt: DateTime(2026, 9, 9, 10, 0),
        dispensedAt: dispensedTime,
      );

      // Morning dose (8:00 AM = 480 mins) is prior to dispense time -> inactive on day 1
      expect(med.isDoseActiveOn(today, 480), isFalse);

      // Lunch dose (1:00 PM = 780 mins) is prior to dispense time -> inactive on day 1
      expect(med.isDoseActiveOn(today, 780), isFalse);

      // Evening dose (7:00 PM = 1140 mins) is after dispense time -> active!
      expect(med.isDoseActiveOn(today, 1140), isTrue);

      // Tomorrow all doses are active
      final tomorrow = today.add(const Duration(days: 1));
      expect(med.isDoseActiveOn(tomorrow, 480), isTrue);
      expect(med.isDoseActiveOn(tomorrow, 780), isTrue);
      expect(med.isDoseActiveOn(tomorrow, 1140), isTrue);
    });
  });

  group('Midnight (12:00 AM) & Circular Status Timing', () {
    test('12:00 AM bedtime dose is UPCOMING during morning/day, DUE near midnight, and never falsely overdue', () {
      const timeStr = '12:00 AM';

      // 8:00 AM (480 mins) -> UPCOMING (in 16 hours), NOT OVERDUE!
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 480),
        equals('UPCOMING'),
      );

      // 4:00 PM (960 mins) -> UPCOMING (in 8 hours)
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 960),
        equals('UPCOMING'),
      );

      // 11:15 PM (1395 mins, 45 min before midnight) -> UPCOMING
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 1395),
        equals('UPCOMING'),
      );

      // 11:35 PM (1415 mins, 25 min before midnight) -> DUE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 1415),
        equals('DUE'),
      );

      // 12:00 AM (0 mins, exact time) -> DUE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 0),
        equals('DUE'),
      );

      // 12:30 AM (30 mins past midnight, within 120 min grace) -> DUE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 30),
        equals('DUE'),
      );

      // 2:05 AM (125 mins past midnight, grace period elapsed) -> LATE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 125),
        equals('LATE'),
      );
    });

    test('Standard daytime doses follow [-30m, +120m] window accurately', () {
      const timeStr = '08:00 AM'; // 480 mins

      // 7:00 AM (420 mins) -> UPCOMING
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 420),
        equals('UPCOMING'),
      );

      // 7:30 AM (450 mins, exactly 30 mins before) -> DUE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 450),
        equals('DUE'),
      );

      // 8:00 AM (480 mins, exact time) -> DUE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 480),
        equals('DUE'),
      );

      // 10:00 AM (600 mins, exactly 120 mins after) -> DUE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 600),
        equals('DUE'),
      );

      // 10:01 AM (601 mins, past 120 mins grace) -> LATE
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: false, isToday: true, isFuture: false, isPast: false, nowMins: 601),
        equals('LATE'),
      );

      // Marked taken overrides time
      expect(
        _getIntakeStatus(timeStr: timeStr, allTaken: true, isToday: true, isFuture: false, isPast: false, nowMins: 601),
        equals('TAKEN'),
      );
    });

    test('Late Intake: On-time intake within 45 minutes triggers no shift', () {
      final tid = _createMed(id: 30, name: 'Amoxicillin', frequency: 'Three times daily');
      // Scheduled: 08:00 AM (480), 01:00 PM (780), 07:00 PM (1140)
      // Taken at 08:30 AM (510) -> delay = 30m (< 45m)
      final shifts = tid.computeLateIntakeShifts(
        takenDoseIndex: 0,
        actualTakenMinutes: 510,
        currentScheduledMinutes: [480, 780, 1140],
      );
      expect(shifts, isEmpty);
    });

    test('Late Intake: Violating minimum safe gap shifts subsequent doses with proper intervals', () {
      final tid = _createMed(id: 31, name: 'Amoxicillin', frequency: 'Three times daily'); // interval 5h (300m), minSafeGap 4h (240m)
      // Scheduled: 08:00 AM (480), 01:00 PM (780), 07:00 PM (1140)
      // Taken at 11:30 AM (690) -> delay = 210m, gap to next (780 - 690 = 90m) < minSafeGap (240m)
      final shifts = tid.computeLateIntakeShifts(
        takenDoseIndex: 0,
        actualTakenMinutes: 690,
        currentScheduledMinutes: [480, 780, 1140],
      );
      expect(shifts.length, equals(2));
      expect(shifts[1], equals(690 + 300)); // 990 = 04:30 PM
      expect(shifts[2], equals(990 + 300)); // 1290 = 09:30 PM
    });

    test('Late Intake: Shifts are clamped to bedtime (10:30 PM / 1350m)', () {
      final tid = _createMed(id: 32, name: 'Amoxicillin', frequency: 'Three times daily'); // interval 5h (300m)
      // Dose 1 taken at 06:30 PM (1110)
      // Dose 2 would normally be 1110 + 300 = 1410 (11:30 PM)
      // Clamped to 10:30 PM (1350)
      final shifts = tid.computeLateIntakeShifts(
        takenDoseIndex: 1,
        actualTakenMinutes: 1110,
        currentScheduledMinutes: [480, 780, 1140],
      );
      expect(shifts.length, equals(1));
      expect(shifts[2], equals(1350));
    });

    test('Late Intake: Twice-daily regimen does not shift if safe gap (8h) is preserved', () {
      final bid = _createMed(id: 33, name: 'Metformin', frequency: 'Twice daily');
      // Scheduled: 08:00 AM (480), 08:00 PM (1200)
      // Taken at 09:30 AM (570) -> delay = 90m, but gap to 08:00 PM is 1200 - 570 = 630m (10.5h) >= 480m
      final shifts = bid.computeLateIntakeShifts(
        takenDoseIndex: 0,
        actualTakenMinutes: 570,
        currentScheduledMinutes: [480, 1200],
      );
      expect(shifts, isEmpty);

      // But taken at 02:00 PM (840) -> delay = 360m, gap to 08:00 PM is 360m (6h) < 480m -> shifts
      final shiftsLate = bid.computeLateIntakeShifts(
        takenDoseIndex: 0,
        actualTakenMinutes: 840,
        currentScheduledMinutes: [480, 1200],
      );
      expect(shiftsLate.length, equals(1));
      expect(shiftsLate[1], equals(1350)); // 840 + 720 = 1560 clamped to 1350 (10:30 PM)
    });

    test('Late Intake: PRN and once-daily regimens return empty shifts', () {
      final qd = _createMed(id: 34, name: 'Amlodipine', frequency: 'Once daily');
      expect(
        qd.computeLateIntakeShifts(takenDoseIndex: 0, actualTakenMinutes: 700, currentScheduledMinutes: [480]),
        isEmpty,
      );

      final prn = _createMed(id: 35, name: 'Paracetamol', frequency: 'PRN as needed');
      expect(
        prn.computeLateIntakeShifts(takenDoseIndex: 0, actualTakenMinutes: 700, currentScheduledMinutes: []),
        isEmpty,
      );
    });
  });

  group('Continuous Rolling 24/7 Regimen (User Problem Verification)', () {
    test('Bioflu q8h started at 5:00 PM Wednesday schedules 1:00 AM Thursday, not 6:00 AM', () {
      final wed = DateTime(2026, 9, 9, 17, 0); // Wednesday, Sep 9, 2026 at 5:00 PM
      final bioflu = _createMed(
        id: 40,
        name: 'Bioflu',
        frequency: 'Every 8 hours',
        dosage: '250 mg',
        duration: '7 days',
        quantity: 21,
        issuedAt: DateTime(2026, 9, 9, 10, 0),
        dispensedAt: wed,
      );

      // Total doses for 7 days * 3 doses/day = 21 doses
      expect(bioflu.totalPrescribedDoses, equals(21));

      // Day 1: Wednesday Sep 9
      final wedDoses = bioflu.getDosesForDate(DateTime(2026, 9, 9));
      expect(wedDoses.length, equals(1));
      expect(wedDoses[0]['time'], equals('05:00 PM'));
      expect(wedDoses[0]['doseIndex'], equals(0));

      // Day 2: Thursday Sep 10 - MUST be 1:00 AM, 9:00 AM, 5:00 PM (NOT 6:00 AM!)
      final thuDoses = bioflu.getDosesForDate(DateTime(2026, 9, 10));
      expect(thuDoses.length, equals(3));
      expect(thuDoses[0]['time'], equals('01:00 AM')); // <--- 5:00 PM + 8 hours = 1:00 AM!
      expect(thuDoses[0]['doseIndex'], equals(0));
      expect(thuDoses[1]['time'], equals('09:00 AM')); // 1:00 AM + 8 hours = 9:00 AM
      expect(thuDoses[1]['doseIndex'], equals(1));
      expect(thuDoses[2]['time'], equals('05:00 PM')); // 9:00 AM + 8 hours = 5:00 PM
      expect(thuDoses[2]['doseIndex'], equals(2));

      // Day 3: Friday Sep 11 - MUST be 1:00 AM, 9:00 AM, 5:00 PM
      final friDoses = bioflu.getDosesForDate(DateTime(2026, 9, 11));
      expect(friDoses.length, equals(3));
      expect(friDoses[0]['time'], equals('01:00 AM'));
      expect(friDoses[1]['time'], equals('09:00 AM'));
      expect(friDoses[2]['time'], equals('05:00 PM'));

      // Day 8: Wednesday Sep 16 - Finishes the remaining 2 doses of the 21-tablet regimen
      final lastDayDoses = bioflu.getDosesForDate(DateTime(2026, 9, 16));
      expect(lastDayDoses.length, equals(2));
      expect(lastDayDoses[0]['time'], equals('01:00 AM'));
      expect(lastDayDoses[1]['time'], equals('09:00 AM'));

      // End date must extend to Sep 16 to encompass all 21 doses
      expect(bioflu.endDate, equals(DateTime(2026, 9, 16)));
    });

    test('Minute Precision: Custom start time 5:15 PM preserves minutes across all rolling doses', () {
      final wed = DateTime(2026, 9, 9, 17, 15); // 5:15 PM
      final med = _createMed(
        id: 41,
        name: 'Amoxicillin',
        frequency: 'Every 8 hours',
        dosage: '500 mg',
        dispensedAt: wed,
      );

      final wedDoses = med.getDosesForDate(DateTime(2026, 9, 9));
      expect(wedDoses.first['time'], equals('05:15 PM'));

      final thuDoses = med.getDosesForDate(DateTime(2026, 9, 10));
      expect(thuDoses.map((d) => d['time']).toList(), equals(['01:15 AM', '09:15 AM', '05:15 PM']));
    });

    test('Multiple Simultaneous Prescriptions coordinate harmoniously on the same day', () {
      final bioflu = _createMed(
        id: 51,
        name: 'Bioflu',
        frequency: 'Every 8 hours',
        dosage: '250 mg',
        dispensedAt: DateTime(2026, 9, 9, 17, 0), // 5:00 PM
      );
      final amox = _createMed(
        id: 52,
        name: 'Amoxicillin',
        frequency: 'Every 12 hours',
        dosage: '500 mg',
        dispensedAt: DateTime(2026, 9, 9, 18, 30), // 6:30 PM
      );
      final vitC = _createMed(
        id: 53,
        name: 'Vitamin C',
        frequency: 'Once daily',
        dosage: '500 mg',
        dispensedAt: DateTime(2026, 9, 9, 8, 0), // 8:00 AM
      );

      // Project onto Thursday Sep 10
      final thu = DateTime(2026, 9, 10);
      final List<Map<String, dynamic>> combinedDoses = [];
      combinedDoses.addAll(bioflu.getDosesForDate(thu));
      combinedDoses.addAll(amox.getDosesForDate(thu));
      combinedDoses.addAll(vitC.getDosesForDate(thu));

      // Sort chronologically
      combinedDoses.sort((a, b) => (a['mins'] as int).compareTo(b['mins'] as int));

      final timeline = combinedDoses.map((d) => '${d['time']} - ${(d['med'] as ScheduledMedicine).medicineName}').toList();

      expect(timeline, equals([
        '01:00 AM - Bioflu',
        '06:30 AM - Amoxicillin',
        '08:00 AM - Vitamin C',
        '09:00 AM - Bioflu',
        '05:00 PM - Bioflu',
        '06:30 PM - Amoxicillin',
      ]));
    });
  });
}
