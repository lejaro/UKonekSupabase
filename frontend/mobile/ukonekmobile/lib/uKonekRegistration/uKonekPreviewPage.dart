import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../uKonekCredentialsPage.dart';

class uKonekPreviewPage extends StatelessWidget {
  final String firstName, middleName, surname, nameExtension;
  final String dob, age, contact, sex, email, address;
  final String emergencyName, emergencyContact, relation;
  final File?  idImage;
  final bool   idVerified;
  final String extractedOcrText;

  const uKonekPreviewPage({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.surname,
    required this.nameExtension,
    required this.dob,
    required this.age,
    required this.contact,
    required this.sex,
    required this.email,
    required this.address,
    required this.emergencyName,
    required this.emergencyContact,
    required this.relation,
    required this.idImage,
    required this.idVerified,
    this.extractedOcrText = '',
  });

  static const _primary   = Color(0xFF0077B6);
  static const _primary2  = Color(0xFF0096C7);
  static const _bg        = Color(0xFFF0F7FA);
  static const _surface   = Colors.white;
  static const _textDark  = Color(0xFF1A2740);
  static const _textMuted = Color(0xFF8A93A0);
  static const _divider   = Color(0xFFEEF1F6);
  static const _success   = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              _buildProfileBanner(),
              const SizedBox(height: 16),
              _infoCard(
                icon:  Icons.person_outline_rounded,
                title: 'Personal Information',
                rows: [
                  _Row('First Name',       firstName),
                  _Row('Middle Name',      middleName),
                  _Row('Name Extension',   nameExtension),
                  _Row('Surname',          surname),
                  _Row('Date of Birth',    dob),
                  _Row('Age',              age),
                  _Row('Sex',              sex),
                  _Row('Contact',          contact),
                  _Row('Email',            email),
                  _Row('Address',          address),
                ],
              ),
              const SizedBox(height: 14),
              _infoCard(
                icon:  Icons.emergency_outlined,
                title: 'Emergency Contact',
                rows: [
                  _Row('Name',      emergencyName),
                  _Row('Contact',   emergencyContact),
                  _Row('Relation',  relation),
                ],
              ),
              const SizedBox(height: 14),
              _idCard(),
              const SizedBox(height: 28),
              _buildSubmitBtn(context),
              const SizedBox(height: 12),
              _buildBackBtn(context),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Header ───────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primary2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Review Your Info',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
                SizedBox(height: 2),
                Text('Check everything before creating your account',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  // ── Profile Banner ───────────────────────────────────────────
  Widget _buildProfileBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        )],
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 56, height: 56,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_primary, _primary2]),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(
              firstName.isNotEmpty
                  ? firstName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$firstName $surname',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                  letterSpacing: -0.3,
                )),
            const SizedBox(height: 2),
            Text(email,
                style: const TextStyle(
                    fontSize: 12, color: _textMuted)),
            const SizedBox(height: 8),
            // ID verified badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: idVerified
                    ? _success.withOpacity(0.10)
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: idVerified
                        ? _success.withOpacity(0.3)
                        : Colors.orange.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    idVerified
                        ? Icons.verified_rounded
                        : Icons.warning_amber_rounded,
                    size: 13,
                    color: idVerified
                        ? _success
                        : Colors.orange),
                const SizedBox(width: 5),
                Text(
                    idVerified ? 'ID Verified' : 'ID Unverified',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: idVerified
                          ? _success
                          : Colors.orange.shade700,
                    )),
              ]),
            ),
          ],
        )),
      ]),
    );
  }

  // ── Info card ────────────────────────────────────────────────
  Widget _infoCard({
    required IconData icon,
    required String title,
    required List<_Row> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        )],
      ),
      padding: const EdgeInsets.all(20),
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
          const SizedBox(height: 14),
          const Divider(height: 1, color: _divider),
          const SizedBox(height: 10),
          ...rows.map((r) => _rowWidget(r.label, r.value)),
        ],
      ),
    );
  }

  Widget _rowWidget(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                    fontWeight: FontWeight.w500,
                  ))),
          const SizedBox(width: 8),
          Expanded(child: Text(
              value.isNotEmpty ? value : '—',
              style: const TextStyle(
                fontSize: 13,
                color: _textDark,
                fontWeight: FontWeight.w600,
              ))),
        ],
      ),
    );
  }

  // ── ID Card ──────────────────────────────────────────────────
  Widget _idCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        )],
      ),
      padding: const EdgeInsets.all(20),
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
              child: const Icon(Icons.credit_card_outlined,
                  color: _primary, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('National ID',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textDark,
                )),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _divider),
          const SizedBox(height: 14),
          if (idImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: kIsWeb
                  ? Image.network(idImage!.path,
                  width: double.infinity,
                  height: 170,
                  fit: BoxFit.cover)
                  : Image.file(idImage!,
                  width: double.infinity,
                  height: 170,
                  fit: BoxFit.cover),
            )
          else
            Container(
              height: 80,
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(14)),
              child: const Center(
                  child: Text('No ID uploaded',
                      style: TextStyle(color: _textMuted))),
            ),
        ],
      ),
    );
  }

  // ── Submit button ────────────────────────────────────────────
  Widget _buildSubmitBtn(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 4,
          shadowColor: _primary.withOpacity(0.35),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => uKonekCredentialsPage(
              firstName:        firstName,
              middleName:       middleName,
              surname:          surname,
<<<<<<< HEAD:frontend/mobile/ukonekmobile/lib/uKonekRegistration/uKonekPreviewPage.dart
<<<<<<< HEAD:frontend/mobile/ukonekmobile/lib/uKonekRegistration/uKonekPreviewPage.dart
              nameExtension:    nameExtension,
=======
>>>>>>> parent of ac9d4b4 (Family number implemented):frontend/mobile/ukonekmobile/lib/uKonekPreviewPage.dart
=======
>>>>>>> parent of ac9d4b4 (Family number implemented):frontend/mobile/ukonekmobile/lib/uKonekPreviewPage.dart
              dob:              dob,
              age:              age,
              contact:          contact,
              sex:              sex,
              email:            email,
              address:          address,
              emergencyName:    emergencyName,
              emergencyContact: emergencyContact,
              relation:         relation,
              idImage:          idImage,
              idVerified:       idVerified,
              extractedOcrText: extractedOcrText,
            ),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SUBMIT & CONTINUE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.8,
                )),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBackBtn(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(
              color: Color(0xFFDDE3F0), width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          foregroundColor: _textMuted,
        ),
        onPressed: () => Navigator.pop(context),
        child: const Text('BACK TO EDIT',
            style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }
}

class _Row {
  final String label, value;
  const _Row(this.label, this.value);
}