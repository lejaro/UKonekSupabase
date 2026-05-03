import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/api_service.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekMedicineScheduler.dart';

class _C {
  // ── Medical Green Design Tokens ──────────────────────────────
  static const primary      = Color(0xFF28A745); // Health Green
  static const primaryMid   = Color(0xFF1B5E20); // Forest Green
  static const bg           = Color(0xFFF8FCF9); // Mint Background
  static const surface      = Colors.white;
  static const textDark     = Color(0xFF1B2E1E); // Dark Forest Charcoal
  static const textMuted    = Color(0xFF637367); // Muted Sage
  static const fieldBorder  = Color(0xFFE2E9E3); // Light Mist Divider
  static const success      = Color(0xFF28A745);
  static const warning      = Color(0xFFF59E0B);
  static const shadow       = Color(0x0A000000);
}

class uKonekJoinQueuePage extends StatefulWidget {
  // Fixed: Parameters added to resolve image_89b13b.png errors
  final String username;
  final String citizenId;

  const uKonekJoinQueuePage({
    super.key,
    required this.username,
    required this.citizenId,
  });

  @override
  State<uKonekJoinQueuePage> createState() => _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState extends State<uKonekJoinQueuePage> {
  late Future<QueueDashboardSnapshot> _dashboardFuture;
  late Future<List<QueueServiceOption>> _servicesFuture;
  Timer? _refreshTimer;
  int _selectedTab = 2; // Queue tab index

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

  Future<void> _handleJoin() async {
    if (_selectedService == null) return _showSnack("Please select a service.");
    if (_reasonController.text.trim().isEmpty) return _showSnack("Reason is required.");

    setState(() => _isSubmitting = true);
    try {
      await ApiService.joinQueue(QueueJoinRequest(
        serviceKey: _selectedService!.serviceKey,
        serviceLabel: _selectedService!.serviceLabel,
        citizenType: _citizenType,
        reason: _reasonController.text.trim(),
        symptoms: _symptomsController.text.trim(),
      ));
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
                  return const Center(child: CircularProgressIndicator(color: _C.primary));
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
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.dashboard_rounded,           'label': 'Home'},
      {'icon': Icons.event_note_rounded,           'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded,  'label': 'Queue'},
      {'icon': Icons.person_outline_rounded,       'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
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
                  if (i == 0) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekDashboardPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    ));
                  } else if (i == 1) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekMedicineSchedulerPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    ));
                  } else if (i == 2) {
                    // Already on Queue page
                    setState(() => _selectedTab = i);
                  } else if (i == 3) {
                    // ✅ Queue page doesn't have profile data — just pop back to Dashboard
                    // which will then navigate to Profile with full data
                    Navigator.pop(context);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _C.primaryMid.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(tabs[i]['icon'] as IconData,
                      color: isSelected ? _C.primaryMid : Colors.grey.shade400,
                      size: 22,
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      Text(tabs[i]['label'] as String,
                        style: const TextStyle(color: _C.primaryMid, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
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

  // ── HEADER ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 60, 24, 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(40)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text("Queue Tracker", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          IconButton(onPressed: _refreshDashboard, icon: const Icon(Icons.refresh, color: Colors.white70)),
        ],
      ),
    );
  }

  // ── FORM VIEW ───────────────────────────────────────────────
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
                decoration: _inputDecoration("Select Healthcare Service"),
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
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  // ── ACTIVE TICKET VIEW ──────────────────────────────────────
  Widget _buildActiveTicketView(QueueDashboardSnapshot queue) {
    int ahead = (queue.myQueueNumber ?? 0) - (queue.currentlyServingQueueNumber ?? 0);
    Color statusColor = queue.isOnCall ? _C.warning : (ahead <= 0 ? _C.success : _C.primaryMid);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildPeopleAheadBanner(ahead, queue.currentlyServingQueueNumber ?? 0, statusColor),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: _C.textDark.withOpacity(0.05), blurRadius: 20)],
            ),
            child: Column(
              children: [
                QrImageView(
                  data: queue.ticketCode,
                  size: 180,
                  eyeStyle: const QrEyeStyle(color: _C.primaryMid, eyeShape: QrEyeShape.square),
                ),
                const SizedBox(height: 20),
                Text('#${(queue.myQueueNumber ?? 0).toString().padLeft(3, '0')}',
                    style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: statusColor)),
                Text(queue.serviceLabel.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: _C.textMuted, fontSize: 12)),
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(color: _C.fieldBorder)),
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
                        : const Text("CANCEL QUEUE", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── UI HELPERS ──────────────────────────────────────────────
  InputDecoration _inputDecoration(String hint) => InputDecoration(
    filled: true, fillColor: Colors.white, hintText: hint,
    hintStyle: const TextStyle(color: _C.textMuted, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.fieldBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.fieldBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.primary, width: 1.5)),
  );

  Widget _buildPeopleAheadBanner(int ahead, int current, Color color) {
    bool isTurn = ahead <= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(isTurn ? Icons.check_circle : Icons.groups_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("CURRENTLY SERVING: #$current", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            Text(isTurn ? "PLEASE PROCEED TO CLINIC" : "There are $ahead people ahead of you", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _C.textDark)),
          ])),
        ],
      ),
    );
  }

  Widget _submitButton() => SizedBox(
    width: double.infinity, height: 58,
    child: ElevatedButton(
      onPressed: _isSubmitting ? null : _handleJoin,
      style: ElevatedButton.styleFrom(backgroundColor: _C.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0),
      child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text("JOIN QUEUE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _buildTypeSelector() {
    final types = ['regular', 'pwd', 'pregnant'];
    return Row(children: types.map((t) => Expanded(child: GestureDetector(
      onTap: () => setState(() => _citizenType = t),
      child: Container(
        margin: const EdgeInsets.all(4), padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: _citizenType == t ? _C.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.fieldBorder)),
        child: Center(child: Text(t.toUpperCase(), style: TextStyle(color: _citizenType == t ? Colors.white : _C.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
      ),
    ))).toList());
  }

  Widget _textField(TextEditingController c, String h, int l) => TextField(
    controller: c, maxLines: l,
    decoration: _inputDecoration(h),
  );

  Widget _sectionLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: _C.textDark)));

  Widget _detailRow(String l, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: _C.textMuted)),
      Text(v, style: const TextStyle(fontWeight: FontWeight.bold, color: _C.textDark))
    ]),
  );

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Queue?"),
        content: const Text("Are you sure?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("NO")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("YES", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isSubmitting = true);
    try {
      if (await ApiService.cancelMyQueue()) { _refreshDashboard(); }
    } catch (e) { _showSnack(e.toString()); } finally { if (mounted) setState(() => _isSubmitting = false); }
  }
}