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

enum _PinLockOverlay { none, forgotPin, signOut }

class _PinLockScreenState extends State<PinLockScreen> {
  final GlobalKey<PinPadState> _pinPadKey = GlobalKey<PinPadState>();
  String? _errorMessage;
  bool _isThrottled = false;
  int _throttleSeconds = 0;
  Timer? _throttleTimer;
  bool _isVerifying = false;

  // ── Overlay state ──
  _PinLockOverlay _activeOverlay = _PinLockOverlay.none;
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmittingForgot = false;
  String? _forgotError;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _checkInitialLockout();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _passwordController.dispose();
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

  void _openForgotPinDialog() {
    _passwordController.clear();
    setState(() {
      _obscurePassword = true;
      _forgotError = null;
      _isSubmittingForgot = false;
      _activeOverlay = _PinLockOverlay.forgotPin;
    });
  }

  void _openSignOutDialog() {
    setState(() {
      _isSigningOut = false;
      _activeOverlay = _PinLockOverlay.signOut;
    });
  }

  void _closeOverlay() {
    setState(() {
      _activeOverlay = _PinLockOverlay.none;
      _forgotError = null;
      _isSubmittingForgot = false;
      _isSigningOut = false;
    });
  }

  Future<void> _submitForgotPassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.isEmpty) {
      setState(() => _forgotError = 'Please enter your account password');
      return;
    }

    setState(() {
      _isSubmittingForgot = true;
      _forgotError = null;
    });

    final verified = await PinSecurityService.instance.verifyAccountPassword(pwd);
    if (!mounted) return;

    if (verified) {
      await PinSecurityService.instance.removePin();
      PinSecurityService.instance.unlock();

      setState(() {
        _isSubmittingForgot = false;
        _activeOverlay = _PinLockOverlay.none;
      });

      final rootCtx = NotificationService.navigatorKey.currentContext;
      if (rootCtx != null && rootCtx.mounted) {
        try {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PIN reset successfully. You can configure a new PIN in Profile Settings.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } catch (_) {}
      }
    } else {
      setState(() {
        _isSubmittingForgot = false;
        _forgotError = 'Incorrect account password. Please try again.';
      });
    }
  }

  Future<void> _submitSignOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);

    try {
      await ApiService.signOut();
    } catch (e) {
      debugPrint('[PinLockScreen] Sign out notice: $e');
    }

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

  Widget _buildForgotPinOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isSubmittingForgot ? null : _closeOverlay,
      child: Container(
        color: const Color(0x8C000000),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: GestureDetector(
          onTap: () {}, // Prevent taps inside card from closing
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF059669), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Forgot PIN?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _isSubmittingForgot ? null : _closeOverlay,
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter your account password to verify your identity and reset your 4-digit PIN.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitForgotPassword(),
                    decoration: InputDecoration(
                      labelText: 'Account Password',
                      hintText: 'Enter password',
                      prefixIcon: const Icon(Icons.password_rounded, color: Color(0xFF059669), size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: _forgotError,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmittingForgot ? null : _closeOverlay,
                        child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isSubmittingForgot ? null : _submitForgotPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmittingForgot
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Verify & Reset',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 24, color: Color(0xFFF1F5F9)),
                  Center(
                    child: TextButton(
                      onPressed: _isSubmittingForgot ? null : _openSignOutDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Forgot your password too? Sign out here',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isSigningOut ? null : _closeOverlay,
      child: Container(
        color: const Color(0x8C000000),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: GestureDetector(
          onTap: () {}, // Prevent taps inside card from closing
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Sign Out?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Are you sure you want to log out of U-Konek on this device? You will need to log in again with your email and password.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSigningOut ? null : _closeOverlay,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSigningOut ? null : _submitSignOut,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isSigningOut
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Yes, Sign Out',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
        body: Stack(
          children: [
            SafeArea(
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),

                              const SizedBox(height: 24),

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
                                    onPressed: _openForgotPinDialog,
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
                                    onPressed: _openSignOutDialog,
                                    icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFFDC2626)),
                                    label: const Text(
                                      'Sign Out',
                                      style: TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.w700,
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

            // In-screen Modal Overlays (avoids Navigator issues outside MaterialApp routes)
            if (_activeOverlay == _PinLockOverlay.forgotPin)
              Positioned.fill(child: _buildForgotPinOverlay()),
            if (_activeOverlay == _PinLockOverlay.signOut)
              Positioned.fill(child: _buildSignOutOverlay()),
          ],
        ),
      ),
    );
  }
}
