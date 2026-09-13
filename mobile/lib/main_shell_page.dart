import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/medicine_cache_service.dart';
import 'utils/app_transitions.dart';
import 'prescription_page.dart';
import 'dashboard_page.dart';
import 'medicine_scheduler_page.dart';
import 'join_queue_page.dart';
import 'profile_page.dart';
import 'core/navigation/shell_navigation.dart';
import 'widgets/prescription_details_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Unified persistent App Shell for uKonek.
/// Hosts Dashboard, Medicine Scheduler, Queue, and Profile tabs without route pushing.
class uKonekMainShellPage extends StatefulWidget {
  final String username;
  final String citizenId;
  final String fullname;
  final String email;
  final String phone;
  final String address;
  final int initialTab;

  const uKonekMainShellPage({
    super.key,
    required this.username,
    required this.citizenId,
    this.fullname = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.initialTab = 0,
  });

  /// Helper to allow child widgets to switch tabs in the shell
  static void switchTab(BuildContext context, int index) {
    ShellNavigation.switchTab(index);
  }

  /// Helper to trigger an immediate check for newly issued prescriptions
  static void checkPrescriptions(BuildContext context) {
    ShellNavigation.checkPrescriptions();
  }

  @override
  State<uKonekMainShellPage> createState() => _uKonekMainShellPageState();
}

class _uKonekMainShellPageState extends State<uKonekMainShellPage> with WidgetsBindingObserver {
  static const Color _primary      = Color(0xFF059669);
  static const Color _primaryLight = Color(0xFFECFDF5);
  static const Color _textDark     = Color(0xFF0F172A);

  late int _selectedTab;
  late final List<Widget> _pages;
  Timer? _prescriptionCheckTimer;
  bool _isShowingPrescriptionModal = false;
  bool _isCheckingPrescriptionAlert = false;
  int? _lastAlertedPrescriptionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedTab = widget.initialTab;
    ShellNavigation.currentTab.value = _selectedTab;
    ShellNavigation.currentTab.addListener(_onNavigationTabChanged);
    ShellNavigation.prescriptionAlertTrigger.addListener(_onPrescriptionTrigger);

    _pages = [
      uKonekDashboardPage(
        username: widget.username,
        citizenId: widget.citizenId,
        fullname: widget.fullname,
        email: widget.email,
        phone: widget.phone,
        address: widget.address,
        isEmbeddedInShell: true,
      ),
      uKonekMedicineSchedulerPage(
        username: widget.username,
        citizenId: widget.citizenId,
        isEmbeddedInShell: true,
      ),
      uKonekJoinQueuePage(
        username: widget.username,
        citizenId: widget.citizenId,
        isEmbeddedInShell: true,
      ),
      uKonekProfilePage(
        username: widget.username,
        citizenId: widget.citizenId,
        fullName: widget.fullname.isNotEmpty ? widget.fullname : widget.username,
        email: widget.email,
        phone: widget.phone,
        address: widget.address,
        isEmbeddedInShell: true,
      ),
    ];

    // Check for newly issued prescriptions shortly after startup
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _checkNewPrescriptionAlert();
    });

    // Check periodically every 30 seconds while the app is active
    _prescriptionCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _checkNewPrescriptionAlert();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShellNavigation.currentTab.removeListener(_onNavigationTabChanged);
    ShellNavigation.prescriptionAlertTrigger.removeListener(_onPrescriptionTrigger);
    _prescriptionCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNewPrescriptionAlert();
    }
  }

  Future<void> _checkNewPrescriptionAlert() async {
    if (!mounted || _isShowingPrescriptionModal || _isCheckingPrescriptionAlert) return;
    _isCheckingPrescriptionAlert = true;
    try {
      final alert = await ApiService.fetchLatestUnacknowledgedPrescription();
      if (alert != null &&
          mounted &&
          !_isShowingPrescriptionModal &&
          alert.prescriptionId != _lastAlertedPrescriptionId) {
        _lastAlertedPrescriptionId = alert.prescriptionId;
        _showNewPrescriptionModal(alert);
      }
    } catch (e) {
      debugPrint('Error checking new prescription alert: $e');
    } finally {
      _isCheckingPrescriptionAlert = false;
    }
  }

  void _showNewPrescriptionModal(NewPrescriptionAlert alert) {
    if (!mounted || _isShowingPrescriptionModal) return;
    _isShowingPrescriptionModal = true;
    _lastAlertedPrescriptionId = alert.prescriptionId;

    // Immediately mark as acknowledged so background checks or tab switches cannot trigger it again
    ApiService.acknowledgePrescription(alert.prescriptionId);
    MedicineCacheService.invalidateScheduleCache(widget.citizenId);

    // Trigger immediate push notification in system bar
    NotificationService.showImmediateNotification(
      id: 777,
      title: 'New E-Prescription Issued!',
      body: '${alert.displayDoctorName} has issued a new prescription (${alert.prescriptionCode}).',
      payload: '{"action":"prescription","id":${alert.prescriptionId}}',
    );

    PrescriptionAlertDialog.show(
      context,
      alert: alert,
      onViewPrescription: () async {
        await ApiService.acknowledgePrescription(alert.prescriptionId);
        if (mounted) Navigator.of(context).pop();
        _isShowingPrescriptionModal = false;
        if (mounted) {
          Navigator.push(
            context,
            AppPageRoute.slideRight(PrescriptionPage(
              initialPrescriptionId: alert.prescriptionId,
            )),
          );
        }
      },
      onDismiss: () async {
        await ApiService.acknowledgePrescription(alert.prescriptionId);
        if (mounted) Navigator.of(context).pop();
        _isShowingPrescriptionModal = false;
      },
    ).then((_) {
      _isShowingPrescriptionModal = false;
    });
  }

  void _onNavigationTabChanged() {
    final target = ShellNavigation.currentTab.value;
    if (target != _selectedTab && mounted) {
      selectTab(target);
    }
  }

  void _onPrescriptionTrigger() {
    if (mounted) _checkNewPrescriptionAlert();
  }

  void selectTab(int index) {
    if (index == _selectedTab) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    HapticFeedback.selectionClick();
    ShellNavigation.currentTab.value = index;
    setState(() {
      _selectedTab = index;
    });
  }

  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedTab != 0) {
          selectTab(0);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Press back again to exit'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: _textDark,
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedTab,
          children: _pages,
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    const Color barColor = Color(0xFF1E4E2B); // Dark green background
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
                    // 1. Home
                    _buildNavCircleButton(
                      icon: Icons.home_rounded,
                      isSelected: currentTab == ShellNavigation.tabDashboard,
                      onTap: () => selectTab(ShellNavigation.tabDashboard),
                    ),
                    // 2. Schedule
                    _buildNavCircleButton(
                      icon: Icons.calendar_month_rounded,
                      isSelected: currentTab == ShellNavigation.tabMedicineScheduler,
                      onTap: () => selectTab(ShellNavigation.tabMedicineScheduler),
                    ),
                    // Gap for center QR
                    const SizedBox(width: 54),
                    // 4. Queue
                    _buildNavCircleButton(
                      icon: Icons.confirmation_number_rounded,
                      isSelected: currentTab == ShellNavigation.tabQueue,
                      onTap: () => selectTab(ShellNavigation.tabQueue),
                    ),
                    // 5. Profile
                    _buildNavCircleButton(
                      icon: Icons.person_rounded,
                      isSelected: currentTab == ShellNavigation.tabProfile,
                      onTap: () => selectTab(ShellNavigation.tabProfile),
                    ),
                  ],
                ),
              ),
              // Prominent Raised Center QR Button
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
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/icons/patient_id_icon.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const Icon(Icons.badge_rounded, color: _primary, size: 22),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Patient Digital Pass',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Present this QR code at clinic reception or triage for instant check-in',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4),
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
                    data: widget.citizenId.isNotEmpty ? widget.citizenId : 'UKONEK-PATIENT',
                    version: QrVersions.auto,
                    size: 190.0,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF064E3B)),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF064E3B)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.fullname.isNotEmpty ? widget.fullname : widget.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _primaryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'CITIZEN ID: #${widget.citizenId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        color: _primary,
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
                  backgroundColor: _primary,
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
}
