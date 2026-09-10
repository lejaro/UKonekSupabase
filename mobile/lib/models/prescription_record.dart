import '../utils/formatters.dart';

class PrescriptionRecord {
  final int prescriptionId;
  final String prescriptionCode;
  final String dispensingStatus;
  final DateTime issuedAt;
  final DateTime? dispensedAt;
  final String doctorName;
  final String medicineName;
  final int quantity;
  final int dispensedQuantity;
  final int remainingQuantity;
  final String unit;
  final String dosage;
  final String frequency;
  final String duration;
  final String instructions;
  final String additionalInfo;
  final bool isAvailable;
  final bool isDispensed;

  const PrescriptionRecord({
    required this.prescriptionId,
    required this.prescriptionCode,
    required this.dispensingStatus,
    required this.issuedAt,
    this.dispensedAt,
    required this.doctorName,
    required this.medicineName,
    required this.quantity,
    required this.dispensedQuantity,
    required this.remainingQuantity,
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

  bool get isPrescriptionDispensed => dispensingStatus == 'dispensed';
  bool get isCancelled            => dispensingStatus == 'cancelled';
  bool get isPending              => dispensingStatus == 'pending';
  bool get isPartial              => dispensingStatus == 'partial';

  String get quantityLabel {
    final normalizedUnit = unit.trim();
    if (normalizedUnit.isEmpty) return quantity.toString();
    return '$quantity $normalizedUnit';
  }

  String get dispensedQuantityLabel {
    final normalizedUnit = unit.trim();
    if (normalizedUnit.isEmpty) return dispensedQuantity.toString();
    return '$dispensedQuantity $normalizedUnit';
  }

  String get remainingQuantityLabel {
    final normalizedUnit = unit.trim();
    if (normalizedUnit.isEmpty) return remainingQuantity.toString();
    return '$remainingQuantity $normalizedUnit';
  }

  factory PrescriptionRecord.fromMap(Map<String, dynamic> m) {
    return PrescriptionRecord(
      prescriptionId:   (m['prescription_id']   as num?)?.toInt() ?? (m['id'] as num?)?.toInt() ?? 0,
      prescriptionCode: (m['prescription_code']  as String?) ?? '',
      dispensingStatus: (m['dispensing_status']  as String?) ?? 'pending',
      issuedAt:         DateTime.parse((m['issued_at'] as String?) ?? DateTime.now().toIso8601String()).toLocal(),
      dispensedAt:      m['dispensed_at'] != null ? DateTime.tryParse(m['dispensed_at'] as String)?.toLocal() : null,
      doctorName:       (m['doctor_name']        as String?) ?? '',
      medicineName:     (m['medicine_name']      as String?) ?? '',
      quantity:         (m['quantity']           as num?)?.toInt() ?? 0,
      dispensedQuantity: (m['dispensed_quantity'] as num?)?.toInt() ?? 0,
      remainingQuantity: (m['remaining_quantity'] as num?)?.toInt() ?? ((m['quantity'] as num?)?.toInt() ?? 0),
      unit:             (m['unit']               as String?) ?? '',
      dosage:           (m['dosage']             as String?) ?? '',
      frequency:        (m['frequency']          as String?) ?? '',
      duration:         (m['duration']           as String?) ?? '',
      instructions:     (m['instructions']       as String?) ?? '',
      additionalInfo:   (m['additional_info']    as String?) ?? '',
      isAvailable:      (m['is_available']       as bool?) ?? true,
      isDispensed:      (m['is_dispensed']       as bool?) ?? false,
    );
  }
}

class PrescriptionDispenseLog {
  final int dispenseId;
  final int prescriptionId;
  final String prescriptionCode;
  final int prescriptionItemId;
  final String medicineName;
  final String dosage;
  final int dispensedQuantity;
  final String unit;
  final String note;
  final String pharmacistName;
  final DateTime dispensedAt;

  const PrescriptionDispenseLog({
    required this.dispenseId,
    required this.prescriptionId,
    required this.prescriptionCode,
    required this.prescriptionItemId,
    required this.medicineName,
    required this.dosage,
    required this.dispensedQuantity,
    required this.unit,
    required this.note,
    required this.pharmacistName,
    required this.dispensedAt,
  });

  String get quantityLabel {
    final normalizedUnit = unit.trim();
    if (normalizedUnit.isEmpty) return dispensedQuantity.toString();
    return '$dispensedQuantity $normalizedUnit';
  }

  factory PrescriptionDispenseLog.fromMap(Map<String, dynamic> m) {
    DateTime parsedDate;
    try {
      final raw = m['dispensed_at']?.toString() ?? '';
      parsedDate = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return PrescriptionDispenseLog(
      dispenseId: (m['dispense_id'] as num?)?.toInt() ?? 0,
      prescriptionId: (m['prescription_id'] as num?)?.toInt() ?? 0,
      prescriptionCode: (m['prescription_code'] as String?) ?? '',
      prescriptionItemId: (m['prescription_item_id'] as num?)?.toInt() ?? 0,
      medicineName: (m['medicine_name'] as String?) ?? '',
      dosage: (m['dosage'] as String?) ?? '',
      dispensedQuantity: (m['dispensed_quantity'] as num?)?.toInt() ?? 0,
      unit: (m['unit'] as String?) ?? '',
      note: (m['note'] as String?) ?? '',
      pharmacistName: (m['pharmacist_name'] as String?) ?? 'Pharmacist',
      dispensedAt: parsedDate,
    );
  }
}

/// Holds information about a newly issued prescription for alerting the patient.
class NewPrescriptionAlert {
  final int prescriptionId;
  final String prescriptionCode;
  final String doctorName;
  final DateTime issuedAt;
  final List<PrescriptionRecord> items;

  const NewPrescriptionAlert({
    required this.prescriptionId,
    required this.prescriptionCode,
    required this.doctorName,
    required this.issuedAt,
    required this.items,
  });

  String get displayDoctorName => formatDoctorName(doctorName);
}

class PrescribedMedicine {
  final String medicineName;
  final int quantity;
  final String unit;
  final String doctorName;
  final DateTime issuedAt;

  const PrescribedMedicine({
    required this.medicineName,
    required this.quantity,
    required this.unit,
    required this.doctorName,
    required this.issuedAt,
  });

  String get quantityLabel {
    final normalizedUnit = unit.trim();
    if (normalizedUnit.isEmpty) return quantity.toString();
    return '$quantity $normalizedUnit';
  }

  factory PrescribedMedicine.fromMap(Map<String, dynamic> map) {
    final issuedAtRaw = (map['issued_at'] ?? '').toString().trim();
    return PrescribedMedicine(
      medicineName: (map['medicine_name'] ?? '').toString().trim(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unit: (map['unit'] ?? '').toString().trim(),
      doctorName: (map['doctor_name'] ?? '').toString().trim(),
      issuedAt: DateTime.tryParse(issuedAtRaw)?.toLocal() ?? DateTime.now(),
    );
  }
}
