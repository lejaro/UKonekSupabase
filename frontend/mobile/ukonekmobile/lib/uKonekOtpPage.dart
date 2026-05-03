import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  });

  @override
  State<uKonekOtpPage> createState() => _uKonekOtpPageState();
}

class _uKonekOtpPageState extends State<uKonekOtpPage> {
// ── Design Tokens ──────────────────────────────────────────────
  static const _primary   = Color(0xFF28A745); // Health Green
  static const _primary2  = Color(0xFF1B5E20); // Forest Green
  static const _bg        = Color(0xFFF8FCF9); // Mint Background
  static const _fieldBg   = Color(0xFFF8FCF9); // Add this line
  static const _surface   = Colors.white;
  static const _textDark  = Color(0xFF1B2E1E); // Dark Forest Charcoal
  static const _textMuted = Color(0xFF637367); // Muted Sage
  static const _divider   = Color(0xFFE2E9E3); // Light Mist

  bool _isSending = false;
  bool _isChecking = false;
  bool _linkSent = false;

  // ── OTP Controllers & Focus Nodes ──────────────────────────────
  final List<TextEditingController> _otpControllers = List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(8, (_) => FocusNode());
  final TextEditingController _hiddenOtpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendMagicLink();
    });
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _hiddenOtpController.dispose();
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
      _showSnack('Invalid birth date format.', isError: true);
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
      _showSnack('Verification email sent. Check your inbox.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _continueAfterVerification() async {
    if (_isChecking) return;

    // Consolidate OTP from the 8 boxes
    String otp = "";
    for (var controller in _otpControllers) {
      otp += controller.text;
    }

    if (otp.length < 8) {
      _showSnack('Please enter the full 8-digit OTP code.', isError: true);
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
            extractedOcrText: '',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString().replaceFirst('Exception: ', ''), isError: true);
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
    return name.length <= 2 ? "${name[0]}***@$domain" : "${name.substring(0, 2)}***@$domain";
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
                  _buildOtpBoxGrid(), // The 8-box input section
                  const SizedBox(height: 32),
                  _buildStatusMessages(),
                  _buildActionButton(),
                  const SizedBox(height: 24),
                  const Text(
                    "Check your spam folder if the email doesn't appear.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
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
      height: 160,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primary2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: const SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 36),
              SizedBox(height: 12),
              Text(
                "EMAIL VERIFICATION",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
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
        boxShadow: [BoxShadow(color: _textDark.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _primary.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.email_outlined, color: _primary, size: 28),
          ),
          const SizedBox(height: 16),
          const Text("OTP code will be sent to", style: TextStyle(fontSize: 13, color: _textMuted)),
          const SizedBox(height: 6),
          Text(_maskEmail(widget.email), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
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
              "Phase 1: Verify via OTP code\nPhase 2: Create your credentials",
              style: TextStyle(fontSize: 12, color: Color(0xFF874D00), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBoxGrid() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(8, (index) {
        return SizedBox(
          width: 38, // Optimized for 8 boxes on mobile
          child: TextFormField(
            controller: _otpControllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textDark),
            decoration: InputDecoration(
              counterText: "",
              filled: true,
              fillColor: _fieldBg,
              contentPadding: EdgeInsets.zero,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _primary, width: 2)),
            ),
            onChanged: (value) {
              if (value.isNotEmpty && index < 7) {
                _focusNodes[index + 1].requestFocus();
              } else if (value.isEmpty && index > 0) {
                _focusNodes[index - 1].requestFocus();
              }
            },
          ),
        );
      }),
    );
  }

  Widget _buildStatusMessages() {
    if (_isSending) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
            const SizedBox(width: 12),
            Text('Sending code...', style: TextStyle(color: _textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if (_linkSent) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Text('Code has been sent successfully.', style: TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 13)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: (_isSending || _isChecking) ? null : _continueAfterVerification,
        child: _isChecking
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('VERIFY & CONTINUE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }
}