import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:string_similarity/string_similarity.dart';
import 'uKonekPreviewPage.dart';

class uKonekRegisterPage extends StatefulWidget {
  const uKonekRegisterPage({super.key});
  @override
  State<uKonekRegisterPage> createState() => _uKonekRegisterPageState();
}

class _uKonekRegisterPageState extends State<uKonekRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final surnameController = TextEditingController();
  final ageController = TextEditingController();
  final contactController = TextEditingController();
  final emailController = TextEditingController();
  final houseNumberController = TextEditingController();
  final streetNameController = TextEditingController();
  final barangayController = TextEditingController(text: "Ugong"); // Default to Barangay Ugong
  final emergencyNameController = TextEditingController();
  final emergencyContactController = TextEditingController();
  final relationController = TextEditingController();

  DateTime? selectedDate;
  String selectedSex = "Male";
  File? _idImage;
  bool _idVerified = false;
  bool _isVerifying = false;
  String _extractedOcrText = "";
  bool _nameMatched = false;
  bool _birthdayMatched = false;

  // ── Design tokens ───────────────────────────────────────────
  static const _primary = Color(0xFF0D47A1);
  static const _primaryLight = Color(0xFF1976D2);
  static const _surface = Color(0xFFF8FAFF);
  static const _cardBg = Colors.white;

  Future<void> pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        int age = DateTime.now().year - picked.year;
        if (DateTime.now().month < picked.month ||
            (DateTime.now().month == picked.month && DateTime.now().day < picked.day)) {
          age--;
        }
        ageController.text = age.toString();
      });
    }
  }

  Future<void> pickIDImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _idImage = File(pickedFile.path);
        _idVerified = false;
        _extractedOcrText = "";
        _nameMatched = false;
        _birthdayMatched = false;
      });
      await verifyID();
    }
  }

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
      '${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}-$year',
      '$year-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}',
      '${monthNames[month]} $day, $year','${monthNames[month]} $day $year',
      '${monthShort[month]} $day, $year','${monthShort[month]} $day $year',
      '$day ${monthNames[month]} $year','$day ${monthShort[month]} $year',
      '${monthNames[month]} $year','${monthShort[month]} $year',
    ];
    for (final v in variants) { if (ocrLower.contains(v.toLowerCase())) return true; }
    final digitsOnly = ocrRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final ms = month.toString().padLeft(2,'0'); final ds = day.toString().padLeft(2,'0'); final ys = year.toString();
    if (digitsOnly.contains('$ys$ms$ds') || digitsOnly.contains('$ds$ms$ys') || digitsOnly.contains('$ms$ds$ys')) return true;
    return false;
  }

  Future<void> verifyID() async {
    if (_idImage == null) return;
    if (kIsWeb) {
      setState(() {
        _isVerifying = false;
        _idVerified = false;
        _nameMatched = false;
        _birthdayMatched = false;
        _extractedOcrText = "ID verification is currently unavailable on web. Please continue on mobile for OCR verification.";
      });
      return;
    }
    setState(() => _isVerifying = true);
    final inputImage = InputImage.fromFile(_idImage!);
    final textRecognizer = TextRecognizer();
    final recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();
    final rawText = recognizedText.text.trim();
    final ocrNorm = _normalize(rawText);
    final ocrLowerSpaced = _toLower(rawText);
    final fullName = _normalize('${firstNameController.text} ${middleNameController.text} ${surnameController.text}');
    final shortName = _normalize('${firstNameController.text} ${surnameController.text}');
    final firstName = _toLower(firstNameController.text);
    final middleName = _toLower(middleNameController.text);
    final surname = _toLower(surnameController.text);
    final fullSim = StringSimilarity.compareTwoStrings(ocrNorm, fullName);
    final shortSim = StringSimilarity.compareTwoStrings(ocrNorm, shortName);
    final ocrContainsFirst = firstName.length > 1 && ocrLowerSpaced.contains(firstName);
    final ocrContainsSurname = surname.length > 1 && ocrLowerSpaced.contains(surname);
    final ocrContainsMiddle = middleName.length > 1 && ocrLowerSpaced.contains(middleName);
    final nameMatched = fullSim > 0.45 || shortSim > 0.45 || (ocrContainsFirst && ocrContainsSurname) || (ocrContainsFirst && ocrContainsMiddle);
    bool birthdayMatched = false;
    if (selectedDate != null) birthdayMatched = _checkBirthdayInOcr(rawText, selectedDate!);
    final isVerified = nameMatched && (selectedDate == null || birthdayMatched);
    setState(() { _idVerified = isVerified; _nameMatched = nameMatched; _birthdayMatched = birthdayMatched; _extractedOcrText = rawText; _isVerifying = false; });
    String message; Color bgColor;
    if (isVerified) { message = "✅ ID verified — name & birthday matched!"; bgColor = Colors.green.shade700; }
    else if (nameMatched && !birthdayMatched && selectedDate != null) { message = "⚠️ Name matched but birthday not found."; bgColor = Colors.orange.shade700; }
    else if (!nameMatched && birthdayMatched) { message = "⚠️ Birthday matched but name not found."; bgColor = Colors.orange.shade700; }
    else { message = "❌ ID could not be verified. Check your details."; bgColor = Colors.red.shade700; }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: bgColor, duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_primary, _primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text("Create Account", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text("Fill in your details below", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionCard(
                      icon: Icons.person_outline_rounded,
                      title: "Personal Information",
                      children: [
                        _styledField("First Name", firstNameController, Icons.badge_outlined, nameOnly: true),
                        _styledField("Middle Name (Optional)", middleNameController, Icons.badge_outlined, nameOnly: true, isRequired: false),
                        _styledField("Surname", surnameController, Icons.badge_outlined, nameOnly: true),
                        _datePicker(),
                        _styledField("Age", ageController, Icons.cake_outlined, enabled: false),
                        _phoneField("Contact Number", contactController, Icons.phone_outlined),
                        _styledField("Email Address", emailController, Icons.email_outlined),
                        _styledField("House Number", houseNumberController, Icons.home_outlined, numberOnly: true),
                        _styledField("Street Name", streetNameController, Icons.signpost_outlined),
                        _styledField("Barangay", barangayController, Icons.location_city_outlined, enabled: false),
                        _sexSelector(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      icon: Icons.contact_emergency_outlined,
                      title: "Emergency Contact",
                      children: [
                        _styledField("Emergency Contact Name", emergencyNameController, Icons.person_2_outlined, nameOnly: true),
                        _phoneField("Emergency Contact Number", emergencyContactController, Icons.phone_in_talk_outlined),
                        _styledField("Relationship", relationController, Icons.people_outline_rounded, nameOnly: true),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      icon: Icons.credit_card_outlined,
                      title: "National ID Verification",
                      children: [
                        const Text(
                          "Upload a valid government ID. Your name and birthday must match the details you entered.",
                          style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        _idUploadSection(),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _nextButton(),
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

  // ── Section card wrapper ───────────────────────────────────────────────
  Widget _sectionCard({required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _primary, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A2E))),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEEF2FF)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  // ── Styled text field ──────────────────────────────────────────────────
  Widget _styledField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool enabled = true,
    bool nameOnly = false,
    bool numberOnly = false,
    bool isRequired = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: numberOnly ? TextInputType.number : TextInputType.text,
        inputFormatters: [
          if (nameOnly) FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z '\-]")),
          if (numberOnly) FilteringTextInputFormatter.digitsOnly,
        ],
        validator: (v) {
          final value = v?.trim() ?? '';
          if (value.isEmpty && isRequired) return "$label is required";
          if (value.isEmpty && !isRequired) return null;
          if (nameOnly && !RegExp(r"^[A-Za-z]+(?:[ '-][A-Za-z]+)*$").hasMatch(value)) {
            return "$label must not contain numbers";
          }
          if (numberOnly && !RegExp(r"^\d+$").hasMatch(value)) {
            return "$label must contain numbers only";
          }
          return null;
        },
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
          filled: true,
          fillColor: enabled ? const Color(0xFFF8FAFF) : const Color(0xFFEEF0F5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
        ),
      ),
    );
  }

  // ── Phone field with +63 prefix ────────────────────────────────────────
  Widget _phoneField(String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10), // 10 digits after +63
        ],
        validator: (v) {
          if (v == null || v.isEmpty) return "$label is required";
          if (v.length != 10) return "Please enter a valid 10-digit number";
          return null;
        },
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
          prefix: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              "+63 ",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            ),
          ),
          hintText: "9XX XXX XXXX",
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent)),
        ),
      ),
    );
  }

  // ── Date picker ────────────────────────────────────────────────────────
  Widget _datePicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            border: Border.all(color: const Color(0xFFDDE3F0)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined, color: _primary.withOpacity(0.6), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedDate == null ? "Date of Birth" : "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}",
                style: TextStyle(fontSize: 14, color: selectedDate == null ? Colors.grey.shade500 : const Color(0xFF1A1A2E)),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  // ── Sex selector ───────────────────────────────────────────────────────
  Widget _sexSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Sex", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _sexOption("Male", Icons.male_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _sexOption("Female", Icons.female_rounded)),
          ]),
        ],
      ),
    );
  }

  Widget _sexOption(String sex, IconData icon) {
    final selected = selectedSex == sex;
    return GestureDetector(
      onTap: () => setState(() => selectedSex = sex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _primary : const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _primary : const Color(0xFFDDE3F0)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? Colors.white : Colors.grey.shade400, size: 20),
          const SizedBox(width: 6),
          Text(sex, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  // ── ID upload section ──────────────────────────────────────────────────
  Widget _idUploadSection() {
    return Column(
      children: [
        if (_idImage != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: kIsWeb
                ? Image.network(_idImage!.path, width: double.infinity, height: 160, fit: BoxFit.cover)
                : Image.file(_idImage!, width: double.infinity, height: 160, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
          if (_isVerifying)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
                SizedBox(width: 10),
                Text("Verifying your ID...", style: TextStyle(color: _primary, fontSize: 13)),
              ]),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _idVerified ? Colors.green.shade50 : Colors.red.shade50,
                border: Border.all(color: _idVerified ? Colors.green.shade200 : Colors.red.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(_idVerified ? Icons.verified_rounded : Icons.cancel_rounded,
                    color: _idVerified ? Colors.green : Colors.red, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _idVerified ? "ID Successfully Verified" : "Verification Failed",
                  style: TextStyle(color: _idVerified ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 13),
                )),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _matchChip(icon: Icons.person_outline, label: "Name", matched: _nameMatched)),
              const SizedBox(width: 8),
              Expanded(child: _matchChip(icon: Icons.cake_outlined, label: "Birthday", matched: _birthdayMatched, skipped: selectedDate == null)),
            ]),
            if (_extractedOcrText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF0F4FF), border: Border.all(color: const Color(0xFFDDE3F0)), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Extracted ID Text", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _primary)),
                  const SizedBox(height: 6),
                  Text(_extractedOcrText, style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.5)),
                ]),
              ),
            ],
          ],
        ] else
          GestureDetector(
            onTap: pickIDImage,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBCCEE), width: 1.5),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.cloud_upload_outlined, color: _primary.withOpacity(0.5), size: 32),
                const SizedBox(height: 6),
                const Text("Tap to upload your ID", style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                const Text("JPG, PNG supported", style: TextStyle(color: Colors.black38, fontSize: 11)),
              ]),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: pickIDImage,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(_idImage == null ? "Select ID Photo" : "Re-upload ID Photo"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: const BorderSide(color: _primary, width: 1.5),
              foregroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _matchChip({required IconData icon, required String label, required bool matched, bool skipped = false}) {
    final color = skipped ? Colors.grey : matched ? Colors.green : Colors.red;
    final status = skipped ? "Not entered" : matched ? "Matched ✓" : "Not found ✗";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.08), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          Text(status, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8))),
        ])),
      ]),
    );
  }

  String? _customValidationError() {
    final namePattern = RegExp(r"^[A-Za-z]+(?:[ '-][A-Za-z]+)*$");
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (!namePattern.hasMatch(firstNameController.text.trim())) {
      return 'First name must contain letters only';
    }
    if (!namePattern.hasMatch(surnameController.text.trim())) {
      return 'Surname must contain letters only';
    }
    if (middleNameController.text.trim().isNotEmpty &&
        !namePattern.hasMatch(middleNameController.text.trim())) {
      return 'Middle name must contain letters only';
    }
    if (!emailPattern.hasMatch(emailController.text.trim())) {
      return 'Please enter a valid email address';
    }
    if (!RegExp(r'^\d+$').hasMatch(houseNumberController.text.trim())) {
      return 'House number must contain numbers only';
    }
    if (selectedDate == null) {
      return 'Please select your date of birth';
    }
    if (ageController.text.isEmpty) {
      return 'Age is required';
    }
    return null;
  }

  // ── NEXT button ────────────────────────────────────────────────────────
  Widget _nextButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          shadowColor: _primary.withOpacity(0.4),
        ),
        onPressed: () {
          if (_formKey.currentState!.validate() && selectedDate != null && ageController.text.isNotEmpty && _idImage != null) {
            final customValidationMessage = _customValidationError();
            if (customValidationMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(customValidationMessage)));
              return;
            }
            // Format contact numbers with +63 prefix
            final fullContact = "+63${contactController.text}";
            final fullEmergencyContact = emergencyContactController.text.trim().isEmpty
              ? ""
              : "+63${emergencyContactController.text}";

            // Combine address fields
            final completeAddress = "${houseNumberController.text}, ${streetNameController.text}, Brgy. ${barangayController.text}, Valenzuela City";

            Navigator.push(context, MaterialPageRoute(builder: (_) => uKonekPreviewPage(
              firstName: firstNameController.text,
              middleName: middleNameController.text,
              surname: surnameController.text,
              dob: "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}",
              age: ageController.text,
              contact: fullContact,
              sex: selectedSex,
              email: emailController.text,
              address: completeAddress,
              emergencyName: emergencyNameController.text,
              emergencyContact: fullEmergencyContact,
              relation: relationController.text,
              idImage: _idImage,
              idVerified: _idVerified,
              extractedOcrText: _extractedOcrText,
            )));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please complete all fields and upload your ID")));
          }
        },
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text("CONTINUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
          SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded, size: 20),
        ]),
      ),
    );
  }
}