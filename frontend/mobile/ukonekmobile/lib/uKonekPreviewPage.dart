import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'uKonekCredentialPage.dart';

class uKonekPreviewPage extends StatelessWidget {
  final String firstName, middleName, surname, dob, age, contact, sex, email, address;
  final String emergencyName, emergencyContact, relation;
  final File? idImage;
  final bool idVerified;
  final String extractedOcrText;

  const uKonekPreviewPage({
    super.key,
    required this.firstName, required this.middleName, required this.surname,
    required this.dob, required this.age, required this.contact, required this.sex,
    required this.email, required this.address, required this.emergencyName,
    required this.emergencyContact, required this.relation,
    required this.idImage, required this.idVerified, this.extractedOcrText = "",
  });

  static const _primary = Color(0xFF0D47A1);
  static const _primaryLight = Color(0xFF1976D2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_primary, _primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
                  ),
                  const SizedBox(width: 14),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Review Details", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text("Confirm your information before submitting", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ]),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // ── Avatar / name banner ────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_primary.withOpacity(0.08), _primaryLight.withOpacity(0.04)]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _primary.withOpacity(0.1)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 58, height: 58,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_primary, _primaryLight]),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text(
                          firstName.isNotEmpty ? firstName[0].toUpperCase() : "?",
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        )),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("$firstName $surname", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                        const SizedBox(height: 2),
                        Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: idVerified ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: idVerified ? Colors.green.shade200 : Colors.orange.shade200),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(idVerified ? Icons.verified_rounded : Icons.warning_amber_rounded,
                                size: 13, color: idVerified ? Colors.green : Colors.orange),
                            const SizedBox(width: 4),
                            Text(idVerified ? "ID Verified" : "ID Unverified",
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                    color: idVerified ? Colors.green.shade700 : Colors.orange.shade700)),
                          ]),
                        ),
                      ])),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // ── Personal info card ──────────────────────────
                  _infoCard(
                    icon: Icons.person_outline_rounded,
                    title: "Personal Information",
                    rows: [
                      _InfoRow("First Name", firstName),
                      _InfoRow("Middle Name", middleName),
                      _InfoRow("Surname", surname),
                      _InfoRow("Date of Birth", dob),
                      _InfoRow("Age", age),
                      _InfoRow("Sex", sex),
                      _InfoRow("Contact", contact),
                      _InfoRow("Email", email),
                      _InfoRow("Address", address),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Emergency contact card ──────────────────────
                  _infoCard(
                    icon: Icons.emergency_outlined,
                    title: "Emergency Contact",
                    rows: [
                      _InfoRow("Name", emergencyName),
                      _InfoRow("Contact", emergencyContact),
                      _InfoRow("Relation", relation),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── ID card ────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 34, height: 34,
                            decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.credit_card_outlined, color: _primary, size: 18)),
                        const SizedBox(width: 10),
                        const Text("National ID", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A2E))),
                      ]),
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: Color(0xFFEEF2FF)),
                      const SizedBox(height: 14),
                      if (idImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: kIsWeb
                              ? Image.network(idImage!.path, width: double.infinity, height: 170, fit: BoxFit.cover)
                              : Image.file(idImage!, width: double.infinity, height: 170, fit: BoxFit.cover),
                        )
                      else
                        Container(
                          height: 80,
                          decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(14)),
                          child: const Center(child: Text("No ID image uploaded", style: TextStyle(color: Colors.grey))),
                        ),
                      if (extractedOcrText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(12)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text("📄 Extracted ID Text", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primary)),
                            const SizedBox(height: 6),
                            Text(extractedOcrText, style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.5)),
                          ]),
                        ),
                      ],
                    ]),
                  ),

                  const SizedBox(height: 28),

                  // ── SUBMIT button ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: _primary.withOpacity(0.4),
                      ),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => uKonekCredentialsPage(
                        firstName: firstName, middleName: middleName, surname: surname, dob: dob, age: age,
                        contact: contact, sex: sex, email: email, address: address,
                        emergencyName: emergencyName, emergencyContact: emergencyContact, relation: relation,
                        idImage: idImage, idVerified: idVerified, extractedOcrText: extractedOcrText,
                      ))),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text("SUBMIT & CONTINUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 20),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Back button ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFDDE3F0), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        foregroundColor: Colors.black54,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("BACK TO EDIT", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String title, required List<_InfoRow> rows}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34,
              decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _primary, size: 18)),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A2E))),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFEEF2FF)),
        const SizedBox(height: 10),
        ...rows.map((r) => _buildRow(r.label, r.value)),
      ]),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        Expanded(child: Text(value.isNotEmpty ? value : "—",
            style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _InfoRow {
  final String label, value;
  const _InfoRow(this.label, this.value);
}