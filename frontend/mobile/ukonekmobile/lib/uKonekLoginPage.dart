import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'services/api_service.dart';
import 'uKonekDashboardPage.dart';
import 'package:ukonekmobile/uKonekRegistration/uKonekRegisterWrapper.dart';
import 'uKonekMenuPage.dart';
import 'uKonekForgotPasswordPage.dart';

class uKonekLoginPage extends StatefulWidget {
  const uKonekLoginPage({super.key});
  @override
  State<uKonekLoginPage> createState() => _uKonekLoginPageState();
}

class _uKonekLoginPageState extends State<uKonekLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // ── Attempt & lockout state ──────────────────────────────────
  int _attemptsLeft = 3;
  bool _isLocked = false;
  int _lockSecondsLeft = 60;
  Timer? _lockTimer;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── Updated Medical Green Design Tokens ──────────────────────
  static const _primary      = Color(0xFF28A745); // Health Green
  static const _primary2     = Color(0xFF1B5E20); // Forest Green
  static const _bg           = Color(0xFFF8FCF9); // Mint Background
  static const _textDark     = Color(0xFF1B2E1E); // Dark Forest Charcoal
  static const _textMuted    = Color(0xFF637367); // Muted Sage
  static const _fieldBdr     = Color(0xFFE2E9E3); // Light Mist Border

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  void _startLockout() {
    setState(() {
      _isLocked = true;
      _lockSecondsLeft = 60;
    });
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockSecondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _isLocked = false;
          _attemptsLeft = 3;
          _lockSecondsLeft = 60;
        });
        passwordController.clear();
      } else {
        setState(() => _lockSecondsLeft--);
      }
    });
  }

  Future<void> _resendVerificationOtp() async {
    final email = usernameController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSnack('Enter your email first, then tap Resend OTP.', isError: true);
      return;
    }

    try {
      await ApiService.requestCitizenOtp(email: email, purpose: 'email_verification');
      if (!mounted) return;
      _showSnack('OTP verification link sent to your email.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : _primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> login() async {
    if (_isLocked || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.loginCitizen(
        identifier: usernameController.text,
        password: passwordController.text,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _attemptsLeft = 3;
      });

      final user = response['user'] as Map<String, dynamic>?;
      final displayName = (user?['username'] as String?)?.trim().isNotEmpty == true
          ? user!['username'] as String
          : usernameController.text.trim();

      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => uKonekDashboardPage(
            username: displayName,
            citizenId: (user?['id'] ?? '').toString(),
          ),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
            (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      final loginError = error is LoginFailureException ? error : null;
      final message = loginError?.message ?? error.toString().replaceFirst('Exception: ', '');
      final countsAsAttempt = loginError?.countsAsAttempt ?? false;

      if (loginError?.type == LoginFailureType.unverifiedEmail) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Email not verified. Tap RESEND OTP for a magic link.'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'RESEND', textColor: Colors.white, onPressed: _resendVerificationOtp),
          ),
        );
        return;
      }

      setState(() {
        _isLoading = false;
        if (countsAsAttempt) _attemptsLeft--;
      });

      if (countsAsAttempt) passwordController.clear();

      if (countsAsAttempt && _attemptsLeft <= 0) {
        _startLockout();
      } else {
        final suffix = countsAsAttempt ? ' ($_attemptsLeft left)' : '';
        _showSnack('$message$suffix', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: _bg, // Updated mint background
      body: Stack(
        children: [
          // ── Green gradient top ────────────────────────────────
          Container(
            height: size.height * 0.42,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary, _primary2], // Updated Green Gradient
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildHeaderSection(),
                      _buildLoginCard(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const uKonekMenuPage()),
                      (route) => false,
                ),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.health_and_safety_rounded, color: _primary, size: 34), // Updated icon
          ),
          const SizedBox(height: 14),
          const Text("Welcome Back", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text("Sign in to your U-Konek+ account", style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: _textDark.withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Sign In", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textDark)),
            const SizedBox(height: 4),
            const Text("Enter your credentials to continue", style: TextStyle(fontSize: 12, color: _textMuted)),
            const SizedBox(height: 24),

            _inputField(
              label: "Email",
              controller: usernameController,
              icon: Icons.person_outline_rounded,
              enabled: !_isLocked,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return "Email is required";
                if (!v.contains('@') || !v.contains('.')) return "Enter a valid email address";
                return null;
              },
            ),
            const SizedBox(height: 14),

            _inputField(
              label: "Password",
              controller: passwordController,
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePassword,
              enabled: !_isLocked,
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: _textMuted.withOpacity(0.5)),
                onPressed: _isLocked ? null : () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) => (v == null || v.isEmpty) ? "Password is required" : (v.length < 8 ? "Min. 8 characters" : null),
            ),

            const SizedBox(height: 10),
            if (!_isLocked && _attemptsLeft < 3) _attemptIndicator(),
            if (_isLocked) _lockoutBanner(),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const uKonekForgotPasswordPage())),
                child: const Text("Forgot password?", style: TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 4),
            _buildInfoTip(),
            const SizedBox(height: 24),

            // Sign in button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLocked ? _fieldBdr : _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: _isLocked ? 0 : 4,
                  shadowColor: _primary.withOpacity(0.4),
                ),
                onPressed: (_isLoading || _isLocked) ? null : login,
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isLocked ? "Locked — ${_lockSecondsLeft}s" : "SIGN IN",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.2, color: _isLocked ? _textMuted : Colors.white)),
                    if (!_isLocked) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 18)],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Center(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13, color: _textMuted),
                  children: [
                    const TextSpan(text: "Don't have an account? "),
                    TextSpan(
                      text: "Register here",
                      style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const uKonekRegisterWrapper())),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _primary.withOpacity(0.04),
        border: Border.all(color: _primary.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: _primary, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text("Use your registered citizen email address.", style: TextStyle(fontSize: 11, color: _primary2, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _attemptIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
          const SizedBox(width: 6),
          Text("$_attemptsLeft attempt${_attemptsLeft == 1 ? '' : 's'} left", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Row(
            children: List.generate(3, (i) {
              return Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < _attemptsLeft ? Colors.orange : _fieldBdr),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _lockoutBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red.shade100), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Account Locked", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                Text("Try again in $_lockSecondsLeft seconds.", style: TextStyle(color: Colors.red.shade400, fontSize: 12)),
              ],
            ),
          ),
          SizedBox(
            width: 44, height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: _lockSecondsLeft / 60, strokeWidth: 3, backgroundColor: Colors.red.shade100, valueColor: const AlwaysStoppedAnimation<Color>(Colors.red)),
                Text("$_lockSecondsLeft", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool obscure = false,
    bool enabled = true,
    Widget? suffixIcon,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: _textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: _textMuted),
        prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? _bg : _fieldBdr.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _fieldBdr)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _fieldBdr)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
      ),
    );
  }
}