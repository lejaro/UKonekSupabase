import 'package:flutter/material.dart';

class _C {
  static const primary    = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const accent     = Color(0xFF1976D2);
  static const bg         = Color(0xFFF0F4FA);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1A2740);
  static const textMuted  = Color(0xFF8A93A0);
  static const divider    = Color(0xFFEEF1F6);
  static const success    = Color(0xFF10B981);
  static const shadow     = Color(0x0A000000);
}

class uKonekHealthRecordsPage extends StatefulWidget {
  const uKonekHealthRecordsPage({super.key});

  @override
  State<uKonekHealthRecordsPage> createState() =>
      _uKonekHealthRecordsPageState();
}

class _uKonekHealthRecordsPageState
    extends State<uKonekHealthRecordsPage> {

  final List<Map<String, dynamic>> _records = [
    {
      'date':     'March 20, 2026',
      'service':  'General Consultation',
      'provider': 'Dr. Cruz',
      'diagnosis':'Seasonal Flu',
      'isRecent': true,
      'color':    const Color(0xFF1565C0),
      'icon':     Icons.medical_services_outlined,
    },
    {
      'date':     'Jan 15, 2026',
      'service':  'Dental',
      'provider': 'Dr. Reyes',
      'diagnosis':'Routine Cleaning',
      'isRecent': false,
      'color':    const Color(0xFF10B981),
      'icon':     Icons.health_and_safety,
    },
    {
      'date':     'Nov 10, 2025',
      'service':  'Vaccination',
      'provider': 'Nurse Santos',
      'diagnosis':'Flu Shot (Annual)',
      'isRecent': false,
      'color':    const Color(0xFF7B1FA2),
      'icon':     Icons.vaccines_outlined,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: _records.isEmpty
              ? _buildEmptyState()
              : _buildRecordList(),
        ),
      ]),
    );
  }

  // ── Header ───────────────────────────────────────────────────
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
                  Text('View your consultation history',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Export',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    )),
              ),
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
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(children: [
        const SizedBox(width: 16),
        Icon(Icons.search_rounded,
            color: Colors.white.withOpacity(0.6), size: 20),
        const SizedBox(width: 10),
        Text('Search by date or service...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            )),
      ]),
    );
  }

  // ── Record List ──────────────────────────────────────────────
  Widget _buildRecordList() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 28),
          const Text('Visit History',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _C.textDark,
                letterSpacing: -0.4,
              )),
          const SizedBox(height: 14),
          ...(_records.map(
                  (r) => _buildHistoryCard(r)).toList()),
          const SizedBox(height: 12),
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
    );
  }

  // ── Summary Card ─────────────────────────────────────────────
  Widget _buildSummaryCard() {
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
        // Top strip
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _C.primaryMid.withOpacity(0.06),
            borderRadius: const BorderRadius.only(
              topLeft:  Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_rounded,
                color: _C.primaryMid, size: 16),
            const SizedBox(width: 10),
            const Text('LAST VISIT:',
                style: TextStyle(
                  color: _C.primaryMid,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                )),
            const Spacer(),
            const Text('March 20, 2026',
                style: TextStyle(
                  color: _C.textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                )),
          ]),
        ),
        // Bottom section
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Diagnosis',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 4),
                const Text('Seasonal Flu',
                    style: TextStyle(
                      color: _C.textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
              ],
            )),
            Container(width: 1, height: 40,
                color: _C.divider),
            const SizedBox(width: 20),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Handled by',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 4),
                const Text('Nurse Maria',
                    style: TextStyle(
                      color: _C.textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            )),
          ]),
        ),
      ]),
    );
  }

  // ── History Card ─────────────────────────────────────────────
  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final color = data['color'] as Color;
    return GestureDetector(
      onTap: () => _showDetailsSheet(data),
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
              color: color,
              borderRadius: const BorderRadius.only(
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
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data['icon'] as IconData,
                        color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['date'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _C.textDark,
                          )),
                      const SizedBox(height: 2),
                      Text(data['service'] as String,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          )),
                    ],
                  )),
                  if (data['isRecent'] as bool)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.success.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('RECENT',
                          style: TextStyle(
                            color: _C.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          )),
                    ),
                ]),
                const SizedBox(height: 14),
                Divider(height: 1, color: _C.divider),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DIAGNOSIS',
                          style: TextStyle(
                            color: _C.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          )),
                      const SizedBox(height: 3),
                      Text(data['diagnosis'] as String,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _C.textDark,
                          )),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded,
                      color: _C.textMuted, size: 20),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Empty State ──────────────────────────────────────────────
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
          child: const Icon(Icons.folder_open_outlined,
              size: 50, color: _C.textMuted),
        ),
        const SizedBox(height: 20),
        const Text('No health records yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _C.textDark,
            )),
        const SizedBox(height: 8),
        const Text('Your consultations will appear here',
            style: TextStyle(color: _C.textMuted, fontSize: 14)),
      ],
    ));
  }

  // ── Detail Sheet ─────────────────────────────────────────────
  void _showDetailsSheet(Map<String, dynamic> data) {
    final color = data['color'] as Color;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize:     0.9,
        expand: false,
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
            // Sheet header
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
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(data['icon'] as IconData,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Record Details',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        )),
                    const SizedBox(height: 2),
                    Text(data['date'] as String,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                )),
              ]),
            ),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  _detailSection('Provider & Location',
                      '${data['provider']}\nBrgy. Ugong Health Center'),
                  _detailSection('Service Type',
                      data['service'] as String),
                  _detailSection('Symptoms',
                      'Patient reported moderate fever, dry cough, and body aches for 2 days.'),
                  _detailSection('Diagnosis',
                      data['diagnosis'] as String),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.primaryMid,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(16)),
                      ),
                      child: const Text('CLOSE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          )),
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
          Text(title.toUpperCase(),
              style: const TextStyle(
                color: _C.primaryMid,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              )),
          const SizedBox(height: 8),
          Text(content,
              style: const TextStyle(
                fontSize: 14,
                color: _C.textDark,
                height: 1.6,
              )),
        ],
      ),
    );
  }
}