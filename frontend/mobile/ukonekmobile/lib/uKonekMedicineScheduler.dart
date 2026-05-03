import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekJoinQueuePage.dart';
import 'services/api_service.dart';

class uKonekMedicineSchedulerPage extends StatefulWidget {
  // Session data passed from the Dashboard to maintain user identity
  final String username;
  final String citizenId;

  const uKonekMedicineSchedulerPage({
    super.key,
    required this.username,
    required this.citizenId,
  });

  @override
  State<uKonekMedicineSchedulerPage> createState() => _uKonekMedicineSchedulerPageState();
}

class _uKonekMedicineSchedulerPageState extends State<uKonekMedicineSchedulerPage> {
  static const Color _primary    = Color(0xFF28A745);
  static const Color _primaryMid = Color(0xFF1B5E20);
  static const Color _bg         = Color(0xFFF8FCF9);
  static const Color _textDark   = Color(0xFF1B2E1E);
  static const Color _textMuted  = Color(0xFF637367);
  static const Color _fieldBdr   = Color(0xFFE2E9E3);

  int _selectedTab = 1;

  bool _loading = true;
  String? _error;
  List<ScheduledMedicine> _medicines = [];
  final Set<String> _takenDoses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final meds = await ApiService.getMedicineSchedule();
      setState(() { _medicines = meds; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _todayDoses {
    final doses = <Map<String, dynamic>>[];
    for (final med in _medicines) {
      for (int i = 0; i < med.doseTimes.length; i++) {
        doses.add({'med': med, 'time': med.doseTimes[i], 'doseIndex': i});
      }
    }
    doses.sort((a, b) => _parseTime(a['time'] as String).compareTo(_parseTime(b['time'] as String)));
    return doses;
  }

  int _parseTime(String t) {
    try {
      final p = t.split(' '); final hm = p[0].split(':');
      int h = int.parse(hm[0]); final m = int.parse(hm[1]);
      if (p[1] == 'PM' && h != 12) h += 12;
      if (p[1] == 'AM' && h == 12) h = 0;
      return h * 60 + m;
    } catch (_) { return 0; }
  }

  @override
  void dispose() { super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final doses = _todayDoses;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null ? _buildError()
          : RefreshIndicator(
              color: _primary,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionHeader("Today's Schedule"),
                  const SizedBox(height: 4),
                  Text(DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                      style: const TextStyle(fontSize: 12, color: _textMuted)),
                  const SizedBox(height: 16),
                  if (doses.isEmpty) _buildEmptyState(
                    Icons.event_available_rounded,
                    'No medicines scheduled today',
                    'Dispensed prescriptions will appear here',
                  ) else ...doses.map((d) => _scheduleCard(
                    d['med'] as ScheduledMedicine,
                    d['time'] as String,
                    d['doseIndex'] as int,
                  )),
                  const SizedBox(height: 28),
                  _sectionHeader('My Prescriptions'),
                  const SizedBox(height: 12),
                  if (_medicines.isEmpty) _buildEmptyState(
                    Icons.receipt_long_outlined,
                    'No dispensed prescriptions',
                    'Ask your pharmacist to dispense your prescription',
                  ) else ..._medicines.map((m) => _prescriptionCard(m)),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
        ),
      ]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 48),
      const SizedBox(height: 12),
      const Text('Failed to load schedule', style: TextStyle(fontWeight: FontWeight.w700, color: _textDark)),
      const SizedBox(height: 6),
      Text(_error!, style: const TextStyle(fontSize: 12, color: _textMuted), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
      ),
    ]),
  ));

  Widget _buildEmptyState(IconData icon, String title, String sub) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _fieldBdr),
    ),
    child: Column(children: [
      Icon(icon, size: 48, color: _primary.withOpacity(0.22)),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: _textDark, fontSize: 14)),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(fontSize: 12, color: _textMuted), textAlign: TextAlign.center),
    ]),
  );

  void _showRxModal(ScheduledMedicine med) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: _fieldBdr, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(children: [
                Container(width: 48, height: 48,
                  decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                  child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 26)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('UKonek Clinic', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _primaryMid)),
                  const Text('Digital Prescription', style: TextStyle(fontSize: 11, color: _textMuted)),
                ]),
              ]),
              const SizedBox(height: 16),
              const Divider(color: _fieldBdr),
              const SizedBox(height: 12),
              const Text('PATIENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _primary, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(widget.username, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark)),
              Text('ID: ${widget.citizenId}', style: const TextStyle(fontSize: 12, color: _textMuted)),
              const SizedBox(height: 4),
              Text('Prescribed by: ${med.displayDoctorName}',
                  style: const TextStyle(fontSize: 12, color: _textMuted)),
              Text('Issued: ${DateFormat('MMM d, yyyy').format(med.issuedAt)}',
                  style: const TextStyle(fontSize: 12, color: _textMuted)),
              const SizedBox(height: 20),
              const Text('℞', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _primaryMid, height: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: _fieldBdr)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(med.medicineName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _textDark)),
                  if (med.dosage.isNotEmpty)
                    Text(med.dosage, style: const TextStyle(fontSize: 13, color: _primary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  const Divider(color: _fieldBdr),
                  const SizedBox(height: 10),
                  if (med.frequency.isNotEmpty) _rxRow('Frequency', med.frequency),
                  _rxRow('Quantity', '${med.quantity}${med.unit.isNotEmpty ? " ${med.unit}" : ""}'),
                  _rxRow('Prescription ID', med.prescriptionCode),
                  if (med.dispensedAt != null)
                    _rxRow('Dispensed', DateFormat('MMM d, yyyy').format(med.dispensedAt!)),
                  if (med.instructions.isNotEmpty) ...[const SizedBox(height: 10), const Divider(color: _fieldBdr), const SizedBox(height: 8),
                    const Text('DOCTOR\'S INSTRUCTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textMuted)),
                    const SizedBox(height: 6),
                    Text(med.instructions, style: const TextStyle(fontSize: 13, color: _textDark, height: 1.5)),
                  ],
                  if (med.additionalInfo.isNotEmpty) ...[const SizedBox(height: 8),
                    const Text('ADDITIONAL INFO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textMuted)),
                    const SizedBox(height: 4),
                    Text(med.additionalInfo, style: const TextStyle(fontSize: 12, color: _textMuted, height: 1.4)),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
              Center(child: QrImageView(
                data: med.prescriptionCode.isNotEmpty ? med.prescriptionCode : 'RX-${widget.citizenId}',
                version: QrVersions.auto, size: 140.0,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _primaryMid),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _primaryMid),
              )),
              const SizedBox(height: 8),
              Center(child: Text(med.prescriptionCode,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primaryMid, letterSpacing: 1, fontFamily: 'monospace'))),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: _primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rxRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
    ]),
  );

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Medicine Scheduler",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text("Hello, ${widget.username}", // Dynamically uses the passed username
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ),
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
        color: Colors.white,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: _textDark.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -4))],
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
                    // Already on Medicine page
                    setState(() => _selectedTab = i);
                  } else if (i == 2) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekJoinQueuePage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    ));
                  } else if (i == 3) {
                    // ✅ Medicine page doesn't have profile data — pop back to Dashboard
                    // which will then navigate to Profile with full data
                    Navigator.pop(context);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _primary.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(tabs[i]['icon'] as IconData,
                      color: isSelected ? _primary : _textMuted.withOpacity(0.5),
                      size: 22,
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      Text(tabs[i]['label'] as String,
                        style: const TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.bold),
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


  Widget _scheduleCard(ScheduledMedicine med, String time, int doseIndex) {
    final key = '${med.prescriptionItemId}_$doseIndex';
    final taken = _takenDoses.contains(key);
    final timeParts = time.split(' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _textDark.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: taken ? _primary.withOpacity(0.08) : _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: taken ? _primary.withOpacity(0.3) : _fieldBdr),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(timeParts[0], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                color: taken ? _primary : _textDark)),
            Text(timeParts.length > 1 ? timeParts[1] : '',
                style: TextStyle(fontSize: 9, color: taken ? _primary : _textMuted)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(med.medicineName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _textDark)),
          Text(
            [if (med.dosage.isNotEmpty) med.dosage, if (med.frequency.isNotEmpty) med.frequency]
                .join(' • '),
            style: const TextStyle(fontSize: 12, color: _textMuted),
          ),
          if (med.instructions.isNotEmpty)
            Text(med.instructions, style: const TextStyle(fontSize: 11, color: _textMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        IconButton(
          onPressed: () => _showRxModal(med),
          icon: const Icon(Icons.receipt_long_rounded, color: _primaryMid, size: 20),
          tooltip: 'View Prescription',
        ),
        GestureDetector(
          onTap: () => setState(() {
            if (taken) _takenDoses.remove(key); else _takenDoses.add(key);
          }),
          child: Icon(
            taken ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: taken ? _primary : _fieldBdr, size: 26,
          ),
        ),
      ]),
    );
  }

  Widget _prescriptionCard(ScheduledMedicine med) {
    return GestureDetector(
      onTap: () => _showRxModal(med),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _fieldBdr),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: _primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.medication_rounded, color: _primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(med.medicineName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _textDark)),
            Text(
              [if (med.dosage.isNotEmpty) med.dosage,
               if (med.frequency.isNotEmpty) med.frequency,
               if (med.quantity > 0) '×${med.quantity}${med.unit.isNotEmpty ? " ${med.unit}" : ""}']
                  .join(' • '),
              style: const TextStyle(fontSize: 12, color: _textMuted),
            ),
            Text(med.prescriptionCode,
                style: const TextStyle(fontSize: 11, color: _primaryMid,
                    fontWeight: FontWeight.w600, fontFamily: 'monospace')),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _fieldBdr),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark));
}