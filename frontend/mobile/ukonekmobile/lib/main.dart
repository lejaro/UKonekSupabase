import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ukonekmobile/uKonekMenuPage.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://dqjxpwbsbzagbjtulhue.supabase.co',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw Exception(
      'Missing Supabase config. Provide --dart-define=SUPABASE_URL and --dart-define=SUPABASE_ANON_KEY'
    );
  }

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HomePage(),
  ));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // ── TOP: Blue gradient background (covers top 60% of screen) ──
          Container(
            height: screenHeight * 0.62,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF1565C0),
                  Color(0xFF1E88E5),
                ],
              ),
            ),
          ),

          // ── BOTTOM: White rounded card ────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: screenHeight * 0.45,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(30, 36, 30, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── Text content ─────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "WELCOME TO",
                        style: TextStyle(
                          fontSize: 28,
                          fontStyle: FontStyle.italic,
                          color: Colors.black87,
                          letterSpacing: 1,
                        ),
                      ),
                      const Text(
                        "U-KONEK",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B6EFF),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Connect with trusted healthcare professionals anytime, anywhere. "
                            "Track your health, get reminders, and stay informed with U-KONEK — "
                            "your personal healthcare companion.",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),

                  // ── GET STARTED Button ───────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => uKonekMenuPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2B6EFF),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: const Color(0xFF2B6EFF).withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                      child: const Text("GET STARTED"),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Decorative floating icons (top area) ──────────────────────
          SafeArea(
            child: SizedBox(
              height: screenHeight * 0.58,
              width: double.infinity,
              child: Stack(
                children: [
                  // Top-left bell icon
                  Positioned(
                    top: 16,
                    right: 24,
                    child: _floatingIcon(Icons.notifications_none, 28),
                  ),

                  // Shield icon top-right area
                  Positioned(
                    top: 60,
                    right: 20,
                    child: _glowCircle(
                      Icons.shield_outlined,
                      size: 48,
                      iconSize: 26,
                    ),
                  ),

                  // Chat bubble left
                  Positioned(
                    top: 100,
                    left: 16,
                    child: _glowCircle(
                      Icons.chat_bubble_outline,
                      size: 44,
                      iconSize: 22,
                    ),
                  ),

                  // Person icon left
                  Positioned(
                    top: 190,
                    left: 10,
                    child: _glowCircle(
                      Icons.person_outline,
                      size: 40,
                      iconSize: 20,
                    ),
                  ),

                  // Medical cross right
                  Positioned(
                    top: 200,
                    right: 14,
                    child: _glowCircle(
                      Icons.add_circle_outline,
                      size: 40,
                      iconSize: 20,
                    ),
                  ),

                  // Pills/medication bottom-left of image area
                  Positioned(
                    bottom: 60,
                    left: 14,
                    child: _glowCircle(
                      Icons.medication_outlined,
                      size: 40,
                      iconSize: 20,
                    ),
                  ),

                  // Heart icon bottom-right
                  Positioned(
                    bottom: 60,
                    right: 14,
                    child: _glowCircle(
                      Icons.favorite_border,
                      size: 40,
                      iconSize: 20,
                    ),
                  ),

                  // ── Center: Phone frame + doctor illustration ──────────
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        // Phone frame container
                        Container(
                          width: screenWidth * 0.52,
                          height: screenHeight * 0.38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(33),
                            child: Image.asset(
                              "assets/welcome_screen/welcomPhoto-removebg-preview.png",
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Floating icon helper (plain icon, no circle)
  Widget _floatingIcon(IconData icon, double size) {
    return Icon(icon, color: Colors.white70, size: size);
  }

  // Glowing circle icon helper
  Widget _glowCircle(IconData icon,
      {double size = 44, double iconSize = 22}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white30, width: 1),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}