import 'package:flutter/material.dart';
import 'uKonekMenuPage.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _onboardingData = [
    {
      "title": "Welcome to uKonek 👋",
      "subtitle": "Your easier way to connect with your barangay health center.",
      "description": "Skip long lines and manage your health services anytime, anywhere.",
      "icon": Icons.volunteer_activism_rounded,
      "color": const Color(0xFF10B981), // Green
    },
    {
      "title": "No More Waiting in Line",
      "subtitle": "Join the queue digitally",
      "description": "Get your number, track your turn, and know exactly when it’s your time—no need to wait onsite.",
      "icon": Icons.confirmation_number_rounded,
      "color": const Color(0xFF1565C0), // Blue
    },
    {
      "title": "Stay on Track with Your Health",
      "subtitle": "Appointments & reminders made simple",
      "description": "Book visits, track schedules, and receive reminders for medicines and check-ups.",
      "icon": Icons.notifications_active_rounded,
      "color": const Color(0xFF7B1FA2), // Purple
    },
    {
      "title": "Ready to Begin?",
      "subtitle": "Let’s get you set up",
      "description": "Create your account and start accessing healthcare services with ease.",
      "icon": Icons.rocket_launch_rounded,
      "color": const Color(0xFFF59E0B), // Yellow/Orange
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button disappears on last screen
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.topRight,
                child: _currentPage != _onboardingData.length - 1
                    ? TextButton(
                  onPressed: _navigateToLogin,
                  child: const Text("Skip", style: TextStyle(color: Color(0xFF8A93A0))),
                )
                    : const SizedBox(height: 48), // Maintain spacing
              ),
            ),

            Expanded(
              flex: 4,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (value) => setState(() => _currentPage = value),
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) => _OnboardingContent(
                  title: _onboardingData[index]["title"]!,
                  subtitle: _onboardingData[index]["subtitle"]!,
                  description: _onboardingData[index]["description"]!,
                  icon: _onboardingData[index]["icon"]!,
                  accentColor: _onboardingData[index]["color"]!,
                ),
              ),
            ),

            // Navigation Area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  // Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _onboardingData.length,
                          (index) => _buildDot(index: index),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A2E6E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (_currentPage == _onboardingData.length - 1) {
                          _navigateToLogin();
                        } else {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                          );
                        }
                      },
                      child: Text(
                        _currentPage == _onboardingData.length - 1 ? "Create Account" : "Continue",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot({required int index}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? const Color(0xFF0A2E6E) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const uKonekMenuPage()),
    );
  }
}

class _OnboardingContent extends StatelessWidget {
  final String title, subtitle, description;
  final IconData icon;
  final Color accentColor;

  const _OnboardingContent({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Graphic Area
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 100, color: accentColor),
          ),
          const SizedBox(height: 48),

          // Text Area
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1A2740), letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Color(0xFF8A93A0), height: 1.6),
          ),
        ],
      ),
    );
  }
}