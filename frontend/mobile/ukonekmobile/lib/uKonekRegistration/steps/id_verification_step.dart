import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:string_similarity/string_similarity.dart';

class IdVerificationStep extends StatefulWidget {
  final String firstName;
  final String surname;
  final String middleName;
  final DateTime? dob;
  final Function(bool, File?) onVerified;

  const IdVerificationStep({
    super.key,
    required this.firstName,
    required this.surname,
    required this.middleName,
    this.dob,
    required this.onVerified,
  });

  @override
  State<IdVerificationStep> createState() => _IdVerificationStepState();
}

class _IdVerificationStepState extends State<IdVerificationStep> {
  File? _idImage;
  bool _isVerifying = false;
  bool _idVerified = false;
  String _statusMessage = "";

  // Design Tokens
  static const _primary = Color(0xFF0A2E6E);
  static const _textDark = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);

  // ── OCR LOGIC ──────────────────────────────────────────────────────────

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  String _toLower(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

  bool _checkBirthdayInOcr(String ocrRaw, DateTime dob) {
    final month = dob.month; final day = dob.day; final year = dob.year;
    final monthNames = ['','january','february','march','april','may','june','july','august','september','october','november','december'];
    final monthShort = ['','jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
    final ocrLower = ocrRaw.toLowerCase();

    final variants = [
      '${month.toString().padLeft(2,'0')}/${day.toString().padLeft(2,'0')}/$year',
      '${day.toString().padLeft(2,'0')}/${month.toString().padLeft(2,'0')}/$year',
      '$month/$day/$year','$day/$month/$year',
      '${monthNames[month]} $day, $year',
      '${monthShort[month]} $day, $year',
      '$year-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}',
    ];

    for (final v in variants) { if (ocrLower.contains(v.toLowerCase())) return true; }

    // Fallback: Check digits only
    final digitsOnly = ocrRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final ms = month.toString().padLeft(2,'0');
    final ds = day.toString().padLeft(2,'0');
    final ys = year.toString();
    if (digitsOnly.contains('$ys$ms$ds') || digitsOnly.contains('$ms$ds$ys')) return true;

    return false;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _idImage = File(picked.path);
        _isVerifying = true;
        _idVerified = false;
        _statusMessage = "";
      });
      _processOCR();
    }
  }

  Future<void> _processOCR() async {
    if (kIsWeb) {
      setState(() { _isVerifying = false; _statusMessage = "OCR not supported on Web"; });
      return;
    }

    try {
      final inputImage = InputImage.fromFile(_idImage!);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final rawText = recognizedText.text.trim();
      final ocrNorm = _normalize(rawText);
      final ocrLowerSpaced = _toLower(rawText);

      // Match against widget properties passed from Step 1
      final fullName = _normalize('${widget.firstName} ${widget.middleName} ${widget.surname}');
      final shortName = _normalize('${widget.firstName} ${widget.surname}');

      final fullSim = StringSimilarity.compareTwoStrings(ocrNorm, fullName);
      final shortSim = StringSimilarity.compareTwoStrings(ocrNorm, shortName);

      // Name Match Logic: similarity threshold OR both first and last name found
      final containsFirst = _toLower(widget.firstName).length > 2 && ocrLowerSpaced.contains(_toLower(widget.firstName));
      final containsLast = _toLower(widget.surname).length > 2 && ocrLowerSpaced.contains(_toLower(widget.surname));

      bool nameMatched = fullSim > 0.45 || shortSim > 0.45 || (containsFirst && containsLast);
      bool birthdayMatched = widget.dob == null || _checkBirthdayInOcr(rawText, widget.dob!);

      setState(() {
        _isVerifying = false;
        if (nameMatched && birthdayMatched) {
          _idVerified = true;
          _statusMessage = "ID successfully verified ✅";
        } else {
          _idVerified = false;
          _statusMessage = "We couldn’t read your ID. Please try again.";
        }
      });

      widget.onVerified(_idVerified, _idImage);

    } catch (e) {
      setState(() { _isVerifying = false; _statusMessage = "We couldn’t read your ID. Please try again."; });
    }
  }

  // ── UI BUILDING ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Verify Your Identity",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _textDark)),
          const SizedBox(height: 6),
          const Text("Upload a valid ID to confirm your identity.",
              style: TextStyle(fontSize: 15, color: _textMuted)),

          const SizedBox(height: 32),

          _buildUploadArea(),

          const SizedBox(height: 20),

          Column(
            children: [
              _microcopyItem("Make sure the photo is clear"),
              _microcopyItem("All details must be readable"),
            ],
          ),

          const SizedBox(height: 32),

          if (_statusMessage.isNotEmpty) _buildStatusBox(),
        ],
      ),
    );
  }

  Widget _buildUploadArea() {
    return GestureDetector(
      onTap: _isVerifying ? null : _pickImage,
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _idImage != null ? (_idVerified ? Colors.green : Colors.red) : const Color(0xFFDDE3F0),
            width: 2,
            style: _idImage == null ? BorderStyle.none : BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_idImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(_idImage!, width: double.infinity, fit: BoxFit.cover),
              ),
            if (_idImage == null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _primary.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.cloud_upload_outlined, color: _primary, size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text("Tap to upload ID", style: TextStyle(fontWeight: FontWeight.bold, color: _primary)),
                ],
              ),
            if (_isVerifying)
              Container(
                decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(18)),
                child: const Center(child: CircularProgressIndicator(color: _primary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _microcopyItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: _textMuted),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13, color: _textMuted)),
        ],
      ),
    );
  }

  Widget _buildStatusBox() {
    final isSuccess = _idVerified;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSuccess ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.verified : Icons.error_outline,
              color: isSuccess ? Colors.green : Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_statusMessage,
                style: TextStyle(
                  color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                )),
          ),
        ],
      ),
    );
  }
}