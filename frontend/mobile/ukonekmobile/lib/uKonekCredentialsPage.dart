import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'uKonekLoginPage.dart';

class uKonekCredentialsPage extends StatefulWidget {
  final String firstName, middleName, surname, nameExtension, dob, age, contact, sex, email, address, extractedOcrText;
  final String emergencyName, emergencyContact, relation;
  final File? idImage;
  final bool idVerified;

  const uKonekCredentialsPage({
    super.key,
    required this.firstName, required this.middleName, required this.surname, required this.nameExtension,
    required this.dob, required this.age, required this.contact, required this.sex,
    required this.email, required this.address, required this.emergencyName,
    required this.emergencyContact, required this.relation,
    required this.idImage, required this.idVerified, required this.extractedOcrText
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
  static const _formBg = Color(0xFFF8FAFF);
  static const _textDark = Color(0xFF1A1A2E);
  static const _fieldBorder = Color(0xFFDDE3F0);

  // --- PASSWORD STRENGTH LOGIC ---
  int get _strengthLevel {
    String p = passwordController.text;
    if (p.isEmpty) return 0;
    int score = 0;
    if (p.length >= 8) score++;
    if (p.contains(RegExp(r'[A-Z]'))) score++;
    if (p.contains(RegExp(r'[0-9]'))) score++;
    if (p.contains(RegExp(r'[!@#\$&*~]'))) score++;
    return score;
  }

  // --- TERMS DIALOG ---
  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.gavel_rounded, color: _primary, size: 22),
                const SizedBox(width: 12),
                const Text("Terms & Privacy", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
              ]),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: const SingleChildScrollView(
                  child: Text(
                    "1. DATA COLLECTION: We collect your personal data and ID for verification purposes.\n\n"
                        "2. PRIVACY ACT: Your data is protected under the Data Privacy Act of 2012 (RA 10173).\n\n"
                        "3. SECURITY: You are responsible for your account security. Do not share your password.\n\n"
                        "4. CONSENT: By signing up, you consent to the processing of your data for citizen services.",
                    style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("I UNDERSTAND", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- REGISTRATION SUBMISSION ---
  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Auth Sign Up (Creates the user in auth.users)
      final AuthResponse res = await supabase.auth.signUp(
        email: widget.email.trim().toLowerCase(),
        password: passwordController.text,
      );

      if (res.user != null) {
        // 2. Insert into citizens using the EXACT schema names
        await supabase.from('citizens').insert({
          'auth_user_id': res.user!.id, // Changed from 'id' to 'auth_user_id'
          'firstname': widget.firstName.trim(),
          'surname': widget.surname.trim(),
          'middle_initial': widget.middleName.trim(),
          'date_of_birth': widget.dob,
          'age': int.tryParse(widget.age) ?? 0,
          'contact_number': widget.contact,
          'sex': widget.sex,
          'email': widget.email.trim().toLowerCase(),
          'complete_address': widget.address,
          'username': usernameController.text.trim(),
          // Matching your schema file's emergency names:
          'emergency_contact_complete_name': widget.emergencyName,
          'emergency_contact_contact_number': widget.emergencyContact,
          'relation': widget.relation,
          // 'id_verified' REMOVED because it's missing in your schema file
        });
      }
      _showSuccessDialog();
    } catch (e) {
      _showSnackBar("Database Error: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _formBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E6E),
        elevation: 0,
        centerTitle: true,
        title: const Text("Set Credentials", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Security Details", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _textDark)),
              const SizedBox(height: 4),
              Text("Create your login information.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(height: 32),

              // --- CREDENTIALS CARD ---
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Column(
                  children: [
                    _buildInputField("Username", usernameController, Icons.alternate_email_rounded),
                    _buildPasswordField("Password", passwordController, _obscurePassword, () => setState(() => _obscurePassword = !_obscurePassword)),
                    if (passwordController.text.isNotEmpty) _buildStrengthBar(),
                    _buildPasswordField("Confirm Password", confirmPasswordController, _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _buildTermsCheckbox(),
              const SizedBox(height: 32),

              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI WIDGETS ---

  Widget _buildInputField(String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: _inputDecoration(label, icon),
        validator: (v) => (v == null || v.isEmpty) ? "Field required" : null,
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool obscure, VoidCallback toggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 14),
        decoration: _inputDecoration(label, Icons.lock_outline_rounded).copyWith(
          suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey.shade400), onPressed: toggle),
        ),
        validator: (v) => (v == null || v.length < 8) ? "Min. 8 characters" : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
      prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _fieldBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _fieldBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
    );
  }

  Widget _buildStrengthBar() {
    List<Color> colors = [Colors.grey, Colors.red, Colors.orange, Colors.yellow.shade700, Colors.green];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LinearProgressIndicator(value: _strengthLevel / 4, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation(colors[_strengthLevel]), minHeight: 4),
    );
  }

  Widget _buildTermsCheckbox() {
    return Row(
      children: [
        Checkbox(value: _agreedToTerms, activeColor: _primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), onChanged: (v) => setState(() => _agreedToTerms = v ?? false)),
        Expanded(
          child: RichText(
            text: TextSpan(style: const TextStyle(fontSize: 13, color: Colors.black54), children: [
              const TextSpan(text: "I agree to the "),
              TextSpan(text: "Terms & Privacy Policy", style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = _showTermsDialog),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final bool isEnabled = _agreedToTerms && !_isSubmitting;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? _primary : Colors.grey.shade300,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: isEnabled ? 4 : 0,
        ),
        onPressed: isEnabled ? _submitRegistration : null,
        child: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text("CREATE ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: isEnabled ? Colors.white : Colors.grey.shade500)),
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Verify Email"),
        content: const Text("Please check your email for the verification link."),
        actions: [TextButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const uKonekLoginPage()), (route) => false), child: const Text("OK"))],
      ),
    );
  }
}
