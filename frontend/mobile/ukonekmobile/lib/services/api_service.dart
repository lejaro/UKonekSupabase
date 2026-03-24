import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Compatibility method: OTP flow was removed in backendless mode.
  /// Keep a no-op so existing UI flow does not crash.
  static Future<void> requestCitizenOtp({
    required String email,
    required String purpose,
  }) async {
    return;
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

    final authResponse = await _client.auth.signUp(
      email: email,
      password: password,
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

    if (authResponse.user == null) {
      throw Exception('Registration failed. Please try again.');
    }

    if (authResponse.session == null) {
      // Email confirmation may be required depending on project settings.
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
