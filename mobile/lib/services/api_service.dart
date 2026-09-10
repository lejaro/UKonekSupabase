import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/formatters.dart' as fmt;
import '../models/models.dart';

// Re-export domain models so all existing consumers maintain 100% backwards compatibility
export '../models/models.dart';

// ── BACKEND WEB WORKER SUBSYSTEM ENGINE (API SERVICE INTERFACE) ───────
class ApiService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Formats a doctor's name cleanly, stripping redundant 'Dr.', 'Dr', 'Doctor' prefixes
  /// and returning a single standardized 'Dr. [Clean Name]'.
  static String formatDoctorName(String? raw) => fmt.formatDoctorName(raw);

  // ── TTL-based in-memory cache to reduce redundant RPC calls ──────────
  static final Map<String, _CacheEntry> _cache = {};

  /// Retrieve a cached value if it exists and hasn't expired.
  static T? _getCached<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  /// Store a value in the cache with a TTL duration.
  static void _setCache<T>(String key, T value, Duration ttl) {
    _cache[key] = _CacheEntry(value: value, expiresAt: DateTime.now().add(ttl));
  }

  /// Clear all cached data (call on sign-out or manual refresh).
  static void clearAllCaches() {
    _cache.clear();
    _cachedCitizenProfile = null;
  }

  static String? _resolveEmailRedirectUrl() {
    const configured = String.fromEnvironment('APP_REDIRECT_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return Uri.base.origin;
    return null;
  }

  static Future<void> requestCitizenPreAuthOtp({required Map<String, dynamic> payload}) async {
    final response = await _client.functions.invoke('citizen-request-otp', body: payload);
    if (response.status != 200) {
      final data = response.data;
      final message = data is Map<String, dynamic> ? (data['error']?.toString() ?? 'Unable to send OTP.') : 'Unable to send OTP.';
      throw Exception(message);
    }
  }

  static Future<void> verifyCitizenPreAuthOtp({required String email, required String otp}) async {
    final response = await _client.functions.invoke('citizen-verify-otp', body: {
      'email': email.trim().toLowerCase(),
      'otp': otp.trim(),
    });
    if (response.status != 200) {
      final data = response.data;
      final message = data is Map<String, dynamic> ? (data['error']?.toString() ?? 'OTP verification failed.') : 'OTP verification failed.';
      throw Exception(message);
    }
  }

  static Future<void> completeCitizenPreAuthSignup({required String email, required String username, required String password}) async {
    final response = await _client.functions.invoke('citizen-complete-signup', body: {
      'email': email.trim().toLowerCase(),
      'username': username.trim(),
      'password': password,
    });
    if (response.status != 200) {
      final data = response.data;
      final message = data is Map<String, dynamic> ? (data['error']?.toString() ?? 'Unable to complete signup.') : 'Unable to complete signup.';
      throw Exception(message);
    }
  }

  static Future<void> requestCitizenOtp({required String email, required String purpose}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final emailRedirectTo = _resolveEmailRedirectUrl();

    try {
      await _client.auth.signInWithOtp(email: normalizedEmail, emailRedirectTo: emailRedirectTo, shouldCreateUser: false);
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();
      if (message.contains('otp_expired') || message.contains('token has expired') || message.contains('token has expired or is invalid')) {
        throw Exception('Verification link expired. Please request a new verification email and open the latest link only.');
      }
      if (message.contains('rate limit') || message.contains('too many')) {
        throw Exception('Please wait a minute before requesting another email.');
      }
      if (message.contains('security purposes') || code == '429') {
        throw Exception('Please wait about 55 seconds before requesting another verification email.');
      }
      if (message.contains('not authorized')) {
        throw Exception('Email sending is restricted by Supabase SMTP settings. Configure custom SMTP in Supabase Auth settings.');
      }
      rethrow;
    }
  }

  static Future<void> verifyCitizenEmailOtp({required String email, required String otp}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedOtp = otp.trim();

    if (normalizedOtp.isEmpty) throw Exception('Please enter the OTP code from your email.');

    try {
      await _client.auth.verifyOTP(email: normalizedEmail, token: normalizedOtp, type: OtpType.email);
    } on AuthException catch (_) {
      await _client.auth.verifyOTP(email: normalizedEmail, token: normalizedOtp, type: OtpType.signup);
    }
  }

  static bool hasVerifiedSessionForEmail(String email) {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    return (user.email ?? '').trim().toLowerCase() == email.trim().toLowerCase();
  }

  static Future<void> startCitizenEmailVerification({required Map<String, dynamic> payload}) async {
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
          'emergency_contact_complete_name': payload['emergency_contact_complete_name'] ?? '',
          'emergency_contact_contact_number': payload['emergency_contact_contact_number'] ?? '',
          'relation': payload['relation'] ?? '',
        },
      );
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();
      if (message.contains('otp_expired') || message.contains('token has expired') || message.contains('token has expired or is invalid')) {
        throw Exception('Verification link expired. Please request a new verification email and open the latest link only.');
      }
      if (message.contains('already registered')) throw Exception('Email already used, please use other email.');
      if (message.contains('security purposes') || message.contains('rate limit') || code == '429') {
        throw Exception('Please wait about 55 seconds before requesting another verification email.');
      }
      rethrow;
    }
  }

  static Future<void> completeCitizenRegistration({required Map<String, dynamic> payload}) async {
    final email = (payload['email'] as String).trim().toLowerCase();
    final username = (payload['username'] as String).trim();
    final password = payload['password'] as String;

    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Please verify your email first using the OTP magic link.');

    final sessionEmail = (user.email ?? '').trim().toLowerCase();
    if (sessionEmail != email) {
      throw Exception('Verified session email does not match registration email. Please verify the same email you entered.');
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw Exception(error.message);
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
        'p_emergency_contact_complete_name': payload['emergency_contact_complete_name'] ?? '',
        'p_emergency_contact_contact_number': payload['emergency_contact_contact_number'] ?? '',
        'p_relation': payload['relation'] ?? '',
        'p_username': username,
      },
    );

    if (response is Map<String, dynamic> && response['ok'] == false) {
      final message = (response['error'] ?? 'Unable to complete registration.').toString();
      throw Exception(message);
    }
  }

  static Future<Map<String, dynamic>> loginCitizen({required String identifier, required String password}) async {
    final loginEmail = identifier.trim().toLowerCase();
    if (!loginEmail.contains('@')) {
      throw const LoginFailureException(type: LoginFailureType.validation, message: 'Please enter your email address');
    }

    AuthResponse authResponse;
    try {
      authResponse = await _client.auth.signInWithPassword(email: loginEmail.toLowerCase(), password: password);
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();

      if (message.contains('invalid login credentials') || message.contains('invalid credentials') || message.contains('incorrect password') || code == '400') {
        throw const LoginFailureException(type: LoginFailureType.invalidCredentials, message: 'Wrong password or email. Please try again.');
      }
      if (message.contains('email not confirmed')) {
        throw const LoginFailureException(type: LoginFailureType.unverifiedEmail, message: 'Please verify your email using the OTP magic link before signing in.');
      }
      if (message.contains('network') || message.contains('timeout') || message.contains('failed to fetch')) {
        throw const LoginFailureException(type: LoginFailureType.network, message: 'Network issue. Please check your internet and try again.');
      }
      throw const LoginFailureException(type: LoginFailureType.unknown, message: 'Unable to sign in right now. Please try again.');
    }

    if (authResponse.user == null) {
      throw const LoginFailureException(type: LoginFailureType.invalidCredentials, message: 'Wrong password or email. Please try again.');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = authResponse.session?.accessToken ?? 'authenticated';
      await prefs.setString('session_token', token);
    } catch (e) {
      debugPrint('ApiService: Failed to save session_token: $e');
    }

    Map<String, dynamic>? profile = await _client.from('citizens').select().eq('auth_user_id', authResponse.user!.id).maybeSingle();

    if (profile == null) {
      try {
        await _client.rpc('link_my_citizen_auth_by_email');
      } catch (_) {}
      profile = await _client.from('citizens').select().eq('auth_user_id', authResponse.user!.id).maybeSingle();
    }

    if (profile == null) {
      throw const LoginFailureException(type: LoginFailureType.validation, message: 'Your account is missing a citizen profile. Please contact the health center admin for account setup.');
    }

    return {
      'user': profile,
      'session': {'access_token': authResponse.session?.accessToken},
    };
  }

  static Future<void> registerCitizen({required Map<String, dynamic> payload}) async {
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
          'emergency_contact_complete_name': payload['emergency_contact_complete_name'] ?? '',
          'emergency_contact_contact_number': payload['emergency_contact_contact_number'] ?? '',
          'relation': payload['relation'] ?? '',
          'username': username,
        },
      );
    } on AuthException catch (error) {
      final code = (error.statusCode ?? '').toString();
      final message = error.message.toLowerCase();
      if (message.contains('already registered')) throw Exception('Email already used, please use other email.');
      if (message.contains('security purposes') || message.contains('rate limit') || code == '429') {
        throw Exception('Please wait about 55 seconds before trying again.');
      }
      rethrow;
    }

    if (authResponse.user == null) throw Exception('Registration failed. Please try again.');

    if (authResponse.session == null) {
      await requestCitizenOtp(email: email, purpose: 'registration');
      return;
    }
  }

  static Future<void> requestPasswordReset({required String email}) async {
    String? redirectTo = const String.fromEnvironment('APP_REDIRECT_URL');
    if (redirectTo.isEmpty) {
      redirectTo = kIsWeb ? Uri.base.origin : 'ukonekmobile://reset-password';
    }
    await _client.auth.resetPasswordForEmail(
      email.trim().toLowerCase(),
      redirectTo: redirectTo,
    );
  }

  static Future<void> resetCitizenPassword({required String password}) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw Exception(error.message);
    }
  }

  static Future<void> signOut() async {
    clearAllCaches();
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Server signOut failed: $e, forcing local signout.');
    } finally {
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('session_token');
      } catch (_) {}
    }
  }

  static Future<List<DoctorStatus>> listDoctorStatus({bool forceRefresh = false}) async {
    const cacheKey = 'doctor_status_list';
    if (!forceRefresh) {
      final cached = _getCached<List<DoctorStatus>>(cacheKey);
      if (cached != null) return cached;
    }

    final response = await _client.rpc('list_staff_accounts');
    final rows = (response as List<dynamic>?) ?? const [];
    final result = rows
        .whereType<Map<String, dynamic>>()
        .where((row) => (row['role']?.toString().toLowerCase() ?? '') == 'doctor')
        .map(DoctorStatus.fromMap)
        .toList(growable: false);
    _setCache(cacheKey, result, const Duration(minutes: 5));
    return result;
  }

  static Future<List<DoctorSchedule>> listAvailableDoctorSchedules({DateTime? from, DateTime? to}) async {
    final now = DateTime.now();
    final dateFrom = DateTime(now.year, now.month, now.day);
    final dateTo = to ?? dateFrom.add(const Duration(days: 30));
    final cacheKey = 'doctor_schedules_${_asDate(from ?? dateFrom)}_${_asDate(dateTo)}';

    final cached = _getCached<List<DoctorSchedule>>(cacheKey);
    if (cached != null) return cached;

    final response = await _client.rpc(
      'list_available_doctor_schedules',
      params: {
        'p_date_from': _asDate(from ?? dateFrom),
        'p_date_to': _asDate(dateTo),
      },
    );

    final rows = (response as List<dynamic>?) ?? const [];
    final result = rows.whereType<Map<String, dynamic>>().map(DoctorSchedule.fromMap).toList(growable: false);
    _setCache(cacheKey, result, const Duration(minutes: 5));
    return result;
  }

  static Future<void> submitCitizenFeedback(FeedbackSubmission feedback) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Please sign in before sending feedback.');

    final citizen = await _client.from('citizens').select('id, email').eq('auth_user_id', user.id).maybeSingle();

    final citizenId = (citizen?['id'] as num?)?.toInt();
    final citizenEmail = (citizen?['email'] as String?)?.trim();
    final fallbackEmail = user.email?.trim();
    final fromEmail = (citizenEmail?.isNotEmpty == true ? citizenEmail : fallbackEmail) ?? 'unknown@ukonek.local';

    await _client.from('feedbacks').insert({
      'citizen_id': citizenId,
      'from_email': fromEmail,
      'subject': feedback.subject.trim(),
      'message': feedback.message.trim(),
      'rating': feedback.rating,
    });
  }

  static Future<List<QueueServiceOption>> listAvailableQueueServices({DateTime? date}) async {
    final normalizedDate = date ?? DateTime.now();
    final cacheKey = 'queue_services_${_asDate(normalizedDate)}';

    final cached = _getCached<List<QueueServiceOption>>(cacheKey);
    if (cached != null) return cached;

    final response = await _client.rpc('list_available_queue_services', params: {'p_date': _asDate(normalizedDate)});

    final rows = (response as List<dynamic>?) ?? const [];
    final result = rows
        .whereType<Map<String, dynamic>>()
        .map(QueueServiceOption.fromMap)
        .where((entry) => entry.serviceKey.isNotEmpty && entry.serviceLabel.isNotEmpty)
        .toList(growable: false);
    _setCache(cacheKey, result, const Duration(minutes: 5));
    return result;
  }

  static Future<QueueTicket> joinQueue(QueueJoinRequest request) async {
    final citizenType = request.citizenType.trim().toLowerCase();
    if (request.serviceKey.trim().isEmpty || request.serviceLabel.trim().isEmpty) {
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
        throw Exception('Your account is missing a citizen profile. Please contact the health center admin for account setup.');
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
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) return QueueDashboardSnapshot.empty;
    final map = rows.first as Map<String, dynamic>;
    // Read has_vitals directly from the RPC response (eliminates secondary query)
    final hasVitals = map['has_vitals'] == true;
    return QueueDashboardSnapshot.fromMap(map, hasVitals: hasVitals);
  }

  static Future<QueueLimiterStatus> getQueueLimiterStatus() async {
    const cacheKey = 'queue_limiter_status';
    final cached = _getCached<QueueLimiterStatus>(cacheKey);
    if (cached != null) return cached;

    final response = await _client.rpc('get_queue_limiter_status');
    final rows = (response as List<dynamic>?) ?? const [];
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) return QueueLimiterStatus.disabled();
    final result = QueueLimiterStatus.fromMap(rows.first as Map<String, dynamic>);
    _setCache(cacheKey, result, const Duration(seconds: 30));
    return result;
  }

  static Future<List<PrescribedMedicine>> getMyPrescribedMedicines() async {
    final response = await _client.rpc('get_my_prescribed_medicines');
    final rows = (response as List<dynamic>?) ?? const [];
    return rows.whereType<Map<String, dynamic>>().map(PrescribedMedicine.fromMap).where((item) => item.medicineName.isNotEmpty).toList(growable: false);
  }

  static Future<bool> cancelMyQueue() async {
    final response = await _client.rpc('cancel_my_queue_ticket');
    return response == true;
  }

  /// Retrieves the current status and details of a specific queue ticket.
  static Future<Map<String, dynamic>?> getTicketStatus(int ticketId) async {
    try {
      final response = await _client
          .from('queue_tickets')
          .select('id, status, service_label, queue_number, ticket_code, completed_at')
          .eq('id', ticketId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error getting ticket status: $e');
      return null;
    }
  }

  /// Retrieves the citizen's latest completed queue ticket for today.
  static Future<Map<String, dynamic>?> getCompletedQueueTicket({int? ticketId}) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await fetchMyCitizenProfile();
      final citizenId = profile['id'];

      var query = _client
          .from('queue_tickets')
          .select('id, status, service_label, queue_number, ticket_code, completed_at, queue_date')
          .eq('citizen_id', citizenId)
          .eq('status', 'completed');

      if (ticketId != null) {
        query = query.eq('id', ticketId);
      }

      final response = await query
          .order('completed_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error getting completed queue ticket: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _cachedCitizenProfile;

  static void clearCitizenProfileCache() {
    _cachedCitizenProfile = null;
  }

  static Future<Map<String, dynamic>> fetchMyCitizenProfile({bool force = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    if (!force && _cachedCitizenProfile != null && _cachedCitizenProfile!['auth_user_id'] == user.id) {
      return _cachedCitizenProfile!;
    }

    final response = await _client.from('citizens').select('*').eq('auth_user_id', user.id).maybeSingle();
    if (response == null) throw Exception('Citizen profile not found');
    _cachedCitizenProfile = response;
    return response;
  }

  static String _asDate(DateTime value) {
    final d = DateTime(value.year, value.month, value.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static Future<List<VitalSigns>> fetchVitalSigns({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final profile = await fetchMyCitizenProfile();
      final citizenId = profile['id'];

      final response = await _client.from('vital_signs').select().eq('citizen_id', citizenId).order('created_at', ascending: false).limit(limit);
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(VitalSigns.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching vital signs: $e');
      return [];
    }
  }

  static Future<List<ScheduledMedicine>> getMedicineSchedule() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _client.rpc('get_my_medicine_schedule');
      final rows = (response as List<dynamic>?) ?? const <dynamic>[];
      return rows.whereType<Map<String, dynamic>>().map(ScheduledMedicine.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching medicine schedule: $e');
      return [];
    }
  }

  static Future<List<PrescriptionRecord>> fetchPrescriptions({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _client.rpc('get_my_prescribed_medicines', params: {'p_limit': limit});
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(PrescriptionRecord.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching prescriptions: $e');
      return [];
    }
  }

  /// Synthesizes dispense log entries from dispensed prescription records.
  /// Used as a robust fallback when the backend dispense logs RPC returns empty
  /// or encounters an overloaded function error, ensuring the patient's Purchase Logs
  /// accurately reflect all fulfilled prescriptions.
  static List<PrescriptionDispenseLog> synthesizeDispenseLogsFromPrescriptions(
    List<PrescriptionRecord> prescriptions,
  ) {
    final List<PrescriptionDispenseLog> logs = [];
    int syntheticId = 1;

    for (final r in prescriptions) {
      final isDisp = r.isPrescriptionDispensed || r.isDispensed || r.dispensedQuantity > 0;
      if (!isDisp) continue;

      final qty = r.dispensedQuantity > 0 ? r.dispensedQuantity : r.quantity;
      final dispensedDate = r.dispensedAt ?? r.issuedAt;

      logs.add(PrescriptionDispenseLog(
        dispenseId: r.prescriptionId * 1000 + (syntheticId++),
        prescriptionId: r.prescriptionId,
        prescriptionCode: r.prescriptionCode,
        prescriptionItemId: r.prescriptionId * 1000 + syntheticId,
        medicineName: r.medicineName,
        dosage: r.dosage,
        dispensedQuantity: qty,
        unit: r.unit,
        note: r.instructions.isNotEmpty ? r.instructions : 'Fulfilled by Pharmacy',
        pharmacistName: 'Pharmacy Staff',
        dispensedAt: dispensedDate,
      ));
    }

    logs.sort((a, b) => b.dispensedAt.compareTo(a.dispensedAt));
    return logs;
  }

  /// Synthesizes ScheduledMedicine items from dispensed prescription records.
  /// Guarantees newly fulfilled dispensed medicines immediately populate
  /// the Medicine Scheduler even before background RPC synchronization completes.
  static List<ScheduledMedicine> synthesizeScheduledMedicinesFromPrescriptions(
    List<PrescriptionRecord> prescriptions,
  ) {
    final List<ScheduledMedicine> meds = [];
    for (final r in prescriptions) {
      final isDisp = r.isPrescriptionDispensed || r.isDispensed || r.dispensedQuantity > 0;
      if (!isDisp) continue;

      final qty = r.dispensedQuantity > 0 ? r.dispensedQuantity : r.quantity;
      final dispensedDate = r.dispensedAt ?? r.issuedAt;

      meds.add(ScheduledMedicine(
        prescriptionItemId: r.prescriptionId * 1000 + 1,
        prescriptionId: r.prescriptionId,
        prescriptionCode: r.prescriptionCode,
        dispensingStatus: r.dispensingStatus.isNotEmpty ? r.dispensingStatus : 'dispensed',
        issuedAt: r.issuedAt,
        dispensedAt: dispensedDate,
        doctorName: r.doctorName,
        medicineName: r.medicineName,
        quantity: qty,
        unit: r.unit,
        dosage: r.dosage,
        frequency: r.frequency,
        duration: r.duration,
        instructions: r.instructions,
        additionalInfo: r.additionalInfo,
        isAvailable: true,
        isDispensed: true,
      ));
    }
    return meds;
  }

  static Future<List<PrescriptionDispenseLog>> fetchPrescriptionDispenseLogs({
    int? prescriptionId,
    int limit = 50,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final params = <String, dynamic>{'p_limit': limit};
    if (prescriptionId != null) {
      params['p_prescription_id'] = prescriptionId;
    }

    // 1. Try canonical function
    try {
      final response = await _client.rpc('get_my_prescription_dispense_logs', params: params);
      final rows = (response as List<dynamic>?) ?? const [];
      if (rows.isNotEmpty) {
        return rows.whereType<Map<String, dynamic>>().map(PrescriptionDispenseLog.fromMap).toList();
      }
    } catch (e) {
      debugPrint('Primary get_my_prescription_dispense_logs failed: $e, trying alias...');
    }

    // 2. Try alias get_my_dispense_history
    try {
      final response = await _client.rpc('get_my_dispense_history', params: params);
      final rows = (response as List<dynamic>?) ?? const [];
      if (rows.isNotEmpty) {
        return rows.whereType<Map<String, dynamic>>().map(PrescriptionDispenseLog.fromMap).toList();
      }
    } catch (e) {
      debugPrint('Alias get_my_dispense_history failed: $e');
    }

    return [];
  }

  static Future<List<Consultation>> fetchConsultations({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final profile = await fetchMyCitizenProfile();
      final citizenId = profile['id'];

      final response = await _client.from('consultations').select('*, doctor:staff!doctor_staff_id(first_name, last_name)').eq('patient_citizen_id', citizenId).order('consulted_at', ascending: false).limit(limit);
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(Consultation.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching consultations: $e');
      return [];
    }
  }

  static Future<List<Announcement>> fetchAnnouncements() async {
    try {
      final response = await _client.from('announcements').select('id,title,content,visibility,created_at').inFilter('visibility', ['all', 'citizen']).order('created_at', ascending: false).limit(10);
      final rows = (response as List<dynamic>?) ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(Announcement.fromMap).toList();
    } catch (e) {
      debugPrint('Error fetching announcements: $e');
      return [];
    }
  }

  static Future<void> logMedicineIntake({required int prescriptionItemId, required String scheduledTime, required int doseIndex, int? citizenId, String? intakeDate}) async {
    if (citizenId == null) {
      final profile = await fetchMyCitizenProfile();
      citizenId = (profile['id'] as num).toInt();
    }

    // Bug #5 fix: Use the passed intakeDate (from UI's selected date) rather than DateTime.now()
    final dateStr = intakeDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    await _client.from('medicine_intake_logs').upsert({
      'citizen_id': citizenId,
      'prescription_item_id': prescriptionItemId,
      'scheduled_time': scheduledTime,
      'dose_index': doseIndex,
      'status': 'taken',
      'actual_time': DateTime.now().toUtc().toIso8601String(),
      'intake_date': dateStr,
    }, onConflict: 'citizen_id,prescription_item_id,dose_index,intake_date');
  }

  static Future<void> deleteMedicineIntakeLog({
    required int prescriptionItemId,
    required int doseIndex,
    required String intakeDate,
    int? citizenId,
  }) async {
    if (citizenId == null) {
      final profile = await fetchMyCitizenProfile();
      citizenId = (profile['id'] as num).toInt();
    }
    await _client
        .from('medicine_intake_logs')
        .delete()
        .eq('citizen_id', citizenId)
        .eq('prescription_item_id', prescriptionItemId)
        .eq('dose_index', doseIndex)
        .eq('intake_date', intakeDate);
  }

  static Future<List<Map<String, dynamic>>> getIntakeLogsForDate(DateTime date, {int? citizenId}) async {
    if (citizenId == null) {
      final profile = await fetchMyCitizenProfile();
      citizenId = (profile['id'] as num).toInt();
    }

    // Bug #4 fix: Query by intake_date (plain DATE column) instead of created_at (UTC timestamp)
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    final response = await _client
        .from('medicine_intake_logs')
        .select()
        .eq('citizen_id', citizenId)
        .eq('intake_date', dateStr);

    return (response as List<dynamic>?)?.whereType<Map<String, dynamic>>().toList() ?? [];
  }

  static Future<void> updateMyCitizenProfile(Map<String, dynamic> data) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await _client.from('citizens').update(data).eq('auth_user_id', user.id);
    _cachedCitizenProfile = null;
  }

  // â”€â”€ ðŸ’¡ FIXED: Missing function definition completely integrated â”€â”€
  static Future<Map<String, dynamic>> getTvQueueDisplay() async {
    try {
      final response = await _client.rpc('get_tv_queue_display');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {};
    } catch (e) {
      debugPrint('Error fetching TV display: $e');
      return {};
    }
  }

  static String _prescriptionAckKeyForUser() {
    try {
      final session = _client.auth.currentSession;
      final userId = session?.user.id;
      if (userId != null && userId.isNotEmpty) {
        return 'last_acknowledged_prescription_id_$userId';
      }
    } catch (_) {}
    return 'last_acknowledged_prescription_id';
  }

  /// Retrieves the latest prescription if it has not been acknowledged yet.
  /// Used to trigger the New E-Prescription pop-up modal and local notification.
  static Future<NewPrescriptionAlert?> fetchLatestUnacknowledgedPrescription() async {
    try {
      final records = await fetchPrescriptions(limit: 20);
      if (records.isEmpty) return null;

      // Group by prescriptionId
      final Map<int, List<PrescriptionRecord>> groups = {};
      for (final r in records) {
        if (r.prescriptionId <= 0) continue;
        groups.putIfAbsent(r.prescriptionId, () => []).add(r);
      }
      if (groups.isEmpty) return null;

      // Find the newest prescription group by highest ID or most recent issuedAt
      final sortedEntries = groups.entries.toList()
        ..sort((a, b) {
          final timeComp = b.value.first.issuedAt.compareTo(a.value.first.issuedAt);
          if (timeComp != 0) return timeComp;
          return b.key.compareTo(a.key);
        });

      final latestGroup = sortedEntries.first;
      final latestId = latestGroup.key;
      final latestItems = latestGroup.value;
      final firstItem = latestItems.first;

      final prefs = await SharedPreferences.getInstance();
      final userKey = _prescriptionAckKeyForUser();
      final lastAckIdUser = prefs.getInt(userKey) ?? 0;
      final lastAckIdGlobal = prefs.getInt('last_acknowledged_prescription_id') ?? 0;
      final lastAckId = lastAckIdUser > lastAckIdGlobal ? lastAckIdUser : lastAckIdGlobal;

      // If already acknowledged, do not alert again
      if (latestId <= lastAckId) return null;

      // Only alert if issued recently (within last 24 hours)
      final age = DateTime.now().difference(firstItem.issuedAt);
      if (age.inHours > 24) {
        // Automatically mark stale prescription as acknowledged so it doesn't pop up later
        await acknowledgePrescription(latestId);
        return null;
      }

      return NewPrescriptionAlert(
        prescriptionId: latestId,
        prescriptionCode: firstItem.prescriptionCode,
        doctorName: firstItem.displayDoctorName,
        issuedAt: firstItem.issuedAt,
        items: latestItems,
      );
    } catch (e) {
      debugPrint('Error checking unacknowledged prescription: $e');
      return null;
    }
  }

  /// Marks a prescription ID as acknowledged so its pop-up notification is not repeated.
  static Future<void> acknowledgePrescription(int prescriptionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('last_acknowledged_prescription_id') ?? 0;
      if (prescriptionId > current) {
        await prefs.setInt('last_acknowledged_prescription_id', prescriptionId);
      }
      final userKey = _prescriptionAckKeyForUser();
      if (userKey != 'last_acknowledged_prescription_id') {
        final userCurrent = prefs.getInt(userKey) ?? 0;
        if (prescriptionId > userCurrent) {
          await prefs.setInt(userKey, prescriptionId);
        }
      }
    } catch (e) {
      debugPrint('Error acknowledging prescription: $e');
    }
  }
}

/// Internal cache entry with expiry time.
class _CacheEntry {
  final dynamic value;
  final DateTime expiresAt;

  const _CacheEntry({required this.value, required this.expiresAt});
}
