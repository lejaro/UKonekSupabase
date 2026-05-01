import 'package:flutter/material.dart';

class uKonekMedicineSchedulerPage extends StatefulWidget {
  const uKonekMedicineSchedulerPage({super.key});

  @override
  State<uKonekMedicineSchedulerPage> createState() => _uKonekMedicineSchedulerPageState();
}

class _uKonekMedicineSchedulerPageState extends State<uKonekMedicineSchedulerPage> {
  // --- DESIGN TOKENS ---
  static const Color _primary = Color(0xFF0D47A1);
  static const Color _bg = Color(0xFFF4F7FE);
  static const Color _textDark = Color(0xFF1A1A2E);

  // --- FORM STATE ---
  String? _selectedMed;
  bool _isOtherSelected = false;
  String _mealInstruction = "After Meals";
  String _dosageUnit = "Tablet";

  // Separated Frequency and Interval
  String _selectedFrequency = "3x a day";
  String _selectedInterval = "8 Hours";
  String _durationDays = "7 Days";

  final TextEditingController _otherMedController = TextEditingController();
  final TextEditingController _dosageQtyController = TextEditingController();

  // Mock Database Lists
  final List<String> _medicineDb = ["Amoxicillin", "Paracetamol", "Vitamin C", "Mefenamic Acid", "Other"];
  final List<String> _units = ["Tablet", "Capsule", "ml", "Drops", "Spoon"];
  final List<String> _frequencies = ["Once a day", "2x a day", "3x a day", "4x a day", "5x a day"];
  final List<String> _intervals = ["4 Hours", "6 Hours", "8 Hours", "12 Hours"];
  final List<String> _durations = ["3 Days", "5 Days", "7 Days", "14 Days", "Until finished"];

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

                  // Displaying generated reminders based on the setup
                  _medScheduleCard("Amoxicillin", "500mg • After Meals", "08:00 AM", Colors.orange, true),
                  _medScheduleCard("Amoxicillin", "500mg • After Meals", "04:00 PM", Colors.orange, false),

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
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Medicine Scheduler",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text("Manage your daily health routine",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. ADD MEDICINE FORM (BOTTOM SHEET) ──────────────────────────────
  void _showAddMedicineSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24, right: 24, top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("New Prescription", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),

                // MEDICINE NAME
                _fieldLabel("Medicine Name"),
                _buildDropdownContainer(
                  DropdownButton<String>(
                    value: _selectedMed,
                    hint: const Text("Select from list"),
                    isExpanded: true,
                    items: _medicineDb.map((med) => DropdownMenuItem(value: med, child: Text(med))).toList(),
                    onChanged: (val) => setModalState(() {
                      _selectedMed = val;
                      _isOtherSelected = (val == "Other");
                    }),
                  ),
                ),
                if (_isOtherSelected) ...[
                  const SizedBox(height: 12),
                  _buildTextInput(_otherMedController, "Enter medicine name"),
                ],

                const SizedBox(height: 16),

                // DOSAGE
                _fieldLabel("Dosage"),
                Row(
                  children: [
                    Expanded(flex: 2, child: _buildTextInput(_dosageQtyController, "Qty", isNumber: true)),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _buildDropdownContainer(
                        DropdownButton<String>(
                          value: _dosageUnit,
                          items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                          onChanged: (val) => setModalState(() => _dosageUnit = val!),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // FREQUENCY & INTERVALS (SEPARATED)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel("Frequency"),
                          _buildDropdownContainer(
                            DropdownButton<String>(
                              value: _selectedFrequency,
                              isExpanded: true,
                              items: _frequencies.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                              onChanged: (val) => setModalState(() => _selectedFrequency = val!),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel("Interval"),
                          _buildDropdownContainer(
                            DropdownButton<String>(
                              value: _selectedInterval,
                              isExpanded: true,
                              items: _intervals.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                              onChanged: (val) => setModalState(() => _selectedInterval = val!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                _fieldLabel("Previewed Times"),
                _buildSmartSchedulePreview(_selectedFrequency, _selectedInterval),

                const SizedBox(height: 16),

                // MEAL INSTRUCTION
                _fieldLabel("Instruction"),
                Row(
                  children: [
                    _instructionChip("Before Meals", setModalState),
                    const SizedBox(width: 12),
                    _instructionChip("After Meals", setModalState),
                  ],
                ),

                const SizedBox(height: 16),

                // DURATION
                _fieldLabel("Duration"),
                _buildDropdownContainer(
                  DropdownButton<String>(
                    value: _durationDays,
                    isExpanded: true,
                    items: _durations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (val) => setModalState(() => _durationDays = val!),
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
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

  // ── UI HELPERS & SMART LOGIC ───────────────────────────────────────

  Widget _buildSmartSchedulePreview(String freq, String interval) {
    // FIX: Remove any non-numeric characters (like 'x' or 'a day') before parsing
    int count = int.parse(freq.replaceAll(RegExp(r'[^0-9]'), ''));
    int hours = int.parse(interval.replaceAll(RegExp(r'[^0-9]'), ''));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(count, (index) {
        int startHour = 8; // Start at 8:00 AM
        int nextHour = (startHour + (index * hours)) % 24;
        String period = nextHour >= 12 ? "PM" : "AM";
        int displayHour = nextHour > 12 ? nextHour - 12 : (nextHour == 0 ? 12 : nextHour);
        String timeString = "${displayHour.toString().padLeft(2, '0')}:00 $period";

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: _primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)
          ),
          child: Text(
              timeString,
              style: const TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.bold)
          ),
        );
      }),
    );
  }

  Widget _medScheduleCard(String name, String desc, String time, Color color, bool taken) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          Column(children: [
            Text(time.split(" ")[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(time.split(" ")[1], style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          Icon(taken ? Icons.check_circle : Icons.radio_button_unchecked, color: taken ? Colors.green : Colors.grey.shade300),
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _primary.withOpacity(0.1))),
        child: Column(children: [
          Icon(Icons.add_alarm_rounded, color: _primary.withOpacity(0.3), size: 40),
          const SizedBox(height: 12),
          const Text("Add New Schedule", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text("Set custom intervals for your meds", style: TextStyle(color: Colors.grey, fontSize: 12)),
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
        decoration: BoxDecoration(color: isSel ? _primary : _bg, borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
      ),
    ));
  }

  Widget _buildDropdownContainer(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
    child: DropdownButtonHideUnderline(child: child),
  );

  Widget _buildTextInput(TextEditingController ctrl, String hint, {bool isNumber = false}) => TextField(
    controller: ctrl, keyboardType: isNumber ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(hintText: hint, filled: true, fillColor: _bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
  );

  Widget _fieldLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)));

  Widget _sectionHeader(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark));
}