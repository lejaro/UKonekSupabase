import 'package:flutter/material.dart';

// ── Design tokens (DentCare+ palette) ─────────────────────────
const _primary   = Color(0xFF0077B6);
const _primary2  = Color(0xFF0096C7);
const _textDark  = Color(0xFF1A2740);
const _textMuted = Color(0xFF8A93A0);
const _fieldBg   = Color(0xFFF0F9FF);
const _fieldBdr  = Color(0xFFDDE3F0);
const _success   = Color(0xFF10B981);
const _warning   = Color(0xFFF59E0B);

class uKonekMedicalStep extends StatefulWidget {
  final Function(Map<String, String>) onDataChanged;
  final Map<String, String> initialData;
  final String firstName;
  final String surname;
  final String middleName;
  final DateTime? dob;
  final Function(bool, dynamic) onVerified;



  const uKonekMedicalStep({
    super.key,
    required this.onDataChanged,
    required this.firstName,
    required this.surname,
    required this.middleName,
    required this.dob,
    required this.onVerified,
    this.initialData = const {},
  });

  @override
  State<uKonekMedicalStep> createState() =>
      _uKonekMedicalStepState();
}

class _uKonekMedicalStepState extends State<uKonekMedicalStep> {
  final _allergiesCtrl    = TextEditingController();
  final _conditionsCtrl   = TextEditingController();
  final _prevDentistCtrl  = TextEditingController();
  final _emergNameCtrl    = TextEditingController();
  final _emergPhoneCtrl   = TextEditingController();
  final _emergRelCtrl     = TextEditingController();

  // Allergy quick-select chips
  final List<String> _commonAllergies = [
    'Penicillin', 'Latex', 'Aspirin',
    'Ibuprofen', 'Codeine', 'None',
  ];
  final Set<String> _selectedAllergies = {};

  // Existing conditions
  final List<String> _conditions = [
    'Diabetes', 'Hypertension', 'Heart Disease',
    'Asthma', 'Pregnancy', 'Blood Disorder',
  ];
  final Set<String> _selectedConditions = {};

  bool _hadPreviousDentist = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from initial data if any
    _allergiesCtrl.text   =
        widget.initialData['allergies'] ?? '';
    _conditionsCtrl.text  =
        widget.initialData['conditions'] ?? '';
    _prevDentistCtrl.text =
        widget.initialData['prevDentist'] ?? '';
    _emergNameCtrl.text   =
        widget.initialData['emergName'] ?? '';
    _emergPhoneCtrl.text  =
        widget.initialData['emergPhone'] ?? '';
    _emergRelCtrl.text    =
        widget.initialData['emergRel'] ?? '';
  }

  void _notify() {
    widget.onDataChanged({
      'allergies':   _selectedAllergies.isEmpty
          ? _allergiesCtrl.text
          : _selectedAllergies.join(', '),
      'conditions':  _selectedConditions.isEmpty
          ? _conditionsCtrl.text
          : _selectedConditions.join(', '),
      'prevDentist': _prevDentistCtrl.text,
      'emergName':   _emergNameCtrl.text,
      'emergPhone':  _emergPhoneCtrl.text,
      'emergRel':    _emergRelCtrl.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────
          const Text('Medical History',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text('Optional but helps your dentist prepare.',
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 24),

          // ── Allergies ─────────────────────────────────────
          _card(children: [
            _sectionTitle('Known Allergies',
                Icons.warning_amber_outlined),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
                children: _commonAllergies.map((a) {
                  final sel = _selectedAllergies.contains(a);
                  return GestureDetector(
                      onTap: () => setState(() {
                        if (a == 'None') {
                          _selectedAllergies.clear();
                          _selectedAllergies.add('None');
                        } else {
                          _selectedAllergies.remove('None');
                          sel
                              ? _selectedAllergies.remove(a)
                              : _selectedAllergies.add(a);
                        }
                        _notify();
                      }),
                      child: AnimatedContainer(
                          duration: const Duration(
                              milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: sel
                                  ? _primary : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel ? _primary : _fieldBdr)),
                          child: Text(a,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white : _textDark))));
                }).toList()),
            const SizedBox(height: 12),
            _field('Other allergies not listed',
                _allergiesCtrl,
                Icons.add_circle_outline_rounded,
                hint: 'Type here...',
                required: false),
          ]),
          const SizedBox(height: 16),

          // ── Existing conditions ───────────────────────────
          _card(children: [
            _sectionTitle('Existing Medical Conditions',
                Icons.medical_information_outlined),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
                children: _conditions.map((c) {
                  final sel = _selectedConditions.contains(c);
                  return GestureDetector(
                      onTap: () => setState(() {
                        sel
                            ? _selectedConditions.remove(c)
                            : _selectedConditions.add(c);
                        _notify();
                      }),
                      child: AnimatedContainer(
                          duration: const Duration(
                              milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: sel
                                  ? _primary2 : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel ? _primary2 : _fieldBdr)),
                          child: Text(c,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white : _textDark))));
                }).toList()),
            const SizedBox(height: 12),
            _field('Other conditions not listed',
                _conditionsCtrl,
                Icons.add_circle_outline_rounded,
                hint: 'Type here...',
                required: false),
          ]),
          const SizedBox(height: 16),

          // ── Previous dentist ──────────────────────────────
          _card(children: [
            _sectionTitle('Previous Dentist',
                Icons.local_hospital_outlined),
            const SizedBox(height: 8),
            // Toggle
            Row(children: [
              const Expanded(child: Text(
                  'Have you seen a dentist before?',
                  style: TextStyle(
                      fontSize: 13, color: _textDark))),
              Switch(
                  value: _hadPreviousDentist,
                  activeColor: _primary,
                  onChanged: (v) => setState(() {
                    _hadPreviousDentist = v;
                    _notify();
                  })),
            ]),
            if (_hadPreviousDentist) ...[
              const SizedBox(height: 12),
              _field('Previous Dentist / Clinic Name',
                  _prevDentistCtrl,
                  Icons.person_search_rounded,
                  required: false,
                  hint: 'e.g. Dr. Smith / ABC Dental'),
            ],
          ]),
          const SizedBox(height: 16),

          // ── Emergency contact ─────────────────────────────
          _card(children: [
            _sectionTitle('Emergency Contact',
                Icons.emergency_share_outlined),
            const SizedBox(height: 14),
            _field('Full Name',
                _emergNameCtrl,
                Icons.person_add_alt_1_outlined),
            _phoneField(_emergPhoneCtrl),
            _field('Relationship',
                _emergRelCtrl,
                Icons.people_outline_rounded,
                hint: 'e.g. Mother, Spouse'),
          ]),
          const SizedBox(height: 16),

          // ── Info note ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _primary.withOpacity(0.12))),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: _primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                  'This information helps your dentist '
                      'provide safer and more personalized care. '
                      'You can update it anytime from your profile.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      height: 1.4))),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────
  Widget _card({required List<Widget> children}) =>
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16, offset: const Offset(0, 6))]),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children));

  Widget _sectionTitle(String title, IconData icon) =>
      Row(children: [
        Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: _primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: _primary, size: 16)),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _textDark)),
      ]);

  Widget _field(String label, TextEditingController ctrl,
      IconData icon, {bool required = true, String? hint}) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
            controller: ctrl,
            onChanged: (_) => _notify(),
            style: const TextStyle(
                fontSize: 14, color: _textDark),
            decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey.shade400),
                labelStyle: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: Icon(icon,
                    color: _primary.withOpacity(0.6), size: 20),
                filled: true, fillColor: _fieldBg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _fieldBdr)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _fieldBdr)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: _primary2, width: 1.8))),
            validator: required
                ? (v) => (v == null || v.trim().isEmpty)
                ? '$label is required' : null
                : null));
  }

  Widget _phoneField(TextEditingController ctrl) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
            controller: ctrl,
            onChanged: (_) => _notify(),
            keyboardType: TextInputType.phone,
            style: const TextStyle(
                fontSize: 14, color: _textDark,
                fontWeight: FontWeight.w600),
            decoration: InputDecoration(
                prefixIcon: Padding(
                    padding: const EdgeInsets.only(
                        left: 14, right: 6),
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_android_rounded,
                              color: _primary.withOpacity(0.6), size: 20),
                          const SizedBox(width: 6),
                          const Text('+63 ',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14, color: _textDark)),
                        ])),
                prefixIconConstraints: const BoxConstraints(
                    minWidth: 0, minHeight: 0),
                hintText: '9XX XXX XXXX',
                labelText: 'Emergency Contact Number',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                labelStyle: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500),
                filled: true, fillColor: _fieldBg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _fieldBdr)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _fieldBdr)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: _primary2, width: 1.8)))));
  }
}