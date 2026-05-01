import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'uKonekCredentialsPage.dart';

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
    required this.idVerified,
  });

  @override
  State<uKonekOtpPage> createState() => _uKonekOtpPageState();
}

class _uKonekOtpPageState extends State<uKonekOtpPage> {
  bool _isSending = false;
  bool _isChecking = false;
  bool _linkSent = false;
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendMagicLink();
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
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

  Future<void> _sendMagicLink() async {
    if (_isSending) return;
    final dateOfBirth = _toIsoDate(widget.dob);

    if (dateOfBirth == null) {
      _showSnack(
        'Invalid birth date format. Please go back and select your date again.',
        isError: true,
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await ApiService.startCitizenEmailVerification(payload: {
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
      });

      if (!mounted) return;
      setState(() => _linkSent = true);
      _showSnack('Verification email sent. Enter the OTP code from your email.');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _continueAfterVerification() async {
    if (_isChecking) return;
    final otp = _otpController.text.trim();
    if (otp.length < 8) {
      _showSnack('Please enter the 8-digit OTP code from your email.', isError: true);
      return;
    }
    setState(() => _isChecking = true);
    try {
      await ApiService.verifyCitizenEmailOtp(email: widget.email, otp: otp);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => uKonekCredentialsPage(
            firstName: widget.firstName,
            middleName: widget.middleName,
            surname: widget.surname,
            nameExtension: '',
            dob: widget.dob,
            age: widget.age,
            contact: widget.contact,
            sex: widget.sex,
            email: widget.email,
            address: widget.address,
            emergencyName: widget.emergencyName,
            emergencyContact: widget.emergencyContact,
            relation: widget.relation,
            idImage: null,
            idVerified: widget.idVerified,
            extractedOcrText: '',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
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
                            "Your OTP code will be sent to",
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
                            "A verification email will be sent using Supabase built-in email.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    const SizedBox(height: 28),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Phase 1: verify email using OTP code.\nPhase 2: create username and password after verification.",
                        style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 28),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      decoration: const InputDecoration(
                        labelText: 'OTP Code',
                        hintText: 'Enter 8-digit code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isSending)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Sending OTP code...'),
                          ],
                        ),
                      ),
                    if (!_isSending && _linkSent)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'OTP code sent to your email.',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: (_isSending || _isChecking)
                            ? null
                            : _continueAfterVerification,
                        child: const Text(
                          'VERIFY OTP & CONTINUE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      "Use the latest OTP code from your email, then tap Continue.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black45, fontSize: 13),
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