import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:ukonekmobile/uKonekDashboardPage.dart';
import 'services/api_service.dart';
import 'uKonekMedicineScheduler.dart';
import 'uKonekProfilePage.dart';
import 'utils/app_transitions.dart';
import 'uKonekMainShellPage.dart';

// ── Design Tokens ─────────────────────────────────────────────
class _C {
  static const primary     = Color(0xFF28A745);
  static const primaryMid  = Color(0xFF1B5E20);
  static const primaryLight= Color(0xFFE8F5E9);
  static const bg          = Color(0xFFF4FAF5);
  static const surface     = Colors.white;
  static const textDark    = Color(0xFF1B2E1E);
  static const textMuted   = Color(0xFF637367);
  static const fieldBorder = Color(0xFFDCEDDF);
  static const fieldBg     = Color(0xFFF8FCF9);
  static const success     = Color(0xFF28A745);
  static const warning     = Color(0xFFF59E0B);
  static const danger      = Color(0xFFDC3545);
  static const shadow      = Color(0x0D1B2E1E);
}

class uKonekJoinQueuePage extends StatefulWidget {
  final String username;
  final String citizenId;
  final String? initialServiceKey;

  final bool isEmbeddedInShell;

  const uKonekJoinQueuePage({
    super.key,
    required this.username,
    required this.citizenId,
    this.initialServiceKey,
    this.isEmbeddedInShell = false,
  });

  @override
  State<uKonekJoinQueuePage> createState() => _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState extends State<uKonekJoinQueuePage>
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

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadInitialData();
    _animController.forward();
    // Timer will be started only when citizen has active queue ticket
  }

  void _loadInitialData() {
    _dashboardFuture = ApiService.getMyQueueDashboard();
    _servicesFuture  = ApiService.listAvailableQueueServices();
    _limiterStatusFuture = ApiService.getQueueLimiterStatus();
    
    // Check if citizen has active queue and start timer accordingly
    _dashboardFuture.then((snapshot) {
      if (!mounted) return;
      if (snapshot.hasActiveQueue) {
        _startRefreshTimer();
      } else {
        _stopRefreshTimer();
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

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
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
    
    // Re-check if we should continue refreshing
    _dashboardFuture.then((snapshot) {
      if (!mounted) return;
      if (snapshot.hasActiveQueue) {
        if (_refreshTimer == null) _startRefreshTimer();
      } else {
        _stopRefreshTimer();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animController.dispose();
    _reasonController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }

  void _showServiceSearchModal(List<QueueServiceOption> services) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ServiceSearchModal(
          services: services,
          onSelected: (service) {
            setState(() => _selectedService = service);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Widget _buildSearchableServicePicker(List<QueueServiceOption> services) {
    return InkWell(
      onTap: () => _showServiceSearchModal(services),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.fieldBorder),
          boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.medical_services_outlined, size: 16, color: _C.primaryMid),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedService?.serviceLabel ?? 'Choose a healthcare service',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _selectedService != null ? FontWeight.w600 : FontWeight.normal,
                  color: _selectedService != null ? _C.textDark : _C.textMuted.withOpacity(0.6),
                ),
              ),
            ),
            const Icon(Icons.search_rounded, color: _C.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handleJoin() async {
    if (_selectedService == null) return _showSnack('Please select a service.', isError: true);
    if (_reasonController.text.trim().isEmpty) return _showSnack('Reason for visit is required.', isError: true);
    setState(() => _isSubmitting = true);
    try {
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
      final success = await ApiService.cancelMyQueue();
      if (success) {
        _stopRefreshTimer(); // Stop auto-refresh after leaving queue
        _refreshDashboard();
        _showSnack('You have left the queue.');
      } else {
        _showSnack('Unable to cancel ticket. Please refresh.', isError: true);
      }
    } catch (e) {
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
                  return _buildActiveTicketView(data);
                }
                return _buildJoinQueueForm();
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

  // ── Join Queue Form ──────────────────────────────────────────
  Widget _buildJoinQueueForm() {
    return FutureBuilder<List<QueueServiceOption>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        final services = snapshot.data ?? [];
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info strip ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _C.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.primary.withOpacity(0.15)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: _C.primaryMid, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Fill in your visit details below to get a queue number.',
                      style: TextStyle(fontSize: 12, color: _C.primaryMid, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // ── Queue Limiter Status ────────────────────────────
              FutureBuilder<QueueLimiterStatus>(
                future: _limiterStatusFuture,
                builder: (context, limiterSnapshot) {
                  final limiterStatus = limiterSnapshot.data;
                  if (limiterStatus == null) {
                    return const SizedBox.shrink();
                  }

                  // Show limit reached warning
                  if (limiterStatus.limitReached) {
                    return Column(children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Column(children: [
                          Row(children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.event_busy_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Consultations Full',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Daily limit reached',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'We\'ve reached our daily consultation limit of ${limiterStatus.dailyLimit} patients for today due to high demand.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF991B1B),
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'What you can do:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildLimiterTip(Icons.schedule_rounded, 'Try again tomorrow when slots reset'),
                                _buildLimiterTip(Icons.phone_rounded, 'Call the clinic for scheduling assistance'),
                                _buildLimiterTip(Icons.emergency_rounded, 'For emergencies, visit immediately'),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ]);
                  }

                  // Show remaining slots info
                  if (limiterStatus.remainingSlots <= 5) {
                    return Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF9C3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE047)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFF854D0E), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Only ${limiterStatus.remainingSlots} consultation slots remaining today!',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF854D0E),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ]);
                  }

                  // Show available slots info
                  return Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF166534), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${limiterStatus.remainingSlots} of ${limiterStatus.dailyLimit} consultation slots available',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF166534),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ]);
                },
              ),

              _sectionLabel('HEALTHCARE SERVICE', Icons.medical_services_outlined),
              const SizedBox(height: 12),
              _buildSearchableServicePicker(services),
              const SizedBox(height: 24),

              // ── Priority category ───────────────────────────────
              _sectionLabel('PRIORITY CATEGORY', Icons.accessibility_new_rounded),
              const SizedBox(height: 12),
              _buildTypeSelector(),
              const SizedBox(height: 24),

              // ── Medical details ─────────────────────────────────
              _sectionLabel('MEDICAL DETAILS', Icons.description_outlined),
              const SizedBox(height: 12),
              _buildTextField(_reasonController, 'Reason for Visit *', 'e.g. Fever, headache, follow-up checkup...', 2, Icons.edit_note_rounded),
              const SizedBox(height: 12),
              _buildTextField(_symptomsController, 'Symptoms (Optional)', 'Describe your symptoms if any...', 3, Icons.sick_outlined),
              const SizedBox(height: 32),

              // ── Submit button ───────────────────────────────────
              FutureBuilder<QueueLimiterStatus>(
                future: _limiterStatusFuture,
                builder: (context, limiterSnapshot) {
                  final limiterStatus = limiterSnapshot.data;
                  final isLimitReached = limiterStatus?.limitReached ?? false;
                  final isDisabled = _isSubmitting || isLimitReached;

                  return SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isDisabled ? null : _handleJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDisabled ? Colors.grey : _C.primary,
                        foregroundColor: Colors.white,
                        elevation: isDisabled ? 0 : 4,
                        shadowColor: _C.primary.withOpacity(0.35),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(isLimitReached ? Icons.block_rounded : Icons.confirmation_number_rounded, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                isLimitReached ? 'LIMIT REACHED' : 'GET QUEUE NUMBER',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                              ),
                            ]),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Priority type selector ───────────────────────────────────
  Widget _buildTypeSelector() {
    final types = [
      {'key': 'regular',  'label': 'Regular',  'icon': Icons.person_outline_rounded,       'desc': 'Standard'},
      {'key': 'pwd',      'label': 'PWD',       'icon': Icons.accessible_rounded,           'desc': 'Priority'},
      {'key': 'pregnant', 'label': 'Pregnant',  'icon': Icons.pregnant_woman_rounded,       'desc': 'Priority'},
    ];
    return Row(children: types.map((t) {
      final isSelected = _citizenType == t['key'];
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _citizenType = t['key'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? _C.primary : _C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isSelected ? _C.primary : _C.fieldBorder, width: isSelected ? 2 : 1),
              boxShadow: isSelected ? [BoxShadow(color: _C.primary.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))] : [const BoxShadow(color: _C.shadow, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(children: [
              Icon(t['icon'] as IconData, color: isSelected ? Colors.white : _C.textMuted, size: 22),
              const SizedBox(height: 6),
              Text(t['label'] as String, style: TextStyle(color: isSelected ? Colors.white : _C.textDark, fontSize: 11, fontWeight: FontWeight.bold)),
              Text(t['desc'] as String, style: TextStyle(color: isSelected ? Colors.white70 : _C.textMuted, fontSize: 9)),
            ]),
          ),
        ),
      );
    }).toList());
  }

  // ── Text field ───────────────────────────────────────────────
  Widget _buildTextField(TextEditingController ctrl, String label, String hint, int maxLines, IconData icon) {
    return Container(
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.fieldBorder), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 8, offset: Offset(0, 3))]),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, color: _C.textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(fontSize: 13, color: _C.textMuted),
          hintStyle: TextStyle(fontSize: 13, color: _C.textMuted.withOpacity(0.5)),
          prefixIcon: Padding(padding: EdgeInsets.only(bottom: maxLines > 1 ? 40 : 0), child: Icon(icon, color: _C.primary.withOpacity(0.6), size: 20)),
          filled: true,
          fillColor: _C.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  // ── Active Ticket View ───────────────────────────────────────
  Widget _buildActiveTicketView(QueueDashboardSnapshot queue) {
    final ahead       = (queue.myQueueNumber ?? 0) - (queue.currentlyServingQueueNumber ?? 0);
    final isTurn      = ahead <= 0;
    final isOnCall    = queue.isOnCall || queue.status.toLowerCase() == 'on_call';
    final Color statusColor = isOnCall ? _C.warning : (isTurn ? _C.success : _C.primaryMid);
    final String statusMsg  = isOnCall 
        ? 'Please proceed to the nurse for vital assessment' 
        : (isTurn ? 'Please proceed to the doctor\'s office for consultation' : '$ahead ${ahead == 1 ? 'person' : 'people'} ahead of you');
    final IconData statusIcon = isOnCall ? Icons.campaign_rounded : (isTurn ? Icons.check_circle_rounded : Icons.groups_rounded);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(children: [

        // ── Status banner ─────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: statusColor.withOpacity(0.15), shape: BoxShape.circle), child: Icon(statusIcon, color: statusColor, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isOnCall ? 'YOU ARE ON CALL' : (isTurn && queue.status == 'serving' ? 'YOU ARE NOW SERVING' : 'NOW SERVING #${(queue.currentlyServingQueueNumber ?? 0).toString().padLeft(3, '0')}'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(statusMsg, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.textDark)),
            ])),
            if (isOnCall) Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _C.warning, borderRadius: BorderRadius.circular(8)),
              child: const Text('ON CALL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Step Progress Tracker ────────────────────────────
        _buildQueueStepTracker(queue, isOnCall, isTurn),
        const SizedBox(height: 16),

        // ── Ticket card ───────────────────────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: _C.primaryMid.withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(children: [

            // Ticket header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_C.primary, _C.primaryMid]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                const Text('YOUR QUEUE TICKET', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(queue.serviceLabel.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
            ),

            // Queue number + QR
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(children: [

                // Queue number badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.20), width: 2),
                  ),
                  child: Text(
                    '#${(queue.myQueueNumber ?? 0).toString().padLeft(3, '0')}',
                    style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: -2),
                  ),
                ),
                const SizedBox(height: 6),
                Text('YOUR NUMBER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _C.textMuted.withOpacity(0.6), letterSpacing: 1.5)),
                const SizedBox(height: 24),

                // Divider with dots (ticket stub look)
                Row(children: [
                  Container(width: 20, height: 20, decoration: BoxDecoration(color: _C.bg, shape: BoxShape.circle, border: Border.all(color: _C.fieldBorder))),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: List.generate(18, (i) => Expanded(child: Container(height: 1, color: i.isEven ? _C.fieldBorder : Colors.transparent)))),
                  )),
                  Container(width: 20, height: 20, decoration: BoxDecoration(color: _C.bg, shape: BoxShape.circle, border: Border.all(color: _C.fieldBorder))),
                ]),
                const SizedBox(height: 24),

                // QR Code
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: _C.fieldBorder)),
                  child: QrImageView(
                    data: queue.ticketCode,
                    size: 160,
                    eyeStyle: const QrEyeStyle(color: _C.primaryMid, eyeShape: QrEyeShape.square),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _C.primaryMid),
                  ),
                ),
                const SizedBox(height: 16),
                Text(queue.ticketCode, style: const TextStyle(fontSize: 11, color: _C.textMuted, fontWeight: FontWeight.w600, letterSpacing: 1)),
                const SizedBox(height: 24),

                // Stats row
                Row(children: [
                  _statChip(Icons.timer_outlined, 'Est. Wait', '${queue.estimatedWaitMinutes} mins', _C.primaryMid),
                  const SizedBox(width: 12),
                  _statChip(
                    Icons.people_outline_rounded,
                    'People Ahead',
                    '${ahead > 0 ? ahead : "0"}',
                    _C.primaryMid,
                  ),
                ]),
                const SizedBox(height: 24),

                // Cancel button (Hidden when On Call or Serving)
                if (!isOnCall && !isTurn)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _handleCancel,
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _C.danger))
                        : const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('LEAVE QUEUE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _C.danger,
                      side: BorderSide(color: _C.danger.withOpacity(0.5), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _statChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.15))),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildQueueStepTracker(QueueDashboardSnapshot queue, bool isOnCall, bool isTurn) {
    final status = queue.status.toLowerCase();
    final bool vitalsDone = queue.hasVitals || status == 'serving' || status == 'completed';
    final bool vitalsActive = !vitalsDone && (isOnCall || status == 'on_call');
    final bool consultDone = status == 'completed';
    final bool consultActive = status == 'serving';
    final bool allDone = status == 'completed';

    // Step states:
    // Step 0: Ticket (Issued) -> Always completed for an active ticket
    // Step 1: Vitals (Nurse)  -> Completed ONLY when vitals are recorded or consultation started
    // Step 2: Consult (Doctor)-> Completed ONLY when consultation finishes
    // Step 3: Done (Rx/Exit)  -> Completed when ticket is marked completed
    final stepStates = [
      {
        'label': 'Ticket',
        'desc': 'Issued',
        'icon': Icons.confirmation_number_outlined,
        'isDone': true,
        'isCurrent': !vitalsActive && !vitalsDone && status == 'waiting',
      },
      {
        'label': 'Vitals',
        'desc': vitalsDone ? 'Completed' : (vitalsActive ? 'On Call' : 'Pending'),
        'icon': Icons.monitor_heart_outlined,
        'isDone': vitalsDone,
        'isCurrent': vitalsActive,
      },
      {
        'label': 'Consult',
        'desc': consultDone ? 'Completed' : (consultActive ? 'Serving' : (vitalsDone ? 'Waiting Dr.' : 'Queueing')),
        'icon': Icons.medical_services_outlined,
        'isDone': consultDone,
        'isCurrent': consultActive,
      },
      {
        'label': 'Done',
        'desc': allDone ? 'Finished' : 'Rx / Exit',
        'icon': Icons.task_alt_rounded,
        'isDone': allDone,
        'isCurrent': false,
      },
    ];

    String stepBadgeText = 'Step 1 of 4';
    if (allDone) {
      stepBadgeText = 'Step 4 of 4 (Complete)';
    } else if (consultActive) {
      stepBadgeText = 'Step 3 of 4 (Consultation)';
    } else if (vitalsDone) {
      stepBadgeText = 'Step 2 of 4 (Vitals Taken)';
    } else if (vitalsActive) {
      stepBadgeText = 'Step 2 of 4 (On Call)';
    } else {
      stepBadgeText = 'Step 1 of 4 (Ticket Issued)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8F5E9), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Color(0x0C1B2E1E), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VISIT PROGRESSION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _C.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _C.primaryMid.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stepBadgeText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryMid,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(stepStates.length, (i) {
              final item = stepStates[i];
              final bool isDone = item['isDone'] as bool;
              final bool isCurrent = item['isCurrent'] as bool;
              final Color stepColor = isDone
                  ? _C.success
                  : (isCurrent
                      ? (vitalsActive ? _C.warning : _C.primaryMid)
                      : _C.textMuted.withOpacity(0.35));

              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? _C.success
                                  : (isCurrent
                                      ? stepColor.withOpacity(0.12)
                                      : Colors.grey.shade100),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCurrent ? stepColor : (isDone ? _C.success : Colors.grey.shade300),
                                width: isCurrent ? 2 : 1.2,
                              ),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                        color: stepColor.withOpacity(0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Icon(
                              isDone ? Icons.check_rounded : (item['icon'] as IconData),
                              size: isDone ? 18 : 16,
                              color: isDone ? Colors.white : stepColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: (isCurrent || isDone) ? FontWeight.w800 : FontWeight.w600,
                              color: isDone ? _C.textDark : (isCurrent ? _C.textDark : _C.textMuted),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            item['desc'] as String,
                            style: TextStyle(
                              fontSize: 8,
                              color: isCurrent ? stepColor : (isDone ? _C.success : _C.textMuted.withOpacity(0.7)),
                              fontWeight: (isCurrent || isDone) ? FontWeight.w700 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (i < stepStates.length - 1)
                      Container(
                        width: 14,
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 24),
                        color: (i == 0 && vitalsDone) ||
                               (i == 1 && consultDone) ||
                               (i == 2 && allDone)
                            ? _C.success
                            : Colors.grey.shade300,
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
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

  Widget _sectionLabel(String text, IconData icon) {
    return Row(children: [
      Container(width: 28, height: 28, decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: _C.primaryMid, size: 14)),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _C.textMuted, letterSpacing: 1.1)),
    ]);
  }

  Widget _buildLimiterTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF991B1B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF991B1B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSearchModal extends StatefulWidget {
  final List<QueueServiceOption> services;
  final Function(QueueServiceOption) onSelected;

  const _ServiceSearchModal({required this.services, required this.onSelected});

  @override
  State<_ServiceSearchModal> createState() => _ServiceSearchModalState();
}

class _ServiceSearchModalState extends State<_ServiceSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  List<QueueServiceOption> _filteredServices = [];

  @override
  void initState() {
    super.initState();
    _filteredServices = widget.services;
  }

  void _filterServices(String query) {
    setState(() {
      _filteredServices = widget.services
          .where((s) => s.serviceLabel.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.75,
      decoration: const BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: _C.textMuted.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(children: [
            const Text('Select Healthcare Service', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.textDark)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.fieldBorder),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterServices,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search healthcare service...',
                  hintStyle: TextStyle(color: _C.textMuted.withOpacity(0.5), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: _C.primary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _filteredServices.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, size: 48, color: _C.textMuted.withOpacity(0.3)),
                    const SizedBox(height: 12),
                    Text('No services found', style: TextStyle(color: _C.textMuted.withOpacity(0.6), fontSize: 14)),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  itemCount: _filteredServices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final s = _filteredServices[index];
                    return InkWell(
                      onTap: () => widget.onSelected(s),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _C.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _C.fieldBorder),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.medical_services_outlined, size: 18, color: _C.primaryMid),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.serviceLabel, style: const TextStyle(fontWeight: FontWeight.w600, color: _C.textDark, fontSize: 14)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: _C.textMuted, size: 20),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}