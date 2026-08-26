import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  VitalSigns? _latestVitals;
  Consultation? _latestConsultation;
  String _selectedFilter = 'all'; // 'all', 'consultation', 'vitals'

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

      if (vitals.isNotEmpty) {
        _latestVitals = vitals.first;
      } else {
        _latestVitals = null;
      }

      if (consults.isNotEmpty) {
        _latestConsultation = consults.first;
      } else {
        _latestConsultation = null;
      }

      final List<Map<String, dynamic>> vitalsMapped = vitals.map((v) => {
        'id': v.id,
        'date': DateFormat('MMMM dd, yyyy').format(v.createdAt),
        'timestamp': v.createdAt,
        'service': 'Vitals Assessment',
        'provider': 'Clinic Nurse',
        'diagnosis': v.chiefComplaint.isNotEmpty ? v.chiefComplaint : 'Routine Vital Signs Check',
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
        'diagnosis': c.diagnosis.isNotEmpty ? c.diagnosis : 'Clinical Consultation',
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
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final keyword = _searchController.text.trim().toLowerCase();
    setState(() {
      _foundRecords = _allRecords.where((r) {
        final matchesType = _selectedFilter == 'all' || r['type'] == _selectedFilter;
        if (!matchesType) return false;
        if (keyword.isEmpty) return true;

        final s = (r['service'] as String).toLowerCase();
        final d = (r['diagnosis'] as String).toLowerCase();
        final p = (r['provider'] as String).toLowerCase();
        return s.contains(keyword) || d.contains(keyword) || p.contains(keyword);
      }).toList();
    });
  }

  void _runFilter(String keyword) {
    _applyFilters();
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
              : _foundRecords.isEmpty && _allRecords.isEmpty
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
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
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _loadRecords();
                },
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
            const SizedBox(height: 16),
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
          hintText: 'Search diagnoses, services, doctors...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded,
              color: Colors.white.withOpacity(0.7), size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _applyFilters();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildRecordList() {
    final vitalsCount = _allRecords.where((r) => r['type'] == 'vitals').length;
    final consultsCount = _allRecords.where((r) => r['type'] == 'consultation').length;

    return RefreshIndicator(
      onRefresh: _loadRecords,
      color: _C.primaryMid,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Latest Vitals Metrics Matrix ──────────────────────
            if (_latestVitals != null && _searchController.text.isEmpty) ...[
              _buildVitalsMetricsGrid(_latestVitals!),
              const SizedBox(height: 20),
            ],

            // ── Filter Chips Row ─────────────────────────────────
            _buildFilterTabs(allCount: _allRecords.length, consultCount: consultsCount, vitalsCount: vitalsCount),
            const SizedBox(height: 20),

            // ── Section Header ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _searchController.text.isEmpty 
                      ? (_selectedFilter == 'vitals' ? 'Vitals Timeline' : (_selectedFilter == 'consultation' ? 'Consultations' : 'Medical Timeline'))
                      : 'Search Results (${_foundRecords.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _C.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_foundRecords.length} ${_foundRecords.length == 1 ? 'record' : 'records'}',
                  style: const TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_foundRecords.isEmpty)
              _buildEmptySearchResults()
            else
              ..._foundRecords.map((r) => _buildHistoryCard(r)),

            const SizedBox(height: 20),
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_outlined, size: 14, color: _C.textMuted),
                  SizedBox(width: 6),
                  Text('All medical assessments are encrypted and private',
                      style: TextStyle(color: _C.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Vitals Metrics Grid ────────────────────────────────────────
  Widget _buildVitalsMetricsGrid(VitalSigns v) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8F5E9), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Color(0x0C1B2E1E), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.monitor_heart_rounded, color: _C.primaryMid, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'LATEST VITALS SUMMARY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _C.primaryMid,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Text(
                DateFormat('MMM dd, yyyy').format(v.createdAt),
                style: const TextStyle(fontSize: 11, color: _C.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _vitalChip('BP', v.bp ?? '—', Icons.favorite_rounded, const Color(0xFFE53935))),
              const SizedBox(width: 10),
              Expanded(child: _vitalChip('Pulse', v.heartRate != null ? '${v.heartRate} bpm' : '—', Icons.speed_rounded, const Color(0xFF1976D2))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _vitalChip('Temp', v.temp != null ? '${v.temp} °C' : '—', Icons.thermostat_rounded, const Color(0xFFF59E0B))),
              const SizedBox(width: 10),
              Expanded(child: _vitalChip('SpO2', v.spo2 != null ? '${v.spo2}%' : '—', Icons.air_rounded, const Color(0xFF00897B))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vitalChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _C.textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter Tabs ────────────────────────────────────────────────
  Widget _buildFilterTabs({required int allCount, required int consultCount, required int vitalsCount}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _filterChip('all', 'All Records ($allCount)'),
          const SizedBox(width: 8),
          _filterChip('consultation', 'Consultations ($consultCount)'),
          const SizedBox(width: 8),
          _filterChip('vitals', 'Vitals Signs ($vitalsCount)'),
        ],
      ),
    );
  }

  Widget _filterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedFilter = filterKey;
          _applyFilters();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _C.primaryMid : _C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _C.primaryMid : const Color(0xFFE8F5E9)),
          boxShadow: isSelected
              ? [BoxShadow(color: _C.primaryMid.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))]
              : const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : _C.textDark,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final color = data['color'] as Color;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showDetailsSheet(data);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8F5E9), width: 1),
          boxShadow: const [BoxShadow(color: Color(0x0C1B2E1E), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: color, 
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                    child: Icon(data['icon'] as IconData, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['date'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _C.textDark)),
                      const SizedBox(height: 2),
                      Text(data['service'] as String, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
                    ],
                  )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('VIEW', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, color: color, size: 14),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Divider(height: 1, color: _C.divider),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['type'] == 'vitals' ? 'CHIEF COMPLAINT' : 'DIAGNOSIS / FINDINGS', 
                        style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        data['diagnosis'] as String, 
                        maxLines: 2, 
                        overflow: TextOverflow.ellipsis, 
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _C.textDark),
                      ),
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
          width: 90, height: 90,
          decoration: BoxDecoration(color: _C.primaryMid.withOpacity(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.folder_open_rounded, size: 44, color: _C.primaryMid),
        ),
        const SizedBox(height: 16),
        const Text('No clinical records yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _C.textDark)),
        const SizedBox(height: 6),
        const Text('Your clinic visits and vitals will appear here', style: TextStyle(color: _C.textMuted, fontSize: 13)),
      ],
    ));
  }

  Widget _buildEmptySearchResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text('No matching records found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _C.textDark)),
            const SizedBox(height: 4),
            const Text('Try adjusting your search keyword or filter', style: TextStyle(color: _C.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _showDetailsSheet(Map<String, dynamic> data) {
    final isVitals = data['type'] == 'vitals';
    final color = data['color'] as Color;
    final VitalSigns? v = isVitals ? data['raw'] as VitalSigns : null;
    final Consultation? c = !isVitals ? data['raw'] as Consultation : null;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        maxChildSize:     0.92,
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
                gradient: LinearGradient(colors: [color, color.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(13)),
                  child: Icon(data['icon'] as IconData, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVitals ? 'Vital Signs Assessment' : 'Doctor Consultation Report', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
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
                  _detailSection('Attending Practitioner', data['provider'] as String),
                  
                  if (isVitals && v != null) ...[
                    _detailSection('Chief Complaint / Reason', v.chiefComplaint.isNotEmpty ? v.chiefComplaint : 'Routine assessment'),
                    Row(children: [
                      Expanded(child: _detailSection('Blood Pressure', v.bp ?? '—')),
                      Expanded(child: _detailSection('Heart Rate', v.heartRate != null ? '${v.heartRate} bpm' : '—')),
                    ]),
                    Row(children: [
                      Expanded(child: _detailSection('Resp. Rate', v.rr != null ? '${v.rr} bpm' : '—')),
                      Expanded(child: _detailSection('Temperature', v.temp != null ? '${v.temp}°C' : '—')),
                    ]),
                    _detailSection('Oxygen Saturation (SpO2)', v.spo2 != null ? '${v.spo2}%' : '—'),
                    _detailSection('Current Medications', v.meds?.isNotEmpty == true ? v.meds! : 'None recorded'),
                  ] else if (c != null) ...[
                    if (c.allergies?.isNotEmpty == true)
                      _buildAllergyAlert(c.allergies!),
                      
                    _detailSection('Primary Diagnosis', c.diagnosis.isNotEmpty ? c.diagnosis : 'Consultation record'),
                    
                    if (c.hpi?.isNotEmpty == true)
                      _detailSection('History of Present Illness', c.hpi!),
                    
                    if (c.pmh?.isNotEmpty == true)
                      _detailSection('Past Medical History', c.pmh!),

                    if (c.labOrders?.isNotEmpty == true)
                      _detailSection('Lab Requests / Orders', c.labOrders!),

                    if (c.notes?.isNotEmpty == true)
                      _detailSection('Clinical Notes & Plan', c.notes!),

                    if (c.followupDate != null)
                      _detailSection('Scheduled Follow-up', DateFormat('MMMM dd, yyyy').format(c.followupDate!)),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('DISMISS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(color: _C.primaryMid, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(fontSize: 14, color: _C.textDark, height: 1.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}