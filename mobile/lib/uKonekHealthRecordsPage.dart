import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

// ── Medical/Dental Green Design tokens ────────────────────────────────
class _C {
  static const primary    = Color(0xFF1B5E20);   // Deep Forest Green
  static const primaryMid = Color(0xFF28A745);   // Vibrant Health Green
  static const accent     = Color(0xFF20C997);   // Mint Accent
  static const bg         = Color(0xFFF8FCF9);   // Mint-tinted Background
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1B2E1E);   // Dark Forest Charcoal
  static const textMuted  = Color(0xFF637367);   // Muted Sage
  static const divider    = Color(0xFFE2E9E3);   // Light Mist Divider
  static const success    = Color(0xFF28A745);
  static const shadow     = Color(0x0A000000);
}

class uKonekHealthRecordsPage extends StatefulWidget {
  const uKonekHealthRecordsPage({super.key});

  @override
  State<uKonekHealthRecordsPage> createState() =>
      _uKonekHealthRecordsPageState();
}

class _uKonekHealthRecordsPageState extends State<uKonekHealthRecordsPage> {
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = true;
  final List<Map<String, dynamic>> _allRecords = [];
  List<Map<String, dynamic>> _foundRecords = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final vitals = await ApiService.fetchVitalSigns();
      final consults = await ApiService.fetchConsultations();

      final List<Map<String, dynamic>> vitalsMapped = vitals.map((v) => {
        'id': v.id,
        'date': DateFormat('MMMM dd, yyyy').format(v.createdAt),
        'timestamp': v.createdAt,
        'service': 'Vitals Assessment',
        'provider': 'Clinic Nurse',
        'diagnosis': v.chiefComplaint,
        'color': _C.primaryMid,
        'icon': Icons.monitor_heart_outlined,
        'type': 'vitals',
        'raw': v,
      }).toList();

      final List<Map<String, dynamic>> consultsMapped = consults.map((c) => {
        'id': c.id.toString(),
        'date': DateFormat('MMMM dd, yyyy').format(c.consultedAt),
        'timestamp': c.consultedAt,
        'service': 'Doctor Consultation',
        'provider': c.doctorName ?? 'Health Center Doctor',
        'diagnosis': c.diagnosis,
        'color': const Color(0xFF007AFF), // Medical Blue
        'icon': Icons.medical_information_outlined,
        'type': 'consultation',
        'raw': c,
      }).toList();

      final List<Map<String, dynamic>> combined = [...vitalsMapped, ...consultsMapped];
      combined.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

      if (mounted) {
        setState(() {
          _allRecords.clear();
          _allRecords.addAll(combined);
          _foundRecords = List.from(_allRecords);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _foundRecords = List.from(_allRecords));
    } else {
      final k = keyword.toLowerCase();
      setState(() {
        _foundRecords = _allRecords.where((r) {
          final s = (r['service'] as String).toLowerCase();
          final d = (r['diagnosis'] as String).toLowerCase();
          final p = (r['provider'] as String).toLowerCase();
          return s.contains(k) || d.contains(k) || p.contains(k);
        }).toList();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _C.primaryMid))
              : _foundRecords.isEmpty
                  ? _buildEmptyState()
                  : _buildRecordList(),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clinical Records',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                      )),
                  SizedBox(height: 2),
                  Text('Your medical history & vitals',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              )),
            ]),
            const SizedBox(height: 18),
            _buildSearchBar(),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _runFilter,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: 'Search records...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded,
              color: Colors.white.withOpacity(0.6), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildRecordList() {
    return RefreshIndicator(
      onRefresh: _loadRecords,
      color: _C.primaryMid,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_searchController.text.isEmpty && _allRecords.isNotEmpty) ...[
              _buildSummaryCard(_allRecords.first),
              const SizedBox(height: 28),
            ],
            Text(_searchController.text.isEmpty ? 'History' : 'Search Results',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _C.textDark,
                  letterSpacing: -0.4,
                )),
            const SizedBox(height: 14),
            ...(_foundRecords.map((r) => _buildHistoryCard(r)).toList()),
            const SizedBox(height: 20),
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 13, color: _C.textMuted),
                  SizedBox(width: 6),
                  Text('Records are secure and private',
                      style: TextStyle(color: _C.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> last) {
    final isVitals = last['type'] == 'vitals';
    final rawVitals = isVitals ? last['raw'] as VitalSigns : null;
    final rawConsult = !isVitals ? last['raw'] as Consultation : null;

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: (last['color'] as Color).withOpacity(0.06),
            borderRadius: const BorderRadius.only(
              topLeft:  Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Row(children: [
            Icon(last['icon'] as IconData, color: last['color'] as Color, size: 16),
            const SizedBox(width: 10),
            Text(last['service'].toString().toUpperCase(),
                style: TextStyle(color: last['color'] as Color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
            const Spacer(),
            Text(last['date'],
                style: const TextStyle(color: _C.textDark, fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isVitals ? 'Primary Concern' : 'Final Diagnosis', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(last['diagnosis'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.textDark, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.4)),
              ],
            )),
            Container(width: 1, height: 40, color: _C.divider),
            const SizedBox(width: 20),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isVitals ? 'BP / HR' : 'Practitioner', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  isVitals 
                    ? '${rawVitals?.bp ?? '—'} / ${rawVitals?.heartRate ?? '—'}'
                    : (rawConsult?.doctorName ?? 'Doctor'), 
                  style: const TextStyle(color: _C.textDark, fontSize: 16, fontWeight: FontWeight.bold)
                ),
              ],
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final color = data['color'] as Color;
    return GestureDetector(
      onTap: () => _showDetailsSheet(data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(children: [
          Container(
            height: 4,
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                    child: Icon(data['icon'] as IconData, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['date'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
                      const SizedBox(height: 2),
                      Text(data['service'] as String, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded, color: _C.textMuted, size: 20),
                ]),
                const SizedBox(height: 14),
                const Divider(height: 1, color: _C.divider),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('REMARKS / COMPLAINT', style: TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 3),
                      Text(data['diagnosis'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _C.textDark)),
                    ],
                  )),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(color: _C.primaryMid.withOpacity(0.06), shape: BoxShape.circle),
          child: const Icon(Icons.search_off_rounded, size: 50, color: _C.textMuted),
        ),
        const SizedBox(height: 20),
        const Text('No records found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.textDark)),
        const SizedBox(height: 8),
        Text('Try searching with different terms', style: const TextStyle(color: _C.textMuted, fontSize: 14)),
      ],
    ));
  }

  void _showDetailsSheet(Map<String, dynamic> data) {
    final raw = data['raw'] as VitalSigns;
    final color = data['color'] as Color;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize:     0.9,
        expand: false,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(color: _C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
            ),
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(13)),
                  child: Icon(data['icon'] as IconData, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assessment Detail', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(data['date'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                )),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  _detailSection('Practitioner', data['provider'] as String),
                  
                  if (data['type'] == 'vitals') ...[
                    _detailSection('Chief Complaint', (data['raw'] as VitalSigns).chiefComplaint),
                    Row(children: [
                      Expanded(child: _detailSection('Blood Pressure', (data['raw'] as VitalSigns).bp ?? '—')),
                      Expanded(child: _detailSection('Heart Rate', (data['raw'] as VitalSigns).heartRate != null ? '${(data['raw'] as VitalSigns).heartRate} bpm' : '—')),
                    ]),
                    Row(children: [
                      Expanded(child: _detailSection('Resp. Rate', (data['raw'] as VitalSigns).rr != null ? '${(data['raw'] as VitalSigns).rr} bpm' : '—')),
                      Expanded(child: _detailSection('Temperature', (data['raw'] as VitalSigns).temp != null ? '${(data['raw'] as VitalSigns).temp}°C' : '—')),
                    ]),
                    _detailSection('Oxygen (SpO2)', (data['raw'] as VitalSigns).spo2 != null ? '${(data['raw'] as VitalSigns).spo2}%' : '—'),
                    _detailSection('Current Medications', (data['raw'] as VitalSigns).meds ?? 'None recorded'),
                  ] else ...[
                    if ((data['raw'] as Consultation).allergies?.isNotEmpty == true)
                      _buildAllergyAlert((data['raw'] as Consultation).allergies!),
                      
                    _detailSection('Primary Diagnosis', (data['raw'] as Consultation).diagnosis),
                    
                    if ((data['raw'] as Consultation).hpi?.isNotEmpty == true)
                      _detailSection('History of Present Illness', (data['raw'] as Consultation).hpi!),
                    
                    if ((data['raw'] as Consultation).pmh?.isNotEmpty == true)
                      _detailSection('Past Medical History', (data['raw'] as Consultation).pmh!),

                    if ((data['raw'] as Consultation).labOrders?.isNotEmpty == true)
                      _detailSection('Lab Requests / Orders', (data['raw'] as Consultation).labOrders!),

                    if ((data['raw'] as Consultation).notes?.isNotEmpty == true)
                      _detailSection('Clinical Notes & Plan', (data['raw'] as Consultation).notes!),

                    if ((data['raw'] as Consultation).followupDate != null)
                      _detailSection('Follow-up Date', DateFormat('MMMM dd, yyyy').format((data['raw'] as Consultation).followupDate!)),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('DISMISS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildAllergyAlert(String allergies) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('KNOWN ALLERGIES', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(allergies, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        )),
      ]),
    );
  }

  Widget _detailSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(color: _C.primaryMid, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 14, color: _C.textDark, height: 1.6)),
        ],
      ),
    );
  }
}