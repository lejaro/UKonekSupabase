import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:ukonekmobile/uKonekRegistration/uKonekRegisterWrapper.dart';
import 'uKonekDentalTheme.dart';
import 'uKonekPatientMain.dart';
import 'uKonekDentistMain.dart';

// ── Demo credentials ───────────────────────────────────────────
const _demoPatient  = {'email': 'patient@demo.com',  'pass': 'patient123',  'role': 'patient'};
const _demoDentist  = {'email': 'dentist@demo.com',  'pass': 'dentist123',  'role': 'dentist'};

class uKonekDentalLoginPage extends StatefulWidget {
  const uKonekDentalLoginPage({super.key});
  @override
  State<uKonekDentalLoginPage> createState() => _uKonekDentalLoginPageState();
}

class _uKonekDentalLoginPageState extends State<uKonekDentalLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();

  String  _selectedRole   = 'patient';
  bool    _obscurePass    = true;
  bool    _isLoading      = false;
  String? _errorMsg;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.10), end: Offset.zero)
        .animate(CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMsg = null; });
    await Future.delayed(const Duration(milliseconds: 900));

    // Demo auth — replace with Supabase auth
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass  = _passCtrl.text;
    final demo  = _selectedRole == 'patient' ? _demoPatient : _demoDentist;

    if (email == demo['email'] && pass == demo['pass']) {
      setState(() => _isLoading = false);
      if (_selectedRole == 'patient') {
        Navigator.pushAndRemoveUntil(context,
            _fade(const uKonekPatientMain(
                patientName: 'Juan Dela Cruz',
                email: 'patient@demo.com')),
                (r) => false);
      } else {
        Navigator.pushAndRemoveUntil(context,
            _fade(const uKonekDentistMain(
                dentistName: 'Dr. Maria Santos')),
                (r) => false);
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMsg  = 'Invalid email or password.';
      });
    }
  }

  PageRoute _fade(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: DC.bg,
      body: Stack(children: [
        // Blue gradient top
        Container(
          height: size.height * 0.40,
          decoration: DC.gradientDecor(radius: 0, colors: [
            DC.primary, DC.primaryMid]),
        ),
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                child: Column(children: [
                  // ── Branding ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        24, 24, 24, 0),
                    child: Column(children: [
                      Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8))],
                        ),
                        child: const Icon(Icons.local_hospital_rounded,
                            color: DC.primary, size: 36),
                      ),
                      const SizedBox(height: 14),
                      const Text('DentCare+',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      const Text('Your Dental Clinic, In Your Pocket',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 36),
                    ]),
                  ),

                  // ── Card ─────────────────────────────────────
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: DC.cardDecor(radius: 28),
                    padding: const EdgeInsets.all(26),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sign In',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: DC.textDark)),
                          const SizedBox(height: 4),
                          Text('Welcome back! Choose your role.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                          const SizedBox(height: 22),

                          // Role selector
                          _roleSelector(),
                          const SizedBox(height: 18),

                          // Email
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: DC.inputDecor(
                                'Email Address',
                                Icons.email_outlined),
                            validator: (v) =>
                            (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 14),

                          // Password
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            decoration: DC.inputDecor(
                                'Password',
                                Icons.lock_outline_rounded).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                    _obscurePass
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: Colors.grey.shade400),
                                onPressed: () => setState(
                                        () => _obscurePass = !_obscurePass),
                              ),
                            ),
                            validator: (v) =>
                            (v == null || v.isEmpty)
                                ? 'Password is required'
                                : null,
                          ),

                          // Error
                          if (_errorMsg != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                  color: DC.error.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: DC.error.withOpacity(0.3))),
                              child: Row(children: [
                                const Icon(Icons.error_outline,
                                    color: DC.error, size: 16),
                                const SizedBox(width: 8),
                                Text(_errorMsg!,
                                    style: const TextStyle(
                                        color: DC.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ],

                          const SizedBox(height: 6),
                          // Forgot password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {},
                              child: const Text('Forgot password?',
                                  style: TextStyle(
                                      color: DC.primaryMid,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Demo hint
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                border: Border.all(
                                    color: Colors.amber.shade300),
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text('Demo Credentials',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade800)),
                                const SizedBox(height: 4),
                                Text(
                                    'Patient: patient@demo.com / patient123\n'
                                        'Dentist: dentist@demo.com / dentist123',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.amber.shade700,
                                        height: 1.5)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Sign in button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: DC.primary,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor:
                                DC.primary.withOpacity(0.3),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(16)),
                              ),
                              onPressed: _isLoading ? null : _login,
                              child: _isLoading
                                  ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5))
                                  : const Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  children: [
                                    Text('SIGN IN',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            letterSpacing: 1)),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded,
                                        size: 18),
                                  ]),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Register link
                          Center(child: RichText(
                            text: TextSpan(
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: DC.textMuted),
                                children: [
                                  const TextSpan(
                                      text: "Don't have an account? "),
                                  TextSpan(
                                    text: 'Register here',
                                    style: const TextStyle(
                                        color: DC.primary,
                                        fontWeight: FontWeight.bold,
                                        decoration:
                                        TextDecoration.underline),
                                    recognizer:
                                    TapGestureRecognizer()
                                      ..onTap = () =>
                                          Navigator.push(context,
                                              MaterialPageRoute(
                                                  builder: (_) => const
                                                  uKonekRegisterWrapper())),
                                  ),
                                ]),
                          )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _roleSelector() {
    return Row(children: [
      _roleBtn('patient', Icons.person_outline_rounded, 'Patient'),
      const SizedBox(width: 12),
      _roleBtn('dentist', Icons.medical_services_outlined, 'Dentist'),
    ]);
  }

  Widget _roleBtn(String role, IconData icon, String label) {
    final sel = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: sel
                ? const LinearGradient(
                colors: [DC.primary, DC.primaryMid])
                : null,
            color: sel ? null : DC.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: sel ? DC.primary : DC.fieldBdr),
            boxShadow: sel
                ? [BoxShadow(
                color: DC.primary.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 4))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: sel ? Colors.white : DC.textMuted,
                  size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: sel ? Colors.white : DC.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}