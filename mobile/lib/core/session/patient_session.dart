import 'package:flutter/foundation.dart';

/// Immutable patient demographic session model.
@immutable
class PatientSession {
  final String id;
  final String username;
  final String fullname;
  final String email;
  final String phone;
  final String address;
  final Map<String, dynamic> rawProfile;

  const PatientSession({
    required this.id,
    required this.username,
    required this.fullname,
    this.email = '',
    this.phone = '',
    this.address = '',
    this.rawProfile = const {},
  });

  factory PatientSession.fromProfile(Map<String, dynamic> profile) {
    final citizenId = (profile['id'] ?? '').toString();
    final username = (profile['username'] ?? '').toString();
    final firstName = (profile['firstname'] ?? '').toString().trim();
    final middleInitial = (profile['middle_initial'] ?? '').toString().trim();
    final surname = (profile['surname'] ?? '').toString().trim();

    final parts = [firstName, middleInitial, surname].where((p) => p.isNotEmpty).join(' ');
    final fullname = parts.isNotEmpty ? parts : username;

    return PatientSession(
      id: citizenId,
      username: username,
      fullname: fullname,
      email: (profile['email'] ?? '').toString().trim(),
      phone: (profile['contact_number'] ?? '').toString().trim(),
      address: (profile['complete_address'] ?? '').toString().trim(),
      rawProfile: profile,
    );
  }

  PatientSession copyWith({
    String? id,
    String? username,
    String? fullname,
    String? email,
    String? phone,
    String? address,
    Map<String, dynamic>? rawProfile,
  }) {
    return PatientSession(
      id: id ?? this.id,
      username: username ?? this.username,
      fullname: fullname ?? this.fullname,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      rawProfile: rawProfile ?? this.rawProfile,
    );
  }
}

/// Global reactive session state provider for the logged-in patient.
class PatientSessionState {
  PatientSessionState._();

  static final ValueNotifier<PatientSession?> current = ValueNotifier<PatientSession?>(null);

  static PatientSession? get session => current.value;

  static String get username => session?.username ?? '';
  static String get citizenId => session?.id ?? '';
  static String get fullname => session?.fullname ?? '';
  static String get email => session?.email ?? '';
  static String get phone => session?.phone ?? '';
  static String get address => session?.address ?? '';

  static void setSession(PatientSession session) {
    current.value = session;
  }

  static void clearSession() {
    current.value = null;
  }
}
