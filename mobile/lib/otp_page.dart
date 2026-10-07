import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'services/api_service.dart';
import 'credentials_page.dart';
import 'utils/app_transitions.dart';

class uKonekOtpPage extends StatefulWidget {
  final String firstName;
  final String middleName;
  final String surname;
  final String nameExtension;
  final String dob;
  final String age;
  final String contact;
  final String sex;
  final String email;
  final String address;
  final String emergencyName;
  final String emergencyContact;
  final String relation;

  const uKonekOtpPage({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.surname,
    this.nameExtension = '',
    required this.dob,
    required this.age,
    required this.contact,
    required this.sex,
    required this.email,
    required this.address,
    required this.emergencyName,
    required this.emergencyContact,
    required this.relation,
  });

  @override
  State<uKonekOtpPage> createState() => _uKonekOtpPageState();
}

class _uKonekOtpPageState extends State<uKonekOtpPage> {
  // ── Unified Design System Tokens ───────────────────────────────
  static const _primary   = Color(0xFF2D5A27); // Forest Green
  static const _bg        = Color(0xFFF8FAFC); // Slate Background
  static const _fieldBg   = Color(0xFFF8FAFC);
  static const _surface   = Colors.white;
  static const _textDark  = Color(0xFF0F172A); // Slate 900
  static const _textMuted = Color(0xFF64748B); // Slate 500
  static const _divider   = Color(0xFFCBD5E1); // Slate 300

  static const int _otpLength = 8;

  bool _isSending = false;
  bool _isChecking = false;
  bool _linkSent = false;

  // ── Resend Countdown Timer ─────────────────────────────────────
  Timer? _resendTimer;
  int _resendCountdown = 60;

  // ── OTP Controllers & Focus Nodes (8 digits) ───────────────────
  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendMagicLink();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
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

  Future<void> _sendMagicLink({bool isResend = false}) async {
    if (_isSending) return;
    final dateOfBirth = _toIsoDate(widget.dob);

    if (dateOfBirth == null) {
      _showSnack('Invalid birth date format.', isError: true);
      return;
    }

    setState(() => _isSending = true);
    try {
      final cleanSurname = widget.nameExtension.trim().isNotEmpty
          ? '${widget.surname.trim()} ${widget.nameExtension.trim()}'
          : widget.surname.trim();

      await ApiService.startCitizenEmailVerification(payload: {
        'firstname': widget.firstName.trim(),
        'surname': cleanSurname,
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
      _startResendTimer();
      _showSnack(isResend
          ? 'New verification code sent. Check your inbox.'
          : 'Verification email sent. Check your inbox.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(
          error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _handlePaste(String pasted) {
    final digitsOnly = pasted.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return;

    for (int i = 0; i < _otpLength; i++) {
      if (i < digitsOnly.length) {
        _otpControllers[i].text = digitsOnly[i];
      } else {
        _otpControllers[i].clear();
      }
    }

    final targetIndex = digitsOnly.length < _otpLength
        ? digitsOnly.length
        : _otpLength - 1;
    _focusNodes[targetIndex].requestFocus();
    setState(() {});
  }

  Future<void> _continueAfterVerification() async {
    if (_isChecking) return;

    // Consolidate OTP from the 6 boxes
    String otp = "";
    for (var controller in _otpControllers) {
      otp += controller.text.trim();
    }

    if (otp.length < _otpLength) {
      _showSnack('Please enter the full 8-digit OTP code.', isError: true);
      return;
    }

    setState(() => _isChecking = true);
    try {
      await ApiService.verifyCitizenEmailOtp(email: widget.email, otp: otp);

      if (!mounted) return;

      // Use pushReplacement so user cannot navigate back to already-consumed OTP screen
      Navigator.pushReplacement(
        context,
        AppPageRoute.slideRight(
          uKonekCredentialsPage(
            firstName: widget.firstName,
            middleName: widget.middleName,
            surname: widget.surname,
            nameExtension: widget.nameExtension,
            dob: widget.dob,
            age: widget.age,
            contact: widget.contact,
            sex: widget.sex,
            email: widget.email,
            address: widget.address,
            emergencyName: widget.emergencyName,
            emergencyContact: widget.emergencyContact,
            relation: widget.relation,
            extractedOcrText: '',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack(
          error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : _primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    return name.length <= 2
        ? "${name[0]}***@$domain"
        : "${name.substring(0, 2)}***@$domain";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  _buildEmailInfoCard(),
                  const SizedBox(height: 24),
                  _buildPhaseInfo(),
                  const SizedBox(height: 32),
                  _buildOtpBoxGrid(), // 6-box input section
                  const SizedBox(height: 24),
                  _buildResendSection(),
                  const SizedBox(height: 16),
                  _buildStatusMessages(),
                  _buildActionButton(),
                  const SizedBox(height: 24),
                  const Text(
                    "Check your spam or junk folder if the email doesn't appear.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text("Go back to review"),
                    style: TextButton.styleFrom(foregroundColor: _textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: _primary, size: 28),
              ),
              const SizedBox(height: 12),
              const Text(
                "EMAIL VERIFICATION",
                style: TextStyle(
                  color: _textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: _textDark.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _primary.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.email_outlined, color: _primary, size: 28),
          ),
          const SizedBox(height: 16),
          const Text("8-digit verification code sent to",
              style: TextStyle(fontSize: 13, color: _textMuted)),
          const SizedBox(height: 6),
          Text(_maskEmail(widget.email),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textDark)),
        ],
      ),
    );
  }

  Widget _buildPhaseInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE58F)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFD48806), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Phase 1: Enter the 8-digit code sent to your email\nPhase 2: Set your password and credentials",
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF874D00), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBoxGrid() {
    return Row(
      children: List.generate(_otpLength, (index) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: SizedBox(
              height: 52,
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace) {
                    if (_otpControllers[index].text.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                      _otpControllers[index - 1].clear();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextFormField(
                  controller: _otpControllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: _fieldBg,
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _primary, width: 2)),
                  ),
                  onChanged: (value) {
                    // Handle multi-character paste
                    if (value.length > 1) {
                      _handlePaste(value);
                      return;
                    }

                    if (value.isNotEmpty) {
                      // Only allow digits
                      if (!RegExp(r'^[0-9]$').hasMatch(value)) {
                        _otpControllers[index].clear();
                        return;
                      }
                      if (index < _otpLength - 1) {
                        _focusNodes[index + 1].requestFocus();
                      } else {
                        _focusNodes[index].unfocus();
                      }
                    } else if (value.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildResendSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Didn't receive the code? ",
          style: TextStyle(fontSize: 13, color: _textMuted),
        ),
        if (_resendCountdown > 0)
          Text(
            "Resend in ${_resendCountdown}s",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textMuted,
            ),
          )
        else
          GestureDetector(
            onTap: _isSending ? null : () => _sendMagicLink(isResend: true),
            child: const Text(
              "Resend Code",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusMessages() {
    if (_isSending) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _primary)),
            SizedBox(width: 12),
            Text('Sending code...',
                style: TextStyle(color: _textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if (_linkSent && _resendCountdown >= 50) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text('Code sent successfully to your email.',
            style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: (_isSending || _isChecking)
            ? null
            : _continueAfterVerification,
        child: _isChecking
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('VERIFY & CONTINUE',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }
}