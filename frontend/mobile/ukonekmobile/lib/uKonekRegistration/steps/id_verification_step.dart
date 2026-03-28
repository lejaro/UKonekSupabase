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
  State<IdVerificationStep> createState() =>
      _IdVerificationStepState();
}

class _IdVerificationStepState
    extends State<IdVerificationStep> {

  File?   _idImage;
  bool    _isVerifying = false;
  bool    _idVerified  = false;
  String  _statusMessage = '';

  static const _primary   = Color(0xFF0A2E6E);
  static const _primary2  = Color(0xFF1565C0);
  static const _textDark  = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);
  static const _success   = Color(0xFF10B981);

  // ── OCR logic (unchanged) ─────────────────────────────────────
  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String _toLower(String s) =>
      s.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .trim();

  bool _checkBirthdayInOcr(String ocrRaw, DateTime dob) {
    final month  = dob.month;
    final day    = dob.day;
    final year   = dob.year;
    final mNames = ['','january','february','march','april','may',
      'june','july','august','september','october','november','december'];
    final mShort = ['','jan','feb','mar','apr','may',
      'jun','jul','aug','sep','oct','nov','dec'];
    final lower  = ocrRaw.toLowerCase();

    final variants = [
      '${month.toString().padLeft(2,'0')}/${day.toString().padLeft(2,'0')}/$year',
      '${day.toString().padLeft(2,'0')}/${month.toString().padLeft(2,'0')}/$year',
      '$month/$day/$year',
      '$day/$month/$year',
      '${mNames[month]} $day, $year',
      '${mShort[month]} $day, $year',
      '$year-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}',
    ];
    for (final v in variants) {
      if (lower.contains(v.toLowerCase())) return true;
    }
    final digits = ocrRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final ms = month.toString().padLeft(2,'0');
    final ds = day.toString().padLeft(2,'0');
    final ys = year.toString();
    return digits.contains('$ys$ms$ds') ||
        digits.contains('$ms$ds$ys');
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _idImage       = File(picked.path);
        _isVerifying   = true;
        _idVerified    = false;
        _statusMessage = '';
      });
      _processOCR();
    }
  }

  Future<void> _processOCR() async {
    if (kIsWeb) {
      setState(() {
        _isVerifying   = false;
        _statusMessage = 'OCR not supported on Web.';
      });
      return;
    }
    try {
      final inputImage    = InputImage.fromFile(_idImage!);
      final recognizer    = TextRecognizer(
          script: TextRecognitionScript.latin);
      final recognizedText= await recognizer.processImage(inputImage);
      await recognizer.close();

      final raw       = recognizedText.text.trim();
      final ocrNorm   = _normalize(raw);
      final ocrLower  = _toLower(raw);

      final fullName  = _normalize(
          '${widget.firstName} ${widget.middleName} ${widget.surname}');
      final shortName = _normalize(
          '${widget.firstName} ${widget.surname}');

      final fullSim  =
      StringSimilarity.compareTwoStrings(ocrNorm, fullName);
      final shortSim =
      StringSimilarity.compareTwoStrings(ocrNorm, shortName);

      final hasFirst = _toLower(widget.firstName).length > 2 &&
          ocrLower.contains(_toLower(widget.firstName));
      final hasLast  = _toLower(widget.surname).length > 2 &&
          ocrLower.contains(_toLower(widget.surname));

      final nameMatched = fullSim > 0.45 || shortSim > 0.45 ||
          (hasFirst && hasLast);
      final bdayMatched = widget.dob == null ||
          _checkBirthdayInOcr(raw, widget.dob!);

      setState(() {
        _isVerifying = false;
        if (nameMatched && bdayMatched) {
          _idVerified    = true;
          _statusMessage = 'ID successfully verified ✅';
        } else {
          _idVerified    = false;
          _statusMessage =
          "We couldn't read your ID clearly. Please try again.";
        }
      });
      widget.onVerified(_idVerified, _idImage);
    } catch (_) {
      setState(() {
        _isVerifying   = false;
        _statusMessage =
        "We couldn't read your ID. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verify Your Identity',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _textDark,
                letterSpacing: -0.4,
              )),
          const SizedBox(height: 4),
          const Text(
              'Upload a valid government-issued ID to confirm your identity.',
              style: TextStyle(fontSize: 13, color: _textMuted)),
          const SizedBox(height: 24),

          // ── Upload area ───────────────────────────────────
          GestureDetector(
            onTap: _isVerifying ? null : _pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _idImage != null
                    ? Colors.transparent
                    : const Color(0xFFF0F4FA),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _idImage == null
                      ? const Color(0xFFDDE3F0)
                      : (_idVerified
                      ? _success.withOpacity(0.5)
                      : Colors.redAccent.withOpacity(0.4)),
                  width: _idImage == null ? 1.5 : 2,
                  style: _idImage == null
                      ? BorderStyle.solid
                      : BorderStyle.solid,
                ),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Image preview
                  if (_idImage != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(
                        _idImage!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  // Empty state
                  if (_idImage == null)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.cloud_upload_outlined,
                              color: _primary, size: 30),
                        ),
                        const SizedBox(height: 14),
                        const Text('Tap to upload your ID',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _primary,
                              fontSize: 14,
                            )),
                        const SizedBox(height: 4),
                        Text('JPG, PNG • Max 10MB',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            )),
                      ],
                    ),
                  // Processing overlay
                  if (_isVerifying)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                              color: _primary, strokeWidth: 3),
                          const SizedBox(height: 14),
                          const Text('Scanning ID...',
                              style: TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              )),
                        ],
                      ),
                    ),
                  // Re-upload chip on top right
                  if (_idImage != null && !_isVerifying)
                    Positioned(
                      top: 10, right: 10,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 6,
                            )],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.refresh_rounded,
                                  size: 14, color: _primary),
                              const SizedBox(width: 4),
                              const Text('Change',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _primary,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Tips ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _primary.withOpacity(0.10)),
            ),
            child: Column(children: [
              _tip(Icons.light_mode_outlined,
                  'Take the photo in good lighting'),
              const SizedBox(height: 8),
              _tip(Icons.center_focus_strong_outlined,
                  'All details must be clear and readable'),
              const SizedBox(height: 8),
              _tip(Icons.crop_outlined,
                  'Make sure the full ID is visible'),
            ]),
          ),

          const SizedBox(height: 16),

          // ── Status box ────────────────────────────────────
          if (_statusMessage.isNotEmpty)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _idVerified
                    ? _success.withOpacity(0.08)
                    : Colors.red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _idVerified
                        ? _success.withOpacity(0.3)
                        : Colors.red.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(
                    _idVerified
                        ? Icons.verified_rounded
                        : Icons.error_outline_rounded,
                    color: _idVerified ? _success : Colors.red,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(_statusMessage,
                    style: TextStyle(
                      color: _idVerified
                          ? _success
                          : Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ))),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _tip(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 16, color: _primary.withOpacity(0.6)),
      const SizedBox(width: 10),
      Text(text,
          style: const TextStyle(
              fontSize: 12, color: _textMuted)),
    ]);
  }
}