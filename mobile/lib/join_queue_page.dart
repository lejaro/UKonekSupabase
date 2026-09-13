import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'dashboard_page.dart';
import 'medicine_scheduler_page.dart';
import 'profile_page.dart';
import 'utils/app_transitions.dart';
import 'core/navigation/shell_navigation.dart';

import 'core/theme/app_colors.dart';
import 'widgets/queue/consultation_completed_dialog.dart';
import 'widgets/queue/active_ticket_card.dart';
import 'widgets/queue/queue_join_form.dart';

typedef _C = AppColors;

typedef uKonekJoinQueuePage = JoinQueuePage;

class JoinQueuePage extends StatefulWidget {
  final String username;
  final String citizenId;
  final String? initialServiceKey;

  final bool isEmbeddedInShell;

  const JoinQueuePage({
    super.key,
    required this.username,
    required this.citizenId,
    this.initialServiceKey,
    this.isEmbeddedInShell = false,
  });

  @override
  State<JoinQueuePage> createState() => _JoinQueuePageState();
}

class _JoinQueuePageState extends State<JoinQueuePage>
    with SingleTickerProviderStateMixin {

  late Future<QueueDashboardSnapshot> _dashboardFuture;
  late Future<List<QueueServiceOption>> _servicesFuture;
  late Future<QueueLimiterStatus> _limiterStatusFuture;
  Timer? _refreshTimer;
  int _selectedTab = 2;

  // Form state
  QueueServiceOption? _selectedService;
  String _citizenType = 'regular';
  final _reasonController   = TextEditingController();
  final _symptomsController = TextEditingController();
  bool _isSubmitting = false;

  // Tracking & completion state
  int? _activeQueueId;
  String? _activeServiceLabel;
  int? _activeQueueNumber;
  String? _activeTicketCode;
  bool _isShowingDoneModal = false;
  bool _userManuallyCancelled = false;
  RealtimeChannel? _queueRealtimeChannel;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadInitialData();
    _animController.forward();
  }

  void _loadInitialData() {
    _dashboardFuture = ApiService.getMyQueueDashboard();
    _servicesFuture  = ApiService.listAvailableQueueServices();
    _limiterStatusFuture = ApiService.getQueueLimiterStatus();
    
    // Check if citizen has active queue and start timer accordingly
    _dashboardFuture.then((snapshot) {
      if (!mounted) return;
      if (snapshot.hasActiveQueue) {
        _activeQueueId = snapshot.queueId;
        _activeServiceLabel = snapshot.serviceLabel;
        _activeQueueNumber = snapshot.myQueueNumber;
        _activeTicketCode = snapshot.ticketCode;
        _userManuallyCancelled = false;
        _subscribeQueueRealtime(snapshot.queueId);
        _startRefreshTimer();
      } else {
        _stopRefreshTimer();
        _unsubscribeQueueRealtime();
        if (snapshot.isCompleted && snapshot.queueId != null) {
          _handleConsultationDone(
            ticketId: snapshot.queueId!,
            serviceLabel: snapshot.serviceLabel.isNotEmpty ? snapshot.serviceLabel : (_activeServiceLabel ?? 'Consultation'),
            queueNumber: snapshot.myQueueNumber ?? _activeQueueNumber ?? 0,
            ticketCode: snapshot.ticketCode.isNotEmpty ? snapshot.ticketCode : (_activeTicketCode ?? ''),
          );
        } else {
          _checkRecentCompletedTicket();
        }
      }
    });
    
    // Pre-select service if launched from a health service card
    if (widget.initialServiceKey != null && widget.initialServiceKey!.isNotEmpty) {
      _servicesFuture.then((services) {
        if (!mounted) return;
        final match = services.where(
          (s) => s.serviceKey.toLowerCase().contains(widget.initialServiceKey!.toLowerCase()) ||
                 s.serviceLabel.toLowerCase().contains(widget.initialServiceKey!.toLowerCase()),
        ).firstOrNull;
        if (match != null) setState(() => _selectedService = match);
      });
    }
  }

  void _subscribeQueueRealtime(int? ticketId) {
    if (ticketId == null) return;
    _unsubscribeQueueRealtime();

    try {
      final client = Supabase.instance.client;
      _queueRealtimeChannel = client
          .channel('queue_ticket_$ticketId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'queue_tickets',
            callback: (payload) {
              final rec = payload.newRecord;
              if (rec.isEmpty) return;
              final id = (rec['id'] as num?)?.toInt();
              final status = (rec['status'] ?? '').toString().toLowerCase().trim();

              if (id == ticketId) {
                if (const {'completed', 'finished', 'done'}.contains(status)) {
                  _handleConsultationDone(
                    ticketId: id!,
                    serviceLabel: rec['service_label']?.toString() ?? _activeServiceLabel ?? 'Consultation',
                    queueNumber: (rec['queue_number'] as num?)?.toInt() ?? _activeQueueNumber ?? 0,
                    ticketCode: rec['ticket_code']?.toString() ?? _activeTicketCode ?? '',
                  );
                } else if (status == 'serving') {
                  HapticFeedback.heavyImpact();
                  NotificationService.showImmediateNotification(
                    id: 889,
                    title: 'Now Serving! Please proceed.',
                    body: 'Your ticket is now being served. Please proceed to the consultation room.',
                    payload: '{"action":"queue"}',
                  );
                  _refreshDashboard();
                } else if (status == 'on_call') {
                  HapticFeedback.mediumImpact();
                  NotificationService.showImmediateNotification(
                    id: 888,
                    title: 'Your number is being called!',
                    body: 'Please proceed to the nurse for your vital assessment.',
                    payload: '{"action":"queue"}',
                  );
                  _refreshDashboard();
                } else {
                  _refreshDashboard();
                }
              } else if (status == 'serving' || status == 'completed') {
                // Another patient ahead moved forward, refresh countdown immediately
                _refreshDashboard();
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error subscribing to queue realtime: $e');
    }
  }

  void _unsubscribeQueueRealtime() {
    if (_queueRealtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_queueRealtimeChannel!);
        debugPrint('[Queue Realtime] Unsubscribed channel successfully.');
      } catch (_) {}
      _queueRealtimeChannel = null;
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    // 30-second fallback polling while realtime pushes live events
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshDashboard());
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _refreshDashboard() {
    if (!mounted) return;
    setState(() { 
      _dashboardFuture = ApiService.getMyQueueDashboard();
      _limiterStatusFuture = ApiService.getQueueLimiterStatus();
    });
    
    // Re-check if we should continue refreshing or if ticket completed
    _dashboardFuture.then((snapshot) async {
      if (!mounted) return;
      if (snapshot.hasActiveQueue) {
        _activeQueueId = snapshot.queueId;
        _activeServiceLabel = snapshot.serviceLabel;
        _activeQueueNumber = snapshot.myQueueNumber;
        _activeTicketCode = snapshot.ticketCode;
        _userManuallyCancelled = false;
        if (_refreshTimer == null) _startRefreshTimer();
        if (_queueRealtimeChannel == null) _subscribeQueueRealtime(snapshot.queueId);
      } else {
        _stopRefreshTimer();
        _unsubscribeQueueRealtime();

        if (snapshot.isCompleted && snapshot.queueId != null) {
          _handleConsultationDone(
            ticketId: snapshot.queueId!,
            serviceLabel: snapshot.serviceLabel.isNotEmpty ? snapshot.serviceLabel : (_activeServiceLabel ?? 'Consultation'),
            queueNumber: snapshot.myQueueNumber ?? _activeQueueNumber ?? 0,
            ticketCode: snapshot.ticketCode.isNotEmpty ? snapshot.ticketCode : (_activeTicketCode ?? ''),
          );
        } else if (_activeQueueId != null && !_userManuallyCancelled && !_isShowingDoneModal) {
          final prevId = _activeQueueId!;
          final prevService = _activeServiceLabel ?? 'Consultation';
          final prevNum = _activeQueueNumber ?? 0;
          final prevCode = _activeTicketCode ?? '';

          final ticketInfo = await ApiService.getTicketStatus(prevId);
          final status = ticketInfo?['status']?.toString().toLowerCase().trim();
          if (const {'completed', 'finished', 'done'}.contains(status)) {
            _handleConsultationDone(
              ticketId: prevId,
              serviceLabel: ticketInfo?['service_label']?.toString() ?? prevService,
              queueNumber: (ticketInfo?['queue_number'] as num?)?.toInt() ?? prevNum,
              ticketCode: ticketInfo?['ticket_code']?.toString() ?? prevCode,
            );
          } else {
            _activeQueueId = null;
          }
        }
      }
    });
  }

  Future<void> _checkRecentCompletedTicket() async {
    if (_isShowingDoneModal || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAck = prefs.getInt('last_acknowledged_completed_ticket_id');
      final completedTicket = await ApiService.getCompletedQueueTicket();
      if (completedTicket != null && mounted) {
        final ticketId = (completedTicket['id'] as num?)?.toInt();
        if (ticketId != null && ticketId != lastAck) {
          final completedAtStr = completedTicket['completed_at']?.toString();
          if (completedAtStr != null) {
            final completedAt = DateTime.tryParse(completedAtStr);
            if (completedAt != null && DateTime.now().difference(completedAt.toLocal()).inHours < 2) {
              _handleConsultationDone(
                ticketId: ticketId,
                serviceLabel: completedTicket['service_label']?.toString() ?? 'Consultation',
                queueNumber: (completedTicket['queue_number'] as num?)?.toInt() ?? 0,
                ticketCode: completedTicket['ticket_code']?.toString() ?? '',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking recent completed ticket: $e');
    }
  }

  Future<void> _handleConsultationDone({
    required int ticketId,
    required String serviceLabel,
    required int queueNumber,
    required String ticketCode,
  }) async {
    if (_isShowingDoneModal || !mounted) return;
    _isShowingDoneModal = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_acknowledged_completed_ticket_id', ticketId);

      // Erase all inputs in the queue tracker
      _clearFormInputs();
      _activeQueueId = null;
      _activeServiceLabel = null;
      _activeQueueNumber = null;
      _activeTicketCode = null;

      // Notify citizen immediately
      NotificationService.showImmediateNotification(
        id: 890,
        title: 'Consultation Completed!',
        body: 'Your consultation for $serviceLabel has been completed. Prescriptions & instructions are ready.',
        payload: '{"action":"consultation_done"}',
      );

      // Pop up the completion modal
      await _showConsultationDoneModal(
        serviceLabel: serviceLabel,
        queueNumber: queueNumber,
        ticketCode: ticketCode,
      );
    } finally {
      _isShowingDoneModal = false;
    }
  }

  void _clearFormInputs() {
    if (!mounted) return;
    setState(() {
      _selectedService = null;
      _citizenType = 'regular';
      _reasonController.clear();
      _symptomsController.clear();
    });
  }

  void _navigateToMainMenu() {
    if (widget.isEmbeddedInShell) {
      ShellNavigation.switchTab(ShellNavigation.tabDashboard);
      ShellNavigation.checkPrescriptions();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _showConsultationDoneModal({
    required String serviceLabel,
    required int queueNumber,
    required String ticketCode,
  }) async {
    if (!mounted) return;
    await ConsultationCompletedDialog.show(
      context: context,
      serviceLabel: serviceLabel,
      queueNumber: queueNumber,
      ticketCode: ticketCode,
      onReturnToMainMenu: _navigateToMainMenu,
    );
  }

  @override
  void dispose() {
    _unsubscribeQueueRealtime();
    _refreshTimer?.cancel();
    _animController.dispose();
    _reasonController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }


  Future<void> _handleJoin() async {
    if (_selectedService == null) return _showSnack('Please select a service.', isError: true);
    if (_reasonController.text.trim().isEmpty) return _showSnack('Reason for visit is required.', isError: true);
    setState(() => _isSubmitting = true);
    try {
      _userManuallyCancelled = false;
      await ApiService.joinQueue(QueueJoinRequest(
        serviceKey:   _selectedService!.serviceKey,
        serviceLabel: _selectedService!.serviceLabel,
        citizenType:  _citizenType,
        reason:       _reasonController.text.trim(),
        symptoms:     _symptomsController.text.trim(),
      ));
      if (mounted) { 
        _refreshDashboard();
        _startRefreshTimer(); // Start auto-refresh after joining queue
        setState(() => _isSubmitting = false); 
      }
    } catch (e) {
      if (mounted) { setState(() => _isSubmitting = false); _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true); }
    }
  }

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: _C.danger.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.cancel_outlined, color: _C.danger, size: 28),
          ),
          const SizedBox(height: 16),
          const Text('Leave Queue?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _C.textDark)),
          const SizedBox(height: 8),
          const Text('Your spot will be lost and you\'ll need to rejoin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _C.textMuted, height: 1.4)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: _C.fieldBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel', style: TextStyle(color: _C.textMuted, fontWeight: FontWeight.bold)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.danger,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Leave', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )),
          ]),
        ]),
      ),
    );
    if (confirm != true) return;
    try {
      _userManuallyCancelled = true;
      final success = await ApiService.cancelMyQueue();
      if (success) {
        _unsubscribeQueueRealtime();
        _stopRefreshTimer(); // Stop auto-refresh after leaving queue
        _activeQueueId = null;
        _clearFormInputs();
        _refreshDashboard();
        _showSnack('You have left the queue.');
      } else {
        _userManuallyCancelled = false;
        _showSnack('Unable to cancel ticket. Please refresh.', isError: true);
      }
    } catch (e) {
      _userManuallyCancelled = false;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: isError ? _C.danger : _C.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: FutureBuilder<QueueDashboardSnapshot>(
              future: _dashboardFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: _C.primary));
                }
                final data = snapshot.data;
                if (data != null && data.hasActiveQueue) {
                  return ActiveTicketCard(
                    queue: data,
                    isSubmitting: _isSubmitting,
                    onCancel: _handleCancel,
                  );
                }
                return QueueJoinForm(
                  servicesFuture: _servicesFuture,
                  limiterStatusFuture: _limiterStatusFuture,
                  selectedService: _selectedService,
                  onServiceSelected: (service) => setState(() => _selectedService = service),
                  citizenType: _citizenType,
                  onCitizenTypeChanged: (type) => setState(() => _citizenType = type),
                  reasonController: _reasonController,
                  symptomsController: _symptomsController,
                  isSubmitting: _isSubmitting,
                  onJoin: _handleJoin,
                );
              },
            ),
          ),
        ),
      ]),
      bottomNavigationBar: widget.isEmbeddedInShell ? null : _buildBottomNav(),
    );
  }

  // ── Header ───────────────────────────────────────────────────
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
          padding: const EdgeInsets.fromLTRB(16, 16, 20, 28),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Queue Tracker', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
                SizedBox(height: 2),
                Text('AFM Roquero Medical Clinic', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            GestureDetector(
              onTap: _refreshDashboard,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withOpacity(0.25))),
                child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ),
    );
  }



  // ── Bottom Navigation ────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded,                'label': 'Home'},
      {'icon': Icons.event_note_rounded,          'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded,      'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: const BorderRadius.only(
          topLeft:  Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [BoxShadow(color: _C.textDark.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -4))],
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
                    Navigator.push(context, _pageRoute(
                      uKonekDashboardPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    )).then((_) {
                      if (mounted) setState(() => _selectedTab = 2);
                    });
                  } else if (i == 1) {
                    Navigator.push(context, _pageRoute(
                      uKonekMedicineSchedulerPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    )).then((_) {
                      if (mounted) setState(() => _selectedTab = 2);
                    });
                  } else if (i == 2) {
                    _refreshDashboard(); // Already here — soft refresh
                  } else if (i == 3) {
                    Navigator.push(context, _pageRoute(
                      uKonekProfilePage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                        fullName:  widget.username,
                      ),
                    )).then((_) {
                      if (mounted) setState(() => _selectedTab = 2);
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

  Route _pageRoute(Widget page) =>
  AppPageRoute.slideRight(page);


}