import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ContactAddressStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController contact;
  final TextEditingController email;
  final TextEditingController houseNo;
  final TextEditingController street;
  final TextEditingController brgy;

  // Emergency Contacts
  final TextEditingController eName;
  final TextEditingController eContact;
  final TextEditingController relation;

  const ContactAddressStep({
    super.key,
    required this.formKey,
    required this.contact,
    required this.email,
    required this.houseNo,
    required this.street,
    required this.brgy,
    required this.eName,
    required this.eContact,
    required this.relation,
  });

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
            // --- HEADER ---
            const Text(
              "Contact & Address",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _textDark),
            ),
            const SizedBox(height: 4),
            Text(
              "How can we reach you and where do you live?",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),

            // --- CONTACT & ADDRESS CARD ---
            _buildSectionCard(
              title: "Your Information",
              icon: Icons.contact_mail_outlined,
              children: [
                _buildPhoneField(contact, "Mobile Number"),
                _buildInputField(email, "Email Address", Icons.email_outlined, isEmail: true),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFFF0F4FF)),
                ),

                const Text("Home Address", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark)),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(child: _buildInputField(houseNo, "House #", Icons.home_outlined)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildInputField(street, "Street Name", Icons.signpost_outlined)),
                  ],
                ),
                _buildInputField(brgy, "Barangay", Icons.location_city_outlined, enabled: false),
              ],
            ),

            const SizedBox(height: 20),

            // --- EMERGENCY CONTACT CARD ---
            _buildSectionCard(
              title: "Emergency Contact",
              icon: Icons.emergency_share_outlined,
              children: [
                _buildInputField(eName, "Full Name", Icons.person_add_alt_1_outlined),
                _buildPhoneField(eContact, "Emergency Number"),
                _buildInputField(relation, "Relationship", Icons.people_outline_rounded),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // Helper to build the white card containers
  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primary, size: 20),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textDark)),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  // Modern Phone Field with +63 Prefix
  Widget _buildPhoneField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        style: const TextStyle(fontSize: 14, color: _textDark, fontWeight: FontWeight.w600),
        decoration: _inputDecoration(label, Icons.phone_android_rounded).copyWith(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_android_rounded, color: _primary, size: 20),
                SizedBox(width: 8),
                Text("+63 ", style: TextStyle(color: _textDark, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          hintText: "9XX XXX XXXX",
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
        ),
        validator: (v) => (v == null || v.length != 10) ? "Enter 10-digit number" : null,
      ),
    );
  }

  // Standard Modern Input Field
  Widget _buildInputField(TextEditingController controller, String label, IconData icon, {bool isEmail = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        style: TextStyle(fontSize: 14, color: enabled ? _textDark : Colors.grey),
        decoration: _inputDecoration(label, icon),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return "Required";
          if (isEmail && (!v.contains('@') || !v.contains('.'))) return "Invalid email";
          return null;
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
      prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
    );
  }
}