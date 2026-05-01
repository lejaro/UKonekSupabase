import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ukonekmobile/uKonekMedicineScheduler.dart';
import 'services/api_service.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekHealthRecordsPage.dart';
import 'uKonekProfilePage.dart';
import 'uKonekMedicineScheduler.dart';
import 'uKonekFeedbackPage.dart';

// ── Design tokens ──────────────────────────────────────────────
class _C {
  static const primary = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const accent = Color(0xFF1976D2);
  static const bg = Color(0xFFF0F4FA);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1A2740);
  static const textMuted = Color(0xFF8A93A0);
  static const divider = Color(0xFFEEF1F6);
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
    this.email = 'juan.delacruz@email.com',
    this.phone = '0912 345 6789',
    this.address = 'Brgy. Ugong, Valenzuela City',
  });

  @override
  State<uKonekDashboardPage> createState() => _uKonekDashboardPageState();
}

class _uKonekDashboardPageState extends State<uKonekDashboardPage>
    with WidgetsBindingObserver {
  int _selectedTab = 0;
  late Future<List<DoctorSchedule>> _onDutyTodayFuture;
  late Future<QueueDashboardSnapshot> _queueDashboardFuture;
  late Future<List<PrescribedMedicine>> _prescribedMedicinesFuture;
  Timer? _onDutyRefreshTimer;

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => uKonekProfilePage(
          fullName: widget.username,
          email: widget.email,
          phone: widget.phone,
          address: widget.address,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onDutyTodayFuture = _loadOnDutyToday();
    _queueDashboardFuture = _loadQueueDashboard();
    _prescribedMedicinesFuture = _loadPrescribedMedicines();
    _onDutyRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshOnDutyToday();
      _refreshQueueDashboard();
      _refreshPrescribedMedicines();
    });
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onDutyRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOnDutyToday();
      _refreshQueueDashboard();
      _refreshPrescribedMedicines();
    }
  }

  void _refreshOnDutyToday() {
    if (!mounted) return;
    setState(() {
      _onDutyTodayFuture = _loadOnDutyToday();
    });
  }

  void _refreshPrescribedMedicines() {
    if (!mounted) return;
    setState(() {
      _prescribedMedicinesFuture = _loadPrescribedMedicines();
    });
  }

  Future<List<DoctorSchedule>> _loadOnDutyToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ApiService.listAvailableDoctorSchedules(from: today, to: today);
  }

  Future<QueueDashboardSnapshot> _loadQueueDashboard() {
    return ApiService.getMyQueueDashboard();
  }

  Future<List<PrescribedMedicine>> _loadPrescribedMedicines() {
    return ApiService.getMyPrescribedMedicines();
  }

  void _refreshQueueDashboard() {
    if (!mounted) return;
    setState(() {
      _queueDashboardFuture = _loadQueueDashboard();
    });
  }

  String _queueNumberText(int? number) {
    if (number == null || number <= 0) return '--';
    return '#${number.toString().padLeft(3, '0')}';
  }

  String _formatWaitTime(int minutes) {
    final value = minutes < 0 ? 0 : minutes;
    final h = value ~/ 60;
    final m = value % 60;
    if (h <= 0) return '$m mins';
    if (m == 0) return '$h hr';
    return '$h hr $m mins';
  }

  String _formatTime(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return hhmmss;
    final h24 = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1].padLeft(2, '0');
    final isPm = h24 >= 12;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:$minute ${isPm ? 'PM' : 'AM'}';
  }

  String _formatIssuedDate(DateTime value) {
    final d = value.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOnDutySection(),
                  const SizedBox(height: 24),
                  _buildQueueCard(),
                  const SizedBox(height: 28),
                  _sectionHeader('Health Care Services'),
                  const SizedBox(height: 14),
                  _buildServiceIcons(),
                  const SizedBox(height: 28),
                  _sectionHeader('Quick Actions'),
                  const SizedBox(height: 14),
                  _buildQuickActionGrid(),
                  const SizedBox(height: 28),
                  _sectionHeader('Medicine Schedule'),
                  const SizedBox(height: 14),
                  _buildMedicineCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid],
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
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _navigateToProfile,
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              widget.username.isNotEmpty
                                  ? widget.username[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  widget.username,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white54,
                                  size: 11,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildNotificationBell(),
                ],
              ),
              const SizedBox(height: 18),
              _buildSearchBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationBell() {
    return Stack(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: const Icon(
            Icons.notifications_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        Positioned(
          top: 9,
          right: 9,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252),
              shape: BoxShape.circle,
              border: Border.all(color: _C.primaryMid, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.search_rounded,
            color: Colors.white.withOpacity(0.6),
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            'Search health records...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── On Duty Section ──────────────────────────────────────────
  Widget _buildOnDutySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionHeader('On Duty Today'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _C.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _C.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 11,
                      color: _C.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _C.shadow,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FutureBuilder<List<DoctorSchedule>>(
            future: _onDutyTodayFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Loading today\'s doctors...',
                        style: TextStyle(color: _C.textMuted),
                      ),
                    ],
                  ),
                );
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.error_outline_rounded,
                            color: _C.warning,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Unable to load today\'s doctor schedule.',
                              style: TextStyle(
                                color: _C.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _refreshOnDutyToday,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _C.primaryMid,
                          side: BorderSide(
                            color: _C.primaryMid.withOpacity(0.25),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final schedules = snapshot.data ?? const <DoctorSchedule>[];
              if (schedules.isEmpty) {
                return SizedBox(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: const Center(
                    child: Text(
                      'No doctors are on duty today.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _C.textMuted, fontSize: 16),
                    ),
                  ),
                );
              }

              return Column(
                children: List.generate(schedules.length, (index) {
                  final item = schedules[index];
                  final specialization = item.specialization.trim().isEmpty
                      ? 'General Practice'
                      : item.specialization.trim();
                  final time =
                      '${_formatTime(item.startTime)} – ${_formatTime(item.endTime)}';

                  return Column(
                    children: [
                      _staffTile(
                        specialization,
                        time,
                        _C.success,
                        'Available',
                        Icons.medical_services_rounded,
                      ),
                      if (index < schedules.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Divider(height: 1, color: _C.divider),
                        ),
                    ],
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _staffTile(
    String specialization,
    String time,
    Color statusColor,
    String statusLabel,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _C.primaryMid.withOpacity(0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: _C.primaryMid, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  specialization,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _C.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              statusLabel.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Queue Card ───────────────────────────────────────────────
  Widget _buildQueueCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _C.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FutureBuilder<QueueDashboardSnapshot>(
        future: _queueDashboardFuture,
        builder: (context, snapshot) {
          final queue = snapshot.data ?? QueueDashboardSnapshot.empty;
          final hasQueue = queue.hasActiveQueue;

          return Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _C.success.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _C.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'LIVE QUEUE',
                          style: TextStyle(
                            color: _C.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      hasQueue
                          ? (queue.serviceLabel.isEmpty
                                ? 'Active Queue'
                                : queue.serviceLabel)
                          : 'Not in queue',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _queueInfo(
                    'CURRENTLY SERVING',
                    _queueNumberText(queue.currentlyServingQueueNumber),
                    _C.textMuted,
                  ),
                  Container(width: 1, height: 44, color: _C.divider),
                  _queueInfo(
                    'YOUR NUMBER',
                    _queueNumberText(queue.myQueueNumber),
                    _C.primary,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _C.primaryMid.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: _C.primaryMid),
                    const SizedBox(width: 8),
                    Text(
                      hasQueue
                          ? 'Est. Wait: ${_formatWaitTime(queue.estimatedWaitMinutes)}'
                          : 'Join queue to see your waiting time',
                      style: const TextStyle(
                        color: _C.primaryMid,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _queueInfo(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  // ── Services ─────────────────────────────────────────────────
  Widget _buildServiceIcons() {
    final services = [
      {
        'icon': Icons.medical_services_outlined,
        'label': 'Consult',
        'color': const Color(0xFF1565C0),
      },
      {
        'icon': Icons.vaccines_outlined,
        'label': 'Vaccine',
        'color': const Color(0xFF10B981),
      },
      {
        'icon': Icons.monitor_heart_outlined,
        'label': 'Check-up',
        'color': const Color(0xFFE53935),
      },
      {
        'icon': Icons.child_care_outlined,
        'label': 'Maternal',
        'color': const Color(0xFF7B1FA2),
      },
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: services.map((s) {
        final color = s['color'] as Color;
        return Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withOpacity(0.15)),
              ),
              child: Icon(s['icon'] as IconData, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              s['label'] as String,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _C.textDark,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── Quick Actions ────────────────────────────────────────────
  Widget _buildQuickActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 2.3,
      children: [
        _actionBtn(
          'Join Queue',
          Icons.add_circle_outline_rounded,
          const Color(0xFF1565C0),
          () async {
            final joined = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const uKonekJoinQueuePage()),
            );
            if (joined == true) {
              _refreshQueueDashboard();
            }
          },
        ),
        _actionBtn(
          'Records',
          Icons.assignment_outlined,
          const Color(0xFF10B981),
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const uKonekHealthRecordsPage()),
          ),
        ),
        _actionBtn(
          'Scheduler',
          Icons.alarm_on_outlined,
          const Color(0xFF7B1FA2),
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const uKonekMedicineSchedulerPage(),
            ),
          ),
        ),
        _actionBtn(
          'Feedback',
          Icons.feedback_outlined,
          const Color(0xFFF59E0B),
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const uKonekFeedbackPage()),
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _C.shadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: _C.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Medicine Card ────────────────────────────────────────────
  Widget _buildMedicineCard() {
    return FutureBuilder<List<PrescribedMedicine>>(
      future: _prescribedMedicinesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _C.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _C.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Text(
              'Unable to load prescribed medicines right now.',
              style: TextStyle(color: _C.textMuted, fontSize: 13),
            ),
          );
        }

        final medicines = (snapshot.data ?? const []).take(3).toList();
        if (medicines.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _C.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Text(
              'No prescribed medicines yet.',
              style: TextStyle(color: _C.textMuted, fontSize: 13),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _C.shadow,
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < medicines.length; i++) ...[
                _medRow(
                  medicines[i].medicineName,
                  '${medicines[i].quantityLabel} • ${_formatIssuedDate(medicines[i].issuedAt)}',
                  'PRESCRIBED',
                  _C.primaryMid,
                ),
                if (i < medicines.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: _C.divider),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _medRow(String name, String time, String status, Color color) {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.medication_outlined, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _C.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── Bottom Nav ───────────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.dashboard_rounded, 'label': 'Home'},
      {'icon': Icons.event_note_rounded, 'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () {
                  if (i == 1) {
                    Navigator.push(context, MaterialPageRoute(
                        builder: (context) => const uKonekMedicineSchedulerPage()));
                    return;
                  }
                  if (i == 3) {
                    _navigateToProfile();
                    return;
                  }
                  if (i == 2) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const uKonekJoinQueuePage(),
                      ),
                    ).then((_) => _refreshQueueDashboard());
                    return;
                  }
                  setState(() => _selectedTab = i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _C.primaryMid.withOpacity(0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected
                            ? _C.primaryMid
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: _C.primaryMid,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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

  // ── Helpers ──────────────────────────────────────────────────
  Widget _sectionHeader(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: _C.textDark,
      letterSpacing: -0.3,
    ),
  );

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return '☀️ Good Morning,';
    if (h < 17) return '🌤 Good Afternoon,';
    return '🌙 Good Evening,';
  }
}