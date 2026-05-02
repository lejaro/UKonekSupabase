import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'services/api_service.dart';
import 'uKonekLoginPage.dart';

class uKonekForgotPasswordPage extends StatefulWidget {
  const uKonekForgotPasswordPage({super.key});
  @override
  State<uKonekForgotPasswordPage> createState() =>
      _uKonekForgotPasswordPageState();
}

class _uKonekForgotPasswordPageState extends State<uKonekForgotPasswordPage>
    with SingleTickerProviderStateMixin {

  final emailController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _emailSent = false;

  // ── Updated Medical Green Design Tokens ──────────────────────
  static const _primary      = Color(0xFF28A745); // Health Green
  static const _primary2     = Color(0xFF1B5E20); // Forest Green
  static const _bg           = Color(0xFFF8FCF9); // Mint Background
  static const _textDark     = Color(0xFF1B2E1E); // Dark Forest Charcoal
  static const _textMuted    = Color(0xFF637367); // Muted Sage
  static const _fieldBdr     = Color(0xFFE2E9E3); // Light Mist Border

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    emailController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ApiService.requestPasswordReset(
        email: emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailSent = true;
      });
      _animController
        ..reset()
        ..forward();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 3) return "${name[0]}***@$domain";
    return "${name.substring(0, 3)}***@$domain";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg, // Updated mint background
      body: Column(
        children: [
          // ── Header (Green Gradient) ─────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_primary, _primary2], // Updated Green Gradient
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _emailSent ? "Check Your Email" : "Forgot Password",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _emailSent
                          ? "We've sent a password reset link"
                          : "We'll send a reset link to your email",
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ]),
                ]),
              ),
            ),
          ),

          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _emailSent ? _buildSuccessStep() : _buildEmailStep(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      children: [
        const SizedBox(height: 16),

        // Medical Icon
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_reset_rounded, color: _primary, size: 38),
        ),
        const SizedBox(height: 20),

        const Text("Reset Your Password",
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _textDark)),
        const SizedBox(height: 8),
        Text(
          "Enter the email address you used during registration. We'll send you a password reset link.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _textMuted, height: 1.5),
        ),
        const SizedBox(height: 32),

        // Email card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(
                color: _textDark.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 6))],
          ),
          child: Form(
            key: _emailFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return "Email is required";
                    if (!v.contains('@') || !v.contains('.')) {
                      return "Enter a valid email";
                    }
                    return null;
                  },
                  style: const TextStyle(
                      fontSize: 14, color: _textDark),
                  decoration: InputDecoration(
                    labelText: "Email Address",
                    labelStyle: const TextStyle(
                        fontSize: 13, color: _textMuted),
                    prefixIcon: Icon(Icons.email_outlined,
                        color: _primary.withOpacity(0.6), size: 20),
                    filled: true,
                    fillColor: _bg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                        const BorderSide(color: _fieldBdr)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                        const BorderSide(color: _fieldBdr)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                        const BorderSide(color: _primary, width: 1.8)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                        const BorderSide(color: Colors.redAccent)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: _primary.withOpacity(0.4),
                    ),
                    onPressed: _isLoading ? null : _sendResetEmail,
                    child: _isLoading
                        ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("SEND RESET LINK",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 1)),
                        SizedBox(width: 8),
                        Icon(Icons.send_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      children: [
        const SizedBox(height: 40),

        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
              color: _primary.withOpacity(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.mark_email_read_outlined,
              color: _primary, size: 56),
        ),
        const SizedBox(height: 24),

        const Text("Check Your Email",
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _textDark)),
        const SizedBox(height: 10),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
                fontSize: 13, color: _textMuted, height: 1.6),
            children: [
              const TextSpan(text: "A password reset link was sent to\n"),
              TextSpan(
                text: _maskEmail(emailController.text),
                style: const TextStyle(
                    color: _primary, fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: "\n\nClick the link in the email to reset your password. If you don't see it, check your spam folder."),
            ],
          ),
        ),
        const SizedBox(height: 40),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              shadowColor: _primary.withOpacity(0.4),
            ),
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => const uKonekLoginPage()),
                  (route) => false,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("BACK TO SIGN IN",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1)),
                SizedBox(width: 8),
                Icon(Icons.login_rounded, size: 18),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: () {
              setState(() => _emailSent = false);
              _animController..reset()..forward();
            },
            child: const Text("← Try a different email",
                style: TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline)),
          ),
        ),
      ],
    );
  }
}