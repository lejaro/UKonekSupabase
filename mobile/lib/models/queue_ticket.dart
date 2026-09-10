class QueueServiceOption {
  final String serviceKey;
  final String serviceLabel;
  final int doctorCount;

  const QueueServiceOption({
    required this.serviceKey,
    required this.serviceLabel,
    required this.doctorCount,
  });

  factory QueueServiceOption.fromMap(Map<String, dynamic> map) {
    return QueueServiceOption(
      serviceKey: (map['service_key'] ?? '').toString().trim(),
      serviceLabel: (map['service_label'] ?? '').toString().trim(),
      doctorCount: (map['doctor_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is QueueServiceOption && runtimeType == other.runtimeType && serviceKey == other.serviceKey;

  @override
  int get hashCode => serviceKey.hashCode;
}

class QueueJoinRequest {
  final String serviceKey;
  final String serviceLabel;
  final String citizenType;
  final String reason;
  final String symptoms;

  const QueueJoinRequest({
    required this.serviceKey,
    required this.serviceLabel,
    required this.citizenType,
    required this.reason,
    required this.symptoms,
  });
}

class QueueTicket {
  final int id;
  final int queueNumber;
  final String ticketCode;
  final String serviceKey;
  final String serviceLabel;
  final String citizenType;
  final String status;
  final int estimatedWaitMinutes;

  const QueueTicket({
    required this.id,
    required this.queueNumber,
    required this.ticketCode,
    required this.serviceKey,
    required this.serviceLabel,
    required this.citizenType,
    required this.status,
    required this.estimatedWaitMinutes,
  });

  factory QueueTicket.fromMap(Map<String, dynamic> map) {
    return QueueTicket(
      id: ((map['r_id'] ?? map['id']) as num?)?.toInt() ?? 0,
      queueNumber: ((map['r_queue_number'] ?? map['queue_number']) as num?)?.toInt() ?? 0,
      ticketCode: (map['r_ticket_code'] ?? map['ticket_code'] ?? '').toString().trim(),
      serviceKey: (map['r_service_key'] ?? map['service_key'] ?? '').toString().trim(),
      serviceLabel: (map['r_service_label'] ?? map['service_label'] ?? '').toString().trim(),
      citizenType: (map['r_citizen_type'] ?? map['citizen_type'] ?? '').toString().trim(),
      status: (map['r_status'] ?? map['status'] ?? '').toString().trim(),
      estimatedWaitMinutes: ((map['r_estimated_wait_minutes'] ?? map['estimated_wait_minutes']) as num?)?.toInt() ?? 0,
    );
  }
}

class QueueDashboardSnapshot {
  final int? queueId;
  final String serviceKey;
  final String serviceLabel;
  final String ticketCode;
  final int? myQueueNumber;
  final int? currentlyServingQueueNumber;
  final int estimatedWaitMinutes;
  final String status;
  final DateTime? queueDate;
  final bool isOnCall;
  final int waitingCount;
  final String? citizenFullname;
  final int? citizenAge;
  final String? citizenAddress;
  final String? citizenContact;
  final String? chiefComplaint;
  final bool hasVitals;

  const QueueDashboardSnapshot({
    required this.queueId,
    required this.serviceKey,
    required this.serviceLabel,
    required this.ticketCode,
    required this.myQueueNumber,
    required this.currentlyServingQueueNumber,
    required this.estimatedWaitMinutes,
    required this.status,
    required this.queueDate,
    required this.isOnCall,
    required this.waitingCount,
    this.citizenFullname,
    this.citizenAge,
    this.citizenAddress,
    this.citizenContact,
    this.chiefComplaint,
    this.hasVitals = false,
  });

  bool get hasActiveQueue => queueId != null && myQueueNumber != null;

  factory QueueDashboardSnapshot.fromMap(Map<String, dynamic> map, {bool hasVitals = false}) {
    final dateRaw = map['r_queue_date'] ?? map['queue_date'];
    DateTime? parsedDate;
    if (dateRaw is String && dateRaw.trim().isNotEmpty) {
      parsedDate = DateTime.tryParse(dateRaw.trim());
    }
    return QueueDashboardSnapshot(
      queueId: ((map['r_queue_id'] ?? map['queue_id']) as num?)?.toInt(),
      serviceKey: (map['r_service_key'] ?? map['service_key'] ?? '').toString().trim(),
      serviceLabel: (map['r_service_label'] ?? map['service_label'] ?? '').toString().trim(),
      ticketCode: (map['r_ticket_code'] ?? map['ticket_code'] ?? '').toString().trim(),
      myQueueNumber: ((map['r_my_queue_number'] ?? map['my_queue_number']) as num?)?.toInt(),
      currentlyServingQueueNumber: ((map['r_currently_serving_queue_number'] ?? map['currently_serving_queue_number']) as num?)?.toInt(),
      estimatedWaitMinutes: ((map['r_estimated_wait_minutes'] ?? map['estimated_wait_minutes']) as num?)?.toInt() ?? 0,
      status: (map['r_status'] ?? map['status'] ?? '').toString().trim(),
      queueDate: parsedDate,
      isOnCall: map['is_on_call'] == true,
      waitingCount: (map['waiting_count'] as num?)?.toInt() ?? 0,
      citizenFullname: map['citizen_fullname']?.toString(),
      citizenAge: (map['citizen_age'] as num?)?.toInt(),
      citizenAddress: map['citizen_address']?.toString(),
      citizenContact: map['citizen_contact']?.toString(),
      chiefComplaint: map['chief_complaint']?.toString(),
      hasVitals: hasVitals,
    );
  }

  static const empty = QueueDashboardSnapshot(
    queueId: null,
    serviceKey: '',
    serviceLabel: '',
    ticketCode: '',
    myQueueNumber: null,
    currentlyServingQueueNumber: null,
    estimatedWaitMinutes: 0,
    status: '',
    queueDate: null,
    isOnCall: false,
    waitingCount: 0,
    hasVitals: false,
  );
}

class QueueLimiterStatus {
  final bool enabled;
  final int dailyLimit;
  final int todayCount;
  final bool limitReached;
  final int remainingSlots;
  final bool doctorsAvailable;

  const QueueLimiterStatus({
    required this.enabled,
    required this.dailyLimit,
    required this.todayCount,
    required this.limitReached,
    required this.remainingSlots,
    required this.doctorsAvailable,
  });

  factory QueueLimiterStatus.fromMap(Map<String, dynamic> map) {
    return QueueLimiterStatus(
      enabled: map['enabled'] == true,
      dailyLimit: (map['daily_limit'] as num?)?.toInt() ?? 20,
      todayCount: (map['today_count'] as num?)?.toInt() ?? 0,
      limitReached: map['limit_reached'] == true,
      remainingSlots: (map['remaining_slots'] as num?)?.toInt() ?? 0,
      doctorsAvailable: map['doctors_available'] as bool? ?? true,
    );
  }

  factory QueueLimiterStatus.disabled() {
    return const QueueLimiterStatus(
      enabled: false,
      dailyLimit: 20,
      todayCount: 0,
      limitReached: false,
      remainingSlots: 20,
      doctorsAvailable: true,
    );
  }

  String get statusMessage {
    if (!enabled) return '';
    if (limitReached) return 'Daily consultation limit reached ($dailyLimit/$dailyLimit). Please try again tomorrow.';
    if (remainingSlots <= 5) return 'Only $remainingSlots consultation slots remaining today.';
    return '$remainingSlots consultation slots available today.';
  }
}
