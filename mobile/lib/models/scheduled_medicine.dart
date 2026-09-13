import 'package:intl/intl.dart';
import '../utils/formatters.dart';
class ScheduledMedicine {
  final int prescriptionItemId;
  final int prescriptionId;
  final String prescriptionCode;
  final String dispensingStatus;
  final DateTime issuedAt;
  final DateTime? dispensedAt;
  final String doctorName;
  final String medicineName;
  final int quantity;
  final String unit;
  final String dosage;
  final String frequency;
  final String duration;
  final String instructions;
  final String additionalInfo;
  final bool isAvailable;
  final bool isDispensed;

  const ScheduledMedicine({
    required this.prescriptionItemId,
    required this.prescriptionId,
    required this.prescriptionCode,
    required this.dispensingStatus,
    required this.issuedAt,
    this.dispensedAt,
    required this.doctorName,
    required this.medicineName,
    required this.quantity,
    required this.unit,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.instructions,
    required this.additionalInfo,
    required this.isAvailable,
    required this.isDispensed,
  });

  String get displayDoctorName => formatDoctorName(doctorName);

  int get dailyDoseCount {
    final f = frequency.toLowerCase().trim();
    if (f.isEmpty) return 1;

    // Check PRN / as needed first
    if (RegExp(r'\b(prn|as\s+needed|as-needed|p\.r\.n)\b').hasMatch(f)) return 0;
    if (RegExp(r'\b(stat)\b').hasMatch(f)) return 1;

    // Check specific frequency patterns with word boundaries
    if (RegExp(r'\b(q2h|every\s*2\s*h(ours?)?)\b').hasMatch(f)) return 12;
    if (RegExp(r'\b(q4h|every\s*4\s*h(ours?)?)\b').hasMatch(f)) return 6;
    if (RegExp(r'\b(qid|q6h|every\s*6\s*h(ours?)?|4\s*times?\s*(a|per)?\s*(day|daily)?|four\s*times?\s*(a|per)?\s*(day|daily)?)\b').hasMatch(f)) return 4;
    if (RegExp(r'\b(tid|thrice|q8h|every\s*8\s*h(ours?)?|3\s*times?\s*(a|per)?\s*(day|daily)?|three\s*times?\s*(a|per)?\s*(day|daily)?)\b').hasMatch(f)) return 3;
    if (RegExp(r'\b(bid|twice|q12h|every\s*12\s*h(ours?)?|2\s*times?\s*(a|per)?\s*(day|daily)?|two\s*times?\s*(a|per)?\s*(day|daily)?)\b').hasMatch(f)) return 2;
    if (RegExp(r'\b(od|om|o\.n\.|hs|once|daily|once\s*(a|per)?\s*(day|daily)?|every\s*day|every\s*morning|in\s*the\s*morning|every\s*night|at\s*night|nightly|every\s*evening|at\s*bedtime|q24h)\b').hasMatch(f)) return 1;

    final xday = RegExp(r'(\d+)\s*x').firstMatch(f);
    if (xday != null) return int.tryParse(xday.group(1)!) ?? 1;

    final hrs = RegExp(r'every\s+(\d+)\s+h').firstMatch(f);
    if (hrs != null) {
      final h = int.tryParse(hrs.group(1)!) ?? 8;
      return h > 0 ? (24 / h).floor() : 1;
    }
    final qhr = RegExp(r'q(\d+)h').firstMatch(f);
    if (qhr != null) {
      final h = int.tryParse(qhr.group(1)!) ?? 8;
      return h > 0 ? (24 / h).floor() : 1;
    }

    return 1;
  }

  bool get isDiscreteUnit {
    final u = unit.toLowerCase().trim();
    if (u.isEmpty) return true;
    return RegExp(r'\b(tablet|tab|tablets|capsule|cap|capsules|pill|pills|piece|pieces|pc|pcs)\b').hasMatch(u);
  }

  int get durationDays {
    final d = duration.toLowerCase();
    final match = RegExp(r'(\d+)').firstMatch(d);
    if (match != null) {
      final val = int.tryParse(match.group(1)!);
      if (val != null) {
        if (d.contains('week')) return val * 7;
        if (d.contains('month')) return val * 30;
        return val;
      }
    }
    if (dailyDoseCount > 0 && quantity > 0 && isDiscreteUnit) {
      return (quantity / dailyDoseCount).ceil();
    }
    return 30; // Default to 30 active days for dispensed medicines
  }

  static int parseTimeString(String t) {
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

  static String formatMinutesToTime(int totalMins) {
    final h = (totalMins ~/ 60) % 24;
    final m = totalMins % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${displayH.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  DateTime get startDate => dispensedAt ?? issuedAt;

  DateTime get endDate {
    if (dailyDoseCount <= 0) {
      return DateTime(startDate.year, startDate.month, startDate.day)
          .add(Duration(days: durationDays > 0 ? durationDays - 1 : 0));
    }
    final doses = getScheduledDoseDateTimes();
    if (doses.isNotEmpty) {
      final last = doses.last;
      return DateTime(last.year, last.month, last.day);
    }
    return DateTime(startDate.year, startDate.month, startDate.day)
        .add(Duration(days: durationDays > 0 ? durationDays - 1 : 0));
  }

  bool isActiveOn(DateTime date) {
    if (dailyDoseCount == 0) return true; // PRN / As-needed is always active
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(e) || d.isBefore(e));
  }

  /// Determines whether a specific dose time (in minutes from midnight) is active on [date].
  /// On the day the medicine is dispensed, doses earlier than the dispense time are excluded
  /// so patients are not greeted with false overdue doses before receiving the medication.
  bool isDoseActiveOn(DateTime date, int doseMinutes) {
    if (!isActiveOn(date)) return false;
    if (dailyDoseCount == 0) return true; // PRN always active
    if (dispensedAt != null) {
      final isDispenseDay = date.year == dispensedAt!.year &&
          date.month == dispensedAt!.month &&
          date.day == dispensedAt!.day;
      if (isDispenseDay) {
        final dispMinutes = dispensedAt!.hour * 60 + dispensedAt!.minute;
        if (doseMinutes < dispMinutes - 15) {
          return false;
        }
      }
    }
    return true;
  }

  int get doseIntervalMinutes {
    final count = dailyDoseCount;
    if (count <= 1) return 0;
    final f = frequency.toLowerCase().trim();
    if (RegExp(r'\b(q8h|every\s*8\s*h(ours?)?)\b').hasMatch(f)) return 8 * 60;
    if (RegExp(r'\b(q6h|every\s*6\s*h(ours?)?)\b').hasMatch(f)) return 6 * 60;
    if (RegExp(r'\b(q4h|every\s*4\s*h(ours?)?)\b').hasMatch(f)) return 4 * 60;
    final qMatch = RegExp(r'\b(?:q|every\s*)(\d+)\s*(?:h|hrs?|hours?)\b').firstMatch(f);
    if (qMatch != null) {
      final hours = int.tryParse(qMatch.group(1)!);
      if (hours != null && hours > 0) return hours * 60;
    }
    if (count == 2) return 12 * 60; // 12 hours (e.g. 8:00 AM, 8:00 PM)
    if (count == 3) return 5 * 60;  // 5-6 hours daytime interval (e.g. 8:00 AM, 1:00 PM, 7:00 PM)
    if (count == 4) return 5 * 60;  // 4-5 hours daytime interval (e.g. 7:00 AM, 12:00 PM, 5:00 PM, 9:00 PM)
    return (24 * 60) ~/ count;
  }

  int get totalPrescribedDoses {
    if (dailyDoseCount <= 0) return 0; // PRN

    // For non-discrete packaging (bottles, syrups, drops, suspensions, inhalers, tubes, packs, boxes):
    // quantity represents container count (e.g. 1 bottle), NOT dose count.
    if (!isDiscreteUnit) {
      if (durationDays > 0) return durationDays * dailyDoseCount;
      return dailyDoseCount * 30;
    }

    // For discrete units (tablets, capsules):
    if (durationDays > 0) {
      final expectedDoses = durationDays * dailyDoseCount;
      // If quantity is explicitly smaller (e.g. partial dispense), respect actual quantity
      if (quantity > 0 && quantity < expectedDoses) {
        return quantity;
      }
      return expectedDoses;
    }

    if (quantity > 0) return quantity;
    return dailyDoseCount * 30;
  }

  DateTime getAnchorStartDateTime({String? customStartTime}) {
    final sDate = startDate;
    int h = 8;
    int m = 0;

    if (customStartTime != null && customStartTime.trim().isNotEmpty) {
      final mins = parseTimeString(customStartTime);
      h = (mins ~/ 60) % 24;
      m = mins % 60;
    } else if (dispensedAt != null) {
      h = dispensedAt!.hour;
      m = dispensedAt!.minute;
    } else {
      final dTimes = doseTimes;
      if (dTimes.isNotEmpty) {
        final mins = parseTimeString(dTimes.first);
        h = (mins ~/ 60) % 24;
        m = mins % 60;
      }
    }
    return DateTime(sDate.year, sDate.month, sDate.day, h, m);
  }

  /// Calculates the continuous sequence of scheduled dose DateTimes from the start anchor across all days.
  List<DateTime> getScheduledDoseDateTimes({String? customStartTime, int? maxDoses}) {
    if (dailyDoseCount <= 0) return []; // PRN
    final anchor = getAnchorStartDateTime(customStartTime: customStartTime);
    final count = maxDoses ?? totalPrescribedDoses;
    if (count <= 0) return [];

    final f = frequency.toLowerCase().trim();
    final isMealRoutine = (count == 3 || count == 4) &&
        (f.contains('meal') || instructions.toLowerCase().contains('meal'));

    if (isMealRoutine) {
      // Daytime meal routine without midnight rolling
      final minsList = calculateDoseMinutesFromStart(anchor.hour * 60 + anchor.minute);
      final days = (count / dailyDoseCount).ceil();
      final List<DateTime> list = [];
      for (int d = 0; d < days; d++) {
        final dayDate = anchor.add(Duration(days: d));
        for (final m in minsList) {
          if (list.length >= count) break;
          final dt = DateTime(dayDate.year, dayDate.month, dayDate.day, (m ~/ 60) % 24, m % 60);
          if (d == 0 && dt.isBefore(anchor)) continue;
          list.add(dt);
        }
      }
      return list;
    }

    final isQ8h = RegExp(r'\b(q8h|every\s*8\s*h(ours?)?)\b').hasMatch(f);
    final isQ6h = RegExp(r'\b(q6h|every\s*6\s*h(ours?)?)\b').hasMatch(f);
    final isQ4h = RegExp(r'\b(q4h|every\s*4\s*h(ours?)?)\b').hasMatch(f);
    final isQ12h = RegExp(r'\b(q12h|every\s*12\s*h(ours?)?|bid|twice)\b').hasMatch(f);

    int interval;
    if (isQ8h) {
      interval = 8 * 60;
    } else if (isQ6h) {
      interval = 6 * 60;
    } else if (isQ4h) {
      interval = 4 * 60;
    } else if (isQ12h) {
      interval = 12 * 60;
    } else if (dailyDoseCount > 0) {
      interval = (24 * 60) ~/ dailyDoseCount;
    } else {
      interval = 24 * 60;
    }

    final List<DateTime> list = [];
    for (int i = 0; i < count; i++) {
      list.add(anchor.add(Duration(minutes: i * interval)));
    }
    return list;
  }

  /// Returns scheduled doses for [targetDate] projected from the continuous rolling timeline.
  List<Map<String, dynamic>> getDosesForDate(DateTime targetDate, {String? customStartTime}) {
    if (dailyDoseCount <= 0) {
      // PRN
      return [
        {
          'med': this,
          'time': 'As Needed',
          'mins': 99999,
          'doseIndex': 0,
          'globalDoseIndex': 0,
          'isShifted': false,
        }
      ];
    }

    final doses = getScheduledDoseDateTimes(customStartTime: customStartTime);
    final targetY = targetDate.year;
    final targetM = targetDate.month;
    final targetD = targetDate.day;

    final List<Map<String, dynamic>> dateDoses = [];
    int indexOnDate = 0;

    for (int i = 0; i < doses.length; i++) {
      final dt = doses[i];
      if (dt.year == targetY && dt.month == targetM && dt.day == targetD) {
        final mins = dt.hour * 60 + dt.minute;
        dateDoses.add({
          'med': this,
          'time': formatMinutesToTime(mins),
          'mins': mins,
          'doseIndex': indexOnDate++,
          'globalDoseIndex': i,
          'scheduledDateTime': dt,
          'isShifted': false,
        });
      }
    }

    return dateDoses;
  }

  /// Calculates cascading dose times in minutes from midnight given a custom starting dose time.
  List<int> calculateDoseMinutesFromStart(int startMinutes) {
    final count = dailyDoseCount;
    if (count <= 1) return [startMinutes];

    final f = frequency.toLowerCase().trim();
    final isQ8h = RegExp(r'\b(q8h|every\s*8\s*h(ours?)?)\b').hasMatch(f);
    final isQ6h = RegExp(r'\b(q6h|every\s*6\s*h(ours?)?)\b').hasMatch(f);
    final isQ4h = RegExp(r'\b(q4h|every\s*4\s*h(ours?)?)\b').hasMatch(f);

    if (count == 2) {
      return [startMinutes, (startMinutes + 12 * 60) % 1440];
    } else if (count == 3) {
      if (isQ8h) {
        return [
          startMinutes,
          (startMinutes + 8 * 60) % 1440,
          (startMinutes + 16 * 60) % 1440,
        ];
      }
      // Routine meal times: Breakfast (start), Lunch (+5h), Dinner (+11h)
      return [
        startMinutes,
        (startMinutes + 5 * 60) % 1440,
        (startMinutes + 11 * 60) % 1440,
      ];
    } else if (count == 4) {
      if (isQ6h) {
        return [
          startMinutes,
          (startMinutes + 6 * 60) % 1440,
          (startMinutes + 12 * 60) % 1440,
          (startMinutes + 18 * 60) % 1440,
        ];
      }
      // Routine: Morning (start), Noon (+5h), Evening (+10h), Bedtime (+14h)
      return [
        startMinutes,
        (startMinutes + 5 * 60) % 1440,
        (startMinutes + 10 * 60) % 1440,
        (startMinutes + 14 * 60) % 1440,
      ];
    } else if (isQ4h && count == 6) {
      return List.generate(count, (i) => (startMinutes + i * 4 * 60) % 1440);
    }

    final intervalMins = (24 * 60) ~/ count;
    return List.generate(count, (i) => (startMinutes + i * intervalMins) % 1440);
  }

  /// Minimum safe spacing (in minutes) required before taking the subsequent dose.
  int get minSafeGapMinutes {
    final count = dailyDoseCount;
    if (count <= 1) return 0;
    if (count == 2) return 8 * 60; // 8 hours minimum for twice-daily
    if (count == 3) return 4 * 60; // 4 hours minimum for three-times-daily
    if (count == 4) return 3 * 60; // 3 hours minimum for four-times-daily
    return (doseIntervalMinutes * 0.75).round();
  }

  /// Computes suggested shifted times (in minutes from midnight) for remaining doses on the current day
  /// when [takenDoseIndex] is taken late at [actualTakenMinutes].
  ///
  /// Returns a map of `{ doseIndex: shiftedMinutes }` for doses after [takenDoseIndex] that need shifting.
  /// If the intake was taken within the safe window or the remaining doses already have a safe gap,
  /// returns an empty map.
  Map<int, int> computeLateIntakeShifts({
    required int takenDoseIndex,
    required int actualTakenMinutes,
    required List<int> currentScheduledMinutes,
    int lateThresholdMinutes = 45,
    int bedtimeCapMinutes = 1350, // 10:30 PM
  }) {
    final count = dailyDoseCount;
    if (count <= 1 || takenDoseIndex >= count - 1 || takenDoseIndex >= currentScheduledMinutes.length) {
      return {};
    }

    final scheduledMinutes = currentScheduledMinutes[takenDoseIndex];
    final delay = actualTakenMinutes - scheduledMinutes;
    if (delay < lateThresholdMinutes) {
      return {};
    }

    final minSafeGap = minSafeGapMinutes;
    if (minSafeGap <= 0) return {};

    final nextDoseIndex = takenDoseIndex + 1;
    final nextScheduledMinutes = currentScheduledMinutes[nextDoseIndex];

    // Gap from actual intake to the next scheduled dose
    int gapToNext = nextScheduledMinutes - actualTakenMinutes;
    if (gapToNext < 0) {
      gapToNext = 0;
    }

    // If safe spacing is already preserved, no shift is required
    if (gapToNext >= minSafeGap) {
      return {};
    }

    // Safe spacing violated: calculate cascading shifts for subsequent doses today
    final Map<int, int> shifts = {};
    int prevShiftedMinutes = actualTakenMinutes;
    final interval = doseIntervalMinutes > 0 ? doseIntervalMinutes : minSafeGap;

    for (int i = nextDoseIndex; i < currentScheduledMinutes.length; i++) {
      int suggestedMinutes = prevShiftedMinutes + interval;
      if (suggestedMinutes > bedtimeCapMinutes) {
        suggestedMinutes = bedtimeCapMinutes;
      }
      shifts[i] = suggestedMinutes % 1440;
      prevShiftedMinutes = suggestedMinutes;
    }

    return shifts;
  }

  List<String> get doseTimes {
    final f = frequency.toLowerCase().trim();

    if (RegExp(r'\b(stat)\b').hasMatch(f)) {
      try {
        return [DateFormat('hh:mm a').format(issuedAt)];
      } catch (_) {
        return ['08:00 AM'];
      }
    }

    // Explicit morning / night natural language phrasing (avoiding matching English 'on')
    if (RegExp(r'\b(hs|at\s*bedtime|bedtime|before\s*bed)\b').hasMatch(f)) return ['09:00 PM'];
    if (RegExp(r'\b(o\.n\.|every\s*night|at\s*night|nightly|every\s*evening|in\s*the\s*evening)\b').hasMatch(f)) return ['08:00 PM'];
    if (RegExp(r'\b(om|every\s*morning|in\s*the\s*morning)\b').hasMatch(f)) return ['08:00 AM'];

    final count = dailyDoseCount;
    if (count <= 0) return [];

    if (count == 1) return ['08:00 AM'];
    if (count == 2) return ['08:00 AM', '08:00 PM'];
    if (count == 3) {
      if (RegExp(r'\b(q8h|every\s*8\s*h(ours?)?)\b').hasMatch(f)) {
        // Standard outpatient waking-hour intervals (6 AM, 2 PM, 10 PM)
        return ['06:00 AM', '02:00 PM', '10:00 PM'];
      }
      return ['08:00 AM', '01:00 PM', '07:00 PM'];
    }
    if (count == 4) {
      if (RegExp(r'\b(q6h|every\s*6\s*h(ours?)?)\b').hasMatch(f)) {
        return ['06:00 AM', '12:00 PM', '06:00 PM', '11:59 PM'];
      }
      return ['07:00 AM', '12:00 PM', '05:00 PM', '09:00 PM'];
    }

    final intervalHours = 24 ~/ count;
    return List.generate(count, (i) {
      final totalMins = 8 * 60 + i * intervalHours * 60;
      final h = (totalMins ~/ 60) % 24;
      final m = totalMins % 60;
      final period = h >= 12 ? 'PM' : 'AM';
      final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '${displayH.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
    });
  }

  factory ScheduledMedicine.fromMap(Map<String, dynamic> m) {
    final status = (m['dispensing_status'] as String?)?.toLowerCase().trim() ?? '';
    final isDispensedVal = (m['is_dispensed'] as bool?) ?? 
        (status == 'dispensed' || status == 'partial');
    return ScheduledMedicine(
      prescriptionItemId: (m['prescription_item_id'] as num?)?.toInt() ?? 0,
      prescriptionId:     (m['prescription_id']      as num?)?.toInt() ?? 0,
      prescriptionCode:   (m['prescription_code']    as String?) ?? '',
      dispensingStatus:   status,
      issuedAt:           DateTime.parse((m['issued_at'] as String?) ?? DateTime.now().toIso8601String()).toLocal(),
      dispensedAt:        m['dispensed_at'] != null ? DateTime.tryParse(m['dispensed_at'] as String)?.toLocal() : null,
      doctorName:         (m['doctor_name']           as String?) ?? '',
      medicineName:       (m['medicine_name']         as String?) ?? '',
      quantity:           (m['quantity']              as num?)?.toInt() ?? 0,
      unit:               (m['unit']                  as String?) ?? '',
      dosage:             (m['dosage']                as String?) ?? '',
      frequency:          (m['frequency']             as String?) ?? '',
      duration:           (m['duration']              as String?) ?? '',
      instructions:       (m['instructions']          as String?) ?? '',
      additionalInfo:     (m['additional_info']       as String?) ?? '',
      isAvailable:        (m['is_available']          as bool?) ?? true,
      isDispensed:        isDispensedVal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'prescription_item_id': prescriptionItemId,
      'prescription_id': prescriptionId,
      'prescription_code': prescriptionCode,
      'dispensing_status': dispensingStatus,
      'issued_at': issuedAt.toIso8601String(),
      'dispensed_at': dispensedAt?.toIso8601String(),
      'doctor_name': doctorName,
      'medicine_name': medicineName,
      'quantity': quantity,
      'unit': unit,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'instructions': instructions,
      'additional_info': additionalInfo,
      'is_available': isAvailable,
      'is_dispensed': isDispensed,
    };
  }
}
