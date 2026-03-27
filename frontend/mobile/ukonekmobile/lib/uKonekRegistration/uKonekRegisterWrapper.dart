import 'dart:io'; // <-- REQUIRED for File type
import 'package:flutter/material.dart';
import 'package:ukonekmobile/uKonekPreviewPage.dart';
import 'steps/personal_info_step.dart';
import 'steps/contact_address_step.dart';
import 'steps/id_verification_step.dart';

class uKonekRegisterWrapper extends StatefulWidget {
  const uKonekRegisterWrapper({super.key});

  @override
  State<uKonekRegisterWrapper> createState() => _uKonekRegisterWrapperState();
}

class _uKonekRegisterWrapperState extends State<uKonekRegisterWrapper> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  // --- CONTROLLERS ---
  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final nameExtensionController = TextEditingController();
  final ageController = TextEditingController();

  final contactController = TextEditingController();
  final emailController = TextEditingController();
  final houseNumberController = TextEditingController();
  final streetNameController = TextEditingController();
  final barangayController = TextEditingController(text: "Ugong");

  final emergencyNameController = TextEditingController();
  final emergencyContactController = TextEditingController();
  final relationController = TextEditingController();

  DateTime? selectedDate;
  String selectedSex = "Male";
  bool idVerified = false;
  File? idImage; // Handled by dart:io import

  Future<void> pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF0A2E6E)),
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

  void _handleNext() {
    bool canProceed = false;

    if (_currentStep == 0) {
      if (_step1Key.currentState!.validate()) {
        if (selectedDate == null) {
          _showErrorSnackBar("Please select your date of birth");
        } else {
          canProceed = true;
        }
      } else {
        _showErrorSnackBar("Please complete all required fields");
      }
    }
    else if (_currentStep == 1) {
      if (_step2Key.currentState!.validate()) {
        canProceed = true;
      } else {
        _showErrorSnackBar("Please complete all required fields");
      }
    }
    else if (_currentStep == 2) {
      if (idVerified) {
        _navigateToPreview();
      } else {
        _showErrorSnackBar("Please verify your ID first.");
      }
    }

    if (canProceed && _currentStep < 2) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut
      );
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _navigateToPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => uKonekPreviewPage(
          firstName: firstNameController.text,
          middleName: middleNameController.text,
          surname: lastNameController.text,
          nameExtension: nameExtensionController.text, // Passed correctly now
          dob: selectedDate != null ? "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}" : "",
          age: ageController.text,
          contact: "+63${contactController.text}",
          sex: selectedSex,
          email: emailController.text,
          address: "${houseNumberController.text} ${streetNameController.text}, Brgy. ${barangayController.text}",
          emergencyName: emergencyNameController.text,
          emergencyContact: emergencyContactController.text.isEmpty ? "" : "+63${emergencyContactController.text}",
          relation: relationController.text,
          idImage: idImage,
          idVerified: idVerified,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E6E),
        elevation: 0,
        centerTitle: true,
        title: const Text("Create Account",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () {
            if (_currentStep > 0) {
              _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          _buildProgressBar(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (int page) => setState(() => _currentStep = page),
              children: [
                PersonalInfoStep(
                  formKey: _step1Key,
                  firstName: firstNameController,
                  middleName: middleNameController,
                  lastName: lastNameController,
                  nameExtension: nameExtensionController,
                  age: ageController,
                  onPickDate: pickDate,
                  selectedDate: selectedDate,
                  selectedSex: selectedSex,
                  onSexChanged: (val) => setState(() => selectedSex = val),
                ),
                ContactAddressStep(
                  formKey: _step2Key,
                  contact: contactController,
                  email: emailController,
                  houseNo: houseNumberController,
                  street: streetNameController,
                  brgy: barangayController,
                  eName: emergencyNameController,
                  eContact: emergencyContactController,
                  relation: relationController,
                ),
                IdVerificationStep(
                  firstName: firstNameController.text,
                  surname: lastNameController.text,
                  middleName: middleNameController.text,
                  dob: selectedDate,
                  onVerified: (verified, pickedFile) { // These names must match the child's call
                    setState(() {
                      idVerified = verified;
                      idImage = pickedFile;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildProgressBar() {
    const Color formBg = Color(0xFFF8FAFF);
    const Color activeBlue = Color(0xFF0D47A1);
    const Color fieldBorder = Color(0xFFDDE3F0);
    const Color textGrey = Color(0xFF8A93A0);

    return Container(
      width: double.infinity,
      color: formBg,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Stack(
        alignment: Alignment.topCenter, // Align stack to top to manage text below
        children: [
          // ── 1. THE TRACK LINE (Moves down slightly to center with circles) ──
          Positioned(
            top: 17, // Half of circle height (34/2)
            left: 40,
            right: 40,
            child: Stack(
              children: [
                Container(height: 2, color: fieldBorder),
                LayoutBuilder(
                  builder: (context, constraints) => AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: constraints.maxWidth * (_currentStep / 2),
                    height: 2,
                    color: activeBlue,
                  ),
                ),
              ],
            ),
          ),

          // ── 2. THE NODES AND LABELS ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepWithLabel(0, "Personal", activeBlue, textGrey, fieldBorder),
              _buildStepWithLabel(1, "Contact", activeBlue, textGrey, fieldBorder),
              _buildStepWithLabel(2, "Verify", activeBlue, textGrey, fieldBorder),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepWithLabel(int index, String label, Color active, Color inactive, Color stroke) {
    bool isCompleted = index < _currentStep;
    bool isCurrent = index == _currentStep;
    bool isActive = isCompleted || isCurrent;

    return SizedBox(
      width: 70, // Fixed width to prevent labels from shifting nodes
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The Circle
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isActive ? active : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? active : stroke,
                width: 1.5,
              ),
              boxShadow: isCurrent ? [
                BoxShadow(color: active.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))
              ] : null,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                "${index + 1}",
                style: TextStyle(
                  color: isActive ? Colors.white : inactive,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // The Label
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? active : inactive,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))]
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _handleNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0A2E6E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text(
            _currentStep == 2 ? "FINISH" : "NEXT",
            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }
}