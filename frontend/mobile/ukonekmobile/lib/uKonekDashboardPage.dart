import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'uKonekLoginPage.dart';

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

  // Dummy health stats
  final int _heartRate = 72;
  final int _steps = 6_840;
  final int _sleep = 7;
  final double _bmi = 22.4;

  // Dummy upcoming appointments
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

  // Dummy medications
  final List<Map<String, String>> _medications = [
    {
      'name': 'Metformin 500mg',
      'time': '8:00 AM',
      'status': 'taken',
      'icon': '💊',
    },
    {
      'name': 'Amlodipine 5mg',
      'time': '12:00 PM',
      'status': 'pending',
      'icon': '💊',
    },
    {
      'name': 'Vitamin D3',
      'time': '6:00 PM',
      'status': 'pending',
      'icon': '🟡',
    },
  ];

  // Dummy health tips
  final List<Map<String, String>> _healthTips = [
    {
      'title': 'Stay Hydrated',
      'desc': 'Drink at least 8 glasses of water daily.',
      'icon': '💧',
      'color': '0xFF0288D1',
    },
    {
      'title': 'Walk More',
      'desc': 'Aim for 10,000 steps a day for heart health.',
      'icon': '🚶',
      'color': '0xFF2E7D32',
    },
    {
      'title': 'Sleep Well',
      'desc': '7–9 hours of sleep boosts immunity.',
      'icon': '🌙',
      'color': '0xFF6A1B9A',
    },
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

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
      backgroundColor: const Color(0xFFF4F6FB),
      body: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _slideUp,
          child: Column(
            children: [
              // ── Top Header ─────────────────────────────────────────────
              _buildHeader(),

              // ── Body ───────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),

                      // Health Stats
                      _sectionTitle("Today's Health Summary"),
                      const SizedBox(height: 12),
                      _buildHealthStats(),

                      const SizedBox(height: 28),

                      // Quick Actions
                      _sectionTitle("Quick Actions"),
                      const SizedBox(height: 12),
                      _buildQuickActions(),

                      const SizedBox(height: 28),

                      // Upcoming Appointments
                      _sectionTitle("Upcoming Appointments"),
                      const SizedBox(height: 12),
                      _buildAppointments(),

                      const SizedBox(height: 28),

                      // Medications
                      _sectionTitle("Today's Medications"),
                      const SizedBox(height: 12),
                      _buildMedications(),

                      const SizedBox(height: 28),

                      // Health Tips
                      _sectionTitle("Health Tips"),
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

      // ── Bottom Nav ────────────────────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── HEADER ──────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          child: Column(
            children: [
              // Top row: greeting + notification + avatar
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
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification bell
                  Stack(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.notifications_outlined,
                            color: Colors.white, size: 22),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF5252),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  // Avatar
                  GestureDetector(
                    onTap: _showLogoutDialog,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text("👤", style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Search bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.search, color: Colors.white60, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Search doctors, services...",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 13,
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

  // ── HEALTH STATS GRID ────────────────────────────────────────────────────
  Widget _buildHealthStats() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.55,
      children: [
        _statCard(
          icon: Icons.favorite_rounded,
          iconColor: const Color(0xFFE53935),
          label: "Heart Rate",
          value: "$_heartRate",
          unit: "bpm",
          bgColor: const Color(0xFFFFEBEE),
        ),
        _statCard(
          icon: Icons.directions_walk_rounded,
          iconColor: const Color(0xFF1976D2),
          label: "Steps",
          value: "${(_steps / 1000).toStringAsFixed(1)}k",
          unit: "/ 10k goal",
          bgColor: const Color(0xFFE3F2FD),
        ),
        _statCard(
          icon: Icons.nightlight_round,
          iconColor: const Color(0xFF7B1FA2),
          label: "Sleep",
          value: "$_sleep",
          unit: "hrs last night",
          bgColor: const Color(0xFFF3E5F5),
        ),
        _statCard(
          icon: Icons.monitor_weight_outlined,
          iconColor: const Color(0xFF2E7D32),
          label: "BMI",
          value: "$_bmi",
          unit: "Normal",
          bgColor: const Color(0xFFE8F5E9),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              Text(
                unit,
                style: const TextStyle(fontSize: 10, color: Colors.black38),
              ),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS ────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.calendar_month_rounded, 'label': 'Book\nAppointment', 'color': 0xFF1565C0},
      {'icon': Icons.medical_services_outlined, 'label': 'Find\nDoctor', 'color': 0xFF00838F},
      {'icon': Icons.medication_rounded, 'label': 'My\nMeds', 'color': 0xFF6A1B9A},
      {'icon': Icons.receipt_long_outlined, 'label': 'Medical\nRecords', 'color': 0xFFBF360C},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((a) {
        return GestureDetector(
          onTap: () => _showComingSoon(a['label'].toString().replaceAll('\n', ' ')),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(a['color'] as int),
                      Color(a['color'] as int).withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Color(a['color'] as int).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(a['icon'] as IconData,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                a['label'].toString(),
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

  // ── APPOINTMENTS ─────────────────────────────────────────────────────────
  Widget _buildAppointments() {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _appointments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final apt = _appointments[i];
          return Container(
            width: 200,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(apt['avatar']!,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            apt['doctor']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            apt['specialty']!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: Color(0xFF1976D2)),
                    const SizedBox(width: 4),
                    Text(
                      apt['date']!,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF1976D2)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 12, color: Colors.black38),
                    const SizedBox(width: 4),
                    Text(
                      apt['time']!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
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

  // ── MEDICATIONS ───────────────────────────────────────────────────────────
  Widget _buildMedications() {
    return Column(
      children: _medications.map((med) {
        final isTaken = med['status'] == 'taken';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Row(
            children: [
              Text(med['icon']!, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med['name']!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      med['time']!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isTaken
                      ? Colors.green.shade50
                      : const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isTaken
                        ? Colors.green.shade300
                        : const Color(0xFF1976D2).withOpacity(0.4),
                  ),
                ),
                child: Text(
                  isTaken ? "✓ Taken" : "Pending",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isTaken
                        ? Colors.green.shade700
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

  // ── HEALTH TIPS ───────────────────────────────────────────────────────────
  Widget _buildHealthTips() {
    return Column(
      children: _healthTips.map((tip) {
        final color = Color(int.parse(tip['color']!));
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Text(tip['icon']!, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip['title']!,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tip['desc']!,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
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

  // ── BOTTOM NAV ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.calendar_month_rounded, 'label': 'Schedule'},
      {'icon': Icons.bar_chart_rounded, 'label': 'Health'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedTab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                      horizontal: isSelected ? 18 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0D47A1).withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected
                            ? const Color(0xFF0D47A1)
                            : Colors.black38,
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: Color(0xFF0D47A1),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]
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

  // ── HELPERS ───────────────────────────────────────────────────────────────
  Widget _sectionTitle(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            letterSpacing: 0.2,
          ),
        ),
        Text(
          "See all",
          style: TextStyle(
            fontSize: 12,
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "🌤 Good Morning,";
    if (hour < 17) return "☀️ Good Afternoon,";
    return "🌙 Good Evening,";
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("$feature — coming soon!"),
      backgroundColor: const Color(0xFF0D47A1),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log Out",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => const uKonekLoginPage()),
                    (route) => false,
              );
            },
            child: const Text("Log Out",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}