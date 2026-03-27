import 'package:flutter/material.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekHealthRecordsPage.dart';
import 'uKonekProfilePage.dart';

class uKonekDashboardPage extends StatefulWidget {
  final String username;
  final String email;
  final String phone;
  final String address;

  const uKonekDashboardPage({
    super.key,
    required this.username,
    this.email = "juan.delacruz@email.com",
    this.phone = "0912 345 6789",
    this.address = "Brgy. Ugong, Valenzuela City",
  });

  @override
  State<uKonekDashboardPage> createState() => _uKonekDashboardPageState();
}

class _uKonekDashboardPageState extends State<uKonekDashboardPage> {
  // --- DESIGN TOKENS ---
  static const Color _primary = Color(0xFF0D47A1);
  static const Color _bg = Color(0xFFF4F7FE);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF1976D2);

  int _selectedTab = 0;

  // ── NAVIGATION HELPER ──
  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => uKonekProfilePage(
          fullName: widget.username,
          email: widget.email,
          phone: widget.phone,
          address: widget.address,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          // 1. FIXED STATIC HEADER
          _buildStaticHeader(),

          // 2. SCROLLABLE CONTENT
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  // Section: On Duty Today
                  _buildOnDutySection(),

                  const SizedBox(height: 32),

                  // Section: Queue Card
                  _buildQueueCard(),

                  const SizedBox(height: 32),

                  _sectionHeader("Health Care Services"),
                  const SizedBox(height: 16),
                  _buildServiceIcons(),

                  const SizedBox(height: 32),

                  _sectionHeader("Quick Actions"),
                  const SizedBox(height: 16),
                  _buildQuickActionGrid(),

                  const SizedBox(height: 32),

                  _sectionHeader("Medicine Schedule"),
                  const SizedBox(height: 16),
                  _buildMedicineCard(),

                  const SizedBox(height: 100), // Padding for Bottom Nav
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── COMPONENTS ─────────────────────────────────────────────────────

  Widget _buildStaticHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 25),
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(40)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _navigateToProfile,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getGreeting(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    Row(
                      children: [
                        Text(widget.username,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 12),
                      ],
                    ),
                  ],
                ),
              ),
              _buildNotificationBell(),
            ],
          ),
          const SizedBox(height: 20),
          _buildPillSearchBar(),
        ],
      ),
    );
  }

  Widget _buildOnDutySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("On Duty Today",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _textDark)),
            Text("Updated real-time",
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(
            children: [
              _staffTile("Dr. Maria Santos", "Doctor", "8:00 AM – 5:00 PM", Colors.green, "Available", Icons.medical_services_rounded),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Divider(height: 1, thickness: 1, color: Colors.grey.withOpacity(0.05)),
              ),
              _staffTile("Nurse Juan Dela Cruz", "Nurse", "8:00 AM – 5:00 PM", Colors.orange, "Busy", Icons.person_pin_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _staffTile(String name, String role, String time, Color statusColor, String statusLabel, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            height: 48, width: 48,
            decoration: BoxDecoration(color: _primary.withOpacity(0.05), shape: BoxShape.circle),
            child: Icon(icon, color: _primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _textDark)),
                Text("$role • $time", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(statusLabel.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.fiber_manual_record, color: Colors.green, size: 10),
              const SizedBox(width: 8),
              const Text("LIVE QUEUE", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.1)),
              const Spacer(),
              Text("Mar 28, 2026", style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _queueInfo("CURRENTLY SERVING", "A-123", _primary),
              Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.1)),
              _queueInfo("YOUR NUMBER", "A-124", _accent),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _primary.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 16, color: _primary),
                SizedBox(width: 8),
                Text("You're next • Est. Wait: 5 mins", style: TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      childAspectRatio: 2.3,
      children: [
        _actionBtn("Join Queue", Icons.add_circle_outline_rounded, () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const uKonekJoinQueuePage()));
        }),
        _actionBtn("Records", Icons.assignment_outlined, () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const uKonekHealthRecordsPage()));
        }),
        _actionBtn("Scheduler", Icons.alarm_on_outlined, () {}),
        _actionBtn("Updates", Icons.campaign_outlined, () {}),
      ],
    );
  }

  Widget _buildMedicineCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          _medRow("Amoxicillin", "08:00 AM", "UPCOMING", Colors.orange),
          const Divider(height: 32),
          _medRow("Vitamin C", "12:30 PM", "MISSED", Colors.red),
        ],
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────

  Widget _queueInfo(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
      ],
    );
  }

  Widget _medRow(String name, String time, String status, Color color) {
    return Row(
      children: [
        Container(
          height: 48, width: 48,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.medication_outlined, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _textDark)),
            Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ]),
        ),
        Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10)),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _primary, size: 22),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _textDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcons() {
    final services = [
      {'icon': Icons.medical_services_outlined, 'label': 'Consult'},
      {'icon': Icons.vaccines_outlined, 'label': 'Vax'},
      {'icon': Icons.monitor_heart_outlined, 'label': 'Checkup'},
      {'icon': Icons.child_care_outlined, 'label': 'Maternal'},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: services.map((s) => Column(
        children: [
          Container(
            height: 64, width: 64,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(s['icon'] as IconData, color: _primary, size: 28),
          ),
          const SizedBox(height: 10),
          Text(s['label'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
        ],
      )).toList(),
    );
  }

  Widget _buildPillSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 48,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(30)),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, color: Colors.white60, size: 22),
          SizedBox(width: 12),
          Text("Search health records...", style: TextStyle(color: Colors.white60, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
      child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
    );
  }

  String _getGreeting() {
    int hour = DateTime.now().hour;
    if (hour < 12) return "☀️ Good Morning,";
    if (hour < 17) return "🌤 Good Afternoon,";
    return "🌙 Good Evening,";
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _textDark, letterSpacing: -0.5));
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      selectedItemColor: _primary,
      unselectedItemColor: Colors.grey.shade400,
      currentIndex: _selectedTab,
      onTap: (i) {
        if (i == 3) _navigateToProfile();
        else setState(() => _selectedTab = i);
      },
      backgroundColor: Colors.white,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.event_note_rounded), label: "Medicine"),
        BottomNavigationBarItem(icon: Icon(Icons.confirmation_number_rounded), label: "Queue"),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: "Profile"),
      ],
    );
  }
}