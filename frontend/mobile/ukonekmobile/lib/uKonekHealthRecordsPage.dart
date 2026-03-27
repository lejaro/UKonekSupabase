import 'package:flutter/material.dart';

class uKonekHealthRecordsPage extends StatefulWidget {
  const uKonekHealthRecordsPage({super.key});

  @override
  State<uKonekHealthRecordsPage> createState() => _uKonekHealthRecordsPageState();
}

class _uKonekHealthRecordsPageState extends State<uKonekHealthRecordsPage> {
  // --- DESIGN TOKENS ---
  static const Color _primary = Color(0xFF0D47A1);
  static const Color _bg = Color(0xFFF4F7FE);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF1976D2);

  // Mock Data
  final List<Map<String, dynamic>> _records = [
    {'date': 'March 20, 2026', 'service': 'General Consultation', 'provider': 'Dr. Cruz', 'diagnosis': 'Seasonal Flu', 'isRecent': true},
    {'date': 'Jan 15, 2026', 'service': 'Dental', 'provider': 'Dr. Reyes', 'diagnosis': 'Routine Cleaning', 'isRecent': false},
    {'date': 'Nov 10, 2025', 'service': 'Vaccination', 'provider': 'Nurse Santos', 'diagnosis': 'Flu Shot (Annual)', 'isRecent': false},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildStaticHeader(),
          Expanded(
            child: _records.isEmpty ? _buildEmptyState() : _buildRecordList(),
          ),
        ],
      ),
    );
  }

  // ── 1. STATIC HEADER ────────────────────────────────────────────────
  Widget _buildStaticHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 25),
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(40)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Health Records", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("View your consultation history", style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPillSearchBar(),
        ],
      ),
    );
  }

  Widget _buildPillSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 48,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(30)),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, color: Colors.white60, size: 22),
          const SizedBox(width: 12),
          Text("Search by date or service...", style: TextStyle(color: Colors.white60, fontSize: 14)),
        ],
      ),
    );
  }

  // ── 2. RECORD LIST & SUMMARY ────────────────────────────────────────
  Widget _buildRecordList() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          _buildSummaryCard(),
          const SizedBox(height: 32),
          const Text("Visit History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark)),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _records.length,
            itemBuilder: (context, index) => _buildHistoryCard(_records[index]),
          ),
          const SizedBox(height: 40),
          const Center(child: Text("Your records are secure and private 🔒", style: TextStyle(color: Colors.grey, fontSize: 11))),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── 3. SUMMARY CARD (Top Section) ───────────────────────────────────
  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── TOP SECTION: Highlighted Date ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: _primary, size: 18),
                const SizedBox(width: 10),
                const Text(
                  "LAST VISIT:",
                  style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.1
                  ),
                ),
                const Spacer(),
                const Text(
                  "March 20, 2026",
                  style: TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 13
                  ),
                ),
              ],
            ),
          ),

          // ── BOTTOM SECTION: Diagnosis & Provider ──
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // Diagnosis Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Diagnosis",
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Seasonal Flu",
                        style: TextStyle(
                            color: _textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5
                        ),
                      ),
                    ],
                  ),
                ),

                // Vertical Divider
                Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.2)),
                const SizedBox(width: 20),

                // Provider Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Handled by",
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Nurse Maria",
                        style: TextStyle(
                            color: _textDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w600
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. HISTORY CARD (Main List) ─────────────────────────────────────
  Widget _buildHistoryCard(Map<String, dynamic> data) {
    return GestureDetector(
      onTap: () => _showDetailsSheet(data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['date'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _textDark)),
                if (data['isRecent'])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text("RECENT", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(data['service'], style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("DIAGNOSIS", style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text(data['diagnosis'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 5. EMPTY STATE ──────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          const Text("No health records yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
          const SizedBox(height: 8),
          const Text("Your consultations will appear here", style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  // ── UI HELPERS ──────────────────────────────────────────────────────
  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _textDark)),
      ],
    );
  }

  void _showDetailsSheet(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Visual Handle
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)
                      )
                  )
              ),
              const SizedBox(height: 24),

              // ── CLEAN TITLE (No Download Icon) ──
              const Text(
                  "Record Details",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textDark)
              ),

              const Divider(height: 40, thickness: 1, color: Color(0xFFF1F4F8)),

              _detailSection("Provider & Location", "${data['provider']}\nBrgy. Ugong Health Center"),
              _detailSection("Service Type", data['service']),
              _detailSection("Symptoms", "Patient reported moderate fever, dry cough, and body aches for 2 days."),
              _detailSection("Diagnosis", data['diagnosis']),

              const SizedBox(height: 32),

              // ── CLOSE BUTTON ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                      "CLOSE",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 15, color: _textDark, height: 1.5)),
        ],
      ),
    );
  }
}