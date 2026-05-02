import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/api_service.dart';

class _C {
  static const primary = Color(0xFF0D47A1);
  static const primaryMid = Color(0xFF1976D2);
  static const bg = Color(0xFFF4F7FE);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1A1A2E);
  static const textMuted = Color(0xFF667085);
  static const fieldBorder = Color(0xFFDDE3F0);
  static const success = Color(0xFF079455);
  static const warning = Color(0xFFF59E0B);
}

class uKonekJoinQueuePage extends StatefulWidget {
  const uKonekJoinQueuePage({super.key});

  @override
  State<uKonekJoinQueuePage> createState() => _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState extends State<uKonekJoinQueuePage> {
  late Future<QueueDashboardSnapshot> _dashboardFuture;
  late Future<List<QueueServiceOption>> _servicesFuture;
  Timer? _refreshTimer;

  // Form State
  QueueServiceOption? _selectedService;
  String _citizenType = 'regular';
  final _reasonController = TextEditingController();
  final _symptomsController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 9), (_) => _refreshDashboard());
  }

  void _loadInitialData() {
    _dashboardFuture = ApiService.getMyQueueDashboard();
    _servicesFuture = ApiService.listAvailableQueueServices();
  }

  void _refreshDashboard() {
    if (!mounted) return;
    setState(() {
      _dashboardFuture = ApiService.getMyQueueDashboard();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _reasonController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }

  // ── FIX: REFACTORED JOIN LOGIC (No async inside setState) ──────────
  Future<void> _handleJoin() async {
    if (_selectedService == null) return _showSnack("Please select a service.");
    if (_reasonController.text.trim().isEmpty) return _showSnack("Reason is required.");

    // 1. Set loading state synchronously
    setState(() => _isSubmitting = true);

    try {
      // 2. Perform ASYNC work outside of setState
      await ApiService.joinQueue(QueueJoinRequest(
        serviceKey: _selectedService!.serviceKey,
        serviceLabel: _selectedService!.serviceLabel,
        citizenType: _citizenType,
        reason: _reasonController.text.trim(),
        symptoms: _symptomsController.text.trim(),
      ));

      // 3. Only update the UI state after the work is finished
      if (mounted) {
        _refreshDashboard();
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _C.primary,
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
            child: FutureBuilder<QueueDashboardSnapshot>(
              future: _dashboardFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data;
                if (data != null && data.hasActiveQueue) {
                  return _buildActiveTicketView(data);
                } else {
                  return _buildJoinQueueForm();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. JOIN FORM VIEW ──────────────────────────────────────────────
  Widget _buildJoinQueueForm() {
    return FutureBuilder<List<QueueServiceOption>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        final services = snapshot.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel("Healthcare Service"),
              const SizedBox(height: 12),
              DropdownButtonFormField<QueueServiceOption>(
                value: services.contains(_selectedService) ? _selectedService : null,
                dropdownColor: Colors.white,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _C.primary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: "Select Healthcare Service",
                  hintStyle: const TextStyle(color: _C.textMuted, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _C.primary, width: 1.5)),
                ),
                items: services.map((s) => DropdownMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      const Icon(Icons.medical_services_outlined, size: 20, color: _C.primaryMid),
                      const SizedBox(width: 12),
                      Text(s.serviceLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _C.textDark)),
                    ],
                  ),
                )).toList(),
                onChanged: (val) => setState(() => _selectedService = val),
              ),
              const SizedBox(height: 24),
              _sectionLabel("Priority Category"),
              _buildTypeSelector(),
              const SizedBox(height: 24),
              _sectionLabel("Medical Details"),
              const SizedBox(height: 12),
              _textField(_reasonController, "Reason for Visit", 2),
              const SizedBox(height: 12),
              _textField(_symptomsController, "Symptoms (Optional)", 3),
              const SizedBox(height: 32),
              _submitButton(),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }

  // ── 2. ACTIVE TICKET VIEW (INTEGRATED PEOPLE AHEAD) ────────────────
  Widget _buildActiveTicketView(QueueDashboardSnapshot queue) {
    int myNum = queue.myQueueNumber ?? 0;
    int currentNum = queue.currentlyServingQueueNumber ?? 0;
    int peopleAhead = myNum - currentNum;

    // Status color motifs
    Color statusColor;
    String statusLabel;
    final rawStatus = (queue.status ?? "").toLowerCase().trim();
    final bool isOnCall = queue.isOnCall || rawStatus == 'on_call';
    final bool isServing = !isOnCall && rawStatus == 'serving';

    if (isOnCall) {
      statusColor = _C.warning;
      statusLabel = "ON CALL";
    } else if (isServing) {
      statusColor = _C.success;
      statusLabel = "NOW SERVING";
    } else {
      statusColor = _C.primaryMid;
      statusLabel = "WAITING";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildPeopleAheadBanner(peopleAhead, currentNum, queue),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
            ),
            child: Column(
              children: [
                QrImageView(data: queue.ticketCode, size: 180),
                const SizedBox(height: 20),
                Text('#${myNum.toString().padLeft(3, '0')}',
                    style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: statusColor)),
                Text(queue.serviceLabel.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: _C.textMuted, fontSize: 12)),
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
                _detailRow("Your Status", statusLabel, valueColor: statusColor),
                _detailRow("Estimated Wait", "${queue.estimatedWaitMinutes} mins"),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : _handleCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.redAccent, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      foregroundColor: Colors.redAccent,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                        : const Text("CANCEL QUEUE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Queue?"),
        content: const Text("Are you sure you want to cancel your current queue ticket?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("NO")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("YES, CANCEL", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      final success = await ApiService.cancelMyQueue();
      if (success) {
        _showSnack("Queue ticket cancelled.");
        _refreshDashboard();
      } else {
        _showSnack("Failed to cancel ticket.");
      }
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── UI HELPERS ─────────────────────────────────────────────────────

  Widget _buildPeopleAheadBanner(int ahead, int current, QueueDashboardSnapshot queue) {
    final rawStatus = (queue.status ?? "").toLowerCase().trim();
    final bool isOnCall = queue.isOnCall || rawStatus == 'on_call';
    final bool isServing = !isOnCall && rawStatus == 'serving';
    bool isTurn = isServing || isOnCall;

    Color bannerColor = isServing ? _C.success : (isOnCall ? _C.warning : _C.primaryMid);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(isTurn ? (isServing ? Icons.check_circle : Icons.notifications_active) : Icons.groups_rounded,
              color: bannerColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("CURRENTLY SERVING: #$current",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: bannerColor)),
                Text(isServing ? "PLEASE PROCEED TO WINDOW" : (isOnCall ? "YOU ARE CALLED - PLEASE PROCEED" : "There are $ahead people ahead of you"),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isTurn ? bannerColor : _C.textDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleJoin,
        style: ElevatedButton.styleFrom(backgroundColor: _C.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        child: _isSubmitting
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text("JOIN QUEUE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 60, 24, 25), // Adjusted left padding for the icon
      decoration: const BoxDecoration(
        color: _C.primary,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(40)),
      ),
      child: Row(
        children: [
          // THE NEW BACK BUTTON
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () {
              // This takes the user back to the Dashboard/Previous Screen
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              "Queue Tracker",
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          // REFRESH BUTTON
          IconButton(
            onPressed: _refreshDashboard,
            icon: const Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    final types = ['regular', 'pwd', 'pregnant'];
    return Row(
      children: types.map((t) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _citizenType = t),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _citizenType == t ? _C.primary : Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(t.toUpperCase(), style: TextStyle(color: _citizenType == t ? Colors.white : _C.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
          ),
        ),
      )).toList(),
    );
  }

  Widget _textField(TextEditingController c, String hint, int lines) => TextField(
    controller: c, maxLines: lines,
    decoration: InputDecoration(hintText: hint, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
  );

  Widget _sectionLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: _C.textDark)));

  Widget _detailRow(String l, String v, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: _C.textMuted)),
      Text(v,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: valueColor ?? _C.textDark))
    ]),
  );
}