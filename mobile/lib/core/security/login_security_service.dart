import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages password lockout, rate limiting, and persistent timer state
/// for the citizen login screen.
///
/// Prevents bypassing the 60-second lockout timer or resetting failed
/// attempt counts when navigating away from the login page.
class LoginSecurityService {
  LoginSecurityService._();
  static final LoginSecurityService instance = LoginSecurityService._();

  static const String _kLockoutUntilKey = 'ukonek_login_lockout_until';
  static const String _kAttemptsLeftKey = 'ukonek_login_attempts_left';

  static const int maxAttempts = 3;
  static const int lockoutDurationSeconds = 60;

  // In-memory cache for synchronous read fallbacks
  int? _cachedAttemptsLeft;
  int? _cachedLockoutUntil;

  /// Returns the number of seconds remaining in the lockout period.
  /// Returns 0 if not currently locked out.
  Future<int> getLockoutRemainingSeconds() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check in-memory cache first
    if (_cachedLockoutUntil != null) {
      if (_cachedLockoutUntil! > now) {
        return ((_cachedLockoutUntil! - now) / 1000).ceil();
      } else {
        _cachedLockoutUntil = null;
        _cachedAttemptsLeft = maxAttempts;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutUntil = prefs.getInt(_kLockoutUntilKey) ?? 0;
      _cachedLockoutUntil = lockoutUntil > 0 ? lockoutUntil : null;

      if (lockoutUntil > now) {
        return ((lockoutUntil - now) / 1000).ceil();
      } else if (lockoutUntil > 0) {
        // Lockout expired: clean up persistence
        await clearLockout();
      }
    } catch (_) {}

    return 0;
  }

  /// Synchronously checks if an active in-memory lockout is running.
  bool get isCachedLocked {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _cachedLockoutUntil != null && _cachedLockoutUntil! > now;
  }

  /// Returns the remaining login attempts before account lockout (between 0 and 3).
  Future<int> getAttemptsLeft() async {
    final remaining = await getLockoutRemainingSeconds();
    if (remaining > 0) {
      _cachedAttemptsLeft = 0;
      return 0;
    }

    if (_cachedAttemptsLeft != null) {
      return _cachedAttemptsLeft!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final attempts = prefs.getInt(_kAttemptsLeftKey);
      if (attempts != null) {
        _cachedAttemptsLeft = attempts;
        return attempts;
      }
    } catch (_) {}

    _cachedAttemptsLeft = maxAttempts;
    return maxAttempts;
  }

  /// Records a failed credential attempt and starts a 60s lockout if attempts reach zero.
  Future<int> recordFailedAttempt() async {
    int attempts = await getAttemptsLeft();
    attempts = (attempts - 1).clamp(0, maxAttempts);
    _cachedAttemptsLeft = attempts;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAttemptsLeftKey, attempts);

      if (attempts <= 0) {
        final lockoutUntil = DateTime.now()
            .add(const Duration(seconds: lockoutDurationSeconds))
            .millisecondsSinceEpoch;
        _cachedLockoutUntil = lockoutUntil;
        await prefs.setInt(_kLockoutUntilKey, lockoutUntil);
      }
    } catch (_) {}

    return attempts;
  }

  /// Manually starts a lockout period for the specified duration (default: 60s).
  Future<void> startLockout([int seconds = lockoutDurationSeconds]) async {
    _cachedAttemptsLeft = 0;
    final lockoutUntil = DateTime.now()
        .add(Duration(seconds: seconds))
        .millisecondsSinceEpoch;
    _cachedLockoutUntil = lockoutUntil;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAttemptsLeftKey, 0);
      await prefs.setInt(_kLockoutUntilKey, lockoutUntil);
    } catch (_) {}
  }

  /// Resets failed attempt counts and cancels any active lockout upon successful authentication.
  Future<void> resetOnSuccess() async {
    _cachedAttemptsLeft = maxAttempts;
    _cachedLockoutUntil = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAttemptsLeftKey);
      await prefs.remove(_kLockoutUntilKey);
    } catch (_) {}
  }

  /// Clears expired lockout state and restores full attempt allotment.
  Future<void> clearLockout() async {
    _cachedAttemptsLeft = maxAttempts;
    _cachedLockoutUntil = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAttemptsLeftKey);
      await prefs.remove(_kLockoutUntilKey);
    } catch (_) {}
  }
}
