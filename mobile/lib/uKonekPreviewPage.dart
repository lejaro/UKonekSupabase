import 'package:flutter/material.dart';
import 'uKonekOtpPage.dart';

class uKonekPreviewPage extends StatelessWidget {
  final String firstName, middleName, surname, nameExtension;
  final String dob, age, contact, sex, email, address;
  final String emergencyName, emergencyContact, relation;


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
  });

  // ── Updated Medical Green Color Palette ────────────────────────
  static const _primary   = Color(0xFF28A745); // Health Green[cite: 1]
  static const _primary2  = Color(0xFF1B5E20); // Forest Green[cite: 1]
  static const _bg        = Color(0xFFF8FCF9); // Mint-tinted Background[cite: 1]
  static const _surface   = Colors.white;
  static const _textDark  = Color(0xFF1B2E1E); // Dark Forest Charcoal[cite: 1]
  static const _textMuted = Color(0xFF637367); // Muted Sage[cite: 1]
  static const _divider   = Color(0xFFE2E9E3); // Light Mist Divider[cite: 1]
  static const _success   = Color(0xFF28A745);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg, // Updated to Mint-tinted background[cite: 1]
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

  // ── Header (Green Gradient) ───────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primary2], // Updated to Green Gradient[cite: 1]
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
                Text('Review Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
                SizedBox(height: 2),
                Text('Confirm your info before submitting',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  // ── Profile Banner (Green Accents) ─────────────────────────────
  Widget _buildProfileBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
          color: _textDark.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        )],
      ),
      child: Row(children: [
        // Avatar with Medical Green Gradient[cite: 1]
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
          ],
        )),
      ]),
    );
  }

  // ── Info card (Green Accents) ──────────────────────────────────
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
          color: _textDark.withOpacity(0.05),
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


  // ── Submit button (Green Theme) ──────────────────────────────
  Widget _buildSubmitBtn(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary, // Now Health Green[cite: 1]
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
            builder: (_) => uKonekOtpPage(
              firstName:        firstName,
              middleName:       middleName,
              surname:          surname,
              dob:              dob,
              age:              age,
              contact:          contact,
              sex:              sex,
              email:            email,
              address:          address,
              emergencyName:    emergencyName,
              emergencyContact: emergencyContact,
              relation:         relation,
            ),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('VERIFY EMAIL FIRST',
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
              color: _divider, width: 1.5), // Updated to Light Mist Divider[cite: 1]
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