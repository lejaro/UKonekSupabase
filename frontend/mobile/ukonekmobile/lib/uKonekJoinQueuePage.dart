import 'package:flutter/material.dart';

class uKonekJoinQueuePage extends StatefulWidget {
  const uKonekJoinQueuePage({super.key});

  @override
  State<uKonekJoinQueuePage> createState() => _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState extends State<uKonekJoinQueuePage> {
  // --- DESIGN TOKENS ---
  static const Color _primary = Color(0xFF0D47A1);
  static const Color _bg = Color(0xFFF4F7FE);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _fieldBorder = Color(0xFFDDE3F0);

  String? _selectedService;
  String _priorityType = "Regular";
  bool _isJoined = false;

  final List<Map<String, dynamic>> _services = [
    {'id': 'gen', 'label': 'General Con.', 'icon': Icons.medical_services_outlined},
    {'id': 'den', 'label': 'Dental', 'icon': Icons.health_and_safety}, // Use Icons.health_and_safety if tooth is missing
    {'id': 'chk', 'label': 'Check-up', 'icon': Icons.monitor_heart_outlined},
    {'id': 'vax', 'label': 'Vaccination', 'icon': Icons.vaccines_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildStaticHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _isJoined ? _buildSuccessState() : _buildEntryForm(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !_isJoined ? _buildBottomAction() : null,
    );
  }

  // ── 1. STATIC HEADER ────────────────────────────────────────────────
  Widget _buildStaticHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 25),
      decoration: const BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(40)),
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
              Text(_isJoined ? "Queue Status" : "Join Queue",
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text(_isJoined ? "Keep track of your turn" : "This will only take a few seconds",
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. ENTRY FORM (Service Selection & Details) ─────────────────────
  Widget _buildEntryForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel("Select a Service"),
          const SizedBox(height: 16),
          _buildServiceGrid(),
          const SizedBox(height: 32),
          _sectionLabel("Additional Details (Optional)"),
          const SizedBox(height: 16),
          _buildDropdownField("Priority Type", ["Regular", "Senior Citizen", "PWD", "Pregnant"]),
          const SizedBox(height: 16),
          _buildTextField("Reason for Visit (e.g. Fever, Cough)"),
          const SizedBox(height: 32),
          _buildConfirmationSummary(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildServiceGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.3,
      ),
      itemCount: _services.length,
      itemBuilder: (context, index) {
        final service = _services[index];
        bool isSelected = _selectedService == service['id'];
        return GestureDetector(
          onTap: () => setState(() => _selectedService = service['id']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? _primary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? _primary : _fieldBorder),
              boxShadow: isSelected ? [BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(service['icon'], color: isSelected ? Colors.white : _primary, size: 30),
                const SizedBox(height: 8),
                Text(service['label'], style: TextStyle(color: isSelected ? Colors.white : _textDark, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 3. SUCCESS STATE (The Queue Ticket) ─────────────────────────────
  Widget _buildSuccessState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
            ),
            child: Column(
              children: [
                const Text("YOUR QUEUE NUMBER", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                const Text("#12", style: TextStyle(color: _primary, fontSize: 80, fontWeight: FontWeight.w900, letterSpacing: -2)),
                const Divider(height: 40),
                _statusRow("Status", "You are next", Colors.green),
                const SizedBox(height: 12),
                _statusRow("Wait Time", "Est. 10 mins", _primary),
                const SizedBox(height: 12),
                _statusRow("Ahead of you", "2 People", _textDark),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _buildActionToggle(),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _isJoined = false),
            child: const Text("Leave Queue", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark));

  Widget _buildTextField(String hint) {
    return TextField(
      decoration: InputDecoration(
        hintText: hint,
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _fieldBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _fieldBorder)),
      ),
    );
  }

  Widget _buildDropdownField(String label, List<String> items) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _fieldBorder)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _priorityType, isExpanded: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _priorityType = v!),
        ),
      ),
    );
  }

  Widget _buildConfirmationSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _primary.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
      child: const Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Health Center"), Text("Brgy. Ugong Hall", style: TextStyle(fontWeight: FontWeight.bold))]),
          SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Date"), Text("March 28, 2026", style: TextStyle(fontWeight: FontWeight.bold))]),
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    bool canJoin = _selectedService != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(color: Colors.white),
      child: ElevatedButton(
        onPressed: canJoin ? () => setState(() => _isJoined = true) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canJoin ? _primary : Colors.grey.shade300,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text("CONFIRM & JOIN QUEUE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
      ),
    );
  }

  Widget _statusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildActionToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Notify me via SMS", style: TextStyle(fontWeight: FontWeight.w600)),
          Switch(value: true, activeColor: _primary, onChanged: (v) {}),
        ],
      ),
    );
  }
}