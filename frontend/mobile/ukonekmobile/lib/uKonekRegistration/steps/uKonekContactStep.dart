import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class uKonekContactStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController contact;
  final TextEditingController email;
  final TextEditingController houseNo;
  final TextEditingController street;
  final TextEditingController brgy;
  final TextEditingController eName;
  final TextEditingController eContact;
  final TextEditingController relation;

  const uKonekContactStep({
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

  static const _primary   = Color(0xFF0077B6);
  static const _primary2  = Color(0xFF0096C7);
  static const _textDark  = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);
  static const _fieldBg   = Color(0xFFF0F9FF);
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
            const Text('Contact & Address',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                  letterSpacing: -0.5,
                )),
            const SizedBox(height: 4),
            Text('How can we reach you?',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 24),

            // ── Contact card ─────────────────────────────────
            _sectionCard(
              icon:  Icons.contact_mail_outlined,
              title: 'Your Information',
              children: [
                _phoneField(contact, 'Mobile Number'),
                _inputField(email,
                    'Email Address', Icons.email_outlined,
                    isEmail: true),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Divider(color: Color(0xFFF0F4FF))),
                _sectionSubLabel('Home Address'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _inputField(
                      houseNo, 'House #',
                      Icons.home_outlined)),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _inputField(
                      street, 'Street Name',
                      Icons.signpost_outlined)),
                ]),
                _inputField(brgy, 'Barangay',
                    Icons.location_city_outlined,
                    enabled: false),
              ],
            ),
            const SizedBox(height: 16),

            // ── Emergency card ───────────────────────────────
            _sectionCard(
              icon:  Icons.emergency_share_outlined,
              title: 'Emergency Contact',
              children: [
                _inputField(eName, 'Full Name',
                    Icons.person_add_alt_1_outlined),
                _phoneField(eContact, 'Emergency Number'),
                _inputField(relation, 'Relationship',
                    Icons.people_outline_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Card ─────────────────────────────────────────────────────
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
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
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _primary, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textDark,
                )),
          ]),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _sectionSubLabel(String text) => Text(text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: _textDark,
      ));

  // ── Phone field ──────────────────────────────────────────────
  Widget _phoneField(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        style: const TextStyle(
            fontSize: 14, color: _textDark,
            fontWeight: FontWeight.w600),
        decoration: _decoration(label,
            Icons.phone_android_rounded).copyWith(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(
                left: 14, right: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.phone_android_rounded,
                  color: _primary.withOpacity(0.6), size: 20),
              const SizedBox(width: 6),
              const Text('+63 ',
                  style: TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  )),
            ]),
          ),
          prefixIconConstraints: const BoxConstraints(
              minWidth: 0, minHeight: 0),
          hintText: '9XX XXX XXXX',
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontWeight: FontWeight.normal,
          ),
        ),
        validator: (v) => (v == null || v.length != 10)
            ? 'Enter 10-digit number'
            : null,
      ),
    );
  }

  // ── Standard field ───────────────────────────────────────────
  Widget _inputField(TextEditingController ctrl,
      String label, IconData icon,
      {bool isEmail = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        enabled:    enabled,
        style: TextStyle(
            fontSize: 14,
            color: enabled ? _textDark : Colors.grey),
        decoration: _decoration(label, icon),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Required';
          if (isEmail && (!v.contains('@') || !v.contains('.')))
            return 'Invalid email';
          return null;
        },
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText:  label,
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
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
              color: _primary2, width: 1.8)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent)),
    );
  }
}