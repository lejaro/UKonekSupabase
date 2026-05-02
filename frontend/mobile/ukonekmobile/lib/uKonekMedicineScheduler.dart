import 'package:flutter/material.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekJoinQueuePage.dart';

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
  // ── DESIGN TOKENS (MEDICAL GREEN) ───────────────────────────
  static const Color _primary      = Color(0xFF28A745); // Health Green
  static const Color _primaryMid   = Color(0xFF1B5E20); // Forest Green
  static const Color _bg           = Color(0xFFF8FCF9); // Mint Background
  static const Color _textDark     = Color(0xFF1B2E1E); // Dark Forest Charcoal
  static const Color _textMuted    = Color(0xFF637367); // Muted Sage
  static const Color _fieldBdr     = Color(0xFFE2E9E3); // Light Mist Border

  int _selectedTab = 1; // Medicine tab index

  // ── FORM STATE ─────────────────────────────────────────────
  String? _selectedMed;
  bool _isOtherSelected = false;
  String _mealInstruction = "After Meals";
  String _dosageUnit = "Tablet";
  String _selectedFrequency = "3x a day";
  String _selectedInterval = "8 Hours";
  String _durationDays = "7 Days";

  final TextEditingController _otherMedController = TextEditingController();
  final TextEditingController _dosageQtyController = TextEditingController();

  final List<String> _medicineDb = ["Amoxicillin", "Paracetamol", "Vitamin C", "Mefenamic Acid", "Other"];
  final List<String> _units = ["Tablet", "Capsule", "ml", "Drops", "Spoon"];
  final List<String> _frequencies = ["Once a day", "2x a day", "3x a day", "4x a day", "5x a day"];
  final List<String> _intervals = ["4 Hours", "6 Hours", "8 Hours", "12 Hours"];
  final List<String> _durations = ["3 Days", "5 Days", "7 Days", "14 Days", "Until finished"];

  @override
  void dispose() {
    _otherMedController.dispose();
    _dosageQtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildStaticHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader("Today's Schedule"),
                  const SizedBox(height: 16),
                  _medScheduleCard("Amoxicillin", "500mg • After Meals", "08:00 AM", _primary, true),
                  _medScheduleCard("Amoxicillin", "500mg • After Meals", "04:00 PM", _primary, false),
                  const SizedBox(height: 32),
                  _sectionHeader("Prescription Setup"),
                  const SizedBox(height: 16),
                  _buildAddMedicineCard(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── 1. HEADER (GREEN GRADIENT) ───────────────────────────────
  Widget _buildStaticHeader() {
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

  // ── 2. BOTTOM NAVIGATION ALGORITHM ──────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.dashboard_rounded, 'label': 'Home'},
      {'icon': Icons.event_note_rounded, 'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: _textDark.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
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
                    // Returns to dashboard with correct session data
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => uKonekDashboardPage(
                            username: widget.username,
                            citizenId: widget.citizenId
                        ),
                      ),
                          (route) => false,
                    );
                  } else if (i == 2) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => uKonekJoinQueuePage(
                          username: widget.username,
                          citizenId: widget.citizenId,
                        ),
                      ),
                    );
                  } else if (i == 3) {
                    // Profile navigation logic here
                  } else {
                    setState(() => _selectedTab = i);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _primary.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _primary : _textMuted.withOpacity(0.5),
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: _primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── 3. FORM MODAL (GREEN ACCENTS) ───────────────────────────
  void _showAddMedicineSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("New Prescription", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textDark)),
                const SizedBox(height: 24),
                _fieldLabel("Medicine Name"),
                _buildDropdownContainer(
                  DropdownButton<String>(
                    value: _selectedMed,
                    hint: const Text("Select from list"),
                    isExpanded: true,
                    items: _medicineDb.map((med) => DropdownMenuItem(value: med, child: Text(med))).toList(),
                    onChanged: (val) => setModalState(() { _selectedMed = val; _isOtherSelected = (val == "Other"); }),
                  ),
                ),
                if (_isOtherSelected) ...[const SizedBox(height: 12), _buildTextInput(_otherMedController, "Enter medicine name")],
                const SizedBox(height: 16),
                _fieldLabel("Dosage"),
                Row(
                  children: [
                    Expanded(flex: 2, child: _buildTextInput(_dosageQtyController, "Qty", isNumber: true)),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _buildDropdownContainer(
                      DropdownButton<String>(
                        value: _dosageUnit,
                        items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                        onChanged: (val) => setModalState(() => _dosageUnit = val!),
                      ),
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel("Frequency"),
                      _buildDropdownContainer(DropdownButton<String>(
                        value: _selectedFrequency, isExpanded: true,
                        items: _frequencies.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                        onChanged: (val) => setModalState(() => _selectedFrequency = val!),
                      )),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel("Interval"),
                      _buildDropdownContainer(DropdownButton<String>(
                        value: _selectedInterval, isExpanded: true,
                        items: _intervals.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                        onChanged: (val) => setModalState(() => _selectedInterval = val!),
                      )),
                    ])),
                  ],
                ),
                const SizedBox(height: 16),
                _fieldLabel("Previewed Times"),
                _buildSmartSchedulePreview(_selectedFrequency, _selectedInterval),
                const SizedBox(height: 16),
                _fieldLabel("Instruction"),
                Row(children: [ _instructionChip("Before Meals", setModalState), const SizedBox(width: 12), _instructionChip("After Meals", setModalState)]),
                const SizedBox(height: 16),
                _fieldLabel("Duration"),
                _buildDropdownContainer(DropdownButton<String>(
                  value: _durationDays, isExpanded: true,
                  items: _durations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (val) => setModalState(() => _durationDays = val!),
                )),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary, elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("SAVE SCHEDULE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── UI HELPERS ─────────────────────────────────────────────
  Widget _medScheduleCard(String name, String desc, String time, Color color, bool taken) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _textDark.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Column(children: [
            Text(time.split(" ")[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textDark)),
            Text(time.split(" ")[1], style: const TextStyle(fontSize: 10, color: _textMuted)),
          ]),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _textDark)),
            Text(desc, style: const TextStyle(fontSize: 12, color: _textMuted)),
          ])),
          Icon(taken ? Icons.check_circle : Icons.radio_button_unchecked, color: taken ? _primary : _fieldBdr),
        ],
      ),
    );
  }

  Widget _buildAddMedicineCard() {
    return GestureDetector(
      onTap: _showAddMedicineSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _fieldBdr),
        ),
        child: Column(children: [
          Icon(Icons.add_alarm_rounded, color: _primary.withOpacity(0.2), size: 40),
          const SizedBox(height: 12),
          const Text("Add New Schedule", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textDark)),
          const Text("Set custom intervals for your meds", style: TextStyle(color: _textMuted, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _instructionChip(String label, StateSetter setModalState) {
    bool isSel = _mealInstruction == label;
    return Expanded(child: GestureDetector(
      onTap: () => setModalState(() => _mealInstruction = label),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isSel ? _primary : _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? _primary : _fieldBdr)),
        child: Center(child: Text(label, style: TextStyle(color: isSel ? Colors.white : _textMuted, fontWeight: FontWeight.bold, fontSize: 12))),
      ),
    ));
  }

  Widget _buildDropdownContainer(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _fieldBdr)),
    child: DropdownButtonHideUnderline(child: child),
  );

  Widget _buildTextInput(TextEditingController ctrl, String hint, {bool isNumber = false}) => TextField(
    controller: ctrl, keyboardType: isNumber ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(fontSize: 13, color: _textMuted),
      filled: true, fillColor: _bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _fieldBdr)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _fieldBdr)),
    ),
  );

  Widget _buildSmartSchedulePreview(String freq, String interval) {
    int count = int.parse(freq.replaceAll(RegExp(r'[^0-9]'), ''));
    int hours = int.parse(interval.replaceAll(RegExp(r'[^0-9]'), ''));
    return Wrap(spacing: 8, runSpacing: 8, children: List.generate(count, (index) {
      int nextHour = (8 + (index * hours)) % 24;
      String period = nextHour >= 12 ? "PM" : "AM";
      int displayHour = nextHour > 12 ? nextHour - 12 : (nextHour == 0 ? 12 : nextHour);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: _primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Text("${displayHour.toString().padLeft(2, '0')}:00 $period", style: const TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }),
    );
  }

  Widget _fieldLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _textMuted)));

  Widget _sectionHeader(String title) => Text(
    title,
    style: TextStyle( // Removed 'const' for themed variables
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: _textDark,
    ),
  );
}