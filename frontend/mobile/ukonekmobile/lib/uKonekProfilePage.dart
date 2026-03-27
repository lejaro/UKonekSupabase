import 'package:flutter/material.dart';
import 'uKonekMenuPage.dart';

class uKonekProfilePage extends StatelessWidget {
  final String fullName;
  final String email;
  final String phone;
  final String address;

  const uKonekProfilePage({
    super.key,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.address,
  });

  // Design Tokens
  static const _primary = Color(0xFF0D47A1);
  static const _accent = Color(0xFF1976D2);
  static const _bg = Color(0xFFF4F7FE);
  static const _textDark = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          // ── 1. FIXED HEADER ──
          _buildStaticHeader(context),

          // ── 2. SCROLLABLE BODY ──
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _buildIdentityCard(), // Digital ID Section
                  const SizedBox(height: 32),

                  _sectionLabel("PERSONAL INFORMATION"),
                  const SizedBox(height: 12),
                  _buildPersonalDetailsCard(),

                  const SizedBox(height: 32),

                  _sectionLabel("EMERGENCY CONTACT"),
                  const SizedBox(height: 12),
                  _buildEmergencyContactCard(),

                  const SizedBox(height: 32),

                  _sectionLabel("ACCOUNT SETTINGS"),
                  const SizedBox(height: 12),
                  _buildSettingsList(),

                  const SizedBox(height: 40),
                  _buildLogoutButton(context),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STATIC HEADER ──────────────────────────────────────────────────
  Widget _buildStaticHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 25),
      decoration: const BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(40)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Citizen Profile",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text("Manage your account & identity",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.settings_outlined, color: Colors.white, size: 24),
        ],
      ),
    );
  }

  // ── 1. DIGITAL IDENTITY CARD ───────────────────────────────────────
  Widget _buildIdentityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_primary, _accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(radius: 36, backgroundColor: Colors.white24,
                      child: CircleAvatar(radius: 32, backgroundColor: Colors.white,
                          child: Icon(Icons.person_rounded, size: 40, color: _primary))),
                  CircleAvatar(radius: 10, backgroundColor: Colors.green,
                      child: Icon(Icons.check, size: 12, color: Colors.white)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text("Barangay Ugong Resident", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                      child: const Text("ID: BRGY-UG-2026-88", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 48),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. PERSONAL DETAILS CARD ───────────────────────────────────────
  Widget _buildPersonalDetailsCard() {
    return _sectionCard([
      _infoTile("Full Name", fullName, Icons.person_outline),
      _infoTile("Birthday", "January 01, 1995", Icons.cake_outlined),
      _infoTile("Mobile Number", phone, Icons.phone_android_rounded),
      _infoTile("Residential Address", address, Icons.map_outlined),
    ], hasEdit: true);
  }

  // ── 3. EMERGENCY CONTACT CARD ──────────────────────────────────────
  Widget _buildEmergencyContactCard() {
    return _sectionCard([
      _infoTile("Contact Name", "Maria Clara", Icons.contact_emergency_outlined),
      _infoTile("Relationship", "Mother", Icons.people_outline),
      _infoTile("Contact Number", "0912-345-6789", Icons.phone_callback_rounded),
    ], hasEdit: true);
  }

  // ── 4. SETTINGS LIST ───────────────────────────────────────────────
  Widget _buildSettingsList() {
    return _sectionCard([
      _settingsItem("Change Password", Icons.lock_outline),
      _settingsItem("Notification Settings", Icons.notifications_none),
      _settingsItem("Privacy & Security", Icons.security_outlined),
      _settingsItem("About uKonek App", Icons.info_outline),
    ]);
  }

  // ── UI HELPERS ─────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1));

  Widget _sectionCard(List<Widget> children, {bool hasEdit = false}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(
        children: [
          if (hasEdit)
            Align(alignment: Alignment.topRight, child: TextButton(onPressed: () {}, child: const Text("Edit", style: TextStyle(fontSize: 12)))),
          ...children,
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Icon(icon, color: _primary, size: 20),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 14)),
          ]),
        ],
      ),
    );
  }

  Widget _settingsItem(String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: _primary, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textDark)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: () {},
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: TextButton(
        onPressed: () => _showLogoutModal(context),
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 1)),
        ),
        child: const Text("LOG OUT ACCOUNT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
    );
  }

  void _showLogoutModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(radius: 30, backgroundColor: Color(0xFFFFF1F0), child: Icon(Icons.logout_rounded, color: Colors.redAccent, size: 30)),
              const SizedBox(height: 20),
              const Text("Log Out Account?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textDark)),
              const SizedBox(height: 8),
              const Text("Are you sure you want to log out? You will need to login again to access your records.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                      onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const uKonekMenuPage()), (route) => false),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: const Text("Log Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}