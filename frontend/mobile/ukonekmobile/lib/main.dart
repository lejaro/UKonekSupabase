import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'uKonekMenuPage.dart';
import 'uKonekDashboardPage.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

// Database configuration
const _supabaseUrl = 'https://dqjxpwbsbzagbjtulhue.supabase.co';
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Notification Service
  await NotificationService.init();

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
      navigatorKey: NotificationService.navigatorKey,
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
      ),
      home: const RootHandler(),
    );
  }
}

class RootHandler extends StatefulWidget {
  const RootHandler({super.key});

  @override
  State<RootHandler> createState() => _RootHandlerState();
}

class _RootHandlerState extends State<RootHandler> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
    });
  }

  Future<void> _checkSession() async {
    // Add a tiny delay to allow the loading spinner to be visible and everything to settle
    await Future.delayed(const Duration(milliseconds: 500));

    final authClient = Supabase.instance.client.auth;
    final session = authClient.currentSession;

    // Explicit session token check for forced login on logged-out state
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('session_token');

    debugPrint('RootHandler: Checking session... ${session != null ? "Supabase OK" : "No Supabase"} | Token: ${sessionToken != null ? "Present" : "Missing"}');

    if (session == null || sessionToken == null) {
      if (session != null) {
        // Mismatch: Supabase has session but our custom token is gone (happens after signOut)
        debugPrint('RootHandler: Session mismatch, clearing Supabase session.');
        await ApiService.signOut();
      }
      _navigate(const uKonekMenuPage());
      return;
    }

    try {
      debugPrint('RootHandler: Fetching profile for user ${session.user.id}...');
      final profile = await ApiService.fetchMyCitizenProfile();
      debugPrint('RootHandler: Profile fetched successfully.');

      final displayName = profile['username'] ?? session.user.email ?? 'User';

      _navigate(uKonekDashboardPage(
        username: displayName,
        citizenId: profile['id'].toString(),
        fullname: '${profile['firstname']} ${profile['surname']}',
        email: profile['email'] ?? '',
        phone: profile['contact_number'] ?? '',
        address: profile['complete_address'] ?? '',
      ));
    } catch (e) {
      debugPrint('RootHandler: Error fetching profile: $e');
      // If error (e.g. profile missing), clear session and go to onboarding
      try {
        await ApiService.signOut();
      } catch (signOutError) {
        debugPrint('RootHandler: SignOut error: $signOutError');
      }
      _navigate(const uKonekMenuPage());
    }
  }

  void _navigate(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF28A745)),
        ),
      ),
    );
  }
}