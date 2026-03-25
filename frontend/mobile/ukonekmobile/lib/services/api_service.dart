import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

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
      final message = error.message.toLowerCase();
      if (message.contains('rate limit') || message.contains('too many')) {
        throw Exception('Please wait a minute before requesting another email.');
      }
      if (message.contains('not authorized')) {
        throw Exception('Email sending is restricted by Supabase SMTP settings. Configure custom SMTP in Supabase Auth settings.');
      }
      rethrow;
    }
  }

  /// Sign in a citizen using email + password.
  static Future<Map<String, dynamic>> loginCitizen({
    required String identifier,
    required String password,
  }) async {
    final loginEmail = identifier.trim().toLowerCase();
    if (!loginEmail.contains('@')) {
      throw Exception('Please enter your email address');
    }

    final authResponse = await _client.auth.signInWithPassword(
      email: loginEmail.toLowerCase(),
      password: password,
    );

    if (authResponse.user == null) {
      throw Exception('Invalid email or password');
    }

    // Fetch the citizen profile
    final profile = await _client
        .from('citizens')
        .select()
        .eq('auth_user_id', authResponse.user!.id)
        .maybeSingle();

    return {
      'user': profile ?? {'email': loginEmail},
      'session': {
        'access_token': authResponse.session?.accessToken,
      },
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
      final message = error.message.toLowerCase();
      if (message.contains('already registered')) {
        await requestCitizenOtp(email: email, purpose: 'registration');
        return;
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
  static Future<void> requestPasswordReset({
    required String email,
  }) async {
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
      'OTP reset is no longer supported. Use the Supabase recovery email link to reset password.'
    );
  }

  /// Sign out the current user.
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
