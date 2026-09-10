import '../utils/formatters.dart';

class DoctorSchedule {
  final int id;
  final int doctorStaffId;
  final String doctorName;
  final String specialization;
  final DateTime scheduleDate;
  final String startTime;
  final String endTime;
  final String? notes;
  final String availabilityStatus;

  const DoctorSchedule({
    required this.id,
    required this.doctorStaffId,
    required this.doctorName,
    required this.specialization,
    required this.scheduleDate,
    required this.startTime,
    required this.endTime,
    this.notes,
    this.availabilityStatus = 'available',
  });

  String get displayName => formatDoctorName(doctorName);

  factory DoctorSchedule.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    try {
      final rawDate = map['schedule_date']?.toString().trim() ?? '';
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(rawDate);
      if (match != null) {
        parsedDate = DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        );
      } else {
        final dt = DateTime.tryParse(rawDate) ?? DateTime.now();
        parsedDate = DateTime(dt.year, dt.month, dt.day);
      }
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return DoctorSchedule(
      id: (map['id'] as num?)?.toInt() ?? 0,
      doctorStaffId: (map['doctor_staff_id'] as num?)?.toInt() ?? 0,
      doctorName: (map['doctor_name'] as String?)?.trim().isNotEmpty == true
          ? (map['doctor_name'] as String).trim()
          : 'Unknown Doctor',
      specialization: ((map['specialization'] as String?) ?? '').trim(),
      scheduleDate: parsedDate,
      startTime: (map['start_time'] as String?) ?? '',
      endTime: (map['end_time'] as String?) ?? '',
      notes: (map['notes'] as String?)?.trim().isEmpty == true ? null : (map['notes'] as String?),
      availabilityStatus: (map['availability_status'] ?? '').toString().toLowerCase(),
    );
  }
}

class DoctorStatus {
  final int id;
  final String firstName;
  final String lastName;
  final String specialization;
  final String availabilityStatus;

  const DoctorStatus({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.specialization,
    required this.availabilityStatus,
  });

  String get displayName {
    final cleanFirst = firstName.replaceAll(RegExp(r'^(dr\.?|doctor)\s*', caseSensitive: false), '').trim();
    final cleanLast = lastName.replaceAll(RegExp(r'^(dr\.?|doctor)\s*', caseSensitive: false), '').trim();
    final full = '$cleanFirst $cleanLast'.trim();
    return formatDoctorName(full.isNotEmpty ? full : '$firstName $lastName');
  }

  factory DoctorStatus.fromMap(Map<String, dynamic> map) {
    return DoctorStatus(
      id: (map['id'] as num?)?.toInt() ?? 0,
      firstName: (map['first_name'] as String?) ?? '',
      lastName: (map['last_name'] as String?) ?? '',
      specialization: (map['doctor_specialization'] as String?) ?? '',
      availabilityStatus: (map['availability_status'] ?? 'unavailable').toString().toLowerCase(),
    );
  }
}
