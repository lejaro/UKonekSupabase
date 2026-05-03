import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class _C {
  static const primary    = Color(0xFF2D5A27); // Brand Green
  static const primaryMid = Color(0xFF3E7D32);
  static const accent     = Color(0xFF4CAF50); // Vibrant Green
  static const bg         = Color(0xFFF0F4FA);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1A2740);
  static const textMuted  = Color(0xFF8A93A0);
  static const divider    = Color(0xFFEEF1F6);
  static const success    = Color(0xFF4CAF50);
  static const shadow     = Color(0x0A000000);
}

class uKonekHealthRecordsPage extends StatefulWidget {
  const uKonekHealthRecordsPage({super.key});

  @override
  State<uKonekHealthRecordsPage> createState() =>
      _uKonekHealthRecordsPageState();
}

class _uKonekHealthRecordsPageState extends State<uKonekHealthRecordsPage> {
  List<VitalSigns> _vitalSigns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVitals();
  }

  Future<void> _loadVitals() async {
    setState(() => _isLoading = true);
    try {
      final vitals = await ApiService.fetchVitalSigns();
      if (mounted) {
        setState(() {
          _vitalSigns = vitals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _C.accent))
              : _vitalSigns.isEmpty
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
                  Text('Health Records',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                      )),
                  SizedBox(height: 2),
                  Text('View your clinical assessments',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildRecordList() {
    return RefreshIndicator(
      onRefresh: _loadVitals,
      color: _C.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(_vitalSigns.first),
            const SizedBox(height: 28),
            const Text('Vital Assessment History',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _C.textDark,
                  letterSpacing: -0.4,
                )),
            const SizedBox(height: 14),
            ...(_vitalSigns.map((v) => _buildVitalsCard(v)).toList()),
            const SizedBox(height: 20),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 13, color: _C.textMuted),
                  const SizedBox(width: 6),
                  Text('Your records are secure and private',
                      style: const TextStyle(
                          color: _C.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(VitalSigns last) {
    final dateStr = DateFormat('MMMM dd, yyyy').format(last.createdAt);
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
          color: _C.shadow,
          blurRadius: 16,
          offset: const Offset(0, 6),
        )],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _C.primaryMid.withOpacity(0.06),
            borderRadius: const BorderRadius.only(
              topLeft:  Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_rounded, color: _C.primaryMid, size: 16),
            const SizedBox(width: 10),
            const Text('LATEST ASSESSMENT:',
                style: TextStyle(
                  color: _C.primaryMid,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                )),
            const Spacer(),
            Text(dateStr,
                style: const TextStyle(
                  color: _C.textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chief Complaint',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 4),
                Text(last.chiefComplaint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _C.textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
              ],
            )),
            Container(width: 1, height: 40, color: _C.divider),
            const SizedBox(width: 20),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Blood Pressure',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 4),
                Text(last.bp ?? '—',
                    style: const TextStyle(
                      color: _C.textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    )),
              ],
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildVitalsCard(VitalSigns v) {
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(v.createdAt);
    return GestureDetector(
      onTap: () => _showDetailsSheet(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: _C.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          )],
        ),
        child: Column(children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              color: _C.accent,
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _C.accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.monitor_heart_outlined, color: _C.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _C.textDark,
                          )),
                      const SizedBox(height: 2),
                      Text(v.chiefComplaint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _C.accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          )),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded, color: _C.textMuted, size: 20),
                ]),
                const SizedBox(height: 14),
                Divider(height: 1, color: _C.divider),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat('BP', v.bp ?? '—'),
                    _miniStat('TEMP', v.temp != null ? '${v.temp}°C' : '—'),
                    _miniStat('SPO2', v.spo2 != null ? '${v.spo2}%' : '—'),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _C.textDark)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: _C.primaryMid.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.health_and_safety_outlined, size: 50, color: _C.textMuted),
        ),
        const SizedBox(height: 20),
        const Text('No assessments yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _C.textDark,
            )),
        const SizedBox(height: 8),
        const Text('Your clinic records will appear here',
            style: TextStyle(color: _C.textMuted, fontSize: 14)),
      ],
    ));
  }

  void _showDetailsSheet(VitalSigns v) {
    final dateStr = DateFormat('MMMM dd, yyyy • hh:mm a').format(v.createdAt);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize:     0.9,
        expand: false,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
            ),
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_C.primary, _C.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assessment Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                )),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  _detailSection('Chief Complaint', v.chiefComplaint),
                  Row(
                    children: [
                      Expanded(child: _detailSection('Blood Pressure', v.bp ?? '—')),
                      Expanded(child: _detailSection('Temperature', v.temp != null ? '${v.temp}°C' : '—')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _detailSection('Resp. Rate', v.rr != null ? '${v.rr} bpm' : '—')),
                      Expanded(child: _detailSection('Oxygen (SpO2)', v.spo2 != null ? '${v.spo2}%' : '—')),
                    ],
                  ),
                  _detailSection('Current Medications', v.meds ?? 'None recorded'),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.primaryMid,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
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