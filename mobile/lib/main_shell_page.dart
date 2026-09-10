import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import 'core/session/patient_session.dart';
import 'widgets/prescription_details_sheet.dart';

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
  static const Color _shadow       = Color(0x0A0F172A);

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
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.event_note_rounded, 'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: _shadow,
            blurRadius: 20,
            offset: Offset(0, -4),
          )
        ],
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
                  onTap: () => selectTab(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? _primaryLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tabs[i]['icon'] as IconData,
                          color: isSelected ? _primary : const Color(0xFF94A3B8),
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tabs[i]['label'] as String,
                          style: TextStyle(
                            color: isSelected ? _primary : const Color(0xFF94A3B8),
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
}
