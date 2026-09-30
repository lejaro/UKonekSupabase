import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'menu_page.dart';
import 'main_shell_page.dart';
import 'change_password_page.dart';
import 'config/supabase_config.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'utils/app_transitions.dart';
import 'core/session/patient_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Notification Service
  await NotificationService.init();

  // Initialize Supabase for patient authentication
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const UKonekApp());
}

class UKonekApp extends StatefulWidget {
  const UKonekApp({super.key});

  @override
  State<UKonekApp> createState() => _UKonekAppState();
}

class _UKonekAppState extends State<UKonekApp> {
  late final StreamSubscription<AuthState> _authSubscription;
  StreamSubscription<Uri>? _deepLinkSubscription;

  // ── Cold-start recovery guard ─────────────────────────────────
  // Set to true when we detect a recovery deep link at launch so that
  // RootHandler knows it must not navigate away before the auth event fires.
  static bool _pendingPasswordRecovery = false;

  static bool get pendingPasswordRecovery => _pendingPasswordRecovery;

  @override
  void initState() {
    super.initState();

    // ── 1. Listen for Auth state changes (passwordRecovery event) ──
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      debugPrint('UKonekApp: Auth State Change Event: $event');

      if (event == AuthChangeEvent.passwordRecovery) {
        debugPrint('UKonekApp: Password recovery event detected! Navigating to Change Password page.');
        // Clear the pending flag so RootHandler unblocks if it is waiting
        _pendingPasswordRecovery = false;
        NotificationService.navigatorKey.currentState?.pushAndRemoveUntil(
          AppPageRoute.slideRight(const uKonekChangePasswordPage()),
          (route) => false,
        );
      }
    });

    // ── 2. Process deep links ─────────────────────────────────────
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    // Handle the link that launched the app (cold start).
    // We must process this BEFORE RootHandler finishes navigating.
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('UKonekApp: Initial deep link: $initialUri');
        final isRecovery = _isPasswordRecoveryLink(initialUri);
        if (isRecovery) {
          // Flag RootHandler to wait – the recovery event will navigate instead
          _pendingPasswordRecovery = true;
          debugPrint('UKonekApp: Cold-start recovery link detected; blocking RootHandler redirect.');
        }
        await _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('UKonekApp: Error reading initial deep link: $e');
      _pendingPasswordRecovery = false;
    }

    // Handle links when the app is already running (warm start)
    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (uri) async {
        debugPrint('UKonekApp: Incoming deep link: $uri');
        await _handleDeepLink(uri);
      },
      onError: (e) {
        debugPrint('UKonekApp: Deep link stream error: $e');
      },
    );
  }

  /// Returns true if the URI is a Supabase password-recovery deep link.
  static bool _isPasswordRecoveryLink(Uri uri) {
    final uriStr = uri.toString();

    // PKCE flow: ukonekmobile://reset-password?code=...
    // Supabase uses a `code` query param for the PKCE exchange
    if (uri.queryParameters.containsKey('code') &&
        uriStr.contains('reset-password')) return true;

    // Implicit flow fragment: ukonekmobile://reset-password#access_token=...&type=recovery
    if (uri.fragment.isNotEmpty) {
      // Parse fragment as query parameters (key=value&key2=value2)
      final fragParams = Uri.splitQueryString(uri.fragment);
      if (fragParams['type'] == 'recovery') return true;
    }

    // Query-encoded token: ?type=recovery
    if (uri.queryParameters['type'] == 'recovery') return true;

    // Host or path hint (covers both flows)
    if (uriStr.contains('reset-password')) return true;

    return false;
  }

  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint('UKonekApp: Handling deep link: $uri');

    if (!_isPasswordRecoveryLink(uri)) {
      debugPrint('UKonekApp: Not a recovery link, ignoring.');
      return;
    }

    try {
      // Let Supabase process the recovery token from the URL.
      // On success this fires the passwordRecovery AuthChangeEvent which
      // navigates to uKonekChangePasswordPage.
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      debugPrint('UKonekApp: Session recovered from deep link URL.');
    } catch (e) {
      debugPrint('UKonekApp: Failed to get session from URL: $e');
      // Clear the guard so RootHandler doesn't hang indefinitely
      _pendingPasswordRecovery = false;
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'uKonek Medical Clinic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Unified Design System Theme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D5A27), // Forest Green
          primary: const Color(0xFF2D5A27),   // Forest Green
          surface: const Color(0xFFF8FAFC),   // Slate Background
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
            minimumSize: const Size.fromHeight(44), // btn-h-lg equivalent
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
          elevation: 1, // subtle shadow
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
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
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
    });
  }

  void _performNavigation(Widget page) {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      AppPageRoute.fadeThrough(page),
    );
  }

  Future<void> _checkSession() async {
    // ── Guard: if a cold-start password recovery link was detected,
    // wait briefly for the auth event to fire and navigate on its own.
    if (_UKonekAppState.pendingPasswordRecovery) {
      debugPrint('RootHandler: Waiting for password recovery deep link to be processed...');
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!_UKonekAppState.pendingPasswordRecovery) {
          debugPrint('RootHandler: Recovery event handled, skipping normal session check.');
          return;
        }
      }
      debugPrint('RootHandler: Timed out waiting for recovery, continuing normal flow.');
    }

    final authClient = Supabase.instance.client.auth;
    final session = authClient.currentSession;

    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('session_token');

    debugPrint('RootHandler: Checking session... ${session != null ? "Supabase OK" : "No Supabase"} | Token: ${sessionToken != null ? "Present" : "Missing"}');

    Widget resolvedPage;

    if (session == null || sessionToken == null) {
      PatientSessionState.clearSession();
      if (session != null) {
        debugPrint('RootHandler: Session mismatch, clearing Supabase session.');
        await ApiService.signOut();
      }
      resolvedPage = const uKonekMenuPage();
    } else {
      try {
        debugPrint('RootHandler: Fetching profile for user ${session.user.id}...');
        final profile = await ApiService.fetchMyCitizenProfile();
        debugPrint('RootHandler: Profile fetched successfully.');

        final patientSession = PatientSession.fromProfile(profile);
        PatientSessionState.setSession(patientSession);

        final displayName = profile['username'] ?? session.user.email ?? 'User';

        resolvedPage = uKonekMainShellPage(
          username: displayName,
          citizenId: profile['id'].toString(),
          fullname: '${profile['firstname']} ${profile['surname']}',
          email: profile['email'] ?? '',
          phone: profile['contact_number'] ?? '',
          address: profile['complete_address'] ?? '',
        );
      } catch (e) {
        debugPrint('RootHandler: Error fetching profile: $e');
        PatientSessionState.clearSession();
        try {
          await ApiService.signOut();
        } catch (signOutError) {
          debugPrint('RootHandler: SignOut error: $signOutError');
        }
        resolvedPage = const uKonekMenuPage();
      }
    }

    if (!mounted) return;
    _performNavigation(resolvedPage);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: screenWidth * 0.76,
                    maxHeight: 260,
                  ),
                  child: Image.asset(
                    'assets/logo/splash_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const Spacer(flex: 2),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Color(0xFF059669),
                    strokeWidth: 2.2,
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

