import 'package:flutter/material.dart';

class _C {
  static const primary      = Color(0xFF0A2E6E);
  static const primaryMid   = Color(0xFF1565C0);
  static const primaryLight = Color(0xFF1976D2);
  static const bg           = Color(0xFFF0F4FA);
  static const surface      = Colors.white;
  static const textDark     = Color(0xFF1A2740);
  static const textMuted    = Color(0xFF8A93A0);
  static const divider      = Color(0xFFEEF1F6);
  static const heartRed     = Color(0xFFE53935);
  static const success      = Color(0xFF10B981);
  static const warning      = Color(0xFFF59E0B);
  static const shadow       = Color(0x0A000000);
}

class PrescriptionPage extends StatefulWidget {
  const PrescriptionPage({super.key});

  @override
  State<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends State<PrescriptionPage> {
  int _selectedFilter = 0;
  final List<String> _filters = ['All', 'Active', 'Completed'];

  // ── Demo prescriptions ─────────────────────────────────────────
  final List<Map<String, dynamic>> _prescriptions = [
    {
      'name':        'Amoxicillin',
      'dosage':      '500mg',
      'form':        'Capsule',
      'frequency':   '3x a day',
      'duration':    '7 days',
      'meal':        'After meal',
      'startDate':   'March 20, 2026',
      'endDate':     'March 27, 2026',
      'doctor':      'Dr. Maria Santos',
      'status':      'Active',
      'remaining':   5,
      'total':       7,
      'purpose':     'For bacterial infection / Upper respiratory tract infection',
      'instructions':'Take every 8 hours. Complete the full course even if symptoms improve. Store at room temperature.',
      'color':       Color(0xFF1565C0),
      'icon':        Icons.medication_rounded,
      'taken':       [true, true, false, false, false, false, false],
    },
    {
      'name':        'Vitamin C',
      'dosage':      '500mg',
      'form':        'Tablet',
      'frequency':   '1x a day',
      'duration':    '30 days',
      'meal':        'After meal',
      'startDate':   'March 20, 2026',
      'endDate':     'April 19, 2026',
      'doctor':      'Dr. Maria Santos',
      'status':      'Active',
      'remaining':   28,
      'total':       30,
      'purpose':     'Vitamin C supplementation / Immune support',
      'instructions':'Take once daily after breakfast. May be taken with or without water.',
      'color':       Color(0xFF2E7D32),
      'icon':        Icons.local_pharmacy_outlined,
      'taken':       [true, true, false],
    },
    {
      'name':        'Paracetamol',
      'dosage':      '500mg',
      'form':        'Tablet',
      'frequency':   'Every 6 hrs (as needed)',
      'duration':    '3 days',
      'meal':        'With or without food',
      'startDate':   'March 18, 2026',
      'endDate':     'March 21, 2026',
      'doctor':      'Dr. Maria Santos',
      'status':      'Completed',
      'remaining':   0,
      'total':       12,
      'purpose':     'Fever and pain relief',
      'instructions':'Take every 6 hours only when needed for fever above 38°C or pain. Do not exceed 4g daily.',
      'color':       Color(0xFF7B1FA2),
      'icon':        Icons.medication_liquid_outlined,
      'taken':       [],
    },
    {
      'name':        'Cetirizine',
      'dosage':      '10mg',
      'form':        'Tablet',
      'frequency':   '1x a day',
      'duration':    '5 days',
      'meal':        'Before bedtime',
      'startDate':   'February 10, 2026',
      'endDate':     'February 15, 2026',
      'doctor':      'Dr. Jose Reyes',
      'status':      'Completed',
      'remaining':   0,
      'total':       5,
      'purpose':     'Allergic rhinitis / Seasonal allergies',
      'instructions':'Take at bedtime. May cause drowsiness. Avoid driving or operating heavy machinery.',
      'color':       Color(0xFFE65100),
      'icon':        Icons.medication_rounded,
      'taken':       [],
    },
  ];

  List<Map<String, dynamic>> get _filtered {
    if (_selectedFilter == 0) return _prescriptions;
    final f = _filters[_selectedFilter];
    return _prescriptions.where((p) => p['status'] == f).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              // ── Today's reminder strip ───────────────────────
              const SizedBox(height: 16),
              _buildTodayReminder(),
              const SizedBox(height: 20),

              // ── Filter chips ─────────────────────────────────
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  itemBuilder: (_, i) {
                    final sel = _selectedFilter == i;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedFilter = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? _C.primaryMid
                              : _C.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? _C.primaryMid
                                : _C.divider,
                          ),
                          boxShadow: sel
                              ? [BoxShadow(
                            color: _C.primaryMid
                                .withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )]
                              : [],
                        ),
                        child: Text(_filters[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? Colors.white
                                  : _C.textMuted,
                            )),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── Prescription cards ───────────────────────────
              ..._filtered.map((p) => _prescriptionCard(p)),
            ],
          ),
        ),
      ]),
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
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prescriptions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
                SizedBox(height: 2),
                Text('Your medication details',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            )),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 22),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Today's reminder card ──────────────────────────────────────
  Widget _buildTodayReminder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: const Color(0xFF2E7D32).withOpacity(0.25),
          blurRadius: 12,
          offset: const Offset(0, 4),
        )],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.alarm_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today\'s Reminder',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                )),
            SizedBox(height: 4),
            Text('2 medications due — Amoxicillin & Vitamin C',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('View',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              )),
        ),
      ]),
    );
  }

  // ── Prescription card ──────────────────────────────────────────
  Widget _prescriptionCard(Map<String, dynamic> p) {
    final color     = p['color'] as Color;
    final isActive  = p['status'] == 'Active';
    final remaining = p['remaining'] as int;
    final total     = p['total'] as int;
    final progress  = total > 0 ? remaining / total : 0.0;

    return GestureDetector(
      onTap: () => _showPrescriptionDetail(p),
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
          // Color top strip
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? color : _C.divider,
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Top row
              Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(p['icon'] as IconData,
                      color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['name']} ${p['dosage']}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _C.textDark,
                          letterSpacing: -0.3,
                        )),
                    const SizedBox(height: 3),
                    Text(
                        '${p['form']} • ${p['frequency']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _C.textMuted,
                        )),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _C.success.withOpacity(0.10)
                        : _C.divider,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p['status'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? _C.success
                            : _C.textMuted,
                      )),
                ),
              ]),
              const SizedBox(height: 14),

              // Info pills
              Row(children: [
                _infoPill(Icons.schedule_rounded,
                    p['meal'] as String),
                const SizedBox(width: 8),
                _infoPill(Icons.person_outline_rounded,
                    p['doctor'] as String),
              ]),

              if (isActive) ...[
                const SizedBox(height: 14),
                // Progress bar
                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Days remaining: $remaining/$total',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _C.textMuted,
                        )),
                    Text('${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: _C.divider,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _infoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: _C.textMuted),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
              fontSize: 11,
              color: _C.textMuted,
              fontWeight: FontWeight.w500,
            )),
      ]),
    );
  }

  // ── Prescription detail sheet ──────────────────────────────────
  void _showPrescriptionDetail(Map<String, dynamic> p) {
    final color    = p['color'] as Color;
    final isActive = p['status'] == 'Active';

    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize:     0.92,
        minChildSize:     0.45,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(28)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: _C.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Detail header
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(p['icon'] as IconData,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['name']} ${p['dosage']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 4),
                    Text(p['form'] as String,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        )),
                  ],
                )),
              ]),
            ),

            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  // Details grid
                  _detailSection('Prescription Details', [
                    _detailRow2('Frequency',  p['frequency'] as String),
                    _detailRow2('Duration',   p['duration']  as String),
                    _detailRow2('Take with',  p['meal']      as String),
                    _detailRow2('Start Date', p['startDate'] as String),
                    _detailRow2('End Date',   p['endDate']   as String),
                    _detailRow2('Prescribed by', p['doctor'] as String),
                  ]),
                  const SizedBox(height: 16),

                  // Purpose
                  _detailSection('Purpose', [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(p['purpose'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _C.textDark,
                            height: 1.5,
                          )),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // Instructions
                  _detailSection('Instructions', [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(p['instructions'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _C.textDark,
                            height: 1.5,
                          )),
                    ),
                  ]),

                  if (isActive) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _C.primaryMid,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content: Text(
                                'Marked as taken for today!'),
                            backgroundColor: _C.success,
                          ));
                        },
                        icon: const Icon(
                            Icons.check_circle_outline_rounded),
                        label: const Text('Mark as Taken Today',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            )),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _C.primaryMid,
              )),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow2(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 13,
                color: _C.textMuted,
              )),
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _C.textDark,
              )),
        ],
      ),
    );
  }
}