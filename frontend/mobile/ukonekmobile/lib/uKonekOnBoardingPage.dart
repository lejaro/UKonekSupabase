import 'package:flutter/material.dart';
import 'uKonekMenuPage.dart';

// ── Shared design tokens ───────────────────────────────────────
class _C {
  static const primary    = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const bg         = Color(0xFFF8FAFF);
  static const textDark   = Color(0xFF1A2740);
  static const textMuted  = Color(0xFF8A93A0);
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _onboardingData = [
    {
      'title':       'Welcome to U-Konek+ 👋',
      'subtitle':    'Your barangay health center, in your pocket.',
      'description': 'Skip long queues and manage your health services anytime, anywhere with ease.',
      'icon':        Icons.volunteer_activism_rounded,
      'color':       const Color(0xFF10B981),
      'bgColor':     const Color(0xFFECFDF5),
    },
    {
      'title':       'No More Waiting in Line',
      'subtitle':    'Join the queue digitally.',
      'description': 'Get your number, track your turn in real-time — no need to wait onsite.',
      'icon':        Icons.confirmation_number_rounded,
      'color':       const Color(0xFF1565C0),
      'bgColor':     const Color(0xFFEFF6FF),
    },
    {
      'title':       'Stay on Top of Your Health',
      'subtitle':    'Reminders & appointments made simple.',
      'description': 'Book visits, track check-ups, and receive reminders for your medicines.',
      'icon':        Icons.notifications_active_rounded,
      'color':       const Color(0xFF7B1FA2),
      'bgColor':     const Color(0xFFF5F3FF),
    },
    {
      'title':       'Ready to Begin?',
      'subtitle':    "Let's get you set up.",
      'description': 'Create your account and start accessing healthcare services with ease.',
      'icon':        Icons.rocket_launch_rounded,
      'color':       const Color(0xFFF59E0B),
      'bgColor':     const Color(0xFFFFFBEB),
    },
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int value) {
    setState(() => _currentPage = value);
    _animCtrl.reset();
    _animCtrl.forward();
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const uKonekMenuPage(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data    = _onboardingData[_currentPage];
    final accent  = data['color'] as Color;
    final bgColor = data['bgColor'] as Color;
    final isLast  = _currentPage == _onboardingData.length - 1;

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Skip ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Page count pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentPage + 1} / ${_onboardingData.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                if (!isLast)
                  TextButton(
                    onPressed: _navigateToLogin,
                    child: const Text('Skip',
                        style: TextStyle(
                          color: _C.textMuted,
                          fontWeight: FontWeight.w600,
                        )),
                  )
                else
                  const SizedBox(width: 60),
              ],
            ),
          ),

          // ── Page content ────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller:    _pageController,
              onPageChanged: _onPageChanged,
              itemCount:     _onboardingData.length,
              itemBuilder:   (_, index) => _OnboardingContent(
                title:       _onboardingData[index]['title']!    as String,
                subtitle:    _onboardingData[index]['subtitle']! as String,
                description: _onboardingData[index]['description']! as String,
                icon:        _onboardingData[index]['icon']!     as IconData,
                accentColor: _onboardingData[index]['color']!    as Color,
                bgColor:     _onboardingData[index]['bgColor']!  as Color,
                fadeAnim:    _fadeAnim,
              ),
            ),
          ),

          // ── Bottom nav ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
            child: Column(children: [
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _onboardingData.length,
                      (i) => _buildDot(i, accent),
                ),
              ),
              const SizedBox(height: 32),

              // Main button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primary,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: _C.primary.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () {
                    if (isLast) {
                      _navigateToLogin();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOutCubic,
                      );
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isLast ? 'Create Account' : 'Continue',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isLast
                            ? Icons.arrow_forward_rounded
                            : Icons.chevron_right_rounded,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildDot(int index, Color accent) {
    final isActive = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: isActive ? 28 : 8,
      decoration: BoxDecoration(
        color: isActive ? _C.primary : const Color(0xFFDDE3F0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ── Onboarding content widget ──────────────────────────────────
class _OnboardingContent extends StatelessWidget {
  final String title, subtitle, description;
  final IconData icon;
  final Color accentColor, bgColor;
  final Animation<double> fadeAnim;

  const _OnboardingContent({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
    required this.fadeAnim,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon bubble
            Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 60, color: accentColor),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _C.textDark,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            // Subtitle with accent underline pill
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Description
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _C.textMuted,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}