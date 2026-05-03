import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'uKonekOnBoardingPage.dart';
import 'uKonekMenuPage.dart';

// Database configuration
const _supabaseUrl = 'https://dqjxpwbsbzagbjtulhue.supabase.co';
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase for patient authentication
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  runApp(const UKonekApp());
}

class UKonekApp extends StatelessWidget {
  const UKonekApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if a patient session already exists
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'uKonek Medical Clinic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Updated to Medical Green for the Dental Clinic theme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF28A745), // Health Green
          primary: const Color(0xFF1B5E20),   // Deep Forest
          surface: const Color(0xFFF8FCF9),   // Mint-tinted Background
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',

        // Consistent AppBar styling for clinical pages
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B5E20),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),

      // Navigate to the main menu if logged in, otherwise show onboarding
      home: session != null ? const uKonekMenuPage() : const OnboardingPage(),
    );
  }
}