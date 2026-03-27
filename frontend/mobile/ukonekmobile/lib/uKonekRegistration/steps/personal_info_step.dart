import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // Consistency with your Login UI tokens
  static const _primary = Color(0xFF0D47A1);
  static const _textDark = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER SECTION ---
            const Text(
              "Personal Details",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Please enter your basic information as it appears on your ID.",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),

            // --- FORM CARD ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInputField(
                    label: "First Name",
                    controller: firstName,
                    icon: Icons.person_outline_rounded,
                    isRequired: true,
                  ),
                  _buildInputField(
                    label: "Middle Name",
                    controller: middleName,
                    icon: Icons.badge_outlined,
                    isRequired: false,
                    hint: "Optional",
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildInputField(
                          label: "Last Name",
                          controller: lastName,
                          icon: Icons.family_restroom_outlined,
                          isRequired: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: _buildInputField(
                          label: "Ext.",
                          controller: nameExtension,
                          icon: Icons.more_horiz,
                          isRequired: false,
                          hint: "Jr/III",
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 32, thickness: 1, color: Color(0xFFF0F4FF)),

                  const Text(
                    "Date of Birth",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark),
                  ),
                  const SizedBox(height: 12),
                  _buildDatePicker(),

                  const SizedBox(height: 24),

                  const Text(
                    "Sex",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark),
                  ),
                  const SizedBox(height: 12),
                  _buildSexSelector(),
                ],
              ),
            ),

            const SizedBox(height: 32),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(
                    "Your data is encrypted and secure.",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern Input Field matching Login Page style
  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isRequired,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 14, color: _textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _primary, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
        ),
        validator: (value) {
          if (isRequired && (value == null || value.trim().isEmpty)) {
            return "Required";
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: onPickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDE3F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, color: _primary, size: 18),
            const SizedBox(width: 12),
            Text(
              selectedDate == null
                  ? "Select birth date"
                  : "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}",
              style: TextStyle(
                fontSize: 14,
                color: selectedDate == null ? Colors.grey.shade500 : _textDark,
                fontWeight: selectedDate == null ? FontWeight.normal : FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildSexSelector() {
    return Row(
      children: [
        _sexButton("Male", Icons.male_rounded),
        const SizedBox(width: 12),
        _sexButton("Female", Icons.female_rounded),
      ],
    );
  }

  Widget _sexButton(String label, IconData icon) {
    bool isSelected = selectedSex == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSexChanged(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(colors: [_primary, Color(0xFF1976D2)])
                : null,
            color: isSelected ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _primary : const Color(0xFFDDE3F0),
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: _primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.grey.shade400, size: 18),
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