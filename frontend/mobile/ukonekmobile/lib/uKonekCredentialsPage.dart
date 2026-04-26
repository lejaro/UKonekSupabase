import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'uKonekDentalLoginPage.dart';

class uKonekCredentialsPage extends StatefulWidget {
  final String firstName, middleName, surname, nameExtension;
  final String dob, age, contact, sex, email, address;
  final String emergencyName, emergencyContact, relation;
  final String extractedOcrText;
  final File?  idImage;
  final bool   idVerified;

  const uKonekCredentialsPage({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.surname,
    required this.nameExtension,
    required this.dob,
    required this.age,
    required this.contact,
    required this.sex,
    required this.email,
    required this.address,
    required this.emergencyName,
    required this.emergencyContact,
    required this.relation,
    required this.idImage,
    required this.idVerified,
    required this.extractedOcrText,
  });

  @override
  State<uKonekCredentialsPage> createState() =>
      _uKonekCredentialsPageState();
}

class _uKonekCredentialsPageState
    extends State<uKonekCredentialsPage> {

  final _formKey                 = GlobalKey<FormState>();
  final usernameController       = TextEditingController();
  final passwordController       = TextEditingController();
  final confirmPasswordController= TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _agreedToTerms   = false;
  bool _isSubmitting    = false;

  static const _primary   = Color(0xFF0077B6);
  static const _primary2  = Color(0xFF0096C7);
  static const _bg        = Color(0xFFF0F7FA);
  static const _surface   = Colors.white;
  static const _textDark  = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);
  static const _fieldBg   = Color(0xFFF0F9FF);
  static const _fieldBdr  = Color(0xFFDDE3F0);
  static const _success   = Color(0xFF10B981);

  // ── Password strength ────────────────────────────────────────
  int get _strengthLevel {
    final p = passwordController.text;
    if (p.isEmpty) return 0;
    int score = 0;
    if (p.length >= 8)                              score++;
    if (p.contains(RegExp(r'[A-Z]')))              score++;
    if (p.contains(RegExp(r'[0-9]')))              score++;
    if (p.contains(RegExp(r'[!@#\$&*~]')))        score++;
    return score;
  }

  Color get _strengthColor =>
      [Colors.grey, Colors.red, Colors.orange,
        Colors.yellow.shade700, _success][_strengthLevel];

  String get _strengthLabel =>
      ['', 'Weak', 'Fair', 'Good', 'Strong'][_strengthLevel];

  // ── Terms dialog (unchanged) ─────────────────────────────────
  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.gavel_rounded,
                      color: _primary, size: 18),
                ),
                const SizedBox(width: 12),
                const Text('Terms & Privacy',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    )),
              ]),
              const SizedBox(height: 16),
              Divider(color: Colors.grey.shade100),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight:
                    MediaQuery.of(ctx).size.height * 0.4),
                child: const SingleChildScrollView(
                  child: Text(
                      '1. DATA COLLECTION: We collect your personal data and ID for verification purposes.\n\n'
                          '2. PRIVACY ACT: Your data is protected under the Data Privacy Act of 2012 (RA 10173).\n\n'
                          '3. SECURITY: You are responsible for your account security. Do not share your password.\n\n'
                          '4. CONSENT: By signing up, you consent to the processing of your data for citizen services.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.6,
                      )),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('I UNDERSTAND',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Submit (unchanged logic) ──────────────────────────────────
  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;
      final AuthResponse res = await supabase.auth.signUp(
        email:    widget.email.trim().toLowerCase(),
        password: passwordController.text,
      );

      if (res.user != null) {
        await supabase.from('citizens').insert({
          'auth_user_id':                     res.user!.id,
          'firstname':                        widget.firstName.trim(),
          'surname':                          widget.surname.trim(),
          'middle_initial':                   widget.middleName.trim(),
          'date_of_birth':                    widget.dob,
          'age':                              int.tryParse(widget.age) ?? 0,
          'contact_number':                   widget.contact,
          'sex':                              widget.sex,
          'email':                            widget.email.trim().toLowerCase(),
          'complete_address':                 widget.address,
          'username':                         usernameController.text.trim(),
          'emergency_contact_complete_name':  widget.emergencyName,
          'emergency_contact_contact_number': widget.emergencyContact,
          'relation':                         widget.relation,
        });
      }
<<<<<<< HEAD
=======

      await ApiService.completeCitizenRegistration(payload: {
        'firstname': widget.firstName.trim(),
        'surname': widget.surname.trim(),
        'middle_initial': widget.middleName.trim(),
        'date_of_birth': dateOfBirth,
        'age': int.tryParse(widget.age.trim()) ?? 0,
        'contact_number': widget.contact.trim(),
        'sex': widget.sex.trim(),
        'email': widget.email.trim().toLowerCase(),
        'complete_address': widget.address.trim(),
        'emergency_contact_complete_name': widget.emergencyName.trim(),
        'emergency_contact_contact_number': widget.emergencyContact.trim(),
        'relation': widget.relation.trim(),
        'username': usernameController.text.trim(),
        'password': passwordController.text,
      });

>>>>>>> parent of ac9d4b4 (Family number implemented)
      _showSuccessDialog();
    } catch (e) {
      _snackBar('Error: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Security Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                        letterSpacing: -0.5,
                      )),
                  const SizedBox(height: 4),
                  Text('Create your login credentials.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 24),

                  // ── Credentials card ──────────────────────
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )],
                    ),
                    child: Column(children: [
                      _inputField('Username',
                          usernameController,
                          Icons.alternate_email_rounded),
                      _passwordField(
                        'Password',
                        passwordController,
                        _obscurePassword,
                            () => setState(() =>
                        _obscurePassword = !_obscurePassword),
                      ),
                      // Strength bar
                      if (passwordController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 16),
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius:
                                  BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _strengthLevel / 4,
                                    minHeight: 6,
                                    backgroundColor:
                                    Colors.grey.shade100,
                                    valueColor:
                                    AlwaysStoppedAnimation(
                                        _strengthColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(_strengthLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _strengthColor,
                                    fontWeight: FontWeight.bold,
                                  )),
                            ]),
                          ]),
                        ),
                      _passwordField(
                        'Confirm Password',
                        confirmPasswordController,
                        _obscureConfirm,
                            () => setState(() =>
                        _obscureConfirm = !_obscureConfirm),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Terms checkbox ────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _agreedToTerms
                          ? _primary.withOpacity(0.04)
                          : _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _agreedToTerms
                              ? _primary.withOpacity(0.2)
                              : _fieldBdr),
                    ),
                    child: Row(children: [
                      Checkbox(
                        value: _agreedToTerms,
                        activeColor: _primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5)),
                        onChanged: (v) =>
                            setState(() =>
                            _agreedToTerms = v ?? false),
                      ),
                      Expanded(child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textMuted,
                          ),
                          children: [
                            const TextSpan(
                                text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms & Privacy Policy',
                              style: const TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.bold,
                                decoration:
                                TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = _showTermsDialog,
                            ),
                          ],
                        ),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 28),

                  // ── Submit button ─────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _agreedToTerms
                            ? _primary
                            : Colors.grey.shade200,
                        foregroundColor: Colors.white,
                        elevation: _agreedToTerms ? 4 : 0,
                        shadowColor:
                        _primary.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(16)),
                      ),
                      onPressed: (_agreedToTerms && !_isSubmitting)
                          ? _submitRegistration
                          : null,
                      child: _isSubmitting
                          ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5))
                          : Row(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        children: [
                          Text(
                              'CREATE ACCOUNT',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                fontSize: 15,
                                color: _agreedToTerms
                                    ? Colors.white
                                    : Colors.grey.shade400,
                              )),
                          if (_agreedToTerms) ...[
                            const SizedBox(width: 8),
                            const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Header ───────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primary2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create Account',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
                SizedBox(height: 2),
                Text('Set up your login credentials.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  // ── Field builders ───────────────────────────────────────────
  Widget _inputField(String label, TextEditingController ctrl,
      IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14, color: _textDark),
        decoration: _decoration(label, icon),
        validator: (v) => (v == null || v.isEmpty)
            ? 'Field required'
            : null,
      ),
    );
  }

  Widget _passwordField(String label,
      TextEditingController ctrl, bool obscure,
      VoidCallback toggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller:  ctrl,
        obscureText: obscure,
        onChanged:   (_) => setState(() {}),
        style: const TextStyle(
            fontSize: 14, color: _textDark),
        decoration: _decoration(label,
            Icons.lock_outline_rounded).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: Colors.grey.shade400,
            ),
            onPressed: toggle,
          ),
        ),
        validator: (v) => (v == null || v.length < 8)
            ? 'Min. 8 characters'
            : null,
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText:  label,
      labelStyle: TextStyle(
          fontSize: 13, color: Colors.grey.shade500),
      prefixIcon: Icon(icon,
          color: _primary.withOpacity(0.6), size: 20),
      filled:     true,
      fillColor:  _fieldBg,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldBdr)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldBdr)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
              color: _primary2, width: 1.8)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent)),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────
  void _snackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: _success.withOpacity(0.10),
                shape: BoxShape.circle),
            child: const Icon(Icons.mark_email_read_outlined,
                color: _success, size: 32),
          ),
          const SizedBox(height: 16),
          const Text('Check Your Email',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textDark,
              )),
          const SizedBox(height: 10),
          const Text(
              'Please check your email for the verification link to activate your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _textMuted,
                height: 1.5,
              )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => const uKonekDentalLoginPage()),
                    (route) => false,
              ),
              child: const Text('GO TO SIGN IN',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  )),
            ),
          ),
        ]),
      ),
    );
  }
}