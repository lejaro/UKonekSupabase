import 'package:flutter/material.dart';

class PersonalInfoStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController firstName;
  final TextEditingController middleName;
  final TextEditingController lastName;
  final TextEditingController nameExtension;
  final TextEditingController age;
  final DateTime? selectedDate;
  final VoidCallback onPickDate;
  final String selectedSex;
  final Function(String) onSexChanged;

  const PersonalInfoStep({
    super.key,
    required this.formKey,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.nameExtension,
    required this.age,
    required this.onPickDate,
    this.selectedDate,
    required this.selectedSex,
    required this.onSexChanged,
  });

  // ── Medical Green Design Tokens ──────────────────────────────
  static const Color _primary = Color(0xFF28A745);     // Health Green[cite: 1]
  static const Color _primary2 = Color(0xFF1B5E20);    // Forest Green[cite: 1]
  static const Color _textDark = Color(0xFF1B2E1E);    // Dark Forest Charcoal[cite: 1]
  static const Color _textMuted = Color(0xFF637367);   // Muted Sage[cite: 1]
  static const Color _fieldBg = Color(0xFFF8FCF9);     // Mint-tinted Field[cite: 1]
  static const Color _fieldBdr = Color(0xFFE2E9E3);    // Light Mist Border[cite: 1]

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section Heading ──────────────────────────────
            const Text(
              'Personal Details',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter your information as it appears on your ID.',
              style: TextStyle(fontSize: 13, color: _textMuted),
            ),
            const SizedBox(height: 24),

            // ── Name Card ────────────────────────────────────
            _card(children: [
              _field('First Name', firstName, Icons.person_outline_rounded,
                  required: true),
              _field('Middle Name (Optional)', middleName, Icons.badge_outlined,
                  required: false),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _field('Last Name', lastName,
                        Icons.family_restroom_outlined,
                        required: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _extensionDropdown(), // Integrated Dropdown[cite: 1]
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),

            // ── DOB + Sex Card ───────────────────────────────
            _card(children: [
              const Text(
                'Date of Birth',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 10),
              _datePicker(),
              const SizedBox(height: 20),
              const Text(
                'Sex',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 10),
              _sexSelector(),
            ]),
            const SizedBox(height: 24),

            // ── Privacy Note ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primary.withOpacity(0.10)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: _primary, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Your data is encrypted and securely stored.',
                      style: TextStyle(fontSize: 12, color: _textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Component Wrappers ───────────────────────────────────────

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _textDark.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {bool required = true, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14, color: _textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(fontSize: 13, color: _textMuted),
          prefixIcon:
          Icon(icon, color: _primary.withOpacity(0.6), size: 20),
          filled: true,
          fillColor: _fieldBg,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _fieldBdr)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _fieldBdr)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _primary, width: 1.8)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent)),
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) {
            return 'Required';
          }
          return null;
        },
      ),
    );
  }

  Widget _extensionDropdown() {
    final List<String> extensions = ['', 'Sr.', 'Jr.', 'I', 'II', 'III', 'IV', 'V'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: nameExtension.text.isEmpty ? null : nameExtension.text,
        dropdownColor: Colors.white,
        style: const TextStyle(fontSize: 14, color: _textDark),
        decoration: InputDecoration(
          labelText: 'Ext.',
          labelStyle: const TextStyle(fontSize: 13, color: _textMuted),
          prefixIcon: Icon(Icons.more_horiz,
              color: _primary.withOpacity(0.6), size: 20),
          filled: true,
          fillColor: _fieldBg,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _fieldBdr)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _fieldBdr)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _primary, width: 1.8)),
        ),
        items: extensions.map((String val) {
          return DropdownMenuItem<String>(
            value: val,
            child: Text(
              val.isEmpty ? 'None' : val,
              style: TextStyle(color: val.isEmpty ? _textMuted : _textDark),
            ),
          );
        }).toList(),
        onChanged: (String? newValue) {
          nameExtension.text = newValue ?? '';
        },
      ),
    );
  }

  Widget _datePicker() {
    return InkWell(
      onTap: onPickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _fieldBdr),
        ),
        child: Row(
          children: [
            // Icon with a soft medical green glow
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calendar_month_rounded,
                  color: _primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedDate == null
                        ? 'Select birth date'
                        : _formatLongDate(selectedDate!),
                    style: TextStyle(
                      fontSize: 15,
                      color: selectedDate == null ? _textMuted : _textDark,
                      fontWeight: selectedDate == null
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  if (selectedDate == null)
                    Text('Used for medical records',
                        style: TextStyle(fontSize: 11, color: _textMuted))
                ],
              ),
            ),
            // Age Badge: Only shows once a date is selected
            if (selectedDate != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _primary2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${age.text} yrs old',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (selectedDate == null)
              Icon(Icons.arrow_forward_ios_rounded,
                  color: _textMuted.withOpacity(0.3), size: 14),
          ],
        ),
      ),
    );
  }

  // Helper to make the date more readable
  String _formatLongDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _sexSelector() {
    return Row(children: [
      _sexBtn('Male', Icons.male_rounded),
      const SizedBox(width: 12),
      _sexBtn('Female', Icons.female_rounded),
    ]);
  }

  Widget _sexBtn(String label, IconData icon) {
    final isSelected = selectedSex == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSexChanged(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(colors: [_primary, _primary2])
                : null,
            color: isSelected ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? _primary : _fieldBdr),
            boxShadow: isSelected
                ? [
              BoxShadow(
                color: _primary.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: isSelected ? Colors.white : _textMuted.withOpacity(0.4),
                  size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : _textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}