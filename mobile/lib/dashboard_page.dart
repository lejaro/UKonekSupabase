import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/api_service.dart';
import 'join_queue_page.dart';
import 'health_records_page.dart';
import 'profile_page.dart';
import 'feedback_page.dart';
import 'medicine_scheduler_page.dart';
import 'notification_page.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'prescription_page.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/app_transitions.dart';
import 'core/navigation/shell_navigation.dart';
import 'core/theme/app_colors.dart';

typedef _C = AppColors;


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
  RealtimeChannel? _dashboardQueueRealtimeChannel;
  RealtimeChannel? _doctorAvailabilityChannel;
  int? _subscribedTicketId;
  final Map<String, dynamic> _tvQueueDisplay = {};
  late final PageController _promoPageController;
  int _currentPromoPage = 0;

  // ── Navigate to profile with ALL registration fields ──────────
  void _navigateToProfile() {
    if (widget.isEmbeddedInShell) {
      ShellNavigation.switchTab(ShellNavigation.tabProfile);
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
    _promoPageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    _loadAllData(isInitial: true);
    _subscribeDoctorAvailabilityRealtime();
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
    _promoPageController.dispose();
    _refreshTimer?.cancel();
    _unsubscribeDashboardQueueRealtime();
    _unsubscribeDoctorAvailabilityRealtime();
    super.dispose();
  }

  void _subscribeDashboardQueueRealtime(int? ticketId) {
    if (ticketId == null || !mounted) return;
    if (_dashboardQueueRealtimeChannel != null && _subscribedTicketId == ticketId) return;
    _unsubscribeDashboardQueueRealtime();

    try {
      final client = Supabase.instance.client;
      _subscribedTicketId = ticketId;
      _dashboardQueueRealtimeChannel = client
          .channel('dashboard_queue_ticket_$ticketId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'queue_tickets',
            callback: (payload) {
              final rec = payload.newRecord;
              if (rec.isEmpty || !mounted) return;
              final id = (rec['id'] as num?)?.toInt();
              final status = (rec['status'] ?? '').toString().toLowerCase().trim();

              if (id == ticketId) {
                if (status == 'serving') {
                  HapticFeedback.heavyImpact();
                  NotificationService.showImmediateNotification(
                    id: 889,
                    title: 'Now Serving! Please proceed.',
                    body: 'Your ticket is now being served. Please proceed to the consultation room.',
                    payload: '{"action":"queue"}',
                  );
                } else if (status == 'on_call') {
                  HapticFeedback.mediumImpact();
                  NotificationService.showImmediateNotification(
                    id: 888,
                    title: 'Your number is being called!',
                    body: 'Please proceed to the nurse for your vital assessment.',
                    payload: '{"action":"queue"}',
                  );
                } else if (const {'completed', 'finished', 'done'}.contains(status)) {
                  NotificationService.showImmediateNotification(
                    id: 890,
                    title: 'Consultation Completed!',
                    body: 'Your consultation has been completed. Prescriptions and instructions are ready.',
                    payload: '{"action":"consultation_done"}',
                  );
                }
                _loadAllData(isInitial: false);
              } else if (status == 'serving' || status == 'completed') {
                _loadAllData(isInitial: false);
              }
            },
          )
          .subscribe();
      debugPrint('[Dashboard Queue Realtime] Subscribed to ticket $ticketId');
    } catch (e) {
      debugPrint('Error subscribing dashboard queue realtime: $e');
    }
  }

  void _unsubscribeDashboardQueueRealtime() {
    if (_dashboardQueueRealtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_dashboardQueueRealtimeChannel!);
        debugPrint('[Dashboard Queue Realtime] Unsubscribed channel successfully.');
      } catch (_) {}
      _dashboardQueueRealtimeChannel = null;
      _subscribedTicketId = null;
    }
  }

  void _subscribeDoctorAvailabilityRealtime() {
    if (_doctorAvailabilityChannel != null) return;

    try {
      final client = Supabase.instance.client;
      _doctorAvailabilityChannel = client
          .channel('dashboard-staff-availability')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'staff',
            callback: (payload) {
              final record = payload.newRecord;
              if (record.isEmpty || !mounted) return;

              final staffId = (record['id'] as num?)?.toInt();
              final role = (record['role'] ?? '').toString().toLowerCase().trim();
              final isKnownDoctor = staffId != null && _doctors.any((d) => d.id == staffId);
              final isDoctorOrNurse = role == 'doctor' || role == 'nurse';

              if (role.isNotEmpty && !isDoctorOrNurse && !isKnownDoctor) return;

              debugPrint('[Dashboard] Doctor status changed in realtime (id: $staffId, role: $role). Updating UI...');

              // Instant local UI update if availability_status is present
              final newStatus = (record['availability_status'] ?? '').toString().toLowerCase().trim();
              if (staffId != null && newStatus.isNotEmpty && mounted) {
                setState(() {
                  _doctors = _doctors.map((d) {
                    if (d.id == staffId) {
                      return d.copyWith(availabilityStatus: newStatus);
                    }
                    return d;
                  }).toList();
                });
              }

              ApiService.invalidateDoctorCache();
              _refreshDoctorListSilently();
            },
          )
          .subscribe((status, [error]) {
            debugPrint('[Dashboard Staff Realtime] Subscription status: $status${error != null ? ', error: $error' : ''}');
          });
      debugPrint('[Dashboard Staff Realtime] Subscribed to staff availability.');
    } catch (e) {
      debugPrint('Error subscribing to doctor availability realtime: $e');
    }
  }

  Future<void> _refreshDoctorListSilently() async {
    try {
      final doctors = await ApiService.listDoctorStatus(forceRefresh: true);
      if (mounted) {
        setState(() {
          _doctors = doctors;
        });
      }
    } catch (e) {
      debugPrint('Silent doctor list refresh error: $e');
    }
  }

  void _unsubscribeDoctorAvailabilityRealtime() {
    if (_doctorAvailabilityChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_doctorAvailabilityChannel!);
        debugPrint('[Dashboard Staff Realtime] Unsubscribed channel successfully.');
      } catch (_) {}
      _doctorAvailabilityChannel = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_doctorAvailabilityChannel == null) {
        _subscribeDoctorAvailabilityRealtime();
      }
      _loadAllData(isInitial: false);
    }
  }

  Future<void> _loadAllData({bool isInitial = false}) async {
    if (!mounted) return;
    if (isInitial) setState(() => _isInitialLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        ApiService.listDoctorStatus(forceRefresh: !isInitial),
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

        // Realtime subscription management for active ticket
        if (newQueueSnapshot.hasActiveQueue && newQueueSnapshot.queueId != null) {
          _subscribeDashboardQueueRealtime(newQueueSnapshot.queueId);
        } else {
          _unsubscribeDashboardQueueRealtime();
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
      backgroundColor: const Color(0xFFEAF7EA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF1E4E2B),
              backgroundColor: Colors.white,
              displacement: 24,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                await _loadAllData(isInitial: false);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLiveQueueCard(),
                    const SizedBox(height: 16),
                    _buildDoctorsHorizontalSection(),
                    const SizedBox(height: 18),
                    _buildActionIconsRow(),
                    const SizedBox(height: 18),
                    _buildPromoBanner(),
                    const SizedBox(height: 18),
                    _buildPrescriptionRecordsSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingHelpButton(),
      bottomNavigationBar: widget.isEmbeddedInShell ? null : _buildBottomNav(),
    );
  }


  Widget _buildHeader() {
    final initial = widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'B';
    final nameParts = widget.fullname.trim().split(RegExp(r'\s+'));
    final displayName = (nameParts.isNotEmpty && nameParts.first.isNotEmpty)
        ? nameParts.first
        : (widget.username.isNotEmpty ? widget.username : 'User');

    return Container(
      width: double.infinity,
      color: const Color(0xFFEAF7EA),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
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
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E4E2B),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_getGreetingText()}, $displayName',
                      style: const TextStyle(
                        color: Color(0xFF1E4E2B),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              _buildNotificationBell(),
            ],
          ),
        ),
      ),
    );
  }

  String _getGreetingText() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
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
                  child: Image.asset(
                    'assets/icons/patient_id_icon.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const Icon(Icons.badge_rounded, color: _C.primary, size: 22),
                  ),
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
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                )
              ],
            ),
            child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 22),
          ),
          if (_hasUnseenNotifications)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Hero Live Queue Card (Option 2: Modern Split Card) ─────────
  Widget _buildLiveQueueCard() {
    final queue = _queueDashboard;
    final hasQueue = queue.hasActiveQueue;

    // Resolve currently serving queue number from snapshot or real-time map
    int? servingNum = queue.currentlyServingQueueNumber;
    if (servingNum == null || servingNum == 0) {
      final servingList = _tvQueueDisplay['serving'] as List<dynamic>?;
      if (servingList != null && servingList.isNotEmpty) {
        final first = servingList.first as Map<String, dynamic>?;
        servingNum = (first?['queue_number'] as num?)?.toInt();
      }
    }

    // Dynamic subtitle for Right Box (NOW SERVING)
    String servingSubtitle;
    if (hasQueue && queue.myQueueNumber != null && servingNum != null && servingNum > 0) {
      if (queue.myQueueNumber == servingNum) {
        servingSubtitle = "It's your turn!";
      } else if (queue.myQueueNumber! > servingNum) {
        final diff = queue.myQueueNumber! - servingNum - 1;
        servingSubtitle = diff <= 0 ? "You're next in line" : "$diff patient${diff > 1 ? 's' : ''} ahead";
      } else {
        servingSubtitle = "Station active";
      }
    } else if (queue.waitingCount > 0) {
      servingSubtitle = "${queue.waitingCount} in line";
    } else {
      servingSubtitle = "Station ready";
    }

    // Dynamic subtitle for Left Box (YOUR NUMBER)
    String waitSubtitle;
    if (hasQueue) {
      if (queue.isCompleted) {
        waitSubtitle = 'Completed';
      } else if (queue.estimatedWaitMinutes > 0) {
        waitSubtitle = '~${_formatWaitTime(queue.estimatedWaitMinutes)} wait';
      } else {
        waitSubtitle = 'Ready soon';
      }
    } else {
      waitSubtitle = 'Not in queue';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Live indicator & Queue state badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE QUEUE',
                      style: TextStyle(
                        color: Color(0xFF059669),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasQueue ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  hasQueue
                      ? (queue.isCompleted
                          ? 'COMPLETED'
                          : (queue.status.toLowerCase() == 'serving'
                              ? 'SERVING'
                              : (queue.status.toLowerCase() == 'on_call' ? 'ON CALL' : 'WAITING')))
                      : 'NOT IN QUEUE',
                  style: TextStyle(
                    color: hasQueue ? const Color(0xFF166534) : const Color(0xFF64748B),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Split Twin Inset Cards: YOUR NUMBER & NOW SERVING
          Row(
            children: [
              // Left Card: YOUR NUMBER
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: hasQueue ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasQueue ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR NUMBER',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasQueue ? _queueNumberText(queue.myQueueNumber) : '— —',
                        style: TextStyle(
                          color: hasQueue ? const Color(0xFF1E4E2B) : const Color(0xFF94A3B8),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            hasQueue ? Icons.access_time_rounded : Icons.info_outline_rounded,
                            size: 11,
                            color: hasQueue ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              waitSubtitle,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: hasQueue ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Right Card: NOW SERVING
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NOW SERVING',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (servingNum != null && servingNum > 0)
                            ? _queueNumberText(servingNum)
                            : '— —',
                        style: TextStyle(
                          color: (servingNum != null && servingNum > 0)
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF94A3B8),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.people_alt_outlined,
                            size: 11,
                            color: (hasQueue && queue.myQueueNumber != null && servingNum != null && queue.myQueueNumber == servingNum)
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              servingSubtitle,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: (hasQueue && queue.myQueueNumber != null && servingNum != null && queue.myQueueNumber == servingNum)
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bottom Action Button
          GestureDetector(
            onTap: _navigateToQueue,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1E4E2B),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x141E4E2B),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasQueue ? Icons.confirmation_number_outlined : Icons.add_circle_outline_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    hasQueue ? 'VIEW TICKET DETAILS' : 'JOIN CLINIC QUEUE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
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

  void _navigateToQueue() {
    HapticFeedback.lightImpact();
    if (widget.isEmbeddedInShell) {
      ShellNavigation.switchTab(ShellNavigation.tabQueue);
    } else {
      Navigator.push(
        context,
        AppPageRoute.slideRight(
          uKonekJoinQueuePage(username: widget.username, citizenId: widget.citizenId),
        ),
      ).then((_) => _loadAllData(isInitial: false));
    }
  }

  // ── Horizontal Doctors on Duty Section ─────────────────────────
  Widget _buildDoctorsHorizontalSection() {
    final availableCount = _doctors
        .where((d) => d.availabilityStatus.toLowerCase().trim() == 'available')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'DOCTORS ON DUTY',
              style: TextStyle(
                color: Color(0xFF1E4E2B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            if (!_isInitialLoading && _doctors.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: availableCount > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: availableCount > 0 ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$availableCount AVAILABLE',
                      style: TextStyle(
                        color: availableCount > 0 ? const Color(0xFF166534) : const Color(0xFF64748B),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isInitialLoading)
          _buildDoctorHorizontalSkeleton()
        else if (_doctors.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_off_outlined, color: Color(0xFF94A3B8), size: 18),
                SizedBox(width: 8),
                Text(
                  'No doctors on duty at the moment.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _doctors.map((doctor) => _buildDoctorAvatarCard(doctor)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildDoctorAvatarCard(DoctorStatus doctor) {
    final status = doctor.availabilityStatus.toLowerCase().trim();
    final isAvailable = status == 'available';

    return Container(
      width: 122,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Image.asset(
                'assets/icons/doctor_icon.png',
                width: 44,
                height: 44,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E4E2B),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.medical_services_outlined, color: Colors.white, size: 20),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isAvailable ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            doctor.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            doctor.specialization.isNotEmpty ? doctor.specialization : 'General Physician',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: isAvailable ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isAvailable ? 'AVAILABLE' : 'UNAVAILABLE',
              style: TextStyle(
                color: isAvailable ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorHorizontalSkeleton() {
    return _SkeletonPulse(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: List.generate(
            3,
            (index) => Container(
              width: 122,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _skeletonBox(width: 44, height: 44, borderRadius: 22),
                  const SizedBox(height: 8),
                  _skeletonBox(width: 80, height: 11, borderRadius: 4),
                  const SizedBox(height: 4),
                  _skeletonBox(width: 60, height: 9, borderRadius: 4),
                  const SizedBox(height: 8),
                  _skeletonBox(width: 70, height: 16, borderRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Action Icons Row: 6 Solid Lime Circles with Labels ────────
  Widget _buildActionIconsRow() {
    final actions = [
      {
        'label': 'MY PATIENT ID',
        'iconAsset': 'assets/icons/patient_id_icon.png',
        'onTap': () => _showPatientQrModal(),
      },
      {
        'label': 'JOIN QUEUE',
        'iconAsset': 'assets/icons/join_queue_icon.png',
        'onTap': () {
          if (widget.isEmbeddedInShell) {
            ShellNavigation.switchTab(ShellNavigation.tabQueue);
          } else {
            Navigator.push(
              context,
              AppPageRoute.slideRight(
                uKonekJoinQueuePage(username: widget.username, citizenId: widget.citizenId),
              ),
            ).then((_) => _loadAllData(isInitial: false));
          }
        },
      },
      {
        'label': 'E-PRESCRIPTION',
        'iconAsset': 'assets/icons/prescription_icon.png',
        'onTap': () => Navigator.push(context, AppPageRoute.slideRight(const PrescriptionPage())),
      },
      {
        'label': 'RECORDS',
        'iconAsset': 'assets/icons/records_icon.png',
        'onTap': () => Navigator.push(context, AppPageRoute.slideRight(const uKonekHealthRecordsPage())),
      },
      {
        'label': 'SCHEDULER',
        'iconAsset': 'assets/icons/scheduler_icon.png',
        'onTap': () {
          if (widget.isEmbeddedInShell) {
            ShellNavigation.switchTab(ShellNavigation.tabMedicineScheduler);
          } else {
            Navigator.push(
              context,
              AppPageRoute.slideRight(
                uKonekMedicineSchedulerPage(username: widget.username, citizenId: widget.citizenId),
              ),
            );
          }
        },
      },
      {
        'label': 'FEEDBACK',
        'iconAsset': 'assets/icons/feedback_icon.png',
        'onTap': () => Navigator.push(context, AppPageRoute.slideRight(const uKonekFeedbackPage())),
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actions.map((item) {
          final iconAsset = item['iconAsset'] as String?;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              (item['onTap'] as VoidCallback)();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 70,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: iconAsset != null
                        ? Center(
                            child: Image.asset(
                              iconAsset,
                              width: 50,
                              height: 50,
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, stack) => const SizedBox(),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['label'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E4E2B),
                      letterSpacing: -0.2,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Promo Banner (Swipable PageView & Supports Photos / Announcements) ──
  Widget _buildPromoBanner({String? imageUrl, List<Announcement>? announcements}) {
    final activeList = announcements ?? _announcements;
    final bannerCount = activeList.isEmpty ? 1 : activeList.length;
    final safeCurrentPage = _currentPromoPage.clamp(0, bannerCount - 1);

    return Column(
      children: [
        SizedBox(
          height: 206,
          child: PageView.builder(
            controller: _promoPageController,
            physics: const BouncingScrollPhysics(),
            itemCount: bannerCount,
            onPageChanged: (index) {
              setState(() {
                _currentPromoPage = index;
              });
            },
            itemBuilder: (context, index) {
              if (activeList.isEmpty) {
                // Default fallback banner
                return _buildPromoCard(
                  title: 'Healthcare Made Simple & Contactless',
                  content: 'Experience faster check-ins, live queue tracking, and instant digital records right at your fingertips.',
                  imageUrl: imageUrl,
                  onTap: () => _showPromoDetailsModal(
                    customTitle: 'Healthcare Made Simple & Contactless',
                    customContent: 'Experience faster check-ins, live queue tracking, and instant digital records right at your fingertips.',
                    customImageUrl: imageUrl,
                  ),
                );
              }

              final item = activeList[index];
              return _buildPromoCard(
                title: item.title,
                content: item.content,
                imageUrl: item.imageUrl,
                onTap: () => _showPromoDetailsModal(
                  customTitle: item.title,
                  customContent: item.content,
                  customImageUrl: item.imageUrl,
                  postedAt: item.createdAt,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Dynamic Carousel dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(bannerCount, (dotIndex) {
            final isSelected = dotIndex == safeCurrentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: isSelected ? 16 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E4E2B) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildPromoCard({
    required String title,
    required String content,
    String? imageUrl,
    required VoidCallback onTap,
  }) {
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Full-Width Landscape Image / Graphic
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: double.infinity,
                height: 115,
                child: hasImage
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF166534)),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (ctx, err, stack) => Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Center(
                            child: Icon(Icons.image_outlined, color: Color(0xFF94A3B8), size: 28),
                          ),
                        ),
                      )
                    : _buildDefaultHeaderGraphic(),
              ),
            ),
            const SizedBox(height: 10),
            // Title Below
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // Description Below Title
            Text(
              content,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10.5,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultHeaderGraphic() {
    return Container(
      width: double.infinity,
      height: 115,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD1FAE5), Color(0xFFEAF7EA), Color(0xFFDCFCE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(left: 18, top: 16, child: _buildFloatingMiniBadge(Icons.medical_services_outlined)),
          Positioned(right: 22, top: 14, child: _buildFloatingMiniBadge(Icons.health_and_safety_outlined)),
          Positioned(left: 36, bottom: 14, child: _buildFloatingMiniBadge(Icons.event_available_rounded)),
          Positioned(right: 48, bottom: 12, child: _buildFloatingMiniBadge(Icons.medication_outlined)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF6EE7B7), width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_rounded, color: Color(0xFF166534), size: 16),
                SizedBox(width: 6),
                Text(
                  'UKONEK DIGITAL CLINIC PASS',
                  style: TextStyle(
                    color: Color(0xFF166534),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingMiniBadge(IconData icon) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF059669), size: 13),
    );
  }

  void _showPromoDetailsModal({
    String? customTitle,
    String? customContent,
    String? customImageUrl,
    DateTime? postedAt,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (customImageUrl != null && customImageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      customImageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const SizedBox(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1F4DE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.stars_rounded, color: Color(0xFF166534), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customTitle ?? 'Healthcare Made Simple & Contactless',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          postedAt != null
                              ? 'Posted on ${DateFormat('MMM d, yyyy • h:mm a').format(postedAt)}'
                              : 'Clinic Announcement & Features Overview',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (customContent != null && customContent.isNotEmpty) ...[
                Text(
                  customContent,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.45, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
              ],
              const Text(
                'U-Konek brings seamless clinic services right to your pocket:\n\n'
                '• Fast Check-ins: Present your digital Patient ID at triage.\n'
                '• Live Queue Tracking: Monitor your ticket status and estimated waiting time in real time.\n'
                '• Digital Prescriptions: View issued medications, dosage instructions, and dispensing logs.\n'
                '• Medicine Scheduler: Automated dosage reminders for prescribed medications.',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF166534),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Prescriptions Section: "PRESCRIPTION RECORDS" ─────────────
  Widget _buildPrescriptionRecordsSection() {
    final activePrescriptions = _prescribedMedicines
        .where((m) => !m.isPrescriptionDispensed && !m.isDispensed)
        .take(4)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Dark green header bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: const Color(0xFF1E4E2B),
            child: const Center(
              child: Text(
                'PRESCRIPTION RECORDS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Prescription records list
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: _isInitialLoading
                ? _buildMedicineSkeleton()
                : (activePrescriptions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No active prescription records.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < activePrescriptions.length; i++) ...[
                            _buildPrescriptionRow(activePrescriptions[i]),
                            if (i < activePrescriptions.length - 1)
                              const Divider(height: 14, color: Color(0xFFF1F5F9)),
                          ],
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.push(
                                context,
                                AppPageRoute.slideRight(const PrescriptionPage()),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Center(
                                child: Text(
                                  'SEE MORE',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    decoration: TextDecoration.underline,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionRow(PrescriptionRecord record) {
    final name = record.medicineName;
    final sub = record.remainingQuantityLabel.isNotEmpty
        ? record.remainingQuantityLabel
        : (record.dosage.isNotEmpty ? record.dosage : 'As prescribed');
    final isPartial = record.isPartial;
    final status = isPartial ? 'PARTIAL' : 'PRESCRIBED';
    final pillBg = isPartial ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7);
    final pillText = isPartial ? const Color(0xFFD97706) : const Color(0xFF16A34A);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final group = _prescribedMedicines
            .where((m) => m.prescriptionId == record.prescriptionId)
            .toList();
        _showEPrescriptionModal(group.isNotEmpty ? group : [record]);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: pillText,
                  fontWeight: FontWeight.w900,
                  fontSize: 8,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Floating Help Button: Teal/Green Circle with "?" ───────────
  Widget _buildFloatingHelpButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: FloatingActionButton(
        onPressed: _showHelpSupportDialog,
        backgroundColor: const Color(0xFF1E5E38),
        elevation: 6,
        shape: const CircleBorder(),
        child: const Text(
          '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _showHelpSupportDialog() {
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
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1F4DE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      '?',
                      style: TextStyle(
                        color: Color(0xFF1E4E2B),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clinic Help & Support',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Assistance and Consultation Inquiries',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FCF9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1F4DE)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📍 Consultation Hours',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Monday to Friday: 8:00 AM - 5:00 PM\nClosed on Weekends and Public Holidays.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.4),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '📞 Clinic Hotline & Triage Desk',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Hotline: (02) 8123-4567 • Mobile: 0917-123-4567\nFor emergency cases, please proceed immediately to the nearest ER.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E4E2B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Got It', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Standalone Bottom Navigation Bar ───────────────────────────
  Widget _buildBottomNav() {
    const Color barColor = Color(0xFF1E4E2B);
    final currentTab = _selectedTab;

    return Container(
      color: barColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildNavCircleButton(
                      icon: Icons.home_rounded,
                      isSelected: currentTab == 0,
                      onTap: () => setState(() => _selectedTab = 0),
                    ),
                    _buildNavCircleButton(
                      icon: Icons.calendar_month_rounded,
                      isSelected: currentTab == 1,
                      onTap: () {
                        Navigator.push(context, AppPageRoute.slideRight(
                          uKonekMedicineSchedulerPage(
                            username: widget.username,
                            citizenId: widget.citizenId,
                          ),
                        ));
                      },
                    ),
                    const SizedBox(width: 54),
                    _buildNavCircleButton(
                      icon: Icons.confirmation_number_rounded,
                      isSelected: false,
                      onTap: () {
                        Navigator.push(context, AppPageRoute.slideRight(const uKonekFeedbackPage()));
                      },
                    ),
                    _buildNavCircleButton(
                      icon: Icons.person_rounded,
                      isSelected: currentTab == 3,
                      onTap: _navigateToProfile,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -12,
                child: GestureDetector(
                  onTap: _showPatientQrModal,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: barColor,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavCircleButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: const Color(0xFF1E4E2B),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildMedicineSkeleton() {
    return _SkeletonPulse(
      child: Column(
        children: List.generate(3, (index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _skeletonBox(width: 24, height: 24, borderRadius: 4),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonBox(width: 120, height: 13, borderRadius: 4),
                    const SizedBox(height: 4),
                    _skeletonBox(width: 70, height: 10, borderRadius: 4),
                  ],
                ),
              ),
              _skeletonBox(width: 60, height: 20, borderRadius: 10),
            ],
          ),
        )),
      ),
    );
  }

  String _queueNumberText(int? n) => (n == null || n <= 0) ? '--' : '#${n.toString().padLeft(3, '0')}';
  String _formatWaitTime(int m)   => (m ~/ 60) <= 0 ? '$m mins' : '${m ~/ 60} hr ${m % 60} mins';
}