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

  bool get isCompleted => const {'completed', 'finished', 'done'}.contains(status.toLowerCase().trim());
  bool get isCancelled => const {'cancelled', 'canceled'}.contains(status.toLowerCase().trim());
  bool get isServing => status.toLowerCase().trim() == 'serving';
  bool get isOnCallStatus => isOnCall || status.toLowerCase().trim() == 'on_call';
  bool get hasActiveQueue => queueId != null && myQueueNumber != null && !isCompleted && !isCancelled;

  /// True if this patient is currently being served by the doctor.
  bool get isCurrentlyBeingServed {
    if (isCompleted || isCancelled) return false;
    if (isServing) return true;
    if (myQueueNumber != null &&
        currentlyServingQueueNumber != null &&
        currentlyServingQueueNumber! > 0) {
      return myQueueNumber == currentlyServingQueueNumber;
    }
    return false;
  }

  /// True if another patient is currently inside being served by the doctor ahead of this ticket.
  bool get hasServingAhead {
    if (myQueueNumber == null || currentlyServingQueueNumber == null) return false;
    final serving = currentlyServingQueueNumber!;
    return serving > 0 && serving < myQueueNumber!;
  }

  /// Accurate number of patients ahead who must be seen before this patient's consultation begins.
  int get peopleAheadCount {
    if (isCompleted || isCancelled || isCurrentlyBeingServed || isOnCallStatus) {
      return 0;
    }
    // Database returns waiting_count (patients in waiting or on_call with queue_number < myQueueNumber).
    // Plus 1 if a patient is currently inside being served ahead of this ticket.
    final count = waitingCount + (hasServingAhead ? 1 : 0);
    if (count > 0) return count;

    // Fallback if waitingCount was 0/unpopulated but queue numbers indicate a gap ahead
    if (myQueueNumber != null &&
        currentlyServingQueueNumber != null &&
        currentlyServingQueueNumber! > 0) {
      final diff = myQueueNumber! - currentlyServingQueueNumber!;
      if (diff > 0) return diff;
    }
    return 0;
  }

  /// True if this patient is next in line to be called.
  bool get isNextInLine {
    if (!hasActiveQueue || isCurrentlyBeingServed || isOnCallStatus) return false;
    return peopleAheadCount <= 0 || (waitingCount == 0 && hasServingAhead);
  }

  /// Formatted estimated wait minutes (calculated or database fallback).
  int get calculatedWaitMinutes {
    if (isCompleted || isCancelled || isCurrentlyBeingServed || isOnCallStatus) {
      return 0;
    }
    if (estimatedWaitMinutes > 0) {
      return estimatedWaitMinutes;
    }
    // Fallback estimate: 10 minutes per person ahead
    final ahead = peopleAheadCount;
    if (ahead > 0) {
      return ahead * 10;
    }
    // Up next: minimal wait
    return 5;
  }

  /// Human-friendly display string for estimated wait (e.g. '10 mins', '1h 15m', '< 5 mins', 'Now serving').
  String get formattedWaitTime {
    if (isCompleted) return 'Completed';
    if (isCancelled) return 'Cancelled';
    if (isCurrentlyBeingServed) return 'Now serving';
    if (isOnCallStatus) return 'In triage';
    final mins = calculatedWaitMinutes;
    if (mins <= 5 && isNextInLine) return '< 5 mins';
    if (mins < 60) return '$mins mins';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    if (rem == 0) return '${hours}h';
    return '${hours}h ${rem}m';
  }

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
