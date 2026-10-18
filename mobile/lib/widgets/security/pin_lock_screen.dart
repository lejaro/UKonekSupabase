import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/security/pin_security_service.dart';
import '../../core/session/patient_session.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../menu_page.dart';
import '../../utils/app_transitions.dart';
import 'pin_pad.dart';

/// Full-screen security barrier presented when app is locked with a 4-digit PIN.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final GlobalKey<PinPadState> _pinPadKey = GlobalKey<PinPadState>();
  String? _errorMessage;
  bool _isThrottled = false;
  int _throttleSeconds = 0;
  Timer? _throttleTimer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _checkInitialLockout();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialLockout() async {
    final remaining = await PinSecurityService.instance.getLockoutRemainingSeconds();
    if (remaining > 0 && mounted) {
      _startThrottleCountdown(remaining);
    }
  }

  void _startThrottleCountdown(int seconds) {
    _throttleTimer?.cancel();
    setState(() {
      _isThrottled = true;
      _throttleSeconds = seconds;
      _errorMessage = 'Too many attempts. Please wait $_throttleSeconds s.';
    });

    _throttleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_throttleSeconds <= 1) {
        timer.cancel();
        setState(() {
          _isThrottled = false;
          _throttleSeconds = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _throttleSeconds--;
          _errorMessage = 'Too many attempts. Please wait $_throttleSeconds s.';
        });
      }
    });
  }

  Future<void> _onPinEntered(String pin) async {
    if (_isVerifying || _isThrottled) return;
    setState(() => _isVerifying = true);

    final success = await PinSecurityService.instance.verifyPin(pin: pin);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (success) {
      // Unlocked!
      setState(() {
        _errorMessage = null;
      });
    } else {
      final remainingLockout = await PinSecurityService.instance.getLockoutRemainingSeconds();
      if (remainingLockout > 0) {
        _startThrottleCountdown(remainingLockout);
      } else {
        setState(() {
          _errorMessage = 'Incorrect PIN. Please try again.';
        });
        _pinPadKey.currentState?.triggerShake();
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final passwordController = TextEditingController();
    bool isSubmitting = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (sbContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.lock_reset_rounded, color: Color(0xFF059669), size: 26),
              SizedBox(width: 10),
              Text(
                'Forgot PIN?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your account password to verify your identity and reset your 4-digit PIN.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Account Password',
                  hintText: 'Enter password',
                  prefixIcon: const Icon(Icons.password_rounded, color: Color(0xFF059669), size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: dialogError,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final pwd = passwordController.text.trim();
                      if (pwd.isEmpty) {
                        setDialogState(() => dialogError = 'Password cannot be empty');
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = true;
                        dialogError = null;
                      });

                      final verified = await PinSecurityService.instance.verifyAccountPassword(pwd);
                      if (!mounted) return;

                      if (verified) {
                        await PinSecurityService.instance.removePin();
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: const Text('PIN reset successfully. You can set a new PIN in Profile Settings.'),
                            backgroundColor: const Color(0xFF059669),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      } else {
                        setDialogState(() {
                          isSubmitting = false;
                          dialogError = 'Incorrect account password.';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify & Reset', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign Out?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out of U-Konek on this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.signOut();
    } catch (_) {}

    PatientSessionState.clearSession();
    PinSecurityService.instance.unlock();

    final nav = NotificationService.navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        AppPageRoute.fadeThrough(const uKonekMenuPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = PatientSessionState.session;
    final patientFirstName = session != null && session.firstName.isNotEmpty
        ? session.firstName
        : (session?.username.isNotEmpty == true ? session!.username.split(' ').first : 'Patient');

    return PopScope(
      canPop: false, // Prevent physical back button from bypassing lock
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),

                          // ── App Brand & Security Badge ──
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x10059669),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFF059669),
                              size: 32,
                            ),
                          ),

                          const SizedBox(height: 18),

                          const Text(
                            'Enter Security PIN',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            'Welcome back, $patientFirstName',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ── Pin Pad ──
                          PinPad(
                            key: _pinPadKey,
                            onPinComplete: _onPinEntered,
                            errorMessage: _errorMessage,
                            isThrottled: _isThrottled,
                            throttleSeconds: _throttleSeconds,
                          ),

                          const Spacer(),

                          // ── Recovery & Alternative Options ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: _showForgotPasswordDialog,
                                icon: const Icon(Icons.help_outline_rounded, size: 16, color: Color(0xFF059669)),
                                label: const Text(
                                  'Forgot PIN?',
                                  style: TextStyle(
                                    color: Color(0xFF059669),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: _handleSignOut,
                                icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF64748B)),
                                label: const Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
