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

  static const _primary   = Color(0xFF0A2E6E);
  static const _primary2  = Color(0xFF1565C0);
  static const _textDark  = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);
  static const _fieldBg   = Color(0xFFF8FAFF);
  static const _fieldBdr  = Color(0xFFDDE3F0);

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
            // ── Section heading ─────────────────────────────
            const Text('Personal Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                  letterSpacing: -0.5,
                )),
            const SizedBox(height: 4),
            Text(
                'Enter your information as it appears on your ID.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 24),

            // ── Name card ───────────────────────────────────
            _card(children: [
              _field('First Name',  firstName,
                  Icons.person_outline_rounded, required: true),
              _field('Middle Name', middleName,
                  Icons.badge_outlined,
                  required: false, hint: 'Optional'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2,
                      child: _field('Last Name', lastName,
                          Icons.family_restroom_outlined,
                          required: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Ext.', nameExtension,
                      Icons.more_horiz,
                      required: false, hint: 'Jr/III')),
                ],
              ),
            ]),
            const SizedBox(height: 16),

            // ── DOB + Sex card ──────────────────────────────
            _card(children: [
              const Text('Date of Birth',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  )),
              const SizedBox(height: 10),
              _datePicker(),
              const SizedBox(height: 20),
              const Text('Sex',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  )),
              const SizedBox(height: 10),
              _sexSelector(),
            ]),
            const SizedBox(height: 24),

            // ── Privacy note ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _primary.withOpacity(0.10)),
              ),
              child: Row(children: [
                const Icon(Icons.shield_outlined,
                    color: _primary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                    'Your data is encrypted and securely stored.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card wrapper ─────────────────────────────────────────────
  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // ── Input field ──────────────────────────────────────────────
  Widget _field(String label, TextEditingController ctrl,
      IconData icon, {bool required = true, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(
            fontSize: 14, color: _textDark),
        decoration: InputDecoration(
          labelText:  label,
          hintText:   hint,
          labelStyle: TextStyle(
              fontSize: 13, color: Colors.grey.shade500),
          prefixIcon: Icon(icon,
              color: _primary.withOpacity(0.6), size: 20),
          filled:     true,
          fillColor:  _fieldBg,
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
                  color: _primary2, width: 1.8)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Colors.redAccent)),
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty))
            return 'Required';
          return null;
        },
      ),
    );
  }

  // ── Date picker ──────────────────────────────────────────────
  Widget _datePicker() {
    return InkWell(
      onTap: onPickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _fieldBdr),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.calendar_today_rounded,
                color: _primary, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
              selectedDate == null
                  ? 'Select birth date'
                  : '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}',
              style: TextStyle(
                fontSize: 14,
                color: selectedDate == null
                    ? Colors.grey.shade500
                    : _textDark,
                fontWeight: selectedDate == null
                    ? FontWeight.normal
                    : FontWeight.w600,
              )),
          const Spacer(),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  // ── Sex selector ─────────────────────────────────────────────
  Widget _sexSelector() {
    return Row(children: [
      _sexBtn('Male',   Icons.male_rounded),
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
                ? const LinearGradient(
                colors: [_primary, _primary2])
                : null,
            color: isSelected ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isSelected ? _primary : _fieldBdr),
            boxShadow: isSelected
                ? [BoxShadow(
              color: _primary.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: isSelected
                      ? Colors.white
                      : Colors.grey.shade400,
                  size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : _textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}