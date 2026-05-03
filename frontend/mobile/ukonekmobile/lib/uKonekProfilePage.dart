import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'uKonekMenuPage.dart';
import 'services/api_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'uKonekMedicineScheduler.dart';  // ✅ added
import 'uKonekJoinQueuePage.dart';      // ✅ added

// ── Design tokens ──────────────────────────────────────────────
class _C {
  static const primary     = Color(0xFF28A745);
  static const primaryMid  = Color(0xFF1B5E20);
  static const accent      = Color(0xFF20C997);
  static const bg          = Color(0xFFF8FCF9);
  static const surface     = Colors.white;
  static const textDark    = Color(0xFF1B2E1E);
  static const textMuted   = Color(0xFF637367);
  static const divider     = Color(0xFFE2E9E3);
  static const success     = Color(0xFF28A745);
  static const warning     = Color(0xFFF59E0B);
  static const shadow      = Color(0x0A000000);
  static const fieldBg     = Color(0xFFF4FAF5);
  static const fieldBdr    = Color(0xFFD6E8DA);
}

class uKonekProfilePage extends StatefulWidget {
  final String username;
  final String citizenId;
  final String fullName;
  final String email;
  final String phone;
  final String address;
  final String firstName;
  final String middleName;
  final String surname;
  final String nameExtension;
  final String dob;
  final String age;
  final String sex;
  final String emergencyName;
  final String emergencyContact;
  final String relation;
  final bool   idVerified;

  const uKonekProfilePage({
    super.key,
    required this.username,
    required this.citizenId,
    required this.fullName,
    this.email            = '',
    this.phone            = '',
    this.address          = '',
    this.firstName        = '',
    this.middleName       = '',
    this.surname          = '',
    this.nameExtension    = '',
    this.dob              = '',
    this.age              = '',
    this.sex              = '',
    this.emergencyName    = '',
    this.emergencyContact = '',
    this.relation         = '',
    this.idVerified       = false,
  });

  @override
  State<uKonekProfilePage> createState() => _uKonekProfilePageState();
}

class _uKonekProfilePageState extends State<uKonekProfilePage> {

  // ✅ Profile is tab index 3
  int _selectedTab = 3;

  late String _firstName, _middleName, _surname, _nameExtension,
      _dob, _age, _sex, _email, _phone, _address,
      _emergencyName, _emergencyContact, _relation;

  @override
  void initState() {
    super.initState();
    _firstName        = widget.firstName.isNotEmpty ? widget.firstName : widget.fullName.split(' ').first;
    _middleName       = widget.middleName;
    _surname          = widget.surname.isNotEmpty
        ? widget.surname
        : (widget.fullName.split(' ').length > 1 ? widget.fullName.split(' ').last : '');
    _nameExtension    = widget.nameExtension;
    _dob              = widget.dob;
    _age              = widget.age;
    _sex              = widget.sex;
    _email            = widget.email;
    _phone            = widget.phone;
    _address          = widget.address;
    _emergencyName    = widget.emergencyName;
    _emergencyContact = widget.emergencyContact;
    _relation         = widget.relation;
  }

  String get _displayName {
    final parts = [_firstName, _middleName, _surname, _nameExtension]
        .where((s) => s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : widget.fullName;
  }

  String get _initials {
    if (_firstName.isNotEmpty && _surname.isNotEmpty) {
      return '${_firstName[0]}${_surname[0]}'.toUpperCase();
    }
    return widget.fullName.isNotEmpty ? widget.fullName[0].toUpperCase() : 'U';
  }

  // Add this getter to _uKonekProfilePageState
  String get _formattedDob {
    if (_dob.isEmpty) return '—';
    // Try parsing ISO format: 2004-09-24
    final parsed = DateTime.tryParse(_dob);
    if (parsed != null) {
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
    }
    return _dob; // return as-is if already formatted
  }

  // ── QR Code Popup ────────────────────────────────────────────
  void _showQrDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('Patient Digital ID', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _C.textDark)),
            const SizedBox(height: 8),
            const Text('Present this QR code for dental clinic check-in', style: TextStyle(color: _C.textMuted, fontSize: 13)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.divider)),
              child: QrImageView(
                data: widget.citizenId,
                version: QrVersions.auto,
                size: 200.0,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _C.primaryMid),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _C.primaryMid),
              ),
            ),
            const SizedBox(height: 16),
            Text('ID: ${widget.citizenId}', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, color: _C.primaryMid)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _snack('Downloading ID to Gallery...', _C.primaryMid),
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text('DOWNLOAD ID CARD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      bottomNavigationBar: _buildBottomNav(), // ✅ wired in
      body: Column(children: [
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            // ✅ Extra bottom padding so content clears the nav bar
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIdentityButton(),
                const SizedBox(height: 24),
                _sectionLabel('PERSONAL INFORMATION'),
                const SizedBox(height: 12),
                _buildPersonalCard(),
                const SizedBox(height: 24),
                _sectionLabel('CONTACT & ADDRESS'),
                const SizedBox(height: 12),
                _buildContactCard(),
                const SizedBox(height: 24),
                _sectionLabel('EMERGENCY CONTACT'),
                const SizedBox(height: 12),
                _buildEmergencyCard(),
                const SizedBox(height: 24),
                _sectionLabel('ACCOUNT SETTINGS'),
                const SizedBox(height: 12),
                _buildSettingsCard(),
                const SizedBox(height: 28),
                _buildLogoutButton(context),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Bottom Navigation ────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.dashboard_rounded,           'label': 'Home'},
      {'icon': Icons.event_note_rounded,           'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded,  'label': 'Queue'},
      {'icon': Icons.person_outline_rounded,       'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: const BorderRadius.only(
          topLeft:  Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(color: _C.textDark.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () {
                  if (i == 0) {
                    // ✅ Pop back to Dashboard — it still holds all registration data
                    Navigator.pop(context);
                  } else if (i == 1) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekMedicineSchedulerPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    ));
                  } else if (i == 2) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => uKonekJoinQueuePage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    ));
                  } else if (i == 3) {
                    // Already on Profile
                    setState(() => _selectedTab = 3);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _C.primaryMid.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(
                      tabs[i]['icon'] as IconData,
                      color: isSelected ? _C.primaryMid : Colors.grey.shade400,
                      size: 22,
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      Text(
                        tabs[i]['label'] as String,
                        style: const TextStyle(color: _C.primaryMid, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_C.primary, _C.primaryMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
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
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Citizen Profile', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(widget.username, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Identity hero button ──────────────────────────────────────
  Widget _buildIdentityButton() {
    return GestureDetector(
      onTap: _showQrDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_C.primary, _C.primaryMid]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: _C.primary.withOpacity(0.28), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.4), width: 2)),
                child: Center(child: Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold))),
              ),
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: _C.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_displayName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Tap to show your QR check-in code', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 40),
        ]),
      ),
    );
  }

  // ── Cards ────────────────────────────────────────────────────
  Widget _buildPersonalCard() {
    return _card(
      editLabel: 'Edit',
      onEdit: () => _showEditSheet(
        title: 'Personal Information',
        icon: Icons.person_outline_rounded,
        fields: [
          _EditField('First Name',     _firstName,     (v) => _firstName     = v),
          _EditField('Middle Name',    _middleName,    (v) => _middleName    = v, required: false),
          _EditField('Last Name',      _surname,       (v) => _surname       = v),
          _EditField('Name Extension', _nameExtension, (v) => _nameExtension = v, required: false),
          _EditField('Date of Birth',  _dob,           (v) => _dob           = v, hint: 'MM/DD/YYYY'),
          _EditField('Age',            _age,           (v) => _age           = v, numeric: true),
          _EditField('Sex',            _sex,           (v) => _sex           = v),
        ],
      ),
      children: [
        _tile(Icons.person_outline_rounded, 'Full Name',     _displayName),
        _divider(),
        _tile(Icons.cake_outlined, 'Date of Birth', _formattedDob),
        _divider(),
        _tile(Icons.wc_rounded,             'Sex',           _sex.isNotEmpty ? _sex : '—'),
        _divider(),
        _tile(Icons.numbers_rounded,        'Age',           _age.isNotEmpty ? '$_age years old' : '—'),
      ],
    );
  }

  Widget _buildContactCard() {
    return _card(
      editLabel: 'Edit',
      onEdit: () => _showEditSheet(
        title: 'Contact & Address',
        icon: Icons.contact_mail_outlined,
        fields: [
          _EditField('Email',   _email,   (v) => _email   = v),
          _EditField('Phone',   _phone,   (v) => _phone   = v),
          _EditField('Address', _address, (v) => _address = v),
        ],
      ),
      children: [
        _tile(Icons.email_outlined,        'Email',   _email.isNotEmpty   ? _email   : '—'),
        _divider(),
        _tile(Icons.phone_android_rounded, 'Phone',   _phone.isNotEmpty   ? _phone   : '—'),
        _divider(),
        _tile(Icons.location_on_outlined,  'Address', _address.isNotEmpty ? _address : '—'),
      ],
    );
  }

  Widget _buildEmergencyCard() {
    return _card(
      editLabel: 'Edit',
      onEdit: () => _showEditSheet(
        title: 'Emergency Contact',
        icon: Icons.emergency_outlined,
        fields: [
          _EditField('Contact Name',   _emergencyName,    (v) => _emergencyName    = v),
          _EditField('Contact Number', _emergencyContact, (v) => _emergencyContact = v),
          _EditField('Relationship',   _relation,         (v) => _relation         = v),
        ],
      ),
      children: [
        _tile(Icons.contact_emergency_outlined, 'Name',         _emergencyName.isNotEmpty    ? _emergencyName    : '—'),
        _divider(),
        _tile(Icons.people_outline_rounded,     'Relationship', _relation.isNotEmpty         ? _relation         : '—'),
        _divider(),
        _tile(Icons.phone_callback_rounded,     'Number',       _emergencyContact.isNotEmpty ? _emergencyContact : '—'),
      ],
    );
  }

  Widget _buildSettingsCard() {
    return _card(children: [
      _settingsTile(Icons.lock_outline_rounded, 'Change Password', onTap: _showChangePasswordSheet),
      _divider(),
      _settingsTile(Icons.info_outline_rounded, 'About U-Konek+',  onTap: _showAboutDialog),
    ]);
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Log Out?', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const uKonekMenuPage()),
                      (route) => false,
                ),
                child: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
        label: const Text('LOG OUT ACCOUNT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // ── Edit Sheet ───────────────────────────────────────────────
  void _showEditSheet({required String title, required IconData icon, required List<_EditField> fields}) {
    final controllers = {for (final f in fields) f.label: TextEditingController(text: f.value)};
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(color: _C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                Container(width: 38, height: 38, decoration: BoxDecoration(color: _C.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: _C.primary, size: 20)),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.textDark)),
              ]),
            ),
            const SizedBox(height: 4),
            Divider(indent: 20, endIndent: 20, color: _C.divider),
            Expanded(
              child: Form(
                key: formKey,
                child: ListView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: fields.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextFormField(
                      controller: controllers[f.label],
                      keyboardType: f.numeric ? TextInputType.number : TextInputType.text,
                      inputFormatters: f.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
                      style: const TextStyle(fontSize: 14, color: _C.textDark),
                      decoration: InputDecoration(
                        labelText: f.label,
                        hintText:  f.hint,
                        labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        filled: true,
                        fillColor: _C.fieldBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.fieldBdr)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.fieldBdr)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.primaryMid, width: 1.8)),
                      ),
                      validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? '${f.label} is required' : null : null,
                    ),
                  )).toList(),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      setState(() {
                        for (final f in fields) { f.setter(controllers[f.label]!.text.trim()); }
                      });
                      Navigator.pop(context);
                      _snack('✅ $title updated successfully!', _C.success);
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8, fontSize: 15)),
                      SizedBox(width: 8),
                      Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Change Password Sheet ────────────────────────────────────
  void _showChangePasswordSheet() {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confCtrl    = TextEditingController();
    bool showCurrent  = false;
    bool showNew      = false;
    bool showConf     = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: _C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: _C.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.lock_outline_rounded, color: _C.primary, size: 20)),
                  const SizedBox(width: 12),
                  const Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.textDark)),
                ]),
                const SizedBox(height: 20),
                _pwField(currentCtrl, 'Current Password', showCurrent, () => setLocal(() => showCurrent = !showCurrent)),
                const SizedBox(height: 12),
                _pwField(newCtrl,     'New Password',     showNew,     () => setLocal(() => showNew     = !showNew)),
                const SizedBox(height: 12),
                _pwField(confCtrl,    'Confirm Password', showConf,    () => setLocal(() => showConf    = !showConf)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () {
                      if (newCtrl.text.length < 6) { _snack('Password must be at least 6 characters.', Colors.redAccent); return; }
                      if (newCtrl.text != confCtrl.text) { _snack('Passwords do not match.', Colors.redAccent); return; }
                      Navigator.pop(context);
                      _snack('✅ Password updated successfully!', _C.success);
                    },
                    child: const Text('UPDATE PASSWORD', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pwField(TextEditingController ctrl, String label, bool show, VoidCallback toggle) {
    return TextFormField(
      controller: ctrl,
      obscureText: !show,
      style: const TextStyle(fontSize: 14, color: _C.textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        filled: true, fillColor: _C.fieldBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.fieldBdr)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.fieldBdr)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.primaryMid, width: 1.8)),
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: Colors.grey.shade400),
          onPressed: toggle,
        ),
      ),
    );
  }

  // ── Logout dialog ─────────────────────────────────────────────
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle),
              child: const Icon(Icons.logout_rounded,
                  color: Colors.redAccent, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Log Out Account?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _C.textDark,
                )),
            const SizedBox(height: 10),
            const Text(
                'Are you sure you want to log out? You will need to sign in again to access your records.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _C.textMuted,
                  fontSize: 13,
                  height: 1.5,
                )),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      vertical: 13),
                  side: const BorderSide(color: _C.fieldBdr),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cancel',
                    style: TextStyle(
                      color: _C.textMuted,
                      fontWeight: FontWeight.bold,
                    )),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  await ApiService.signOut();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const uKonekMenuPage()),
                        (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Log Out',
                    style: TextStyle(
                        fontWeight: FontWeight.bold)),
              )),
            ]),
          ],
        ),
      ),
    );
  }

  // ── About dialog ──────────────────────────────────────────────
  // ── About Dialog ─────────────────────────────────────────────
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [_C.primary, _C.primaryMid]), shape: BoxShape.circle),
              child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 14),
            const Text('U-Konek+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _C.primary)),
            const SizedBox(height: 4),
            const Text('Version 1.0.0', style: TextStyle(fontSize: 12, color: _C.textMuted)),
            const SizedBox(height: 12),
            const Text('A healthcare management system for AFM Roquero Medical Clinic.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _C.textMuted, height: 1.5)),
            const SizedBox(height: 6),
            const Text('Pamantasan ng Lungsod ng Valenzuela\nCollege of Engineering and Information Technology', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: _C.textMuted, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _C.primary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 13)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable widgets ─────────────────────────────────────────
  Widget _card({String? editLabel, VoidCallback? onEdit, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: _C.shadow, blurRadius: 14, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (editLabel != null && onEdit != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 14, 0),
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: _C.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_rounded, size: 13, color: _C.primary),
                    SizedBox(width: 4),
                    Text('Edit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _C.primary)),
                  ]),
                ),
              ),
            ),
          ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Column(children: children)),
      ]),
    );
  }

  Widget _tile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: _C.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: _C.primary, size: 18)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: _C.textDark, fontSize: 14)),
        ])),
      ]),
    );
  }

  Widget _settingsTile(IconData icon, String title, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: _C.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: _C.primary, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.textDark))),
          const Icon(Icons.chevron_right_rounded, size: 20, color: _C.textMuted),
        ]),
      ),
    );
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: Divider(height: 1, color: _C.divider),
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _C.textMuted, letterSpacing: 1.1)),
  );

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 2),
    ));
  }
}

// ── Edit field model ──────────────────────────────────────────
class _EditField {
  final String label;
  final String value;
  final void Function(String) setter;
  final bool required;
  final bool numeric;
  final String? hint;

  const _EditField(this.label, this.value, this.setter, {this.required = true, this.numeric = false, this.hint});
}