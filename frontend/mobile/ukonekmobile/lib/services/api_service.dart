import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

enum LoginFailureType {
  invalidCredentials,
  unverifiedEmail,
  validation,
  network,
  unknown,
}

class LoginFailureException implements Exception {
  final LoginFailureType type;
  final String message;

  const LoginFailureException({required this.type, required this.message});

  bool get countsAsAttempt => type == LoginFailureType.invalidCredentials;

  @override
  String toString() => message;
}

class DoctorSchedule {
  final int id;
  final int doctorStaffId;
  final String doctorName;
  final String specialization;
  final DateTime scheduleDate;
  final String startTime;
  final String endTime;
  final String? notes;

  const DoctorSchedule({
    required this.id,
    required this.doctorStaffId,
    required this.doctorName,
    required this.specialization,
    required this.scheduleDate,
    required this.startTime,
    required this.endTime,
    this.notes,
  });

  factory DoctorSchedule.fromMap(Map<String, dynamic> map) {
    return DoctorSchedule(
      id: (map['id'] as num?)?.toInt() ?? 0,
      doctorStaffId: (map['doctor_staff_id'] as num?)?.toInt() ?? 0,
      doctorName: (map['doctor_name'] as String?)?.trim().isNotEmpty == true
          ? (map['doctor_name'] as String).trim()
          : 'Unknown Doctor',
      specialization: ((map['specialization'] as String?) ?? '').trim(),
      scheduleDate: DateTime.parse(map['schedule_date'] as String),
      startTime: (map['start_time'] as String?) ?? '',
      endTime: (map['end_time'] as String?) ?? '',
      notes: (map['notes'] as String?)?.trim().isEmpty == true
          ? null
          : (map['notes'] as String?),
    );
  }
}

class FeedbackSubmission {
  final String subject;
  final String message;
  final int? rating;

  const FeedbackSubmission({
    required this.subject,
    required this.message,
    this.rating,
  });
}

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
      id: (map['id'] as num?)?.toInt() ?? 0,
      queueNumber: (map['queue_number'] as num?)?.toInt() ?? 0,
      ticketCode: (map['ticket_code'] ?? '').toString().trim(),
      serviceKey: (map['service_key'] ?? '').toString().trim(),
      serviceLabel: (map['service_label'] ?? '').toString().trim(),
      citizenType: (map['citizen_type'] ?? '').toString().trim(),
      status: (map['status'] ?? '').toString().trim(),
      estimatedWaitMinutes:
          (map['estimated_wait_minutes'] as num?)?.toInt() ?? 0,
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
  });

  bool get hasActiveQueue => queueId != null && myQueueNumber != null;

  factory QueueDashboardSnapshot.fromMap(Map<String, dynamic> map) {
    final dateRaw = map['queue_date'];
    DateTime? parsedDate;
    if (dateRaw is String && dateRaw.trim().isNotEmpty) {
      parsedDate = DateTime.tryParse(dateRaw.trim());
    }
    return QueueDashboardSnapshot(
      queueId: (map['queue_id'] as num?)?.toInt(),
      serviceKey: (map['service_key'] ?? '').toString().trim(),
      serviceLabel: (map['service_label'] ?? '').toString().trim(),
      ticketCode: (map['ticket_code'] ?? '').toString().trim(),
      myQueueNumber: (map['my_queue_number'] as num?)?.toInt(),
      currentlyServingQueueNumber:
          (map['currently_serving_queue_number'] as num?)?.toInt(),
      estimatedWaitMinutes:
          (map['estimated_wait_minutes'] as num?)?.toInt() ?? 0,
      status: (map['status'] ?? '').toString().trim(),
      queueDate: parsedDate,
      isOnCall: map['is_on_call'] == true,
      waitingCount: (map['waiting_count'] as num?)?.toInt() ?? 0,
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
  );
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
    if (normalizedUnit.isEmpty) {
      return quantity.toString();
    }
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

class ApiService {
  static SupabaseClient get _client => Supabase.instance.client;

  static String? _resolveEmailRedirectUrl() {
    const configured = String.fromEnvironment('APP_REDIRECT_URL');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return null;
  }

  static Future<void> requestCitizenPreAuthOtp({
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.functions.invoke(
      'citizen-request-otp',
      body: payload,
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map<String, dynamic>
          ? (data['error']?.toString() ?? 'Unable to send OTP.')
          : 'Unable to send OTP.';
      throw Exception(message);
    }
  }

  static Future<void> verifyCitizenPreAuthOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _client.functions.invoke(
      'citizen-verify-otp',
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map<String, dynamic>
          ? (data['error']?.toString() ?? 'OTP verification failed.')
          : 'OTP verification failed.';
      throw Exception(message);
    }
  }

  static Future<void> completeCitizenPreAuthSignup({
    required String email,
    required String username,
    required String password,
  }) async {
    final response = await _client.functions.invoke(
      'citizen-complete-signup',
      body: {
        'email': email.trim().toLowerCase(),
        'username': username.trim(),
        'password': password,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map<String, dynamic>
          ? (data['error']?.toString() ?? 'Unable to complete signup.')
          : 'Unable to complete signup.';
      throw Exception(message);
    }
  }

  /// Compatibility method: OTP flow was removed in backendless mode.
  /// Sends a magic link email using Supabase OTP endpoint.
  static Future<void> requestCitizenOtp({
    required String email,
    required String purpose,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final emailRedirectTo = _resolveEmailRedirectUrl();

    try {
      await _client.auth.signInWithOtp(
        email: normalizedEmail,
        emailRedirectTo: emailRedirectTo,
        shouldCreateUser: false,
      );
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();
      if (message.contains('otp_expired') ||
          message.contains('token has expired') ||
          message.contains('token has expired or is invalid')) {
        throw Exception(
          'Verification link expired. Please request a new verification email and open the latest link only.',
        );
      }
      if (message.contains('rate limit') || message.contains('too many')) {
        throw Exception(
          'Please wait a minute before requesting another email.',
        );
      }
      if (message.contains('security purposes') || code == '429') {
        throw Exception(
          'Please wait about 55 seconds before requesting another verification email.',
        );
      }
      if (message.contains('not authorized')) {
        throw Exception(
          'Email sending is restricted by Supabase SMTP settings. Configure custom SMTP in Supabase Auth settings.',
        );
      }
      rethrow;
    }
  }

  static Future<void> verifyCitizenEmailOtp({
    required String email,
    required String otp,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedOtp = otp.trim();

    if (normalizedOtp.isEmpty) {
      throw Exception('Please enter the OTP code from your email.');
    }

    try {
      await _client.auth.verifyOTP(
        email: normalizedEmail,
        token: normalizedOtp,
        type: OtpType.email,
      );
    } on AuthException catch (_) {
      await _client.auth.verifyOTP(
        email: normalizedEmail,
        token: normalizedOtp,
        type: OtpType.signup,
      );
    }
  }

  static bool hasVerifiedSessionForEmail(String email) {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    return (user.email ?? '').trim().toLowerCase() ==
        email.trim().toLowerCase();
  }

  static Future<void> startCitizenEmailVerification({
    required Map<String, dynamic> payload,
  }) async {
    final email = (payload['email'] as String).trim().toLowerCase();
    final emailRedirectTo = _resolveEmailRedirectUrl();

    try {
      await _client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: emailRedirectTo,
        shouldCreateUser: true,
        data: {
          'role': 'citizen',
          'firstname': payload['firstname'],
          'surname': payload['surname'],
          'middle_initial': payload['middle_initial'] ?? '',
          'date_of_birth': payload['date_of_birth'],
          'age': payload['age'],
          'contact_number': payload['contact_number'] ?? '',
          'sex': payload['sex'] ?? '',
          'complete_address': payload['complete_address'] ?? '',
          'emergency_contact_complete_name':
              payload['emergency_contact_complete_name'] ?? '',
          'emergency_contact_contact_number':
              payload['emergency_contact_contact_number'] ?? '',
          'relation': payload['relation'] ?? '',
        },
      );
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();
      if (message.contains('otp_expired') ||
          message.contains('token has expired') ||
          message.contains('token has expired or is invalid')) {
        throw Exception(
          'Verification link expired. Please request a new verification email and open the latest link only.',
        );
      }
      if (message.contains('already registered')) {
        throw Exception('Email already used, please use other email.');
      }
      if (message.contains('security purposes') ||
          message.contains('rate limit') ||
          code == '429') {
        throw Exception(
          'Please wait about 55 seconds before requesting another verification email.',
        );
      }
      rethrow;
    }
  }

  static Future<void> completeCitizenRegistration({
    required Map<String, dynamic> payload,
  }) async {
    final email = (payload['email'] as String).trim().toLowerCase();
    final username = (payload['username'] as String).trim();
    final password = payload['password'] as String;

    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Please verify your email first using the OTP magic link.');
    }

    final sessionEmail = (user.email ?? '').trim().toLowerCase();
    if (sessionEmail != email) {
      throw Exception(
        'Verified session email does not match registration email. Please verify the same email you entered.',
      );
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('password')) {
        throw Exception('Please choose a stronger password.');
      }
      rethrow;
    }

    final response = await _client.rpc(
      'complete_my_citizen_profile',
      params: {
        'p_firstname': payload['firstname'],
        'p_surname': payload['surname'],
        'p_middle_initial': payload['middle_initial'] ?? '',
        'p_date_of_birth': payload['date_of_birth'],
        'p_age': payload['age'],
        'p_contact_number': payload['contact_number'] ?? '',
        'p_sex': payload['sex'] ?? '',
        'p_complete_address': payload['complete_address'] ?? '',
        'p_emergency_contact_complete_name':
            payload['emergency_contact_complete_name'] ?? '',
        'p_emergency_contact_contact_number':
            payload['emergency_contact_contact_number'] ?? '',
        'p_relation': payload['relation'] ?? '',
        'p_username': username,
      },
    );

    if (response is Map<String, dynamic> && response['ok'] == false) {
      final message = (response['error'] ?? 'Unable to complete registration.')
          .toString();
      throw Exception(message);
    }
  }

  /// Sign in a citizen using email + password.
  static Future<Map<String, dynamic>> loginCitizen({
    required String identifier,
    required String password,
  }) async {
    final loginEmail = identifier.trim().toLowerCase();
    if (!loginEmail.contains('@')) {
      throw const LoginFailureException(
        type: LoginFailureType.validation,
        message: 'Please enter your email address',
      );
    }

    AuthResponse authResponse;
    try {
      authResponse = await _client.auth.signInWithPassword(
        email: loginEmail.toLowerCase(),
        password: password,
      );
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();

      if (message.contains('invalid login credentials') ||
          message.contains('invalid credentials') ||
          message.contains('incorrect password') ||
          code == '400') {
        throw const LoginFailureException(
          type: LoginFailureType.invalidCredentials,
          message: 'Wrong password or email. Please try again.',
        );
      }

      if (message.contains('email not confirmed')) {
        throw const LoginFailureException(
          type: LoginFailureType.unverifiedEmail,
          message: 'Please verify your email using the OTP magic link before signing in.',
        );
      }

      if (message.contains('network') ||
          message.contains('timeout') ||
          message.contains('failed to fetch')) {
        throw const LoginFailureException(
          type: LoginFailureType.network,
          message: 'Network issue. Please check your internet and try again.',
        );
      }

      throw const LoginFailureException(
        type: LoginFailureType.unknown,
        message: 'Unable to sign in right now. Please try again.',
      );
    }

    if (authResponse.user == null) {
      throw const LoginFailureException(
        type: LoginFailureType.invalidCredentials,
        message: 'Wrong password or email. Please try again.',
      );
    }

    // Fetch the citizen profile.
    // If missing, try to auto-link a legacy citizen row by email.
    Map<String, dynamic>? profile = await _client
        .from('citizens')
        .select()
        .eq('auth_user_id', authResponse.user!.id)
        .maybeSingle();

    if (profile == null) {
      try {
        await _client.rpc('link_my_citizen_auth_by_email');
      } catch (_) {
        // Ignore relink failures and keep original UX fallback below.
      }

      profile = await _client
          .from('citizens')
          .select()
          .eq('auth_user_id', authResponse.user!.id)
          .maybeSingle();
    }

    if (profile == null) {
      throw const LoginFailureException(
        type: LoginFailureType.validation,
        message:
            'Your account is missing a citizen profile. Please contact the health center admin for account setup.',
      );
    }

    return {
      'user': profile,
      'session': {'access_token': authResponse.session?.accessToken},
    };
  }

  /// Register a new citizen via Supabase Auth signUp.
  /// The handle_new_user trigger will auto-create the citizens row.
  static Future<void> registerCitizen({
    required Map<String, dynamic> payload,
  }) async {
    final email = (payload['email'] as String).trim().toLowerCase();
    final password = payload['password'] as String;
    final username = payload['username'] as String;
    final emailRedirectTo = _resolveEmailRedirectUrl();

    AuthResponse authResponse;
    try {
      authResponse = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailRedirectTo,
        data: {
          'role': 'citizen',
          'firstname': payload['firstname'],
          'surname': payload['surname'],
          'middle_initial': payload['middle_initial'] ?? '',
          'date_of_birth': payload['date_of_birth'],
          'age': payload['age'],
          'contact_number': payload['contact_number'] ?? '',
          'sex': payload['sex'] ?? '',
          'complete_address': payload['complete_address'] ?? '',
          'emergency_contact_complete_name':
              payload['emergency_contact_complete_name'] ?? '',
          'emergency_contact_contact_number':
              payload['emergency_contact_contact_number'] ?? '',
          'relation': payload['relation'] ?? '',
          'username': username,
        },
      );
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();
      if (message.contains('already registered')) {
        throw Exception(
          'Email already used, please use other email.',
        );
      }
      if (message.contains('security purposes') ||
          message.contains('rate limit') ||
          code == '429') {
        throw Exception(
          'Please wait about 55 seconds before trying again.',
        );
      }
      rethrow;
    }

    if (authResponse.user == null) {
      throw Exception('Registration failed. Please try again.');
    }

    if (authResponse.session == null) {
      // Covers new unconfirmed users and obfuscated repeated-signup responses.
      await requestCitizenOtp(email: email, purpose: 'registration');
      return;
    }
  }

  /// Request a password reset email via Supabase Auth.
  static Future<void> requestPasswordReset({required String email}) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  /// Compatibility method for old OTP password reset screen.
  /// In backendless mode, use email recovery link + updateUser session flow.
  static Future<void> resetCitizenPassword({
    required String email,
    required String otp,
    required String password,
    required String confirmPassword,
  }) async {
    throw Exception(
      'OTP reset is no longer supported. Use the Supabase recovery email link to reset password.',
    );
  }

  /// Sign out the current user.
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Returns available doctor schedules for citizens.
  static Future<List<DoctorSchedule>> listAvailableDoctorSchedules({
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final dateFrom = DateTime(now.year, now.month, now.day);
    final dateTo = to ?? dateFrom.add(const Duration(days: 30));

    final response = await _client.rpc(
      'list_available_doctor_schedules',
      params: {
        'p_date_from': _asDate(from ?? dateFrom),
        'p_date_to': _asDate(dateTo),
      },
    );

    final rows = (response as List<dynamic>?) ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(DoctorSchedule.fromMap)
        .toList(growable: false);
  }

  static Future<void> submitCitizenFeedback(FeedbackSubmission feedback) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Please sign in before sending feedback.');
    }

    final citizen = await _client
        .from('citizens')
        .select('id, email')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    final citizenId = (citizen?['id'] as num?)?.toInt();
    final citizenEmail = (citizen?['email'] as String?)?.trim();
    final fallbackEmail = user.email?.trim();
    final fromEmail =
        (citizenEmail?.isNotEmpty == true ? citizenEmail : fallbackEmail) ??
        'unknown@ukonek.local';

    await _client.from('feedbacks').insert({
      'citizen_id': citizenId,
      'from_email': fromEmail,
      'subject': feedback.subject.trim(),
      'message': feedback.message.trim(),
      'rating': feedback.rating,
    });
  }

  static Future<List<QueueServiceOption>> listAvailableQueueServices({
    DateTime? date,
  }) async {
    final normalizedDate = date ?? DateTime.now();
    final response = await _client.rpc(
      'list_available_queue_services',
      params: {'p_date': _asDate(normalizedDate)},
    );

    final rows = (response as List<dynamic>?) ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(QueueServiceOption.fromMap)
        .where(
          (entry) =>
              entry.serviceKey.isNotEmpty &&
              entry.serviceLabel.isNotEmpty &&
              entry.doctorCount > 0,
        )
        .toList(growable: false);
  }

  static Future<QueueTicket> joinQueue(QueueJoinRequest request) async {
    final citizenType = request.citizenType.trim().toLowerCase();
    if (request.serviceKey.trim().isEmpty ||
        request.serviceLabel.trim().isEmpty) {
      throw Exception('Please select a healthcare service.');
    }
    if (!const {'regular', 'pwd', 'pregnant'}.contains(citizenType)) {
      throw Exception('Please select a valid citizen type.');
    }

    dynamic response;
    try {
      response = await _client.rpc(
        'create_queue_ticket',
        params: {
          'p_service_key': request.serviceKey.trim(),
          'p_service_label': request.serviceLabel.trim(),
          'p_citizen_type': citizenType,
          'p_reason': request.reason.trim(),
          'p_symptoms': request.symptoms.trim(),
        },
      );
    } on PostgrestException catch (error) {
      final rawMessage = error.message.toLowerCase();
      if (rawMessage.contains('citizen profile not found')) {
        throw Exception(
          'Your account is missing a citizen profile. Please contact the health center admin for account setup.',
        );
      }
      rethrow;
    }

    final rows = (response as List<dynamic>?) ?? const [];
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) {
      throw Exception('Failed to create queue ticket. Please try again.');
    }

    return QueueTicket.fromMap(rows.first as Map<String, dynamic>);
  }

  static Future<QueueDashboardSnapshot> getMyQueueDashboard() async {
    final response = await _client.rpc('get_my_queue_dashboard');
    final rows = (response as List<dynamic>?) ?? const [];
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) {
      return QueueDashboardSnapshot.empty;
    }
    return QueueDashboardSnapshot.fromMap(rows.first as Map<String, dynamic>);
  }

  static Future<List<PrescribedMedicine>> getMyPrescribedMedicines() async {
    final response = await _client.rpc('get_my_prescribed_medicines');
    final rows = (response as List<dynamic>?) ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PrescribedMedicine.fromMap)
        .where((item) => item.medicineName.isNotEmpty)
        .toList(growable: false);
  }

  static String _asDate(DateTime value) {
    final d = DateTime(value.year, value.month, value.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
