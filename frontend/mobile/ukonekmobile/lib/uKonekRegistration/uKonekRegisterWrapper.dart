import 'dart:io';
import 'package:flutter/material.dart';
import 'uKonekPreviewPage.dart';
import 'steps/uKonekPersonalStep.dart';
import 'steps/uKonekContactStep.dart';
import 'steps/uKonekMedicalStep.dart';

class uKonekRegisterWrapper extends StatefulWidget {
  const uKonekRegisterWrapper({super.key});

  @override
  State<uKonekRegisterWrapper> createState() =>
      _uKonekRegisterWrapperState();
}

class _uKonekRegisterWrapperState
    extends State<uKonekRegisterWrapper> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  // Controllers
  final firstNameController      = TextEditingController();
  final middleNameController     = TextEditingController();
  final lastNameController       = TextEditingController();
  final nameExtensionController  = TextEditingController();
  final ageController            = TextEditingController();
  final contactController        = TextEditingController();
  final emailController          = TextEditingController();
  final houseNumberController    = TextEditingController();
  final streetNameController     = TextEditingController();
  final barangayController       =
  TextEditingController(text: 'Ugong');
  final emergencyNameController    = TextEditingController();
  final emergencyContactController = TextEditingController();
  final relationController         = TextEditingController();

  DateTime? selectedDate;
  String    selectedSex  = 'Male';
  bool      idVerified   = false;
  File?     idImage;

  static const _primary   = Color(0xFF0077B6);
  static const _primary2  = Color(0xFF0096C7);
  static const _bg        = Color(0xFFF0F7FA);
  static const _surface   = Colors.white;
  static const _textDark  = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);
  static const _divider   = Color(0xFFEEF1F6);

  // Step labels & icons
  static const _steps = [
    {'label': 'Personal',  'icon': Icons.person_outline_rounded},
    {'label': 'Contact',   'icon': Icons.contact_mail_outlined},
    {'label': 'Medical History', 'icon': Icons.medical_information_outlined},
  ];

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate:   DateTime(1950),
      lastDate:    DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
                primary: _primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        int age = DateTime.now().year - picked.year;
        if (DateTime.now().month < picked.month ||
            (DateTime.now().month == picked.month &&
                DateTime.now().day < picked.day)) {
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
          _snackBar('Please select your date of birth');
        } else {
          canProceed = true;
        }
      } else {
        _snackBar('Please complete all required fields');
      }
    } else if (_currentStep == 1) {
      if (_step2Key.currentState!.validate()) {
        canProceed = true;
      } else {
        _snackBar('Please complete all required fields');
      }
    } else if (_currentStep == 2) {
      if (idVerified) {
        _navigateToPreview();
      } else {
        _snackBar('Please verify your ID first.');
      }
    }
    if (canProceed && _currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _snackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  void _navigateToPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => uKonekPreviewPage(
          firstName:        firstNameController.text,
          middleName:       middleNameController.text,
          surname:          lastNameController.text,
          nameExtension:    nameExtensionController.text,
          dob:              selectedDate != null
              ? '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}'
              : '',
          age:              ageController.text,
          contact:          '+63${contactController.text}',
          sex:              selectedSex,
          email:            emailController.text,
          address:
          '${houseNumberController.text} ${streetNameController.text}, Brgy. ${barangayController.text}',
          emergencyName:    emergencyNameController.text,
          emergencyContact: emergencyContactController.text.isEmpty
              ? ''
              : '+63${emergencyContactController.text}',
          relation:         relationController.text,
          idImage:          idImage,
          idVerified:       idVerified,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        _buildStepper(),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (p) =>
                setState(() => _currentStep = p),
            children: [
              uKonekPersonalStep(
                formKey:      _step1Key,
                firstName:    firstNameController,
                middleName:   middleNameController,
                lastName:     lastNameController,
                nameExtension:nameExtensionController,
                age:          ageController,
                onPickDate:   pickDate,
                selectedDate: selectedDate,
                selectedSex:  selectedSex,
                onSexChanged: (v) =>
                    setState(() => selectedSex = v),
              ),
              uKonekContactStep(
                formKey:  _step2Key,
                contact:  contactController,
                email:    emailController,
                houseNo:  houseNumberController,
                street:   streetNameController,
                brgy:     barangayController,
                eName:    emergencyNameController,
                eContact: emergencyContactController,
                relation: relationController,
              ),
              uKonekMedicalStep(
                firstName: firstNameController.text,
                surname:   lastNameController.text,
                middleName:middleNameController.text,
                dob:       selectedDate,
                onVerified:(verified, file) {
                  setState(() {
                    idVerified = verified;
                    idImage    = file;
                  });
                },
                  onDataChanged: (data) {
                    // handle form data here
                    print(data); // or store it
                  },
              ),
            ],
          ),
        ),
        _buildBottomNav(),
      ]),
    );
  }

  // ── Header ───────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primary2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Row(children: [
            GestureDetector(
              onTap: () {
                if (_currentStep > 0) {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patient Registration',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    )),
                SizedBox(height: 2),
                Text('Tell us about yourself',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  // ── Stepper ──────────────────────────────────────────────────
  Widget _buildStepper() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(children: [
        // Step nodes + connector
        Row(children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepIdx = i ~/ 2;
            final filled  = stepIdx < _currentStep;
            return Expanded(child: Container(
              height: 2,
              color: filled ? _primary : const Color(0xFFE0E7FF),
            ));
          }
          final idx       = i ~/ 2;
          final completed = idx < _currentStep;
          final current   = idx == _currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: (completed || current)
                  ? _primary
                  : _surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: (completed || current)
                    ? _primary
                    : const Color(0xFFDDE3F0),
                width: 2,
              ),
              boxShadow: current
                  ? [BoxShadow(
                color: _primary.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )]
                  : [],
            ),
            child: Center(
              child: completed
                  ? const Icon(Icons.check_rounded,
                  color: Colors.white, size: 18)
                  : Icon(
                _steps[idx]['icon'] as IconData,
                color: current
                    ? Colors.white
                    : _textMuted,
                size: 18,
              ),
            ),
          );
        })),
        const SizedBox(height: 10),
        // Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_steps.length, (i) {
            final isActive = i <= _currentStep;
            return SizedBox(
              width: 80,
              child: Text(
                _steps[i]['label'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i == _currentStep
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isActive ? _primary : _textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  // ── Bottom Nav ───────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 16,
          offset: const Offset(0, -4),
        )],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _handleNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation:  4,
            shadowColor: _primary.withOpacity(0.3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _currentStep == 2 ? 'FINISH' : 'NEXT',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _currentStep == 2
                    ? Icons.check_circle_outline_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}