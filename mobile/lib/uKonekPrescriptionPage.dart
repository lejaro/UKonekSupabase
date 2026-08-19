import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class _C {
  static const primary      = Color(0xFF1B5E20);
  static const primaryMid   = Color(0xFF28A745);
  static const primaryLight = Color(0xFF48C76A);
  static const bg           = Color(0xFFF8FCF9);
  static const surface      = Colors.white;
  static const textDark     = Color(0xFF1B2E1E);
  static const textMuted    = Color(0xFF637367);
  static const divider      = Color(0xFFE2E9E3);
  static const success      = Color(0xFF10B981);
  static const warning      = Color(0xFFF59E0B);
  static const shadow       = Color(0x0A000000);
}

// ── Groups all items under a single prescription header ──────────
class _PrescriptionGroup {
  final int prescriptionId;
  final String prescriptionCode;
  final String dispensingStatus;
  final DateTime issuedAt;
  final DateTime? dispensedAt;
  final String doctorName;
  final List<PrescriptionRecord> items;

  const _PrescriptionGroup({
    required this.prescriptionId,
    required this.prescriptionCode,
    required this.dispensingStatus,
    required this.issuedAt,
    this.dispensedAt,
    required this.doctorName,
    required this.items,
  });

  bool get isDispensed => dispensingStatus == 'dispensed';
  bool get isCancelled => dispensingStatus == 'cancelled';
  bool get isPending   => dispensingStatus == 'pending';
}

class PrescriptionPage extends StatefulWidget {
  const PrescriptionPage({super.key});

  @override
  State<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends State<PrescriptionPage> {
  int _selectedFilter = 0;
  final List<String> _filters = ['All', 'Pending', 'Dispensed'];

  bool _loading = true;
  String? _error;
  List<_PrescriptionGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final records = await ApiService.fetchPrescriptions();
      setState(() {
        _groups = _buildGroups(records);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<_PrescriptionGroup> _buildGroups(List<PrescriptionRecord> records) {
    final Map<int, _PrescriptionGroup> map = {};
    for (final r in records) {
      if (map.containsKey(r.prescriptionId)) {
        map[r.prescriptionId]!.items.add(r);
      } else {
        map[r.prescriptionId] = _PrescriptionGroup(
          prescriptionId:   r.prescriptionId,
          prescriptionCode: r.prescriptionCode,
          dispensingStatus: r.dispensingStatus,
          issuedAt:         r.issuedAt,
          dispensedAt:      r.dispensedAt,
          doctorName:       r.displayDoctorName,
          items:            [r],
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  List<_PrescriptionGroup> get _filtered {
    if (_selectedFilter == 0) return _groups;
    final f = _filters[_selectedFilter].toLowerCase();
    return _groups.where((g) => g.dispensingStatus == f).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text('Failed to load prescriptions', style: TextStyle(color: _C.textDark, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: _C.textMuted, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: _C.primaryMid, foregroundColor: Colors.white),
          ),
        ],
      ));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          const SizedBox(height: 16),
          // ── Filter chips ───────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder: (_, i) {
                final sel = _selectedFilter == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _C.primaryMid : _C.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? _C.primaryMid : _C.divider),
                      boxShadow: sel
                          ? [BoxShadow(color: _C.primaryMid.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))]
                          : [],
                    ),
                    child: Text(_filters[i],
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : _C.textMuted)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          if (_filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(children: [
                Icon(Icons.receipt_long_outlined, size: 56, color: _C.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                const Text('No prescriptions found',
                    style: TextStyle(color: _C.textMuted, fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
            )
          else
            ..._filtered.map((g) => _prescriptionGroupCard(g)),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid, _C.primaryLight],
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
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prescriptions', style: TextStyle(color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.bold, letterSpacing: -0.4)),
                SizedBox(height: 2),
                Text('Your medication records', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            )),
            GestureDetector(
              onTap: _load,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Prescription group card ────────────────────────────────────
  Widget _prescriptionGroupCard(_PrescriptionGroup g) {
    final statusColor = g.isDispensed ? _C.success
        : g.isCancelled ? Colors.red.shade300
        : _C.warning;
    final statusLabel = g.isDispensed ? 'Dispensed'
        : g.isCancelled ? 'Cancelled'
        : 'Pending';

    return GestureDetector(
      onTap: () => _showGroupDetail(g),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: _C.shadow, blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(children: [
          // Status colour strip
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header row
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _C.primaryMid.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: _C.primaryMid, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.prescriptionCode,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                          color: _C.textDark, letterSpacing: 0.5, fontFamily: 'monospace')),
                  const SizedBox(height: 2),
                  Text(g.doctorName,
                      style: const TextStyle(fontSize: 12, color: _C.textMuted)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                ),
              ]),
              const SizedBox(height: 12),

              // Medicine list preview (up to 3)
              ...g.items.take(3).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.medication_rounded, size: 14, color: _C.primaryMid),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '${item.medicineName}${item.dosage.isNotEmpty ? " ${item.dosage}" : ""}${item.frequency.isNotEmpty ? " — ${item.frequency}" : ""}${item.duration.isNotEmpty ? " (${item.duration})" : ""}',
                    style: const TextStyle(fontSize: 13, color: _C.textDark),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                  Text('×${item.quantity}${item.unit.isNotEmpty ? " ${item.unit}" : ""}',
                      style: const TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600)),
                ]),
              )),
              if (g.items.length > 3)
                Text('+${g.items.length - 3} more item(s)',
                    style: const TextStyle(fontSize: 12, color: _C.textMuted)),

              const SizedBox(height: 10),
              // Footer row
              Row(children: [
                const Icon(Icons.calendar_today_rounded, size: 12, color: _C.textMuted),
                const SizedBox(width: 4),
                Text('Issued: ${DateFormat('MMM d, yyyy').format(g.issuedAt)}',
                    style: const TextStyle(fontSize: 11, color: _C.textMuted)),
                if (g.isDispensed && g.dispensedAt != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check_circle_rounded, size: 12, color: _C.success),
                  const SizedBox(width: 4),
                  Text('Dispensed: ${DateFormat('MMM d, yyyy').format(g.dispensedAt!)}',
                      style: const TextStyle(fontSize: 11, color: _C.success)),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Prescription group detail sheet ───────────────────────────
  void _showGroupDetail(_PrescriptionGroup g) {
    final statusColor = g.isDispensed ? _C.success
        : g.isCancelled ? Colors.red.shade400
        : _C.warning;
    final statusLabel = g.isDispensed ? 'Dispensed'
        : g.isCancelled ? 'Cancelled'
        : 'Pending';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.70,
        maxChildSize: 0.95,
        minChildSize: 0.45,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
            ),

            // Header card
            Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_C.primary, _C.primaryMid],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Text(g.prescriptionCode,
                      style: const TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.w800, letterSpacing: 0.5, fontFamily: 'monospace'))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.person_outline_rounded, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(g.doctorName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(DateFormat('MMM d, yyyy').format(g.issuedAt),
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
                if (g.isDispensed && g.dispensedAt != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.check_circle_rounded, color: _C.success, size: 14),
                    const SizedBox(width: 6),
                    Text('Dispensed on ${DateFormat('MMM d, yyyy – h:mm a').format(g.dispensedAt!)}',
                        style: const TextStyle(color: _C.success, fontSize: 12)),
                  ]),
                ],
              ]),
            ),

            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                children: [
                  Text('${g.items.length} Prescribed Medicine${g.items.length != 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.primaryMid)),
                  const SizedBox(height: 12),
                  ...g.items.map((item) => _medicineDetailCard(item)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Per-medicine detail card in detail sheet ──────────────────
  Widget _medicineDetailCard(PrescriptionRecord item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Name + quantity
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _C.primaryMid.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.medication_rounded, color: _C.primaryMid, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.medicineName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.textDark)),
            if (item.dosage.isNotEmpty)
              Text(item.dosage, style: const TextStyle(fontSize: 12, color: _C.textMuted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _C.primaryMid.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('×${item.quantity}${item.unit.isNotEmpty ? " ${item.unit}" : ""}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.primaryMid)),
          ),
        ]),

        if (item.frequency.isNotEmpty) ...[
          const SizedBox(height: 10),
          _infoRow(Icons.schedule_rounded, 'Frequency', item.frequency),
        ],
        if (item.duration.isNotEmpty) ...[
          const SizedBox(height: 8),
          _infoRow(Icons.timer_outlined, 'Duration', item.duration),
        ],
        if (item.instructions.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, size: 14, color: _C.primaryMid),
            const SizedBox(width: 6),
            const Text("Doctor's Notes", style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: _C.primaryMid)),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _C.primaryMid.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.primaryMid.withOpacity(0.15)),
            ),
            child: Text(item.instructions,
                style: const TextStyle(fontSize: 13, color: _C.textDark, height: 1.5)),
          ),
        ],
        if (item.additionalInfo.isNotEmpty) ...[
          const SizedBox(height: 8),
          _infoRow(Icons.note_outlined, 'Additional Info', item.additionalInfo),
        ],
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: _C.textMuted),
      const SizedBox(width: 6),
      Text('$label: ', style: const TextStyle(fontSize: 12, color: _C.textMuted)),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, color: _C.textDark, fontWeight: FontWeight.w500))),
    ]);
  }
}