import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../session/patient_session.dart';

/// Manages 4-Digit Security PIN authentication for U-Konek Mobile.
///
/// Keeps user sessions, push notifications, and background medicine scheduler alarms
/// fully functional while protecting the screen UI with a cryptographic 4-digit PIN.
class PinSecurityService {
  PinSecurityService._();
  static final PinSecurityService instance = PinSecurityService._();

  static const String _kPinHashPrefix = 'sec_pin_hash_';
  static const String _kPinSaltPrefix = 'sec_pin_salt_';
  static const String _kPinEnabledPrefix = 'sec_pin_enabled_';
  static const String _kPinFailedPrefix = 'sec_pin_failed_';
  static const String _kPinLockoutPrefix = 'sec_pin_lockout_until_';

  /// Grace period in seconds before app locks after moving to background (default: 60s).
  int autoLockTimeoutSeconds = 60;

  DateTime? _pausedTime;

  /// Reactive state for whether the app UI is currently locked behind the PIN screen.
  final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);

  bool get isLocked => isLockedNotifier.value;

  /// Lock the UI screen immediately.
  void lock() {
    isLockedNotifier.value = true;
  }

  /// Unlock the UI screen.
  void unlock() {
    isLockedNotifier.value = false;
  }

  String _currentCitizenId() {
    final session = PatientSessionState.session;
    if (session != null && session.id.isNotEmpty) {
      return session.id;
    }
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    return supabaseUser?.id ?? 'default_patient';
  }

  /// Hashes a 4-digit PIN with a cryptographic salt using SHA-256.
  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('UKONEK_SEC_SALT_$salt:$pin:$salt');
    return sha256.convert(bytes).toString();
  }

  String _generateSalt() {
    final rand = Random.secure();
    final values = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(values);
  }

  /// Returns true if a 4-digit PIN has been configured for the given or current patient.
  Future<bool> isPinConfigured([String? citizenId]) async {
    final cid = citizenId ?? _currentCitizenId();
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = prefs.getString('$_kPinHashPrefix$cid');
      return hash != null && hash.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the PIN protection is currently active/enabled.
  Future<bool> isPinEnabled([String? citizenId]) async {
    final cid = citizenId ?? _currentCitizenId();
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPin = prefs.getString('$_kPinHashPrefix$cid') != null;
      if (!hasPin) return false;
      return prefs.getBool('$_kPinEnabledPrefix$cid') ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Sets or updates the 4-digit PIN for the given or current patient.
  Future<void> setPin({required String pin, String? citizenId}) async {
    if (pin.length != 4 || int.tryParse(pin) == null) {
      throw ArgumentError('PIN must be exactly 4 digits');
    }
    final cid = citizenId ?? _currentCitizenId();
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kPinHashPrefix$cid', hash);
    await prefs.setString('$_kPinSaltPrefix$cid', salt);
    await prefs.setBool('$_kPinEnabledPrefix$cid', true);
    await prefs.remove('$_kPinFailedPrefix$cid');
    await prefs.remove('$_kPinLockoutPrefix$cid');

    unlock();
  }

  /// Enables or disables PIN prompt on app access.
  Future<void> setPinEnabled({required bool enabled, String? citizenId}) async {
    final cid = citizenId ?? _currentCitizenId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kPinEnabledPrefix$cid', enabled);
    if (!enabled) {
      unlock();
    }
  }

  /// Completely removes the configured PIN for the patient.
  Future<void> removePin([String? citizenId]) async {
    final cid = citizenId ?? _currentCitizenId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kPinHashPrefix$cid');
    await prefs.remove('$_kPinSaltPrefix$cid');
    await prefs.remove('$_kPinEnabledPrefix$cid');
    await prefs.remove('$_kPinFailedPrefix$cid');
    await prefs.remove('$_kPinLockoutPrefix$cid');
    unlock();
  }

  /// Returns the number of seconds remaining if currently throttled/locked out due to failed attempts.
  Future<int> getLockoutRemainingSeconds([String? citizenId]) async {
    final cid = citizenId ?? _currentCitizenId();
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutUntil = prefs.getInt('$_kPinLockoutPrefix$cid') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lockoutUntil > now) {
        return ((lockoutUntil - now) / 1000).ceil();
      }
    } catch (_) {}
    return 0;
  }

  /// Verifies entered 4-digit PIN.
  /// Returns `true` if correct and unlocks.
  /// Returns `false` on mismatch.
  Future<bool> verifyPin({required String pin, String? citizenId}) async {
    final cid = citizenId ?? _currentCitizenId();
    final remainingLockout = await getLockoutRemainingSeconds(cid);
    if (remainingLockout > 0) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedHash = prefs.getString('$_kPinHashPrefix$cid');
    final savedSalt = prefs.getString('$_kPinSaltPrefix$cid');

    if (savedHash == null || savedSalt == null) {
      // No PIN configured, allow access
      unlock();
      return true;
    }

    final inputHash = _hashPin(pin, savedSalt);
    if (inputHash == savedHash) {
      // Success: reset failure counter
      await prefs.remove('$_kPinFailedPrefix$cid');
      await prefs.remove('$_kPinLockoutPrefix$cid');
      unlock();
      return true;
    } else {
      // Failure: increment failure count
      final failed = (prefs.getInt('$_kPinFailedPrefix$cid') ?? 0) + 1;
      await prefs.setInt('$_kPinFailedPrefix$cid', failed);

      if (failed >= 5) {
        // Lock out for 30 seconds after 5 consecutive failed attempts
        final lockoutUntil = DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch;
        await prefs.setInt('$_kPinLockoutPrefix$cid', lockoutUntil);
      }
      return false;
    }
  }

  /// Verifies account password with Supabase to allow bypassing or resetting forgotten PIN.
  Future<bool> verifyAccountPassword(String password) async {
    final auth = Supabase.instance.client.auth;
    final currentUser = auth.currentUser;
    final email = currentUser?.email ?? PatientSessionState.session?.email;

    if (email == null || email.isEmpty) {
      return false;
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        unlock();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Handles app lifecycle state transitions to auto-lock after inactivity in background.
  Future<void> handleLifecycleChange(AppLifecycleState state) async {
    final hasUser = PatientSessionState.session != null ||
        Supabase.instance.client.auth.currentSession != null;
    if (!hasUser) return;

    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final elapsedSeconds = DateTime.now().difference(_pausedTime!).inSeconds;
        _pausedTime = null;

        if (elapsedSeconds >= autoLockTimeoutSeconds) {
          final enabled = await isPinEnabled();
          if (enabled) {
            lock();
          }
        }
      }
    }
  }
}
