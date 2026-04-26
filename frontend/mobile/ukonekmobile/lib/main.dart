import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'uKonekDentalOnboarding.dart';

// ── Entry point ────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // TODO: Initialize Supabase
  // await Supabase.initialize(
  //   url:     'YOUR_SUPABASE_URL',
  //   anonKey: 'YOUR_SUPABASE_ANON_KEY',
  // );

  runApp(const UKonekApp());
}

class UKonekApp extends StatelessWidget {
  const UKonekApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'uKonek+',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily:      'Poppins',     // or 'Inter'
        primaryColor:    const Color(0xFF0077B6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0077B6),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F7FA),
        useMaterial3: true,
      ),
      home: const uKonekDentalOnboarding(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FILE STRUCTURE
// ═══════════════════════════════════════════════════════════════
//
// lib/
// ├── main.dart                      ← Entry point (this file)
// │
// ├── dental_theme.dart              ← Shared design tokens (DC class)
// │
// ├── dental_onboarding_page.dart    ← Onboarding slides
// ├── dental_login_page.dart         ← Login (Patient / Dentist toggle)
// │
// ├── registration/
// │   ├── dental_register_wrapper.dart  ← 3-step stepper shell
// │   ├── steps/
// │   │   ├── dental_personal_step.dart ← Step 1: Personal Info
// │   │   ├── dental_contact_step.dart  ← Step 2: Contact & Address
// │   │   └── dental_medical_step.dart  ← Step 3: Medical History (NEW)
// │   ├── dental_preview_page.dart   ← Review before submit
// │   └── dental_credentials_page.dart  ← Email + password
// │
// ├── patient/
// │   └── patient_main_page.dart     ← Patient app (5 tabs)
// │       ├── Home tab
// │       ├── Appointments tab (+ booking flow)
// │       ├── Dental Records tab
// │       ├── Notifications tab
// │       └── Profile tab
// │
// ├── dentist/
// │   └── dentist_main_page.dart     ← Dentist app (5 tabs)
// │       ├── Dashboard tab (today's patients + stats)
// │       ├── Schedule tab
// │       ├── Patients tab
// │       ├── Records tab
// │       └── Settings tab
// │
// └── shared/
//     ├── dental_profile_page.dart   ← Patient profile (editable)
//     ├── dental_prescription_page.dart ← Prescriptions list
//     ├── dental_records_page.dart   ← Dental records (standalone)
//     └── dental_settings_page.dart  ← App settings