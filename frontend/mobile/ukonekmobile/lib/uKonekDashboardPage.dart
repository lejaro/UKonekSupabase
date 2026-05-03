import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/api_service.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekHealthRecordsPage.dart';
import 'uKonekProfilePage.dart';
import 'uKonekFeedbackPage.dart';
import 'uKonekMedicineScheduler.dart';

// ── Medical Green Design tokens ────────────────────────────────
class _C {
  static const primary = Color(0xFF28A745);      // Health Green
  static const primaryMid = Color(0xFF1B5E20);   // Forest Green
  static const accent = Color(0xFF20C997);       // Mint Accent
  static const bg = Color(0xFFF8FCF9);           // Mint-tinted Background
  static const surface = Colors.white;
  static const textDark = Color(0xFF1B2E1E);     // Dark Forest Charcoal
  static const textMuted = Color(0xFF637367);    // Muted Sage
  static const divider = Color(0xFFE2E9E3);      // Light Mist Divider
  static const success = Color(0xFF28A745);
  static const warning = Color(0xFFF59E0B);
  static const shadow = Color(0x0A000000);
}

class uKonekDashboardPage extends StatefulWidget {
  final String username;
  final String fullname;
  final String citizenId;
  final String email;
  final String phone;
  final String address;

  const uKonekDashboardPage({
    super.key,
    required this.username,
    required this.citizenId,
    this.fullname = '',       // ← optional with default, fixes all 3 errors
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
  late Future<List<DoctorStatus>> _doctorStatusFuture;
  late Future<QueueDashboardSnapshot> _queueDashboardFuture;
  late Future<List<PrescribedMedicine>> _prescribedMedicinesFuture;
  Timer? _onDutyRefreshTimer;

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => uKonekProfilePage(
          username: widget.username,
          citizenId: widget.citizenId,
          fullName: widget.fullname,
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
    _doctorStatusFuture = _loadDoctorStatus();
    _queueDashboardFuture = _loadQueueDashboard();
    _prescribedMedicinesFuture = _loadPrescribedMedicines();
    _onDutyRefreshTimer = Timer.periodic(const Duration(seconds: 9), (_) {
      _refreshDoctorStatus();
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
      _refreshDoctorStatus();
      _refreshQueueDashboard();
      _refreshPrescribedMedicines();
    }
  }

  void _refreshDoctorStatus() {
    if (!mounted) return;
    setState(() { _doctorStatusFuture = _loadDoctorStatus(); });
  }

  void _refreshPrescribedMedicines() {
    if (!mounted) return;
    setState(() { _prescribedMedicinesFuture = _loadPrescribedMedicines(); });
  }

  void _refreshQueueDashboard() {
    if (!mounted) return;
    setState(() { _queueDashboardFuture = _loadQueueDashboard(); });
  }

  Future<List<DoctorStatus>> _loadDoctorStatus() => ApiService.listDoctorStatus();
  Future<QueueDashboardSnapshot> _loadQueueDashboard() => ApiService.getMyQueueDashboard();
  Future<List<PrescribedMedicine>> _loadPrescribedMedicines() => ApiService.getMyPrescribedMedicines();

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
                  _buildAnnouncements(), // Horizontal Announcement Section
                  const SizedBox(height: 24),
                  _buildQrSection(),
                  const SizedBox(height: 20),
                  _buildDoctorStatusSection(),
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
                  _sectionHeader('Recent Prescriptions'),
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

  // ── Announcement Section ─────────────────────────────────────
  Widget _buildAnnouncements() {
    final announcements = [
      {
        'title': 'Free Dental Checkup',
        'desc': 'Available for Brgy. Ugong residents this Friday.',
        'tag': 'HEALTH ADVISORY',
        'color': _C.primary,
      },
      {
        'title': 'System Maintenance',
        'desc': 'U-Konek+ will be offline on Sunday, 2AM-4AM.',
        'tag': 'MAINTENANCE',
        'color': _C.warning,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Announcements'),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final item = announcements[index];
              final Color accentColor = item['color'] as Color;

              return Container(
                width: 280,
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _C.divider),
                  boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(item['tag'] as String, style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 12),
                    Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _C.textDark)),
                    const SizedBox(height: 4),
                    Text(item['desc'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _C.textMuted, height: 1.3)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Header Component ────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid], //
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
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
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.4)),
                          ),
                          child: Center(
                            child: Text(
                              widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_getGreeting(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Row(
                              children: [
                                Text(widget.username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 11),
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
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
        ),
        Positioned(
          top: 9, right: 9,
          child: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: const Color(0xFFFF5252), shape: BoxShape.circle, border: Border.all(color: _C.primaryMid, width: 1.5)),
          ),
        ),
      ],
    );
  }



  Widget _buildQrSection() {
    if (widget.citizenId.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(
                data: widget.citizenId,
                version: QrVersions.auto,
                size: 160.0,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _C.primaryMid),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _C.primaryMid),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Your Citizen QR Code', style: TextStyle(color: _C.textDark, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Scan for check-in at the health center', textAlign: TextAlign.center, style: TextStyle(color: _C.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── Doctor Status ───────────────────────────────────────────
  Widget _buildDoctorStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionHeader('Doctor Status'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _C.success.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                // Error fix: removed 'const'
                Container(width: 6, height: 6, decoration: BoxDecoration(color: _C.success, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('Live', style: TextStyle(fontSize: 11, color: _C.success, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))]),
          child: FutureBuilder<List<DoctorStatus>>(
            future: _doctorStatusFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
              final doctors = snapshot.data ?? const [];
              if (doctors.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No doctors on duty.', style: TextStyle(color: _C.textMuted))));

              return Column(children: List.generate(doctors.length, (i) {
                final item = doctors[i];
                return Column(children: [
                  _staffTile(item.displayName, item.specialization, _getStatusColor(item.availabilityStatus), _getStatusLabel(item.availabilityStatus), Icons.medical_services_rounded),
                  if (i < doctors.length - 1) const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(height: 1, color: _C.divider)),
                ]);
              }));
            },
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String s) => s.toLowerCase() == 'on_break' ? _C.warning : (s.toLowerCase() == 'unavailable' ? Colors.grey : _C.success);
  String _getStatusLabel(String s) => s.toLowerCase() == 'on_break' ? 'On Break' : (s.toLowerCase() == 'unavailable' ? 'Offline' : 'Online');

  Widget _staffTile(String name, String sub, Color color, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: _C.primaryMid.withOpacity(0.08), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: _C.primaryMid, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
          Text(sub.isEmpty ? 'General Physician' : sub, style: const TextStyle(color: _C.textMuted, fontSize: 11)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)), child: Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  // ── Queue Component ──────────────────────────────────────────
  Widget _buildQueueCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))]),
      child: FutureBuilder<QueueDashboardSnapshot>(
        future: _queueDashboardFuture,
        builder: (context, snapshot) {
          final queue = snapshot.data ?? QueueDashboardSnapshot.empty;
          final hasQueue = queue.hasActiveQueue;
          Color statusColor = hasQueue ? _C.warning : _C.success;

          return Column(children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.10), borderRadius: BorderRadius.circular(8)), child: Row(children: [
                // Error fix: removed 'const'
                Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(hasQueue ? 'ACTIVE QUEUE' : 'LIVE QUEUE', style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 10)),
              ])),
              const Spacer(),
              Text(hasQueue ? queue.serviceLabel : 'Not in queue', style: const TextStyle(color: _C.textMuted, fontSize: 11)),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _queueInfo('CURRENTLY SERVING', _queueNumberText(queue.currentlyServingQueueNumber), _C.textMuted),
              Container(width: 1, height: 44, color: _C.divider),
              _queueInfo('YOUR NUMBER', _queueNumberText(queue.myQueueNumber), hasQueue ? _C.primaryMid : _C.textMuted),
            ]),
            const SizedBox(height: 20),
            Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _C.primaryMid.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.timer_outlined, size: 16, color: _C.primaryMid),
                const SizedBox(width: 8),
                Text(hasQueue ? 'Est. Wait: ${_formatWaitTime(queue.estimatedWaitMinutes)}' : 'Join queue to view waiting time', style: const TextStyle(color: _C.primaryMid, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _queueInfo(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.w900)),
    ]);
  }

  // ── Services ─────────────────────────────────────────────────
  Widget _buildServiceIcons() {
    final services = [
      {'icon': Icons.medical_services_outlined, 'label': 'Consult', 'color': const Color(0xFF28A745)},
      {'icon': Icons.vaccines_outlined, 'label': 'Vaccine', 'color': const Color(0xFF17A2B8)},
      {'icon': Icons.monitor_heart_outlined, 'label': 'Check-up', 'color': const Color(0xFFDC3545)},
      {'icon': Icons.child_care_outlined, 'label': 'Maternal', 'color': const Color(0xFF6F42C1)},
    ];
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: services.map((s) {
      final color = s['color'] as Color;
      return Column(children: [
        Container(width: 62, height: 62, decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(0.15))), child: Icon(s['icon'] as IconData, color: color, size: 28)),
        const SizedBox(height: 8),
        Text(s['label'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _C.textDark)),
      ]);
    }).toList());
  }

  // ── Quick Actions ────────────────────────────────────────────
  Widget _buildQuickActionGrid() {
    return GridView.count(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 2.3,
      children: [
        _actionBtn('Join Queue', Icons.add_circle_outline_rounded, _C.primary, () async {
          final joined = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) =>  uKonekJoinQueuePage(
              username: widget.username, // Provide the required parameter
              citizenId: widget.citizenId
          )));
          if (joined == true) _refreshQueueDashboard();
        }),
        _actionBtn('Records', Icons.assignment_outlined, const Color(0xFF17A2B8), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const uKonekHealthRecordsPage()))),
        _actionBtn('Scheduler', Icons.alarm_on_outlined, const Color(0xFF6F42C1), () => Navigator.push(context, MaterialPageRoute(builder: (_) =>  uKonekMedicineSchedulerPage(
            username: widget.username, // Provide the required parameter
            citizenId: widget.citizenId
        )))),
        _actionBtn('Feedback', Icons.feedback_outlined, const Color(0xFFF59E0B), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const uKonekFeedbackPage()))),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 10, offset: Offset(0, 4))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _C.textDark)),
        ]),
      ),
    );
  }

  // ── Medicine Section ─────────────────────────────────────────
  Widget _buildMedicineCard() {
    return FutureBuilder<List<PrescribedMedicine>>(
      future: _prescribedMedicinesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        final medicines = (snapshot.data ?? const []).take(3).toList();
        if (medicines.isEmpty) return const Text('No recent prescriptions.', style: TextStyle(color: _C.textMuted));

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 14, offset: Offset(0, 5))]),
          child: Column(children: [
            for (var i = 0; i < medicines.length; i++) ...[
              _medRow(medicines[i].medicineName, medicines[i].quantityLabel, 'PRESCRIBED', _C.primaryMid),
              if (i < medicines.length - 1) const Divider(height: 28, color: _C.divider),
            ],
          ]),
        );
      },
    );
  }

  Widget _medRow(String name, String sub, String status, Color color) {
    return Row(children: [
      Container(height: 46, width: 46, decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.medication_outlined, color: color, size: 22)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
        Text(sub, style: const TextStyle(color: _C.textMuted, fontSize: 11)),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10))),
    ]);
  }

  // ── Navigation and Helpers ────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.dashboard_rounded, 'label': 'Home'},
      {'icon': Icons.event_note_rounded, 'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: _C.shadow, blurRadius: 20, offset: Offset(0, -4))],
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
                  setState(() => _selectedTab = i); // ✅ Fix: update selected tab
                  if (i == 1) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => uKonekMedicineSchedulerPage(
                          username: widget.username,
                          citizenId: widget.citizenId,
                        ),
                      ),
                    );
                  } else if (i == 2) { // ✅ Fix: was missing 'else', causing fall-through to i==3
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => uKonekJoinQueuePage(
                          username: widget.username,
                          citizenId: widget.citizenId,
                        ),
                      ),
                    ).then((_) => _refreshQueueDashboard());
                  } else if (i == 3) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => uKonekProfilePage(
                          username: widget.username,
                          citizenId: widget.citizenId,
                          fullName: widget.fullname,
                        ),
                      ),
                    );
                  }
                  // i == 0 (Home): no navigation needed, setState above is enough
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _C.primaryMid.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(tabs[i]['icon'] as IconData, color: isSelected ? _C.primaryMid : Colors.grey.shade400, size: 22),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      Text(tabs[i]['label'] as String, style: const TextStyle(color: _C.primaryMid, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
    title,
    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.textDark, letterSpacing: -0.3),
  );

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return '☀️ Good Morning,';
    if (h < 17) return '🌤 Good Afternoon,';
    return '🌙 Good Evening,';
  }

  String _queueNumberText(int? n) => (n == null || n <= 0) ? '--' : '#${n.toString().padLeft(3, '0')}';
  String _formatWaitTime(int m) => (m ~/ 60) <= 0 ? '$m mins' : '${m ~/ 60} hr ${m % 60} mins';
}