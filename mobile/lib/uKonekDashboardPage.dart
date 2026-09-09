import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekHealthRecordsPage.dart';
import 'uKonekProfilePage.dart';
import 'uKonekFeedbackPage.dart';
import 'uKonekMedicineScheduler.dart';
import 'uKonekNotificationPage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'uKonekPrescriptionPage.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/app_transitions.dart';
import 'uKonekDoctorSchedulesPage.dart';
import 'uKonekMainShellPage.dart';

class _C {
  static const primary      = Color(0xFF059669); // Emerald 600
  static const primaryMid   = Color(0xFF064E3B); // Forest Emerald 900
  static const primaryLight = Color(0xFFECFDF5); // Mint 50
  static const bg           = Color(0xFFF8FAFC); // Slate 50
  static const surface      = Colors.white;
  static const textDark     = Color(0xFF0F172A); // Slate 900
  static const textMuted    = Color(0xFF64748B); // Slate 500
  static const divider      = Color(0xFFE2E8F0); // Slate 200
  static const success      = Color(0xFF10B981);
  static const warning      = Color(0xFFF59E0B);
  static const shadow       = Color(0x080F172A);
}

class _SkeletonPulse extends StatefulWidget {
  final Widget child;
  const _SkeletonPulse({required this.child});

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}

Widget _skeletonBox({double? width, required double height, double borderRadius = 8}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE2E8F0),
      borderRadius: BorderRadius.circular(borderRadius),
    ),
  );
}

class uKonekDashboardPage extends StatefulWidget {
  // ── Core fields ───────────────────────────────────────────────
  final String username;
  final String citizenId;
  final String fullname;

  // ── Registration fields (passed from OTP page after register) ─
  final String firstName;
  final String middleName;
  final String surname;
  final String nameExtension;
  final String dob;
  final String age;
  final String sex;
  final String email;
  final String phone;
  final String address;
  final String emergencyName;
  final String emergencyContact;
  final String relation;

  const uKonekDashboardPage({
    super.key,
    required this.username,
    required this.citizenId,
    this.fullname         = '',
    // Registration fields — all optional so login path still works
    this.firstName        = '',
    this.middleName       = '',
    this.surname          = '',
    this.nameExtension    = '',
    this.dob              = '',
    this.age              = '',
    this.sex              = '',
    this.email            = '',
    this.phone            = '',
    this.address          = '',
    this.emergencyName    = '',
    this.emergencyContact = '',
    this.relation         = '',
    this.isEmbeddedInShell = false,
  });

  final bool isEmbeddedInShell;

  @override
  State<uKonekDashboardPage> createState() => _uKonekDashboardPageState();
}

class _uKonekDashboardPageState extends State<uKonekDashboardPage>
    with WidgetsBindingObserver {
  int _selectedTab = 0;
  List<DoctorStatus> _doctors = [];
  QueueDashboardSnapshot _queueDashboard = QueueDashboardSnapshot.empty;
  List<PrescriptionRecord> _prescribedMedicines = [];
  List<Announcement> _announcements = [];
  bool _isInitialLoading = true;
  bool _hasUnseenNotifications = false;
  Timer? _refreshTimer;
  final Map<String, dynamic> _tvQueueDisplay = {};

  // ── Navigate to profile with ALL registration fields ──────────
  void _navigateToProfile() {
    if (widget.isEmbeddedInShell) {
      uKonekMainShellPage.switchTab(context, 3);
      return;
    }
    Navigator.push(
      context,
      AppPageRoute.slideRight(
        uKonekProfilePage(
          username:         widget.username,
          citizenId:        widget.citizenId,
          fullName:         widget.fullname,
          firstName:        widget.firstName,
          middleName:       widget.middleName,
          surname:          widget.surname,
          nameExtension:    widget.nameExtension,
          dob:              widget.dob,
          age:              widget.age,
          sex:              widget.sex,
          email:            widget.email,
          phone:            widget.phone,
          address:          widget.address,
          emergencyName:    widget.emergencyName,
          emergencyContact: widget.emergencyContact,
          relation:         widget.relation,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllData(isInitial: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 180), (_) {
      _loadAllData(isInitial: false);
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
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAllData(isInitial: false);
    }
  }

  Future<void> _loadAllData({bool isInitial = false}) async {
    if (!mounted) return;
    if (isInitial) setState(() => _isInitialLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        ApiService.listDoctorStatus(),
        ApiService.getMyQueueDashboard(),
        ApiService.fetchPrescriptions(limit: 10),
        ApiService.fetchAnnouncements(),
        SharedPreferences.getInstance(),
      ]);
      
      if (mounted) {
        final newQueueSnapshot = results[1] as QueueDashboardSnapshot;
        final announcements = results[3] as List<Announcement>;
        final prefs = results[4] as SharedPreferences;

        // Check for unseen notifications
        final lastViewedStr = prefs.getString('last_viewed_notifications');
        final clearedAtStr = prefs.getString('notifications_cleared_at');
        DateTime lastViewed = lastViewedStr != null ? DateTime.parse(lastViewedStr) : DateTime.fromMillisecondsSinceEpoch(0);
        if (clearedAtStr != null) {
          final clearedAt = DateTime.parse(clearedAtStr);
          if (clearedAt.isAfter(lastViewed)) lastViewed = clearedAt;
        }

        bool unseen = announcements.any((a) => a.createdAt.isAfter(lastViewed));
        
        // Also check if queue status is "new" to the user
        if (newQueueSnapshot.hasActiveQueue && lastViewedStr == null) {
          unseen = true;
        }
        
        // You could also check for medicine reminders here if needed


        final newStatus = newQueueSnapshot.status.toLowerCase();
        final ticketId = newQueueSnapshot.queueId;

        // Retrieve last notified ID and status to prevent duplicate notifications
        final lastNotifiedId = prefs.getInt('last_notified_ticket_id');
        final lastNotifiedStatus = prefs.getString('last_notified_status');

        // Trigger notification if status changed to on_call and we haven't notified for this ticket/status yet
        if (newStatus == 'on_call' && 
            (lastNotifiedId != ticketId || lastNotifiedStatus != 'on_call') && 
            newQueueSnapshot.hasActiveQueue) {
          
          await prefs.setInt('last_notified_ticket_id', ticketId ?? 0);
          await prefs.setString('last_notified_status', 'on_call');

          NotificationService.showImmediateNotification(
            id: 888, // Unique ID for queue alerts
            title: 'Your number is being called!',
            body: 'Please proceed to the nurse for your vital assessment.',
            payload: '{"action":"queue"}',
          );
        }

        setState(() {
          _doctors = results[0] as List<DoctorStatus>;
          _queueDashboard = newQueueSnapshot;
          _prescribedMedicines = results[2] as List<PrescriptionRecord>;
          _announcements = announcements;
          _hasUnseenNotifications = unseen;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      if (mounted && isInitial) setState(() => _isInitialLoading = false);
    }
  }

  void _showEPrescriptionModal(List<PrescriptionRecord> prescriptionItems) {
    if (prescriptionItems.isEmpty) return;
    
    final firstItem = prescriptionItems.first;
    final prescriptionCode = firstItem.prescriptionCode;
    final doctorName = firstItem.displayDoctorName;
    final issuedDate = DateFormat('MM/dd/yyyy').format(firstItem.issuedAt);
    final expiryDate = DateFormat('MM/dd/yyyy').format(firstItem.issuedAt.add(const Duration(days: 30)));
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E9E3), borderRadius: BorderRadius.circular(2))),
              ),
              Expanded(
                child: ListView(
                  controller: sc,
                  padding: const EdgeInsets.all(24),
                  children: [
                    // ── Clinic Header ──────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 50, height: 50,
                          decoration: const BoxDecoration(color: _C.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AFM ROQUERO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _C.primaryMid)),
                            Text('Medical Clinic', style: TextStyle(fontSize: 12, color: _C.textMuted)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: _C.divider),
                    const SizedBox(height: 16),

                    // ── Patient Info ───────────────────────────────────
                    const Text('PATIENT INFORMATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _C.primary, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    Text("${widget.firstName} ${widget.middleName} ${widget.surname} ${widget.nameExtension}".trim(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _C.textDark)),
                    const SizedBox(height: 4),
                    Text('ID: ${widget.citizenId}', style: const TextStyle(fontSize: 12, color: _C.textMuted)),
                    const SizedBox(height: 4),
                    Text('Doctor: $doctorName', style: const TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Prescription: $prescriptionCode', style: const TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600, fontFamily: 'monospace')),

                    const SizedBox(height: 24),

                    // ── Rx Symbol & Medications ──────────────────────────
                    const Text('℞', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: _C.primaryMid, height: 1)),
                    const SizedBox(height: 8),
                    const Text('PRESCRIBED MEDICATIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _C.primary, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    
                    // ── List all medicines in this prescription (filtering out dispensed ones) ──────────
                    ...prescriptionItems.where((item) => !item.isPrescriptionDispensed && !item.isDispensed).map((item) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: _C.bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _C.divider)
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.medicineName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.textDark)),
                          const SizedBox(height: 4),
                          Text(item.dosage.isNotEmpty ? item.dosage : 'As prescribed', 
                              style: const TextStyle(fontSize: 14, color: _C.primary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          const Divider(color: _C.divider),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: _C.textMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.instructions.isNotEmpty ? item.instructions : 'Follow doctor\'s verbal instructions.',
                                  style: const TextStyle(fontSize: 12, color: _C.textMuted, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                          if (item.frequency.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.schedule, size: 16, color: Color(0xFF637367)),
                                const SizedBox(width: 6),
                                Text('Frequency: ${item.frequency}', style: const TextStyle(fontSize: 12, color: Color(0xFF637367))),
                              ],
                            ),
                          ],
                          if (item.duration.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.history_rounded, size: 16, color: Color(0xFF637367)),
                                const SizedBox(width: 6),
                                Text('Duration: ${item.duration}', style: const TextStyle(fontSize: 12, color: Color(0xFF637367))),
                              ],
                            ),
                          ],
                          if (item.quantity > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF637367)),
                                const SizedBox(width: 6),
                                Text('Remaining: ${item.remainingQuantityLabel} of ${item.quantityLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFF637367))),
                              ],
                            ),
                          ],
                        ],
                      ),
                    )),

                    const SizedBox(height: 24),

                    // ── Prescription Details ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FCF9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD6E8DA)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ISSUED DATE:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _C.textMuted)),
                              Text(issuedDate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.textDark)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('EXPIRATION DATE:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF637367))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                child: Text(expiryDate, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Verification QR ────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          const Text('PHARMACY VERIFICATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _C.textMuted, letterSpacing: 1)),
                          const SizedBox(height: 12),
                          QrImageView(
                            data: prescriptionCode,
                            version: QrVersions.auto,
                            size: 140.0,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _C.primaryMid),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _C.primaryMid),
                          ),
                          const SizedBox(height: 12),
                          const Text('Digital Signature Verified', style: TextStyle(color: _C.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                        label: const Text('DISMISS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: _C.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              color: _C.primary,
              backgroundColor: Colors.white,
              displacement: 24,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                await _loadAllData(isInitial: false);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAnnouncements(),
                    /*const SizedBox(height: 24),
                    _buildQrSection(),*/
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionHeader('My Prescriptions'),
                        if (_prescribedMedicines.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.push(context, AppPageRoute.slideRight(const PrescriptionPage()));
                            },
                            child: const Text('View All', style: TextStyle(color: _C.primaryMid, fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildMedicineCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.isEmbeddedInShell ? null : _buildBottomNav(),
    );
  }

  Widget _buildAnnouncementsSkeleton() {
    return _SkeletonPulse(
      child: SizedBox(
        height: 140,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 2,
          itemBuilder: (context, index) {
            return Container(
              width: 280,
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _C.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBox(width: 90, height: 16, borderRadius: 6),
                  const SizedBox(height: 14),
                  _skeletonBox(width: 190, height: 16, borderRadius: 4),
                  const SizedBox(height: 8),
                  _skeletonBox(width: 230, height: 12, borderRadius: 4),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnnouncements() {
    if (_announcements.isEmpty && !_isInitialLoading) return const SizedBox.shrink();
    final tagColors = [_C.primary, _C.warning, const Color(0xFF0284C7), const Color(0xFF7C3AED)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Announcements'),
        const SizedBox(height: 14),
        _isInitialLoading
            ? _buildAnnouncementsSkeleton()
            : SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _announcements.length,
                  itemBuilder: (context, index) {
                    final item = _announcements[index];
                    final accentColor = tagColors[index % tagColors.length];
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
                            child: Text('ANNOUNCEMENT', style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ),
                          const SizedBox(height: 12),
                          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _C.textDark)),
                          const SizedBox(height: 4),
                          Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _C.textMuted, height: 1.3)),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF064E3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F064E3B),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _navigateToProfile();
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.20),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
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
                            fontWeight: FontWeight.w500,
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
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white60, size: 11),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showPatientQrModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_rounded, color: Colors.white, size: 16),
                          if (widget.citizenId.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text(
                              '#${widget.citizenId}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildNotificationBell(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPatientQrModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 30,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _C.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.badge_rounded, color: _C.primary, size: 22),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Patient Digital Pass',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _C.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Present this QR code at clinic reception or triage for instant check-in',
              textAlign: TextAlign.center,
              style: TextStyle(color: _C.textMuted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: widget.citizenId,
                    version: QrVersions.auto,
                    size: 190.0,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _C.primaryMid),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _C.primaryMid),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.fullname.isNotEmpty ? widget.fullname : widget.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _C.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _C.primaryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'CITIZEN ID: #${widget.citizenId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        color: _C.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBell() {
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_viewed_notifications', DateTime.now().toIso8601String());
        if (mounted) setState(() => _hasUnseenNotifications = false);
        
        if (!mounted) return;
        Navigator.push(
          context,
          AppPageRoute.slideRight(
            uKonekNotificationPage(
              username: widget.username,
              fullname: widget.fullname,
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _C.textDark.withOpacity(0.08), blurRadius: 10)],
            ),
            child: const Icon(Icons.notifications_none_rounded, color: _C.textDark, size: 24),
          ),
          if (_hasUnseenNotifications)
            Positioned(
              right: 0, top: 0,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: Colors.redAccent, 
                  shape: BoxShape.circle, 
                  border: Border.all(color: Colors.white, width: 2)
                ),
              ),
            ),
        ],
      ),
    );
  }



  Widget _buildDoctorSkeleton() {
    return _SkeletonPulse(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.divider),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _skeletonBox(width: 44, height: 44, borderRadius: 13),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBox(width: 130, height: 14, borderRadius: 4),
                      const SizedBox(height: 6),
                      _skeletonBox(width: 170, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                _skeletonBox(width: 70, height: 24, borderRadius: 8),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _C.divider),
            const SizedBox(height: 16),
            Row(
              children: [
                _skeletonBox(width: 44, height: 44, borderRadius: 13),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBox(width: 110, height: 14, borderRadius: 4),
                      const SizedBox(height: 6),
                      _skeletonBox(width: 150, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                _skeletonBox(width: 70, height: 24, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
              decoration: BoxDecoration(color: _C.success.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: _C.success, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('Live', style: TextStyle(fontSize: 11, color: _C.success, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _isInitialLoading
            ? _buildDoctorSkeleton()
            : Container(
                decoration: BoxDecoration(
                  color: _C.surface, 
                  borderRadius: BorderRadius.circular(24), 
                  border: Border.all(color: _C.divider, width: 1),
                  boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: _doctors.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No doctors on duty at the moment.', style: TextStyle(color: _C.textMuted, fontSize: 13))))
                    : Column(children: List.generate(_doctors.length, (i) {
                        final item = _doctors[i];
                        return Column(children: [
                          _staffTile(item.displayName, item.specialization, _getStatusColor(item.availabilityStatus), _getStatusLabel(item.availabilityStatus), Icons.medical_services_rounded),
                          if (i < _doctors.length - 1) const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(height: 1, color: _C.divider)),
                        ]);
                      })),
              ),
      ],
    );
  }

  Color  _getStatusColor(String s) => s.toLowerCase() == 'on_break' ? _C.warning : (s.toLowerCase() == 'unavailable' ? const Color(0xFF94A3B8) : _C.success);
  String _getStatusLabel(String s) => s.toLowerCase() == 'on_break' ? 'On Break' : (s.toLowerCase() == 'unavailable' ? 'Unavailable' : 'Available');

  Widget _staffTile(String name, String sub, Color color, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: _C.primary, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
          Text(sub.isEmpty ? 'General Physician' : sub, style: const TextStyle(color: _C.textMuted, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _buildQueueSkeleton() {
    return _SkeletonPulse(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.divider),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _skeletonBox(width: 90, height: 22, borderRadius: 8),
                _skeletonBox(width: 80, height: 14, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 24),
            _skeletonBox(width: 130, height: 40, borderRadius: 10),
            const SizedBox(height: 20),
            _skeletonBox(width: double.infinity, height: 42, borderRadius: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueCard() {
    if (_isInitialLoading) return _buildQueueSkeleton();

    final queue = _queueDashboard;
    final hasQueue = queue.hasActiveQueue;
    final statusColor = hasQueue ? _C.warning : _C.primary;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasQueue ? statusColor.withOpacity(0.35) : _C.divider,
          width: hasQueue ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasQueue ? statusColor.withOpacity(0.08) : _C.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      hasQueue
                        ? (queue.status.toLowerCase() == 'on_call' ? 'ON CALL' : 'ACTIVE TICKET')
                        : 'CLINIC QUEUE',
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                hasQueue ? queue.serviceLabel : 'Walk-in & Regular',
                style: const TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (hasQueue) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _queueInfo('YOUR TICKET NUMBER', _queueNumberText(queue.myQueueNumber), _C.primary),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _C.primaryLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFA7F3D0).withOpacity(0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined, size: 17, color: _C.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      queue.status.toLowerCase() == 'serving'
                        ? 'You are currently being served'
                        : (queue.status.toLowerCase() == 'on_call'
                            ? 'Please proceed to vital assessment station'
                            : 'Est. Wait: ${_formatWaitTime(queue.estimatedWaitMinutes)}  •  Ahead: ${queue.waitingCount > 0 ? queue.waitingCount : "0"}'),
                      style: const TextStyle(color: _C.primaryMid, fontWeight: FontWeight.bold, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (widget.isEmbeddedInShell) {
                  uKonekMainShellPage.switchTab(context, 2);
                } else {
                  Navigator.push(context, AppPageRoute.slideRight(uKonekJoinQueuePage(username: widget.username, citizenId: widget.citizenId)));
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Open Live Tracker', style: TextStyle(color: _C.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: _C.primary, size: 14),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.divider),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.how_to_reg_outlined, color: _C.textMuted, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Not currently in clinic queue',
                        style: TextStyle(color: _C.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        if (widget.isEmbeddedInShell) {
                          uKonekMainShellPage.switchTab(context, 2);
                        } else {
                          Navigator.push(
                            context,
                            AppPageRoute.slideRight(
                              uKonekJoinQueuePage(username: widget.username, citizenId: widget.citizenId),
                            ),
                          ).then((_) => _loadAllData(isInitial: false));
                        }
                      },
                      icon: const Icon(Icons.confirmation_number_outlined, size: 16, color: Colors.white),
                      label: const Text('Get a Queue Ticket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(color: _C.divider, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 4, height: 14,
                decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              const Text('CURRENTLY SERVING TICKETS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _C.textMuted, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),
          _buildCurrentlyServingTicketsList(),
          if (hasQueue && queue.status.toLowerCase() == 'on_call') ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9E6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFECB3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notification_important_rounded, color: Color(0xFFFF9800), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your number is being called! Please proceed to the nurse for vital assessment.',
                      style: TextStyle(color: Color(0xFF856404), fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentlyServingTicketsList() {
    final List<dynamic> servingList = _tvQueueDisplay['serving'] ?? [];
    if (servingList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 14, color: _C.textMuted),
            SizedBox(width: 6),
            Text(
              'No active clinic consultations at the moment.',
              style: TextStyle(color: _C.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(servingList.length, (index) {
              final t = servingList[index] as Map<String, dynamic>;
              final num = t['queue_number'] ?? 0;
              final numStr = '#${num.toString().padLeft(3, '0')}';
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withOpacity(0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  numStr,
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 14, 
                    fontWeight: FontWeight.w900, 
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _queueInfo(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
    ]);
  }

  Widget _buildServiceIcons() {
    final services = [
      {'icon': Icons.medical_services_outlined, 'label': 'Consult',  'color': const Color(0xFF059669), 'key': 'consult'},
      {'icon': Icons.vaccines_outlined,         'label': 'Vaccine',  'color': const Color(0xFF0284C7), 'key': 'vaccine'},
      {'icon': Icons.monitor_heart_outlined,    'label': 'Check-up', 'color': const Color(0xFFE11D48), 'key': 'checkup'},
      {'icon': Icons.child_care_outlined,       'label': 'Maternal', 'color': const Color(0xFF7C3AED), 'key': 'maternal'},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: services.map((s) {
        final color = s['color'] as Color;
        return GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            if (widget.isEmbeddedInShell) {
              uKonekMainShellPage.switchTab(context, 2);
              return;
            }
            final joined = await Navigator.push<bool>(
              context,
              AppPageRoute.slideRight(
                uKonekJoinQueuePage(
                  username: widget.username,
                  citizenId: widget.citizenId,
                  initialServiceKey: s['key'] as String,
                ),
              ),
            );
            if (joined == true) _loadAllData(isInitial: false);
          },
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.20), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(s['icon'] as IconData, color: color, size: 24),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(s['label'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.textDark)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildQuickActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 2.3,
      children: [
        _actionBtn('My Patient ID', Icons.qr_code_scanner_rounded, const Color(0xFF059669), () {
          _showPatientQrModal();
        }),
        _actionBtn('Health Records', Icons.assignment_outlined, const Color(0xFF0284C7), () =>
            Navigator.push(context, AppPageRoute.slideRight(const uKonekHealthRecordsPage()))),
        _actionBtn('Doctor Schedules', Icons.calendar_month_rounded, const Color(0xFF7C3AED), () =>
            Navigator.push(context, AppPageRoute.slideRight(const uKonekDoctorSchedulesPage()))),
        _actionBtn('Clinic Feedback', Icons.chat_bubble_outline_rounded, const Color(0xFFD97706), () =>
            Navigator.push(context, AppPageRoute.slideRight(const uKonekFeedbackPage()))),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.divider, width: 1),
          boxShadow: const [
            BoxShadow(
              color: _C.shadow, 
              blurRadius: 12, 
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _C.textDark,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicineSkeleton() {
    return _SkeletonPulse(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.divider),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _skeletonBox(width: 46, height: 46, borderRadius: 13),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBox(width: 130, height: 14, borderRadius: 4),
                      const SizedBox(height: 6),
                      _skeletonBox(width: 80, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                _skeletonBox(width: 75, height: 22, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicineCard() {
    // Only show medicines that are not yet dispensed on the dashboard summary
    final medicines = _prescribedMedicines
        .where((m) => !m.isPrescriptionDispensed && !m.isDispensed)
        .take(3)
        .toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surface, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: _C.divider, width: 1),
        boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: _isInitialLoading
          ? _buildMedicineSkeleton()
          : (medicines.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No active prescriptions to claim.', style: TextStyle(color: _C.textMuted, fontSize: 13)),
                  ),
                )
              : Column(children: [
                  for (var i = 0; i < medicines.length; i++) ...[
                    _medRow(medicines[i]),
                    if (i < medicines.length - 1) const Divider(height: 28, color: _C.divider),
                  ],
                ])),
    );
  }

  Widget _medRow(PrescriptionRecord record) {
    final name = record.medicineName;
    final sub = record.remainingQuantityLabel;
    final isPartial = record.isPartial;
    final status = isPartial ? 'PARTIAL' : 'PRESCRIBED';
    final color = isPartial ? _C.warning : _C.primary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final group = _prescribedMedicines.where((m) => m.prescriptionId == record.prescriptionId).toList();
        _showEPrescriptionModal(group.isNotEmpty ? group : [record]);
      },
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        Container(height: 46, width: 46, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.medication_outlined, color: color, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
          Text(sub,  style: const TextStyle(color: _C.textMuted, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10)),
        ),
      ]),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded,                'label': 'Home'},
      {'icon': Icons.event_note_rounded,          'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded,      'label': 'Profile'},
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.only(
          topLeft:  Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [BoxShadow(color: _C.shadow, blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedTab = i);
                    if (i == 0) {
                      // Already on Home
                    } else if (i == 1) {
                      Navigator.push(context, AppPageRoute.slideRight(
                        uKonekMedicineSchedulerPage(
                          username:  widget.username,
                          citizenId: widget.citizenId,
                        ),
                      )).then((_) => setState(() => _selectedTab = 0));
                    } else if (i == 2) {
                      Navigator.push(context, AppPageRoute.slideRight(
                        uKonekJoinQueuePage(
                          username:  widget.username,
                          citizenId: widget.citizenId,
                        ),
                      )).then((_) {
                        _loadAllData(isInitial: false);
                        setState(() => _selectedTab = 0);
                      });
                    } else if (i == 3) {
                      _navigateToProfile();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted) setState(() => _selectedTab = 0);
                      });
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? _C.primaryLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tabs[i]['icon'] as IconData,
                          color: isSelected ? _C.primary : const Color(0xFF94A3B8),
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tabs[i]['label'] as String,
                          style: TextStyle(
                            color: isSelected ? _C.primary : const Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
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
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.textDark, letterSpacing: -0.3),
  );

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return '☀️ Good Morning,';
    if (h < 17) return '🌤 Good Afternoon,';
    return '🌙 Good Evening,';
  }

  String _queueNumberText(int? n) => (n == null || n <= 0) ? '--' : '#${n.toString().padLeft(3, '0')}';
  String _formatWaitTime(int m)   => (m ~/ 60) <= 0 ? '$m mins' : '${m ~/ 60} hr ${m % 60} mins';
}