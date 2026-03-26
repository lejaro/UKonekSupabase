import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'uKonekLoginPage.dart';

// ── Design tokens ──────────────────────────────────────────────────────────
class _C {
  static const primary = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const primaryLight = Color(0xFF1976D2);
  static const bg = Color(0xFFF0F4FA);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1A2740);
  static const textMuted = Color(0xFF8A93A0);
  static const divider = Color(0xFFEEF1F6);
  static const heartRed = Color(0xFFE53935);
  static const sleepPurple = Color(0xFF7B1FA2);
  static const stepsBlue = Color(0xFF1976D2);
  static const bmiGreen = Color(0xFF2E7D32);
}

class uKonekDashboardPage extends StatefulWidget {
  final String username;

  const uKonekDashboardPage({
    super.key,
    this.username = "Juan",
  });

  @override
  State<uKonekDashboardPage> createState() => _uKonekDashboardPageState();
}

class _uKonekDashboardPageState extends State<uKonekDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  int _selectedTab = 0;

  final int _heartRate = 72;
  final int _steps = 6840;
  final int _sleep = 7;
  final double _bmi = 22.4;

  final List<Map<String, String>> _appointments = [
    {
      'doctor': 'Dr. Maria Santos',
      'specialty': 'Cardiologist',
      'date': 'Mar 14, 2026',
      'time': '9:00 AM',
      'avatar': '👩‍⚕️',
    },
    {
      'doctor': 'Dr. Ramon Cruz',
      'specialty': 'General Physician',
      'date': 'Mar 18, 2026',
      'time': '2:30 PM',
      'avatar': '👨‍⚕️',
    },
    {
      'doctor': 'Dr. Lena Reyes',
      'specialty': 'Nutritionist',
      'date': 'Mar 22, 2026',
      'time': '11:00 AM',
      'avatar': '👩‍⚕️',
    },
  ];

  final List<Map<String, String>> _medications = [
    {'name': 'Metformin 500mg', 'time': '8:00 AM', 'status': 'taken', 'icon': '💊'},
    {'name': 'Amlodipine 5mg', 'time': '12:00 PM', 'status': 'pending', 'icon': '💊'},
    {'name': 'Vitamin D3', 'time': '6:00 PM', 'status': 'pending', 'icon': '🟡'},
  ];

  final List<Map<String, dynamic>> _healthTips = [
    {
      'title': 'Stay Hydrated',
      'desc': 'Drink at least 8 glasses of water daily.',
      'icon': '💧',
      'color': const Color(0xFF1D4ED8),
      'bg': const Color(0xFFEFF6FF),
      'border': const Color(0xFFBFDBFE),
    },
    {
      'title': 'Walk More',
      'desc': 'Aim for 10,000 steps a day for heart health.',
      'icon': '🚶',
      'color': const Color(0xFF15803D),
      'bg': const Color(0xFFF0FDF4),
      'border': const Color(0xFFBBF7D0),
    },
    {
      'title': 'Sleep Well',
      'desc': '7–9 hours of sleep boosts immunity.',
      'icon': '🌙',
      'color': const Color(0xFF6D28D9),
      'bg': const Color(0xFFF5F3FF),
      'border': const Color(0xFFDDD6FE),
    },
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      extendBodyBehindAppBar: true,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _slideUp,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 22),
                      _sectionHeader("Today's Health Summary"),
                      const SizedBox(height: 12),
                      _buildHealthStats(),
                      const SizedBox(height: 26),
                      _sectionHeader("Quick Actions", showSeeAll: false),
                      const SizedBox(height: 12),
                      _buildQuickActions(),
                      const SizedBox(height: 26),
                      _sectionHeader("Upcoming Appointments"),
                      const SizedBox(height: 12),
                      _buildAppointments(),
                      const SizedBox(height: 26),
                      _sectionHeader("Today's Medications"),
                      const SizedBox(height: 12),
                      _buildMedications(),
                      const SizedBox(height: 26),
                      _sectionHeader("Health Tips", showSeeAll: false),
                      const SizedBox(height: 12),
                      _buildHealthTips(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A2E6E), Color(0xFF1565C0), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          child: Column(
            children: [
              // Top row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification
                  Stack(
                    children: [
                      _headerBtn(
                        child: const Icon(Icons.notifications_outlined,
                            color: Colors.white, size: 20),
                      ),
                      Positioned(
                        top: 9,
                        right: 9,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5252),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _C.primaryLight, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              const SizedBox(height: 18),

              // Search bar
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.18), width: 1),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.search_rounded,
                        color: Colors.white60, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "Search doctors, services...",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBtn({required Widget child}) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  // ── HEALTH STATS GRID ──────────────────────────────────────────────────
  Widget _buildHealthStats() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.55,
      children: [
        _statCard(
          icon: Icons.favorite_rounded,
          iconColor: _C.heartRed,
          bgColor: const Color(0xFFFFEBEE),
          label: "Heart Rate",
          value: "$_heartRate",
          unit: "bpm",
        ),
        _statCard(
          icon: Icons.directions_walk_rounded,
          iconColor: _C.stepsBlue,
          bgColor: const Color(0xFFE3F2FD),
          label: "Steps",
          value: "${(_steps / 1000).toStringAsFixed(1)}k",
          unit: "/ 10k goal",
        ),
        _statCard(
          icon: Icons.nightlight_round,
          iconColor: _C.sleepPurple,
          bgColor: const Color(0xFFF3E5F5),
          label: "Sleep",
          value: "$_sleep",
          unit: "hrs last night",
        ),
        _statCard(
          icon: Icons.monitor_weight_outlined,
          iconColor: _C.bmiGreen,
          bgColor: const Color(0xFFE8F5E9),
          label: "BMI",
          value: "$_bmi",
          unit: "Normal",
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                  height: 1,
                ),
              ),
              const SizedBox(height: 1),
              Text(unit,
                  style: const TextStyle(fontSize: 9.5, color: Colors.black38)),
              const SizedBox(height: 1),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      {
        'icon': Icons.calendar_month_rounded,
        'label': 'Book\nAppt',
        'gradient': [const Color(0xFF0D47A1), const Color(0xFF1E88E5)],
      },
      {
        'icon': Icons.medical_services_outlined,
        'label': 'Find\nDoctor',
        'gradient': [const Color(0xFF00838F), const Color(0xFF00ACC1)],
      },
      {
        'icon': Icons.medication_rounded,
        'label': 'My\nMeds',
        'gradient': [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)],
      },
      {
        'icon': Icons.receipt_long_outlined,
        'label': 'Records',
        'gradient': [const Color(0xFFBF360C), const Color(0xFFE64A19)],
      },
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((a) {
        final gradients = a['gradient'] as List<Color>;
        return GestureDetector(
          onTap: () => _showComingSoon(
              (a['label'] as String).replaceAll('\n', ' ')),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradients,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: gradients.first.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(a['icon'] as IconData,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                a['label'] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── APPOINTMENTS ───────────────────────────────────────────────────────
  Widget _buildAppointments() {
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _appointments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (context, i) {
          final apt = _appointments[i];
          return Container(
            width: 188,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.black.withOpacity(0.05), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Doctor row
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F0FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(apt['avatar']!,
                            style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            apt['doctor']!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _C.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            apt['specialty']!,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: _C.divider),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: _C.primaryMid),
                    const SizedBox(width: 5),
                    Text(
                      apt['date']!,
                      style: const TextStyle(
                          fontSize: 10.5, color: _C.primaryMid),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 12, color: Colors.black38),
                    const SizedBox(width: 5),
                    Text(
                      apt['time']!,
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black45),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── MEDICATIONS ────────────────────────────────────────────────────────
  Widget _buildMedications() {
    return Column(
      children: _medications.map((med) {
        final isTaken = med['status'] == 'taken';
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.black.withOpacity(0.05), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(med['icon']!, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med['name']!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _C.textDark),
                    ),
                    Text(
                      med['time']!,
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isTaken
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFE3F0FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isTaken
                        ? const Color(0xFFA5D6A7)
                        : const Color(0xFF90CAF9),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  isTaken ? "✓  Taken" : "Pending",
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isTaken
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF1565C0),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── HEALTH TIPS ────────────────────────────────────────────────────────
  Widget _buildHealthTips() {
    return Column(
      children: _healthTips.map((tip) {
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tip['bg'] as Color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: (tip['border'] as Color), width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tip['icon']!, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip['title']!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: tip['color'] as Color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tip['desc']!,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── BOTTOM NAV ─────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.calendar_month_rounded, 'label': 'Schedule'},
      {'icon': Icons.bar_chart_rounded, 'label': 'Health'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        border: const Border(
          top: BorderSide(color: Color(0x14000000), width: 0.5),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedTab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                      horizontal: isSelected ? 16 : 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _C.primaryMid.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _C.primaryMid : Colors.black26,
                        size: 21,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: _C.primaryMid,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, {bool showSeeAll = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _C.textDark,
            letterSpacing: 0.1,
          ),
        ),
        if (showSeeAll)
          Text(
            "See all",
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "☀️  Good Morning,";
    if (hour < 17) return "🌤  Good Afternoon,";
    return "🌙  Good Evening,";
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$feature — coming soon!"),
        backgroundColor: _C.primaryMid,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log Out",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        content: const Text("Are you sure you want to log out?",
            style: TextStyle(fontSize: 14, color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel",
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.primaryMid,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const uKonekLoginPage()),
                (route) => false,
              );
            },
            child: const Text("Log Out"),
          ),
        ],
      ),
    );
  }
}