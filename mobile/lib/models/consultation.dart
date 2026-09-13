import '../utils/formatters.dart';

class VitalSigns {
  final String id;
  final int citizenId;
  final String chiefComplaint;
  final String? bp;
  final int? heartRate;
  final int? rr;
  final double? temp;
  final int? spo2;
  final double? heightCm;
  final double? weightKg;
  final double? bmi;
  final String? meds;
  final DateTime createdAt;

  const VitalSigns({
    required this.id,
    required this.citizenId,
    required this.chiefComplaint,
    this.bp,
    this.heartRate,
    this.rr,
    this.temp,
    this.spo2,
    this.heightCm,
    this.weightKg,
    this.bmi,
    this.meds,
    required this.createdAt,
  });

  factory VitalSigns.fromMap(Map<String, dynamic> map) {
    return VitalSigns(
      id: map['id']?.toString() ?? '',
      citizenId: (map['citizen_id'] as num?)?.toInt() ?? 0,
      chiefComplaint: map['chief_complaint'] ?? 'No complaint recorded',
      bp: map['blood_pressure'],
      heartRate: (map['heart_rate'] as num?)?.toInt(),
      rr: (map['respiratory_rate'] as num?)?.toInt(),
      temp: (map['temperature'] as num?)?.toDouble(),
      spo2: (map['oxygen_saturation'] as num?)?.toInt(),
      heightCm: (map['height_cm'] as num?)?.toDouble(),
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      bmi: (map['bmi'] as num?)?.toDouble(),
      meds: map['current_medications'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class Consultation {
  final int id;
  final String patientIdentifier;
  final String? symptoms;
  final String diagnosis;
  final String? notes;
  final String? hpi;
  final String? pmh;
  final String? allergies;
  final String? immunizationStatus;
  final String? socialHistory;
  final Map<String, dynamic>? physicalExam;
  final String? differentialDiagnosis;
  final String? labOrders;
  final DateTime? followupDate;
  final DateTime consultedAt;
  final String? doctorName;

  const Consultation({
    required this.id,
    required this.patientIdentifier,
    this.symptoms,
    required this.diagnosis,
    this.notes,
    this.hpi,
    this.pmh,
    this.allergies,
    this.immunizationStatus,
    this.socialHistory,
    this.physicalExam,
    this.differentialDiagnosis,
    this.labOrders,
    this.followupDate,
    required this.consultedAt,
    this.doctorName,
  });

  factory Consultation.fromMap(Map<String, dynamic> map) {
    final doctor = map['doctor'] as Map<String, dynamic>?;
    final drName = doctor != null
        ? formatDoctorName('${doctor['first_name'] ?? ''} ${doctor['last_name'] ?? ''}'.trim())
        : null;

    return Consultation(
      id: (map['id'] as num?)?.toInt() ?? 0,
      patientIdentifier: map['patient_identifier'] ?? '',
      symptoms: map['symptoms'],
      diagnosis: map['diagnosis'] ?? 'No diagnosis recorded',
      notes: map['notes'],
      hpi: map['hpi'],
      pmh: map['pmh'],
      allergies: map['allergies'],
      immunizationStatus: map['immunization_status'],
      socialHistory: map['social_history'],
      physicalExam: map['physical_exam'] as Map<String, dynamic>?,
      differentialDiagnosis: map['differential_diagnosis'],
      labOrders: map['lab_orders'],
      followupDate: map['follow_up_date'] != null ? DateTime.tryParse(map['follow_up_date'].toString())?.toLocal() : null,
      consultedAt: DateTime.tryParse(map['consulted_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      doctorName: drName,
    );
  }
}
