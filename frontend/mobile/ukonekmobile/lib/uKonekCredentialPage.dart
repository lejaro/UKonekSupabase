import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'services/api_service.dart';
import 'uKonekLoginPage.dart';

class uKonekCredentialsPage extends StatefulWidget {
  final String firstName, middleName, surname, dob, age, contact, sex, email, address;
  final String emergencyName, emergencyContact, relation;
  final File? idImage;
  final bool idVerified;
  final String extractedOcrText;

  const uKonekCredentialsPage({
    super.key,
    required this.firstName, required this.middleName, required this.surname,
    required this.dob, required this.age, required this.contact, required this.sex,
    required this.email, required this.address, required this.emergencyName,
    required this.emergencyContact, required this.relation,
    required this.idImage, required this.idVerified, this.extractedOcrText = "",
  });

  @override
  State<uKonekCredentialsPage> createState() => _uKonekCredentialsPageState();
}

class _uKonekCredentialsPageState extends State<uKonekCredentialsPage> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _isSubmitting = false;

  static const _primary = Color(0xFF0D47A1);
  static const _primaryLight = Color(0xFF1976D2);

  // Password strength
  String get _password => passwordController.text;
  int get _strengthLevel {
    if (_password.isEmpty) return 0;
    int score = 0;
    if (_password.length >= 8) score++;
    if (_password.contains(RegExp(r'[A-Z]'))) score++;
    if (_password.contains(RegExp(r'[0-9]'))) score++;
    if (_password.contains(RegExp(r'[!@#\$&*~]'))) score++;
    return score;
  }
  Color get _strengthColor => [Colors.grey, Colors.red, Colors.orange, Colors.yellow.shade700, Colors.green][_strengthLevel];
  String get _strengthLabel => ["", "Weak", "Fair", "Good", "Strong"][_strengthLevel];

  String? _toIsoDate(String date) {
    final parts = date.split('/');
    if (parts.length != 3) return null;
    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (month == null || day == null || year == null) return null;
    final parsed = DateTime(year, month, day);
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submitRegistration() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please agree to the Terms & Privacy Policy.")),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    final dateOfBirth = _toIsoDate(widget.dob);
    if (dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid birth date format.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.registerCitizen(payload: {
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Account created. Check your email for the magic link to verify your account before signing in.'),
          backgroundColor: Colors.green,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const uKonekLoginPage()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showTermsDialog() {
    showDialog(context: context, builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.gavel_rounded, color: _primary, size: 18)),
            const SizedBox(width: 10),
            const Text("Terms & Privacy Policy", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          const SizedBox(height: 300, child: SingleChildScrollView(
            child: Text(
              "1. ACCEPTANCE OF TERMS\nBy creating an account with U-Konek, you agree to be bound by these Terms and Conditions and our Privacy Policy.\n\n"
                  "2. DATA COLLECTION & USE\nWe collect personal information including your name, date of birth, contact details, address, and a government-issued ID for identity verification purposes.\n\n"
                  "3. IDENTITY VERIFICATION\nYou consent to our use of OCR technology to read and verify the text on your uploaded ID. The extracted data is used only for verification.\n\n"
                  "4. ACCOUNT SECURITY\nYou are responsible for maintaining the confidentiality of your username and password.\n\n"
                  "5. DATA PRIVACY\nYour personal data is protected in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).\n\n"
                  "6. PROHIBITED USE\nYou agree not to use U-Konek services for any unlawful purpose.\n\n"
                  "7. CHANGES TO TERMS\nU-Konek reserves the right to update these Terms and Privacy Policy at any time.\n\n"
                  "8. CONTACT US\nFor questions, please contact us at support@ukonek.ph.",
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.7),
            ),
          )),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () { Navigator.pop(ctx); setState(() => _agreedToTerms = true); },
            child: const Text("I Understand & Agree"),
          )),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_primary, _primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
                  ),
                  const SizedBox(width: 14),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Set Credentials", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text("Create your login details", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ]),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // ── Credentials card ──────────────────────────────
                    _card(children: [
                      _cardHeader(Icons.key_rounded, "Account Credentials"),
                      _inputField("Username", usernameController, Icons.person_outline_rounded, validator: (v) {
                        if (v == null || v.isEmpty) return "Username is required";
                        if (!RegExp(r'^[a-zA-Z0-9_.-]{4,30}$').hasMatch(v.trim())) {
                          return "Use 4-30 chars: letters, numbers, . _ -";
                        }
                        return null;
                      }),
                      _inputField("Password", passwordController, Icons.lock_outline_rounded, obscure: _obscurePassword,
                        suffix: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey.shade400),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Password is required";
                          if (v.length < 8) return "At least 8 characters";
                          if (!RegExp(r'[A-Z]').hasMatch(v)) return "Add at least one uppercase letter";
                          if (!RegExp(r'[a-z]').hasMatch(v)) return "Add at least one lowercase letter";
                          if (!RegExp(r'\d').hasMatch(v)) return "Add at least one number";
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                      // Password strength bar
                      if (_password.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _strengthLevel / 4,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation(_strengthColor),
                              minHeight: 5,
                            ),
                          )),
                          const SizedBox(width: 10),
                          Text(_strengthLabel, style: TextStyle(fontSize: 11, color: _strengthColor, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 14),
                      ],
                      _inputField("Confirm Password", confirmPasswordController, Icons.lock_outline_rounded, obscure: _obscureConfirm,
                          suffix: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey.shade400),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm)),
                          validator: (v) {
                            if (v == null || v.isEmpty) return "Please confirm your password";
                            if (v != passwordController.text) return "Passwords do not match";
                            return null;
                          }),
                    ]),

                    const SizedBox(height: 16),

                    // ── Terms checkbox card ───────────────────────────
                    _card(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _agreedToTerms ? const Color(0xFFEEF7FF) : const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _agreedToTerms ? _primary.withOpacity(0.3) : const Color(0xFFDDE3F0)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 24, height: 24,
                            child: Checkbox(
                              value: _agreedToTerms,
                              activeColor: _primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                              onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: RichText(text: TextSpan(
                            style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                            children: [
                              const TextSpan(text: "I have read and agree to the "),
                              TextSpan(
                                text: "Terms & Privacy Policy",
                                style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                recognizer: TapGestureRecognizer()..onTap = _showTermsDialog,
                              ),
                              const TextSpan(text: " of U-Konek."),
                            ],
                          ))),
                        ]),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── SIGN UP button ────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_agreedToTerms && !_isSubmitting) ? _primary : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: _agreedToTerms ? 4 : 0,
                          shadowColor: _primary.withOpacity(0.4),
                        ),
                        onPressed: _isSubmitting ? null : _submitRegistration,
                        child: _isSubmitting
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Text("CREATE ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 20, color: _agreedToTerms ? Colors.white : Colors.grey.shade500),
                              ]),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Sign in link ──────────────────────────────────
                    Center(child: RichText(text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                      children: [
                        const TextSpan(text: "Already have an account? "),
                        TextSpan(
                          text: "Sign in here",
                          style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                          recognizer: TapGestureRecognizer()..onTap = () =>
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const uKonekLoginPage()),
                                (route) => false,
                              ),
                        ),
                      ],
                    ))),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _cardHeader(IconData icon, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [
      Container(width: 34, height: 34,
          decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: _primary, size: 18)),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A2E))),
    ]),
  );

  Widget _inputField(String label, TextEditingController controller, IconData icon,
      {bool obscure = false, Widget? suffix, required String? Function(String?) validator, void Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
          suffixIcon: suffix,
          filled: true, fillColor: const Color(0xFFF8FAFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent)),
        ),
      ),
    );
  }
}