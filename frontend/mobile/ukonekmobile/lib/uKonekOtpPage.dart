import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'uKonekLoginPage.dart';

class uKonekOtpPage extends StatefulWidget {
  final String firstName;
  final String middleName;
  final String surname;
  final String dob;
  final String age;
  final String contact;
  final String sex;
  final String email;
  final String address;
  final String emergencyName;
  final String emergencyContact;
  final String relation;
  final String username;
  final String password;
  final bool idVerified;

  const uKonekOtpPage({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.surname,
    required this.dob,
    required this.age,
    required this.contact,
    required this.sex,
    required this.email,
    required this.address,
    required this.emergencyName,
    required this.emergencyContact,
    required this.relation,
    required this.username,
    required this.password,
    required this.idVerified,
  });

  @override
  State<uKonekOtpPage> createState() => _uKonekOtpPageState();
}

class _uKonekOtpPageState extends State<uKonekOtpPage> {
  final List<TextEditingController> _controllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
  List.generate(6, (_) => FocusNode());

  bool _isRequestingOtp = false;
  bool _isVerifying = false;
  bool _isSubmitting = false;

  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _requestOtp(initialRequest: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _enteredOtp =>
      _controllers.map((c) => c.text).join();

  Future<void> _verifyOtp() async {
    final entered = _enteredOtp;
    if (entered.length < 6) {
      _showSnack("⚠️ Please enter all 6 digits.", isError: true);
      return;
    }

    setState(() => _isVerifying = true);
    try {
      await _submitRegistration(entered);
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

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

  Future<void> _submitRegistration(String otp) async {
    if (_isSubmitting) return;
    final dateOfBirth = _toIsoDate(widget.dob);

    if (dateOfBirth == null) {
      _showSnack('Invalid birth date format. Please go back and select your date again.', isError: true);
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
        'username': widget.username.trim(),
        'password': widget.password,
        'confirmPassword': widget.password,
        'otp': otp,
      });

      if (!mounted) return;
      _showSnack('✅ Account registered successfully. You can now sign in.');
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const uKonekLoginPage()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(message, isError: true);
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _requestOtp({bool initialRequest = false}) async {
    if (_isRequestingOtp) return;
    setState(() => _isRequestingOtp = true);

    try {
      await ApiService.requestCitizenOtp(
        email: widget.email,
        purpose: 'registration',
      );
      if (!mounted) return;
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      _startCountdown();
      if (!initialRequest) {
        _showSnack('🔁 A new OTP has been sent to your email.');
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isRequestingOtp = false);
      }
    }
  }

  void _resendOtp() {
    _requestOtp();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
      isError ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return "${name[0]}***@$domain";
    return "${name.substring(0, 2)}***@$domain";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            height: 140,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40)),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      color: Colors.white, size: 36),
                  SizedBox(height: 8),
                  Text(
                    "EMAIL VERIFICATION",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Sent message card ────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.email_outlined,
                              color: Color(0xFF1976D2), size: 32),
                          const SizedBox(height: 10),
                          const Text(
                            "An OTP verification code was sent to",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: Colors.black54),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _maskEmail(widget.email),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D47A1),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "Please check your inbox (and spam folder).",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    const SizedBox(height: 28),

                    // ── OTP Input label ──────────────────────
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Enter 6-digit OTP",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 6 digit boxes ─────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (i) {
                        return SizedBox(
                          width: 46,
                          height: 56,
                          child: TextField(
                            controller: _controllers[i],
                            focusNode: _focusNodes[i],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: InputDecoration(
                              counterText: "",
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                const BorderSide(color: Colors.grey),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFF1976D2), width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty && i < 5) {
                                _focusNodes[i + 1].requestFocus();
                              } else if (value.isEmpty && i > 0) {
                                _focusNodes[i - 1].requestFocus();
                              }
                              if (_enteredOtp.length == 6) {
                                _verifyOtp();
                              }
                            },
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 28),

                    // ── Verify Button ─────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: (_isRequestingOtp || _isVerifying || _isSubmitting) ? null : _verifyOtp,
                        child: (_isRequestingOtp || _isVerifying || _isSubmitting)
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                            : const Text(
                          "VERIFY OTP",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Resend countdown ──────────────────────
                    if (_secondsLeft > 0)
                      Text(
                        "Resend OTP in $_secondsLeft seconds",
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 13),
                      )
                    else
                      GestureDetector(
                        onTap: _isRequestingOtp ? null : _resendOtp,
                        child: const Text(
                          "Didn't receive the code? Resend OTP",
                          style: TextStyle(
                            color: Color(0xFF1976D2),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "← Go back",
                        style: TextStyle(color: Colors.black45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}