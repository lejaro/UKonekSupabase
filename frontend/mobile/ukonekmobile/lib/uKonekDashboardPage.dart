import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ukonekmobile/uKonekHealthRecords.dart';
import 'package:ukonekmobile/uKonekProfilePage.dart';
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

  // Modern additions
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const shadow = Color(0x0A000000);
}

class uKonekDashboardPage extends StatefulWidget {
  final String username;
  final String email;
  final String phone;
  final String address;

  const uKonekDashboardPage({
    super.key,
    required this.username,
    this.email = "Not provided",
    this.phone = "Not provided",
    this.address = "Barangay Ugong, Valenzuela",
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildQueueStatusCard(),
                      const SizedBox(height: 32),
                      _buildActionGrid(),
                      const SizedBox(height: 32),
                      _sectionHeader("Today's Medications"),
                      const SizedBox(height: 12),
                      _buildMedicationSection(),
                      const SizedBox(height: 32),
                      _sectionHeader("Health Services"),
                      const SizedBox(height: 16),
                      _buildServicesGrid(),
                      const SizedBox(height: 32),
                      _sectionHeader("Health Updates"),
                      const SizedBox(height: 12),
                      _buildAnnouncements(),
                      const SizedBox(height: 32),
                      _sectionHeader("Recent Activity"),
                      const SizedBox(height: 12),
                      _buildRecentActivity(),
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
          colors: [_C.primary, _C.primaryMid, _C.primaryLight],
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            children: [
              // Top row with greeting and notification
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  _buildNotificationButton(),
                ],
              ),
              const SizedBox(height: 20),
              // Search bar
              _buildSearchBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return Stack(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: const Icon(Icons.notifications_outlined,
              color: Colors.white, size: 20),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _C.heartRed,
              shape: BoxShape.circle,
              border: Border.all(color: _C.primaryLight, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: _C.heartRed.withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.search_rounded,
              color: Colors.white.withOpacity(0.6), size: 20),
          const SizedBox(width: 10),
          Text(
            "Search doctors, services...",
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ── QUEUE STATUS CARD ──────────────────────────────────────────────────
  Widget _buildQueueStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _C.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Your Queue No.",
                    style: TextStyle(
                      color: _C.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "A-124",
                    style: const TextStyle(
                      color: _C.primary,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _C.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: _C.success),
                    SizedBox(width: 6),
                    Text(
                      "You're next",
                      style: TextStyle(
                        color: _C.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 0.8,
            color: _C.divider,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _queueInfoItem("Now Serving", "A-123"),
              Container(width: 0.8, height: 30, color: _C.divider),
              _queueInfoItem("Est. Wait", "5 mins"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _queueInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _C.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _C.textDark,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ── ACTION GRID ────────────────────────────────────────────────────────
  Widget _buildActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.4,
      children: [
        _actionCard(
          "Join Queue",
          Icons.group_add_rounded,
          isPrimary: true,
          onTap: () => _showJoinQueueSheet(),
        ),
        _actionCard(
          "Health Records",
          Icons.folder_open_rounded,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const HealthRecordsPage(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _actionCard(
      String title,
      IconData icon, {
        bool isPrimary = false,
        VoidCallback? onTap,
      }) {
    return Material(
      child: InkWell(
        onTap: onTap ?? () => _showComingSoon(title),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isPrimary ? _C.primaryMid : _C.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: isPrimary
                    ? _C.primaryMid.withOpacity(0.2)
                    : _C.shadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isPrimary ? Colors.white : _C.primaryMid,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isPrimary ? Colors.white : _C.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MEDICATIONS ───────────────────────────────────────────────────────
  Widget _buildMedicationSection() {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _C.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _medicationTile("Amoxicillin", "8:00 AM", true),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 0.8, color: _C.divider),
                ),
                _medicationTile("Vitamin C", "12:30 PM", false),
              ],
            ),
          ),
          Divider(height: 0.8, color: _C.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text("Add Medication"),
              style: TextButton.styleFrom(
                foregroundColor: _C.primaryMid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medicationTile(String name, String time, bool taken) {
    return Row(
      children: [
        Transform.scale(
          scale: 1.1,
          child: Checkbox(
            value: taken,
            onChanged: (v) {},
            activeColor: _C.primaryMid,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _C.textDark,
                  decoration: taken ? TextDecoration.lineThrough : null,
                  decorationColor: _C.textMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 12,
                  color: _C.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: taken
                ? _C.success.withOpacity(0.12)
                : _C.warning.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            taken ? "Taken" : "Upcoming",
            style: TextStyle(
              fontSize: 11,
              color: taken ? _C.success : _C.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ── HEALTH SERVICES GRID ──────────────────────────────────────────────
  Widget _buildServicesGrid() {
    final services = [
      {'icon': Icons.medical_services_outlined, 'label': 'Consultation'},
      {'icon': Icons.vaccines_outlined, 'label': 'Vaccination'},
      {'icon': Icons.monitor_heart_outlined, 'label': 'Check-up'},
      {'icon': Icons.child_care_rounded, 'label': 'Maternal'},
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.9,
      children: services.map((s) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.primaryMid.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                s['icon'] as IconData,
                color: _C.primaryMid,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s['label'] as String,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: _C.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── ANNOUNCEMENTS ──────────────────────────────────────────────────────
  Widget _buildAnnouncements() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _C.primaryLight,
            _C.primaryMid,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _C.primaryMid.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Health Advisory: Flu Season",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Free flu shots available this Friday at the Barangay Hall.",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── RECENT ACTIVITY ───────────────────────────────────────────────────
  Widget _buildRecentActivity() {
    return Column(
      children: [
        _activityTile(
          "Dental Check-up",
          "Completed • March 20",
          Icons.check_circle_rounded,
          _C.success,
        ),
        const SizedBox(height: 8),
        _activityTile(
          "Queue No. A-045",
          "Last Week • March 15",
          Icons.history_rounded,
          _C.textMuted,
        ),
      ],
    );
  }

  Widget _activityTile(
      String title,
      String sub,
      IconData icon,
      Color iconColor,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.divider, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _C.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _C.textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 18, color: _C.divider),
        ],
      ),
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
          top: BorderSide(color: _C.divider, width: 0.8),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: _C.shadow,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTab = i);
                  if (i == 3) {
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
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _C.primaryMid.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _C.primaryMid : _C.textMuted,
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: _C.primaryMid,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
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

  // ── SECTION HEADER ─────────────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _C.textDark,
        letterSpacing: -0.3,
      ),
    );
  }

  // ── QUEUE SHEET ────────────────────────────────────────────────────────
  void _showJoinQueueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _C.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Join Medical Queue",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _C.primary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Select the service you need today",
                  style: TextStyle(
                    color: _C.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 24),
                _queueOptionTile(
                  "General Consultation",
                  "Est. Wait: 15 mins",
                  Icons.medical_services_outlined,
                ),
                _queueOptionTile(
                  "Vaccination/Immunization",
                  "Est. Wait: 5 mins",
                  Icons.vaccines_outlined,
                ),
                _queueOptionTile(
                  "Maternal & Child Care",
                  "Est. Wait: 10 mins",
                  Icons.child_care_rounded,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primaryMid,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _processQueueJoin();
                    },
                    child: const Text(
                      "Confirm & Get Ticket",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _queueOptionTile(
      String title,
      String wait,
      IconData icon,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border.all(color: _C.divider, width: 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _C.primaryMid.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _C.primaryMid, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: _C.textDark,
          ),
        ),
        subtitle: Text(
          wait,
          style: const TextStyle(
            fontSize: 12,
            color: _C.textMuted,
          ),
        ),
        trailing: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            border: Border.all(color: _C.primaryMid, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  void _processQueueJoin() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: _C.primaryMid),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    Navigator.pop(context);

    _showTicketDialog("A-124", "General Consultation");

    setState(() {});
  }

  void _showTicketDialog(String queueNo, String service) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_C.primary, _C.primaryMid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Queue Ticket",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateTime.now().toString().split(' ')[0],
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Text(
                    service,
                    style: const TextStyle(
                      color: _C.textMuted,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    queueNo,
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      color: _C.primary,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: _C.divider, width: 2),
                      borderRadius: BorderRadius.circular(16),
                      color: _C.bg,
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 100,
                      color: _C.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Scan this at the reception desk",
                    style: TextStyle(
                      fontSize: 12,
                      color: _C.textMuted,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primaryMid,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Close and Save",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────���───────────────────────
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "☀️ Good Morning,";
    if (hour < 17) return "🌤 Good Afternoon,";
    return "🌙 Good Evening,";
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$feature — coming soon!"),
        backgroundColor: _C.primaryMid,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Log Out",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: const Text(
          "Are you sure you want to log out?",
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.primaryMid,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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