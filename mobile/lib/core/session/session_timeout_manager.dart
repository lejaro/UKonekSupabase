import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../menu_page.dart';
import '../../utils/app_transitions.dart';
import 'patient_session.dart';

/// Healthcare-compliant automatic session inactivity manager for U-Konek Mobile.
///
/// Terminates authenticated mobile sessions after [timeoutDuration] (default: 15 minutes)
/// of inactivity to prevent unauthorized access to sensitive patient health records (PHI).
class SessionTimeoutManager {
  SessionTimeoutManager._();

  /// Default idle timeout duration: 15 minutes.
  static const Duration defaultTimeout = Duration(minutes: 15);

  /// Active timeout duration. Can be customized or overridden if necessary.
  static Duration timeoutDuration = defaultTimeout;

  static const String _kLastActiveKey = 'session_last_active_ms';
  static const String _kTimedOutNoticeKey = 'session_timed_out_notice';

  static Timer? _inactivityTimer;
  static DateTime _lastActiveTime = DateTime.now();
  static DateTime _lastPersistTime = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _isLoggingOut = false;
  static bool _isInitialized = false;

  /// Returns true if an authenticated patient session currently exists.
  static bool get isLoggedIn =>
      PatientSessionState.session != null ||
      Supabase.instance.client.auth.currentSession != null;

  /// Initializes the session inactivity watcher and subscribes to session state changes.
  static void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    PatientSessionState.current.addListener(_onSessionStateChanged);

    if (isLoggedIn) {
      recordActivity();
    }
  }

  /// Cleans up observers and timers.
  static void dispose() {
    PatientSessionState.current.removeListener(_onSessionStateChanged);
    _cancelTimer();
    _isInitialized = false;
  }

  static void _onSessionStateChanged() {
    if (PatientSessionState.session != null) {
      _isLoggingOut = false;
      recordActivity();
    } else {
      _cancelTimer();
    }
  }

  /// Records user interaction (touch, drag, scroll, keystroke).
  /// Resets the foreground timer and updates the last active timestamp.
  static void recordActivity() {
    if (!isLoggedIn || _isLoggingOut) return;

    final now = DateTime.now();
    _lastActiveTime = now;
    _resetTimer(timeoutDuration);

    // Throttle persistent writes to SharedPreferences (at most once every 10 seconds)
    if (now.difference(_lastPersistTime).inSeconds >= 10) {
      _lastPersistTime = now;
      _persistLastActive(now);
    }
  }

  static void _resetTimer(Duration duration) {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(duration, () {
      logoutDueToInactivity();
    });
  }

  static void _cancelTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  static Future<void> _persistLastActive(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastActiveKey, time.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Handles app lifecycle state transitions (backgrounding, sleep, resumption).
  static Future<void> handleLifecycleChange(AppLifecycleState state) async {
    if (!isLoggedIn || _isLoggingOut) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App entered background or screen was turned off; persist latest activity
      await _persistLastActive(_lastActiveTime);
    } else if (state == AppLifecycleState.resumed) {
      // App brought back to foreground; verify elapsed background idle time
      final elapsed = DateTime.now().difference(_lastActiveTime);
      if (elapsed >= timeoutDuration) {
        debugPrint(
          '[SessionTimeout] Inactivity threshold exceeded while backgrounded (${elapsed.inMinutes}m elapsed). Logging out.',
        );
        await logoutDueToInactivity();
      } else {
        final remaining = timeoutDuration - elapsed;
        debugPrint(
          '[SessionTimeout] Resumed. Remaining idle time: ${remaining.inMinutes}m ${remaining.inSeconds % 60}s',
        );
        _resetTimer(remaining);
      }
    }
  }

  /// Checks if the persisted session exceeded the idle timeout duration
  /// (used during cold starts or process recovery in RootHandler).
  static Future<bool> checkPersistedTimeout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActiveMs = prefs.getInt(_kLastActiveKey) ?? 0;
      if (lastActiveMs > 0) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastActiveMs;
        if (elapsed >= timeoutDuration.inMilliseconds) {
          await prefs.remove(_kLastActiveKey);
          await prefs.setBool(_kTimedOutNoticeKey, true);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Checks and clears any pending timeout notice flag from a cold-start expiration.
  static Future<bool> consumeColdStartTimeoutNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hadNotice = prefs.getBool(_kTimedOutNoticeKey) ?? false;
      if (hadNotice) {
        await prefs.remove(_kTimedOutNoticeKey);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Automatically logs out the patient, clears sessions, redirects to Menu,
  /// and displays a security notice SnackBar.
  static Future<void> logoutDueToInactivity({String? customMessage}) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    _cancelTimer();

    debugPrint('[SessionTimeout] Triggering automatic logout due to inactivity.');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastActiveKey);
    } catch (_) {}

    try {
      await ApiService.signOut();
    } catch (e) {
      debugPrint('[SessionTimeout] ApiService.signOut error: $e');
    }

    PatientSessionState.clearSession();

    final nav = NotificationService.navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        AppPageRoute.fadeThrough(const uKonekMenuPage()),
        (route) => false,
      );
    }

    _showTimeoutNotice(message: customMessage);
    _isLoggingOut = false;
  }

  static void _showTimeoutNotice({String? message}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navContext = NotificationService.navigatorKey.currentContext;
      if (navContext != null) {
        final messenger = ScaffoldMessenger.maybeOf(navContext);
        if (messenger != null) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.timer_off_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message ??
                          'Session expired after ${timeoutDuration.inMinutes} minutes of inactivity for your security.',
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    });
  }
}

/// A top-level widget that intercepts touch events and forwards lifecycle changes
/// to [SessionTimeoutManager]. Wrap this inside [MaterialApp.builder].
class SessionTimeoutWrapper extends StatefulWidget {
  final Widget? child;

  const SessionTimeoutWrapper({super.key, required this.child});

  @override
  State<SessionTimeoutWrapper> createState() => _SessionTimeoutWrapperState();
}

class _SessionTimeoutWrapperState extends State<SessionTimeoutWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionTimeoutManager.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SessionTimeoutManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SessionTimeoutManager.handleLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SessionTimeoutManager.recordActivity(),
      onPointerMove: (_) => SessionTimeoutManager.recordActivity(),
      child: widget.child ?? const SizedBox.shrink(),
    );
  }
}
