import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:ukonekmobile/uKonekDashboardPage.dart';
import 'services/api_service.dart';
import 'uKonekMedicineScheduler.dart';

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

  const uKonekJoinQueuePage({
    super.key,
    required this.username,
    required this.citizenId,
  });

  @override
  State<uKonekJoinQueuePage> createState() => _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState extends State<uKonekJoinQueuePage>
    with SingleTickerProviderStateMixin {

  late Future<QueueDashboardSnapshot> _dashboardFuture;
  late Future<List<QueueServiceOption>> _servicesFuture;
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 9), (_) => _refreshDashboard());
  }

  void _loadInitialData() {
    _dashboardFuture = ApiService.getMyQueueDashboard();
    _servicesFuture  = ApiService.listAvailableQueueServices();
  }

  void _refreshDashboard() {
    if (!mounted) return;
    setState(() { _dashboardFuture = ApiService.getMyQueueDashboard(); });
  }

  @override
  void dispose() {
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
      await ApiService.joinQueue(QueueJoinRequest(
        serviceKey:   _selectedService!.serviceKey,
        serviceLabel: _selectedService!.serviceLabel,
        citizenType:  _citizenType,
        reason:       _reasonController.text.trim(),
        symptoms:     _symptomsController.text.trim(),
      ));
      if (mounted) { _refreshDashboard(); setState(() => _isSubmitting = false); }
    } catch (e) {
      if (mounted) { setState(() => _isSubmitting = false); _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true); }
    }
  }

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      // AFTER (fixed) — name the parameter 'ctx' so it can be referenced
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
          const Text('Cancel Queue?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _C.textDark)),
          const SizedBox(height: 8),
          const Text('Your spot will be lost and you\'ll need to rejoin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _C.textMuted, height: 1.4)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),  // ✅ ctx instead of _
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: _C.fieldBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Keep Spot', style: TextStyle(color: _C.textMuted, fontWeight: FontWeight.bold)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),   // ✅ ctx instead of _
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.danger,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )),
          ]),
        ]),
      ),
    );
    if (confirm != true) return;
    setState(() => _isSubmitting = true);
    try {
      if (await ApiService.cancelMyQueue()) _refreshDashboard();
    } catch (e) { _showSnack(e.toString()); }
    finally { if (mounted) setState(() => _isSubmitting = false); }
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
                if (snapshot.connectionState == ConnectionState.waiting) {
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
      bottomNavigationBar: _buildBottomNav(),
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
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withOpacity(0.25))),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Info strip ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.primary.withOpacity(0.15))),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _C.primaryMid, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text('Fill in your visit details below to get a queue number.', style: TextStyle(fontSize: 12, color: _C.primaryMid, height: 1.4))),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Service selection ───────────────────────────────
            _sectionLabel('HEALTHCARE SERVICE', Icons.medical_services_outlined),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.fieldBorder), boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 8, offset: Offset(0, 3))]),
              child: DropdownButtonFormField<QueueServiceOption>(
                value: services.contains(_selectedService) ? _selectedService : null,
                dropdownColor: _C.surface,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _C.primary),
                decoration: InputDecoration(
                  hintText: 'Choose a healthcare service',
                  hintStyle: TextStyle(color: _C.textMuted.withOpacity(0.6), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                items: services.map((s) => DropdownMenuItem(
                  value: s,
                  child: Row(children: [
                    Container(width: 32, height: 32, decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.medical_services_outlined, size: 16, color: _C.primaryMid)),
                    const SizedBox(width: 12),
                    Text(s.serviceLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.textDark)),
                  ]),
                )).toList(),
                onChanged: (val) => setState(() => _selectedService = val),
              ),
            ),
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
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: _C.primary.withOpacity(0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.confirmation_number_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('GET QUEUE NUMBER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                ]),
              ),
            ),
          ]),
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
    final isOnCall    = queue.isOnCall;
    final Color statusColor = isOnCall ? _C.warning : (isTurn ? _C.success : _C.primaryMid);
    final String statusMsg  = isOnCall ? 'You\'re being called!' : (isTurn ? 'Please proceed to clinic' : '$ahead ${ahead == 1 ? 'person' : 'people'} ahead of you');
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
              Text('Now Serving #${(queue.currentlyServingQueueNumber ?? 0).toString().padLeft(3, '0')}',
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
        const SizedBox(height: 20),

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
                  _statChip(Icons.confirmation_number_rounded, 'Serving', '#${(queue.currentlyServingQueueNumber ?? 0).toString().padLeft(3, '0')}', statusColor),
                ]),
                const SizedBox(height: 24),

                // Cancel button
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

  // ── Bottom Navigation ────────────────────────────────────────
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
                      builder: (_) => uKonekDashboardPage(username: widget.username, citizenId: widget.citizenId),
                    ));
                  } else if (i == 1) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekMedicineSchedulerPage(username: widget.username, citizenId: widget.citizenId),
                    ));
                  } else if (i == 2) {
                    setState(() => _selectedTab = 2);
                  } else if (i == 3) {
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
                    Icon(tabs[i]['icon'] as IconData, color: isSelected ? _C.primaryMid : Colors.grey.shade400, size: 22),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      Text(tabs[i]['label'] as String, style: const TextStyle(color: _C.primaryMid, fontSize: 12, fontWeight: FontWeight.bold)),
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

  Widget _sectionLabel(String text, IconData icon) {
    return Row(children: [
      Container(width: 28, height: 28, decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: _C.primaryMid, size: 14)),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _C.textMuted, letterSpacing: 1.1)),
    ]);
  }
}