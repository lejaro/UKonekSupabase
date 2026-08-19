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
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';


class _C {
  static const primary    = Color(0xFF28A745);
  static const primaryMid = Color(0xFF1B5E20);
  static const accent     = Color(0xFF20C997);
  static const bg         = Color(0xFFF8FCF9);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1B2E1E);
  static const textMuted  = Color(0xFF637367);
  static const divider    = Color(0xFFE2E9E3);
  static const success    = Color(0xFF28A745);
  static const warning    = Color(0xFFF59E0B);
  static const shadow     = Color(0x0A000000);
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
  });

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
  String? _lastQueueStatus;
  Timer? _refreshTimer;
  Map<String, dynamic> _tvQueueDisplay = {};

  // ── Navigate to profile with ALL registration fields ──────────
  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => uKonekProfilePage(
          username:         widget.username,
          citizenId:        widget.citizenId,
          fullName:         widget.fullname,
          // ✅ Add these — were missing causing profile to show incomplete name
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
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
        ApiService.getTvQueueDisplay(),
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
        _lastQueueStatus = newStatus;

        setState(() {
          _doctors = results[0] as List<DoctorStatus>;
          _queueDashboard = newQueueSnapshot;
          _prescribedMedicines = results[2] as List<PrescriptionRecord>;
          _announcements = announcements;
          _hasUnseenNotifications = unseen;
          _tvQueueDisplay = (results[5] as Map<String, dynamic>?) ?? {};
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
                          decoration: const BoxDecoration(color: Color(0xFF28A745), shape: BoxShape.circle),
                          child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AFM ROQUERO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1B5E20))),
                            Text('Medical Clinic', style: TextStyle(fontSize: 12, color: Color(0xFF637367))),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFE2E9E3)),
                    const SizedBox(height: 16),

                    // ── Patient Info ───────────────────────────────────
                    const Text('PATIENT INFORMATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF28A745), letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    Text("${widget.firstName} ${widget.middleName} ${widget.surname} ${widget.nameExtension}".trim(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2E1E))),
                    const SizedBox(height: 4),
                    Text('ID: ${widget.citizenId}', style: const TextStyle(fontSize: 12, color: Color(0xFF637367))),
                    const SizedBox(height: 4),
                    Text('Doctor: $doctorName', style: const TextStyle(fontSize: 12, color: Color(0xFF637367), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Prescription: $prescriptionCode', style: const TextStyle(fontSize: 12, color: Color(0xFF637367), fontWeight: FontWeight.w600, fontFamily: 'monospace')),

                    const SizedBox(height: 24),

                    // ── Rx Symbol & Medications ──────────────────────────
                    const Text('℞', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20), height: 1)),
                    const SizedBox(height: 8),
                    const Text('PRESCRIBED MEDICATIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF28A745), letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    
                    // ── List all medicines in this prescription (filtering out dispensed ones) ──────────
                    ...prescriptionItems.where((item) => !item.isPrescriptionDispensed && !item.isDispensed).map((item) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF8FCF9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFD6E8DA))
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.medicineName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2E1E))),
                          const SizedBox(height: 4),
                          Text(item.dosage.isNotEmpty ? item.dosage : 'As prescribed', 
                              style: const TextStyle(fontSize: 14, color: Color(0xFF28A745), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          const Divider(color: Color(0xFFD6E8DA)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Color(0xFF637367)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.instructions.isNotEmpty ? item.instructions : 'Follow doctor\'s verbal instructions.',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF637367), height: 1.4),
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
                                Text('Quantity: ${item.quantityLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFF637367))),
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
                              const Text('ISSUED DATE:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF637367))),
                              Text(issuedDate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B2E1E))),
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
                          const Text('PHARMACY VERIFICATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF637367), letterSpacing: 1)),
                          const SizedBox(height: 12),
                          QrImageView(
                            data: prescriptionCode,
                            version: QrVersions.auto,
                            size: 140.0,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1B5E20)),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1B5E20)),
                          ),
                          const SizedBox(height: 12),
                          const Text('Digital Signature Verified', style: TextStyle(color: Color(0xFF28A745), fontWeight: FontWeight.bold, fontSize: 12)),
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
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF28A745), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
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
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrescriptionPage())),
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
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAnnouncements() {
    if (_announcements.isEmpty && !_isInitialLoading) return const SizedBox.shrink();
    final tagColors = [_C.primary, _C.warning, const Color(0xFF17A2B8), const Color(0xFF6F42C1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Announcements'),
        const SizedBox(height: 14),
        _isInitialLoading
            ? const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))
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
        gradient: LinearGradient(colors: [_C.primary, _C.primaryMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _navigateToProfile,
                child: Row(children: [
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
                      Row(children: [
                        Text(widget.username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 11),
                      ]),
                    ],
                  ),
                ]),
              ),
              _buildNotificationBell(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationBell() {
    const Color textDark = Color(0xFF1B2E1E);
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_viewed_notifications', DateTime.now().toIso8601String());
        if (mounted) setState(() => _hasUnseenNotifications = false);
        
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => uKonekNotificationPage(
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
              boxShadow: [BoxShadow(color: textDark.withOpacity(0.05), blurRadius: 10)],
            ),
            child: const Icon(Icons.notifications_none_rounded, color: textDark, size: 24),
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
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: _C.success, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('Live', style: TextStyle(fontSize: 11, color: _C.success, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))]),
          child: _isInitialLoading
              ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
              : (_doctors.isEmpty
                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No doctors on duty.', style: TextStyle(color: _C.textMuted))))
                  : Column(children: List.generate(_doctors.length, (i) {
                      final item = _doctors[i];
                      return Column(children: [
                        _staffTile(item.displayName, item.specialization, _getStatusColor(item.availabilityStatus), _getStatusLabel(item.availabilityStatus), Icons.medical_services_rounded),
                        if (i < _doctors.length - 1) const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(height: 1, color: _C.divider)),
                      ]);
                    }))),
        ),
      ],
    );
  }

  Color  _getStatusColor(String s) => s.toLowerCase() == 'on_break' ? _C.warning : (s.toLowerCase() == 'unavailable' ? Colors.grey : _C.success);
  String _getStatusLabel(String s) => s.toLowerCase() == 'on_break' ? 'On Break' : (s.toLowerCase() == 'unavailable' ? 'Unavailable' : 'Available');

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _buildQueueCard() {
    final queue = _queueDashboard;
    final hasQueue = queue.hasActiveQueue;
    final statusColor = hasQueue ? _C.warning : _C.success;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))]),
      child: _isInitialLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      hasQueue 
                        ? (queue.status.toLowerCase() == 'on_call' ? 'ON CALL' : 'ACTIVE QUEUE') 
                        : 'LIVE QUEUE', 
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 10)
                    ),
                  ]),
                ),
                const Spacer(),
                Text(hasQueue ? queue.serviceLabel : 'Not in queue', style: const TextStyle(color: _C.textMuted, fontSize: 11)),
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _queueInfo('YOUR NUMBER', _queueNumberText(queue.myQueueNumber), hasQueue ? _C.primaryMid : _C.textMuted),
              ]),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: _C.primaryMid.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.timer_outlined, size: 16, color: _C.primaryMid),
                  const SizedBox(width: 8),
                  Text(
                    hasQueue 
                      ? (queue.status.toLowerCase() == 'serving'
                          ? 'You are currently being served'
                          : (queue.status.toLowerCase() == 'on_call'
                              ? 'Please proceed to vital assessment'
                              : 'Est. Wait: ${_formatWaitTime(queue.estimatedWaitMinutes)}   •   Patients Ahead: ${queue.waitingCount > 0 ? queue.waitingCount : "0"}'))
                      : 'Join queue to view waiting time',
                    style: const TextStyle(color: _C.primaryMid, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              const Divider(color: _C.divider, height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 4, height: 14,
                    decoration: BoxDecoration(color: const Color(0xFF1976D2), borderRadius: BorderRadius.circular(2)),
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
            ]),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1976D2).withOpacity(0.3),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.w900)),
    ]);
  }

  Widget _buildServiceIcons() {
    final services = [
      {'icon': Icons.medical_services_outlined, 'label': 'Consult',  'color': const Color(0xFF28A745), 'key': 'consult'},
      {'icon': Icons.vaccines_outlined,         'label': 'Vaccine',  'color': const Color(0xFF17A2B8), 'key': 'vaccine'},
      {'icon': Icons.monitor_heart_outlined,    'label': 'Check-up', 'color': const Color(0xFFDC3545), 'key': 'checkup'},
      {'icon': Icons.child_care_outlined,       'label': 'Maternal', 'color': const Color(0xFF6F42C1), 'key': 'maternal'},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: services.map((s) {
        final color = s['color'] as Color;
        return GestureDetector(
          onTap: () async {
            final joined = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => uKonekJoinQueuePage(
                  username: widget.username,
                  citizenId: widget.citizenId,
                  initialServiceKey: s['key'] as String,
                ),
              ),
            );
            if (joined == true) _loadAllData(isInitial: false);
          },
          child: Column(children: [
            Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Icon(s['icon'] as IconData, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(s['label'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _C.textDark)),
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
        _actionBtn('My Patient ID', Icons.qr_code_scanner_rounded, _C.primaryMid, () {
          _navigateToProfile(); // Navigates to profile where QR is now located
        }),
        _actionBtn('Join Queue', Icons.add_circle_outline_rounded, _C.primary, () async {
          final joined = await Navigator.push<bool>(context, MaterialPageRoute(
            builder: (_) => uKonekJoinQueuePage(username: widget.username, citizenId: widget.citizenId),
          ));
          if (joined == true) _loadAllData(isInitial: false);
        }),
        // NEW: View E-Prescription Button (Dynamic)
        _actionBtn('E-Prescription', Icons.receipt_long_rounded, const Color(0xFF6F42C1), () {
          // Filter out dispensed items for the e-prescription view
          final activeMeds = _prescribedMedicines.where((m) => !m.isPrescriptionDispensed && !m.isDispensed).toList();
          
          if (activeMeds.isNotEmpty) {
            // Group prescriptions by prescription_id and get the latest one
            final Map<int, List<PrescriptionRecord>> grouped = {};
            for (var item in activeMeds) {
              grouped.putIfAbsent(item.prescriptionId, () => []).add(item);
            }
            
            // Get the latest prescription (first group since data is ordered by issued_at desc)
            final latestPrescriptionItems = grouped.values.first.toList();
            _showEPrescriptionModal(latestPrescriptionItems);
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PrescriptionPage()));
          }
        }),
        _actionBtn('Records', Icons.assignment_outlined, const Color(0xFF17A2B8), () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const uKonekHealthRecordsPage()))),
        _actionBtn('Scheduler', Icons.alarm_on_outlined, const Color(0xFF6F42C1), () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => uKonekMedicineSchedulerPage(username: widget.username, citizenId: widget.citizenId)))),
        _actionBtn('Feedback', Icons.feedback_outlined, const Color(0xFFF59E0B), () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const uKonekFeedbackPage()))),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 10, offset: Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _C.textDark,
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

  Widget _buildMedicineCard() {
    // Only show medicines that are not yet dispensed on the dashboard summary
    final medicines = _prescribedMedicines
        .where((m) => !m.isPrescriptionDispensed && !m.isDispensed)
        .take(3)
        .toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 14, offset: Offset(0, 5))]),
      child: _isInitialLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : (medicines.isEmpty
              ? const Text('No recent prescriptions.', style: TextStyle(color: _C.textMuted))
              : Column(children: [
                  for (var i = 0; i < medicines.length; i++) ...[
                    _medRow(medicines[i].medicineName, medicines[i].quantityLabel, 'PRESCRIBED', _C.primaryMid),
                    if (i < medicines.length - 1) const Divider(height: 28, color: _C.divider),
                  ],
                ])),
    );
  }

  Widget _medRow(String name, String sub, String status, Color color) {
    return Row(children: [
      Container(height: 46, width: 46, decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.medication_outlined, color: color, size: 22)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
        Text(sub,  style: const TextStyle(color: _C.textMuted, fontSize: 11)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10)),
      ),
    ]);
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTab = i);
                  if (i == 0) {
                    // Already on Home
                  } else if (i == 1) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekMedicineSchedulerPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    )).then((_) => setState(() => _selectedTab = 0));
                  } else if (i == 2) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekJoinQueuePage(
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _C.primaryMid.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _C.primaryMid : Colors.grey.shade400,
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(height: 4),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color:      _C.primaryMid,
                            fontSize:   10,
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