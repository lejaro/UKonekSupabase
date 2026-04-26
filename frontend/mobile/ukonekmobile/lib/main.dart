import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'uKonekOnBoardingPage.dart';
import 'uKonekMenuPage.dart'; 

const _supabaseUrl = 'https://dqjxpwbsbzagbjtulhue.supabase.co';
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g';

void main() async { 
  WidgetsFlutterBinding.ensureInitialized(); 
  
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
    
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'uKonek',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'Poppins',
      ),
      
      home: session != null ? const uKonekMenuPage() : const OnboardingPage(),
    );
  }
}