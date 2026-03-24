import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'uKonekLoginPage.dart';

class uKonekChangePasswordPage extends StatefulWidget {
  final String email;
  final String otp;
  const uKonekChangePasswordPage({
    super.key,
    required this.email,
    required this.otp,
  });

  @override
  State<uKonekChangePasswordPage> createState() =>
      _uKonekChangePasswordPageState();
}

class _uKonekChangePasswordPageState
    extends State<uKonekChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _success = false;

  static const _primary = Color(0xFF0D47A1);
  static const _primaryLight = Color(0xFF1976D2);

  // Password strength
  String get _password => newPasswordController.text;
  int get _strengthLevel {
    if (_password.isEmpty) return 0;
    int score = 0;
    if (_password.length >= 8) score++;
    if (_password.contains(RegExp(r'[A-Z]'))) score++;
    if (_password.contains(RegExp(r'[0-9]'))) score++;
    if (_password.contains(RegExp(r'[!@#\$&*~]'))) score++;
    return score;
  }
  Color get _strengthColor =>
      [Colors.grey, Colors.red, Colors.orange, Colors.yellow.shade700, Colors.green]
      [_strengthLevel];
  String get _strengthLabel =>
      ["", "Weak", "Fair", "Good", "Strong"][_strengthLevel];

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ApiService.resetCitizenPassword(
        email: widget.email,
        otp: widget.otp,
        password: newPasswordController.text,
        confirmPassword: confirmPasswordController.text,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _success = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_primary, _primaryLight],
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
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.lock_reset_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("New Password",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text("Create a strong new password",
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ]),
                ]),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _success ? _buildSuccessState() : _buildForm(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form ──────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
              color: _primary.withOpacity(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.lock_outline_rounded,
              color: _primary, size: 38),
        ),
        const SizedBox(height: 20),
        const Text("Set a New Password",
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        Text(
          "Your new password must be different\nfrom your previous password.",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.5),
        ),
        const SizedBox(height: 32),

        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 6))],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // New password
                _inputField(
                  label: "New Password",
                  controller: newPasswordController,
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscureNew,
                  suffix: IconButton(
                    icon: Icon(
                        _obscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20, color: Colors.grey.shade400),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return "Password is required";
                    if (v.length < 8) return "At least 8 characters";
                    if (!RegExp(r'[A-Z]').hasMatch(v)) return "Add an uppercase letter";
                    if (!RegExp(r'[a-z]').hasMatch(v)) return "Add a lowercase letter";
                    if (!RegExp(r'\d').hasMatch(v)) return "Add a number";
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),

                // Strength bar
                if (_password.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _strengthLevel / 4,
                          backgroundColor: Colors.grey.shade200,
                          valueColor:
                          AlwaysStoppedAnimation(_strengthColor),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_strengthLabel,
                        style: TextStyle(
                            fontSize: 11,
                            color: _strengthColor,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 14),
                ],

                // Confirm password
                _inputField(
                  label: "Confirm New Password",
                  controller: confirmPasswordController,
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20, color: Colors.grey.shade400),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return "Please confirm your password";
                    }
                    if (v != newPasswordController.text) {
                      return "Passwords do not match";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // Password rules hint
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Password tips:",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _primary)),
                      const SizedBox(height: 6),
                      ...[
                        "At least 8 characters",
                        "Include uppercase letters (A-Z)",
                        "Include lowercase letters (a-z)",
                        "Include numbers (0-9)",
                        "Include symbols (!@#\$&*~)",
                      ].map((tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(Icons.circle,
                              size: 5, color: _primary),
                          const SizedBox(width: 6),
                          Text(tip,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600)),
                        ]),
                      )),
                    ],
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
                    onPressed: _isLoading ? null : _changePassword,
                    child: _isLoading
                        ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("CHANGE PASSWORD",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 1)),
                        SizedBox(width: 8),
                        Icon(Icons.check_circle_outline_rounded,
                            size: 18),
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

  // ── Success state ─────────────────────────────────────────────
  Widget _buildSuccessState() {
    return Column(
      children: [
        const SizedBox(height: 60),
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
              color: Colors.green.shade50, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded,
              color: Colors.green, size: 56),
        ),
        const SizedBox(height: 24),
        const Text("Password Changed!",
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        Text(
          "Your password has been successfully updated.\nYou can now sign in with your new password.",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6),
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
      ],
    );
  }

  // ── Input field builder ───────────────────────────────────────
  Widget _inputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    required String? Function(String?) validator,
    void Function(String)? onChanged,
  }) {
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
          labelStyle:
          TextStyle(fontSize: 13, color: Colors.grey.shade500),
          prefixIcon:
          Icon(icon, color: _primary.withOpacity(0.6), size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
              const BorderSide(color: _primary, width: 1.8)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent)),
        ),
      ),
    );
  }
}