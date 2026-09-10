import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/login_failure.dart';
import '../core/network/api_cache.dart';
import 'citizen_profile_service.dart';

class AuthService {
  AuthService._();

  static SupabaseClient get _client => Supabase.instance.client;

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
      debugPrint('AuthService: Failed to save session_token: $e');
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
    ApiCache.clear();
    CitizenProfileService.clearCitizenProfileCache();
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
}
