import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'uKonekMenuPage.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekMainShellPage.dart';
import 'uKonekChangePasswordPage.dart';
import 'config/supabase_config.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'utils/app_transitions.dart';

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
    // ── Guard: if a cold-start password recovery link was detected,
    // wait briefly for the auth event to fire and navigate on its own.
    // We poll for up to 5 s; if the event fires, the auth listener will
    // push the Change Password page before we do anything here.
    if (_UKonekAppState.pendingPasswordRecovery) {
      debugPrint('RootHandler: Waiting for password recovery deep link to be processed...');
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!_UKonekAppState.pendingPasswordRecovery) {
          debugPrint('RootHandler: Recovery event handled, skipping normal session check.');
          return;
        }
      }
      // Timed out – recovery link processing failed; fall through to normal flow
      debugPrint('RootHandler: Timed out waiting for recovery, continuing normal flow.');
    }

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

      _navigate(uKonekMainShellPage(
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
      AppPageRoute.fadeThrough(page),
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
