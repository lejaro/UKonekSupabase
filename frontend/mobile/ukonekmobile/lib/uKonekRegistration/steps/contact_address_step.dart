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
                                                                const Text(
                                                                  'Contact & Address',
                                                                  style: TextStyle(
                                                                    fontSize: 22,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: _textDark,
                                                                    letterSpacing: -0.5,
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 4),
                                                                const Text(
                                                                  'How can we reach you?',
                                                                  style: TextStyle(fontSize: 13, color: _textMuted),
                                                                ),
                                                                const SizedBox(height: 24),
                                                    
                                                                // ── Contact Card ─────────────────────────────────
                                                                _sectionCard(
                                                                  icon: Icons.contact_mail_outlined,
                                                                  title: 'Your Information',
                                                                  children: [
                                                                    _phoneField(contact, 'Mobile Number'),
                                                                    _inputField(email, 'Email Address', Icons.email_outlined,
                                                                        isEmail: true),
                                                                    const Padding(
                                                                      padding: EdgeInsets.symmetric(vertical: 4),
                                                                      child: Divider(color: _fieldBdr),
                                                                    ),
                                                                    _sectionSubLabel('Home Address'),
                                                                    const SizedBox(height: 12),
                                                                    Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child: _inputField(
                                                                              houseNo, 'House #', Icons.home_outlined),
                                                                        ),
                                                                        const SizedBox(width: 12),
                                                                        Expanded(
                                                                          flex: 2,
                                                                          child: _inputField(
                                                                              street, 'Street Name', Icons.signpost_outlined),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    _barangayDropdown(), // Integrated Valenzuela Barangay Dropdown[cite: 1]
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 16),
                                                    
                                                                // ── Emergency Card ───────────────────────────────
                                                                _sectionCard(
                                                                  icon: Icons.emergency_share_outlined,
                                                                  title: 'Emergency Contact',
                                                                  children: [
                                                                    _inputField(eName, 'Full Name', Icons.person_add_alt_1_outlined),
                                                                    _phoneField(eContact, 'Emergency Number'),
                                                                    _relationshipDropdown(), // Integrated Relationship Dropdown[cite: 1]
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    
                                                      // ── Component Wrappers ───────────────────────────────────────
                                                    
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
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Container(
                                                                    width: 36,
                                                                    height: 36,
                                                                    decoration: BoxDecoration(
                                                                      color: _primary.withOpacity(0.08),
                                                                      borderRadius: BorderRadius.circular(10),
                                                                    ),
                                                                    child: Icon(icon, color: _primary, size: 18),
                                                                  ),
                                                                  const SizedBox(width: 10),
                                                                  Text(
                                                                    title,
                                                                    style: const TextStyle(
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 15,
                                                                      color: _textDark,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 20),
                                                              ...children,
                                                            ],
                                                          ),
                                                        );
                                                      }
                                                    
                                                      Widget _sectionSubLabel(String text) => Text(
                                                        text,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                          color: _textDark,
                                                        ),
                                                      );
                                                    
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
                                                              fontSize: 14,
                                                              color: _textDark,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                            decoration: _decoration(label, Icons.phone_android_rounded).copyWith(
                                                              prefixIcon: Padding(
                                                                padding: const EdgeInsets.only(left: 14, right: 8),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Icon(Icons.phone_android_rounded,
                                                                        color: _primary.withOpacity(0.6), size: 20),
                                                                    const SizedBox(width: 6),
                                                                    const Text(
                                                                      '+63 ',
                                                                      style: TextStyle(
                                                                        color: _textDark,
                                                                        fontWeight: FontWeight.bold,
                                                                        fontSize: 14,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              prefixIconConstraints:
                                                              const BoxConstraints(minWidth: 0, minHeight: 0),
                                                              hintText: '9XX XXX XXXX',
                                                              hintStyle: TextStyle(
                                                                color: _textMuted.withOpacity(0.5),
                                                                fontWeight: FontWeight.normal,
                                                              ),
                                                            ),
                                                            validator: (v) => (v == null || v.length != 10)
                                                                ? 'Enter 10-digit number'
                                                                : null,
                                                          ),
                                                        );
                                                      }
                                                    
                                                      Widget _inputField(TextEditingController ctrl, String label, IconData icon,
                                                          {bool isEmail = false, bool enabled = true}) {
                                                        return Padding(
                                                          padding: const EdgeInsets.only(bottom: 16),
                                                          child: TextFormField(
                                                            controller: ctrl,
                                                            enabled: enabled,
                                                            style: TextStyle(
                                                                fontSize: 14, color: enabled ? _textDark : _textMuted),
                                                            decoration: _decoration(label, icon),
                                                            validator: (v) {
                                                              if (v == null || v.trim().isEmpty) return 'Required';
                                                              if (isEmail && (!v.contains('@') || !v.contains('.'))) {
                                                                return 'Invalid email';
                                                              }
                                                              return null;
                                                            },
                                                          ),
                                                        );
                                                      }
                                                    
                                                      Widget _barangayDropdown() {
                                                        final List<String> valenzuelaBarangays = [
                                                          'Arkong Bato', 'Bisig', 'Coloong', 'Lawang Bato', 'Malanday',
                                                          'Pariancillo Villa', 'Pulo', 'Tagalag', 'Balangkas', 'Canumay East',
                                                          'Dalandanan', 'Lingunan', 'Malinta', 'Pasolo', 'Punturin',
                                                          'Veinte Reales', 'Bignay', 'Canumay West', 'Isla', 'Mabolo',
                                                          'Palasan', 'Poblacion', 'Rincon', 'Wawang Pulo', 'Bagbaguin',
                                                          'Mapulang Lupa', 'Parada', 'Gen. T. de Leon', 'Marulas',
                                                          'Paso de Blas', 'Karuhatan', 'Maysan', 'Ugong'
                                                        ]..sort(); // Alphabetical sorting[cite: 1]
                                                    
                                                        return Padding(
                                                          padding: const EdgeInsets.only(bottom: 16),
                                                          child: DropdownButtonFormField<String>(
                                                            value: brgy.text.isEmpty ? null : brgy.text, // Defaults to hint if empty[cite: 1]
                                                            isExpanded: true,
                                                            dropdownColor: Colors.white,
                                                            style: const TextStyle(fontSize: 14, color: _textDark),
                                                            decoration: _decoration('Barangay', Icons.location_city_outlined),
                                                            hint: Text('Choose a Barangay', // Default placeholder[cite: 1]
                                                                style: TextStyle(color: _textMuted.withOpacity(0.6))),
                                                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textMuted.withOpacity(0.5)),
                                                            items: valenzuelaBarangays.map((String value) {
                                                              return DropdownMenuItem<String>(
                                                                value: value,
                                                                child: Text(value),
                                                              );
                                                            }).toList(),
                                                            onChanged: (String? newValue) {
                                                              brgy.text = newValue ?? '';
                                                            },
                                                            validator: (v) => (v == null || v.isEmpty) ? 'Please choose a barangay' : null,
                                                          ),
                                                        );
                                                      }
                                                    
                                                      Widget _relationshipDropdown() {
                                                        final List<String> relationships = [
                                                          'Parent', 'Spouse', 'Sibling', 'Child', 'Grandparent',
                                                          'Guardian', 'Friend', 'Relative', 'Other'
                                                        ];
                                                    
                                                        return Padding(
                                                          padding: const EdgeInsets.only(bottom: 16),
                                                          child: DropdownButtonFormField<String>(
                                                            value: relation.text.isEmpty ? null : relation.text, // Defaults to hint if empty[cite: 1]
                                                            isExpanded: true,
                                                            dropdownColor: Colors.white,
                                                            style: const TextStyle(fontSize: 14, color: _textDark),
                                                            decoration: _decoration('Relationship', Icons.people_outline_rounded),
                                                            hint: Text('Choose Relationship', // Default placeholder[cite: 1]
                                                                style: TextStyle(color: _textMuted.withOpacity(0.6))),
                                                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textMuted.withOpacity(0.5)),
                                                            items: relationships.map((String value) {
                                                              return DropdownMenuItem<String>(
                                                                value: value,
                                                                child: Text(value),
                                                              );
                                                            }).toList(),
                                                            onChanged: (String? newValue) {
                                                              relation.text = newValue ?? '';
                                                            },
                                                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                                          ),
                                                        );
                                                      }
                                                    
                                                      InputDecoration _decoration(String label, IconData icon) {
                                                        return InputDecoration(
                                                          labelText: label,
                                                          labelStyle: const TextStyle(fontSize: 13, color: _textMuted),
                                                          prefixIcon: Icon(icon, color: _primary.withOpacity(0.6), size: 20),
                                                          filled: true,
                                                          fillColor: _fieldBg,
                                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                          border: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: const BorderSide(color: _fieldBdr)),
                                                          enabledBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: const BorderSide(color: _fieldBdr)),
                                                          disabledBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: const BorderSide(color: _fieldBdr)),
                                                          focusedBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: const BorderSide(color: _primary, width: 1.8)),
                                                          errorBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: const BorderSide(color: Colors.redAccent)),
                                                        );
                                                      }
                                                    }