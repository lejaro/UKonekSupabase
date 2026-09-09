import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'utils/app_transitions.dart';
import 'uKonekPrescriptionPage.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekMedicineScheduler.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekProfilePage.dart';

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
    final state = context.findAncestorStateOfType<_uKonekMainShellPageState>();
    state?.selectTab(index);
  }

  /// Helper to trigger an immediate check for newly issued prescriptions
  static void checkPrescriptions(BuildContext context) {
    final state = context.findAncestorStateOfType<_uKonekMainShellPageState>();
    state?._checkNewPrescriptionAlert();
  }

  @override
  State<uKonekMainShellPage> createState() => _uKonekMainShellPageState();
}

class _uKonekMainShellPageState extends State<uKonekMainShellPage> with WidgetsBindingObserver {
  static const Color _primaryMid = Color(0xFF1B5E20);
  static const Color _textDark = Color(0xFF1B2E1E);
  static const Color _shadow = Color(0x0D1B2E1E);

  late int _selectedTab;
  late final List<Widget> _pages;
  Timer? _prescriptionCheckTimer;
  bool _isShowingPrescriptionModal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedTab = widget.initialTab;

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

    // Check periodically every 10 seconds while the app is active
    _prescriptionCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _checkNewPrescriptionAlert();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!mounted || _isShowingPrescriptionModal) return;
    final alert = await ApiService.fetchLatestUnacknowledgedPrescription();
    if (alert != null && mounted && !_isShowingPrescriptionModal) {
      _showNewPrescriptionModal(alert);
    }
  }

  void _showNewPrescriptionModal(NewPrescriptionAlert alert) {
    if (!mounted || _isShowingPrescriptionModal) return;
    _isShowingPrescriptionModal = true;

    // Trigger immediate push notification in system bar
    NotificationService.showImmediateNotification(
      id: 777,
      title: 'New E-Prescription Issued!',
      body: 'Dr. ${alert.doctorName} has issued a new prescription (${alert.prescriptionCode}).',
      payload: '{"action":"prescription","id":${alert.prescriptionId}}',
    );

    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(alert.issuedAt);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 12,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Icon Badge
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6F42C1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6F42C1).withOpacity(0.32),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),

                // Title & Subtitle
                const Text(
                  'New E-Prescription Issued!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1B2E1E),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Dr. ${alert.doctorName} has issued your official electronic prescription.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF637367),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),

                // Details Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Rx Code:',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7E22CE),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            alert.prescriptionCode,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF581C87),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Issued:',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7E22CE),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF581C87),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Medicines List Preview
                if (alert.items.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'PRESCRIBED MEDICATIONS (${alert.items.length})',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6F42C1),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      child: Column(
                        children: alert.items.map((it) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6F42C1).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.medication_rounded,
                                  size: 15,
                                  color: Color(0xFF6F42C1),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      it.medicineName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1B2E1E),
                                      ),
                                    ),
                                    Text(
                                      '${it.dosage.isNotEmpty ? '${it.dosage} • ' : ''}${it.quantityLabel}${it.frequency.isNotEmpty ? ' (${it.frequency})' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF637367),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      await ApiService.acknowledgePrescription(alert.prescriptionId);
                      if (ctx.mounted) Navigator.of(ctx).pop();
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6F42C1),
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'View E-Prescription',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.1,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      await ApiService.acknowledgePrescription(alert.prescriptionId);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _isShowingPrescriptionModal = false;
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text(
                      'Dismiss for now',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      _isShowingPrescriptionModal = false;
    });
  }

  void selectTab(int index) {
    if (index == _selectedTab) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTab = index;
    });
    // Trigger prescription check when switching tabs
    _checkNewPrescriptionAlert();
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () => selectTab(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _primaryMid.withOpacity(0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _primaryMid : Colors.grey.shade400,
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(height: 4),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: _primaryMid,
                            fontSize: 10,
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
}
