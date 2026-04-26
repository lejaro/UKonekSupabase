import 'package:flutter/material.dart';
import 'uKonekDentalTheme.dart';
import 'uKonekDentalLoginPage.dart';

// ═══════════════════════════════════════════════════════════════
// PATIENT MAIN PAGE — Shell with bottom navigation
// ═══════════════════════════════════════════════════════════════
class uKonekPatientMain extends StatefulWidget {
  final String patientName;
  final String email;

  const uKonekPatientMain({
    super.key,
    required this.patientName,
    this.email = '',
  });

  @override
  State<uKonekPatientMain> createState() => _uKonekPatientMainState();
}

class _uKonekPatientMainState extends State<uKonekPatientMain> {
  int _selectedIndex = 0;

  static const _navItems = [
    {'icon': Icons.home_rounded,            'label': 'Home'},
    {'icon': Icons.calendar_month_rounded,  'label': 'Appointments'},
    {'icon': Icons.folder_open_rounded,     'label': 'Records'},
    {'icon': Icons.notifications_rounded,   'label': 'Alerts'},
    {'icon': Icons.person_rounded,          'label': 'Profile'},
  ];

  Widget _buildTab(int index) {
    switch (index) {
      case 0: return _PatientHomeTab(
          patientName: widget.patientName,
          onTabChange: (i) => setState(() => _selectedIndex = i));
      case 1: return const _PatientAppointmentsTab();
      case 2: return const _PatientRecordsTab();
      case 3: return const _PatientNotificationsTab();
      case 4: return _PatientProfileTab(
          patientName: widget.patientName,
          email: widget.email);
      default: return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DC.bg,
      body: IndexedStack(
          index: _selectedIndex,
          children: List.generate(5, _buildTab)),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
        decoration: BoxDecoration(
            color: DC.surface,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24)),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 20, offset: const Offset(0, -4))]),
        child: SafeArea(top: false,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(_navItems.length, (i) {
                      final sel = _selectedIndex == i;
                      return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedIndex = i),
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: EdgeInsets.symmetric(
                                  horizontal: sel ? 14 : 10, vertical: 8),
                              decoration: BoxDecoration(
                                  color: sel
                                      ? DC.primary.withOpacity(0.10)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedScale(
                                        scale: sel ? 1.15 : 1.0,
                                        duration: const Duration(
                                            milliseconds: 200),
                                        child: Icon(
                                            _navItems[i]['icon'] as IconData,
                                            color: sel
                                                ? DC.primary
                                                : Colors.grey.shade400,
                                            size: 24)),
                                    const SizedBox(height: 4),
                                    Text(_navItems[i]['label'] as String,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: sel
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: sel
                                                ? DC.primary
                                                : Colors.grey.shade400)),
                                  ]));
                      }))));
    }
}

// ═══════════════════════════════════════════════════════════════
// TAB 1 — HOME
// ═══════════════════════════════════════════════════════════════
class _PatientHomeTab extends StatelessWidget {
  final String patientName;
  final void Function(int) onTabChange;

  const _PatientHomeTab({
    required this.patientName,
    required this.onTabChange});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return '☀️ Good Morning,';
    if (h < 17) return '🌤 Good Afternoon,';
    return '🌙 Good Evening,';
  }

  String get _firstName =>
      patientName.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(context),
      Expanded(child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNextAppointment(context),
                const SizedBox(height: 24),
                _label('Quick Actions'),
                const SizedBox(height: 12),
                _buildQuickActions(context),
                const SizedBox(height: 24),
                _label('Available Services'),
                const SizedBox(height: 12),
                _buildServices(),
                const SizedBox(height: 24),
                _buildClinicInfo(),
              ]))),
    ]);
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
        decoration: DC.gradientDecor(
            radius: 0,
            colors: [DC.primary, DC.primaryMid]),
        child: SafeArea(
            bottom: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                child: Column(children: [
                  Row(children: [
                    Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4))),
                        child: Center(child: Text(
                            _firstName[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text(_firstName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3)),
                        ])),
                    GestureDetector(
                        onTap: () => onTabChange(3),
                        child: Stack(children: [
                          Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(
                                  Icons.notifications_none_rounded,
                                  color: Colors.white, size: 24)),
                          Positioned(top: 8, right: 9,
                              child: Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFFF5252),
                                      shape: BoxShape.circle))),
                        ])),
                  ]),
                  const SizedBox(height: 18),
                  // Health status strip
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.25))),
                      child: Row(children: [
                        const Icon(Icons.local_hospital_rounded,
                            color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('DentCare+ Clinic',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              SizedBox(height: 2),
                              Text('Open today • 8:00 AM – 5:00 PM',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ])),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: DC.success.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: DC.success.withOpacity(0.4))),
                            child: const Text('Open',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                      ])),
                ]))));
  }

  Widget _buildNextAppointment(BuildContext context) {
    return GestureDetector(
        onTap: () => onTabChange(1),
        child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0077B6), Color(0xFF0096C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(
                    color: DC.primary.withOpacity(0.3),
                    blurRadius: 16, offset: const Offset(0, 6))]),
            child: Row(children: [
              Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: Colors.white, size: 28)),
              const SizedBox(width: 14),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next Appointment',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    SizedBox(height: 4),
                    Text('Teeth Cleaning',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    SizedBox(height: 2),
                    Text('April 25, 2026 • 10:00 AM',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ])),
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('View',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
            ])));
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      {'icon': Icons.add_circle_outline_rounded,
        'label': 'Book\nAppointment',
        'color': DC.primary, 'tab': 1},
      {'icon': Icons.folder_open_rounded,
        'label': 'My\nRecords',
        'color': const Color(0xFF10B981), 'tab': 2},
      {'icon': Icons.medication_rounded,
        'label': 'Prescriptions',
        'color': const Color(0xFF7B1FA2), 'tab': 2},
      {'icon': Icons.info_outline_rounded,
        'label': 'Clinic\nInfo',
        'color': DC.warning, 'tab': -1},
    ];
    return Row(
        children: actions.asMap().entries.map((e) {
          final i   = e.key;
          final act = e.value;
          final color = act['color'] as Color;
          return Expanded(child: GestureDetector(
              onTap: () {
                final tab = act['tab'] as int;
                if (tab >= 0) onTabChange(tab);
              },
              child: Container(
                  margin: EdgeInsets.only(
                      right: i < actions.length - 1 ? 10 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: DC.cardDecor(),
                  child: Column(children: [
                    Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(13)),
                        child: Icon(act['icon'] as IconData,
                            color: color, size: 22)),
                    const SizedBox(height: 8),
                    Text(act['label'] as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: DC.textDark, height: 1.3)),
                  ]))));
        }).toList());
  }

  Widget _buildServices() {
    final services = [
      {'label': 'Check-up',  'icon': Icons.search_rounded,          'color': DC.primary},
      {'label': 'Cleaning',  'icon': Icons.cleaning_services_rounded,'color': const Color(0xFF10B981)},
      {'label': 'Filling',   'icon': Icons.build_circle_outlined,    'color': const Color(0xFF7B1FA2)},
      {'label': 'Braces',    'icon': Icons.straighten_rounded,       'color': DC.warning},
      {'label': 'Whitening', 'icon': Icons.wb_sunny_outlined,        'color': const Color(0xFFF59E0B)},
      {'label': 'Implant',   'icon': Icons.settings_rounded,         'color': const Color(0xFFE53935)},
    ];
    return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0),
        itemCount: services.length,
        itemBuilder: (_, i) {
          final s     = services[i];
          final color = s['color'] as Color;
          return Container(
              decoration: DC.cardDecor(radius: 16),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14)),
                        child: Icon(s['icon'] as IconData,
                            color: color, size: 24)),
                    const SizedBox(height: 8),
                    Text(s['label'] as String,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DC.textDark)),
                  ]));
        });
  }

  Widget _buildClinicInfo() {
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: DC.cardDecor(),
        child: Column(children: [
          Row(children: [
            Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: DC.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_hospital_rounded,
                    color: DC.primary, size: 22)),
            const SizedBox(width: 12),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DentCare+ Clinic',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15, color: DC.textDark)),
                  SizedBox(height: 2),
                  Text('Dr. Maria Santos, DDS',
                      style: TextStyle(
                          fontSize: 12, color: DC.textMuted)),
                ])),
          ]),
          const SizedBox(height: 14),
          Divider(height: 1, color: DC.divider),
          const SizedBox(height: 12),
          _clinicRow(Icons.location_on_outlined,
              '123 Mabini St., Valenzuela City'),
          const SizedBox(height: 8),
          _clinicRow(Icons.access_time_rounded,
              'Mon–Sat: 8:00 AM – 5:00 PM'),
          const SizedBox(height: 8),
          _clinicRow(Icons.phone_outlined,
              '+63 912 345 6789'),
        ]));
  }

  Widget _clinicRow(IconData icon, String text) =>
      Row(children: [
        Icon(icon, size: 16, color: DC.primary.withOpacity(0.7)),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: const TextStyle(
                fontSize: 12, color: DC.textMuted))),
      ]);

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold,
          color: DC.textDark, letterSpacing: -0.2));
}

// ═══════════════════════════════════════════════════════════════
// TAB 2 — APPOINTMENTS
// ═══════════════════════════════════════════════════════════════
class _PatientAppointmentsTab extends StatefulWidget {
  const _PatientAppointmentsTab();
  @override
  State<_PatientAppointmentsTab> createState() =>
      _PatientAppointmentsTabState();
}

class _PatientAppointmentsTabState
    extends State<_PatientAppointmentsTab>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;
  bool _showBooking = false;

  final _services = [
    'General Check-up', 'Teeth Cleaning', 'Tooth Extraction',
    'Tooth Filling', 'Root Canal', 'Dental Braces',
    'Teeth Whitening', 'Dentures', 'Dental Crown'];

  String? _selectedService;
  DateTime? _selectedDate;
  String? _selectedTime;
  final _reasonCtrl = TextEditingController();

  final _times = [
    '8:00 AM','9:00 AM','10:00 AM','11:00 AM',
    '1:00 PM','2:00 PM','3:00 PM','4:00 PM'];

  static const _upcoming = [
    {'service': 'Teeth Cleaning',    'date': 'April 25, 2026',
      'time': '10:00 AM', 'status': 'confirmed'},
    {'service': 'Dental Check-up',   'date': 'May 3, 2026',
      'time': '2:00 PM',  'status': 'pending'},
  ];
  static const _past = [
    {'service': 'Tooth Filling',     'date': 'March 15, 2026',
      'time': '9:00 AM',  'status': 'completed'},
    {'service': 'General Check-up',  'date': 'Feb 10, 2026',
      'time': '11:00 AM', 'status': 'completed'},
    {'service': 'Teeth Cleaning',    'date': 'Jan 5, 2026',
      'time': '3:00 PM',  'status': 'cancelled'},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      Expanded(child: _showBooking
          ? _buildBookingForm()
          : _buildAppointmentList()),
    ]);
  }

  Widget _buildHeader() {
    return Container(
        decoration: DC.gradientDecor(
            radius: 0, colors: [DC.primary, DC.primaryMid]),
        child: SafeArea(bottom: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(children: [
                  Row(children: [
                    if (_showBooking)
                      GestureDetector(
                          onTap: () =>
                              setState(() => _showBooking = false),
                          child: Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white, size: 18))),
                    if (_showBooking) const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_showBooking
                              ? 'Book Appointment'
                              : 'Appointments',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.4)),
                          const SizedBox(height: 2),
                          Text(_showBooking
                              ? 'Fill in the details below'
                              : 'Manage your dental visits',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ])),
                    if (!_showBooking)
                      GestureDetector(
                          onTap: () =>
                              setState(() => _showBooking = true),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.3))),
                              child: const Row(children: [
                                Icon(Icons.add_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text('Book',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ]))),
                  ]),
                  if (!_showBooking) ...[
                    const SizedBox(height: 16),
                    TabBar(
                        controller: _tabCtrl,
                        indicator: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10)),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: DC.primary,
                        unselectedLabelColor: Colors.white70,
                        labelStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Upcoming'),
                          Tab(text: 'Past'),
                        ]),
                    const SizedBox(height: 4),
                  ],
                ]))));
  }

  Widget _buildAppointmentList() {
    return TabBarView(
        controller: _tabCtrl,
        children: [
          _apptList(_upcoming, upcoming: true),
          _apptList(_past,     upcoming: false),
        ]);
  }

  Widget _apptList(
      List<Map<String, String>> items, {required bool upcoming}) {
    if (items.isEmpty) {
      return Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(upcoming
                ? 'No upcoming appointments'
                : 'No past appointments',
                style: const TextStyle(
                    color: DC.textMuted, fontSize: 14)),
          ]));
    }
    return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        itemCount: items.length,
        itemBuilder: (_, i) => _apptCard(items[i],
            upcoming: upcoming));
  }

  Widget _apptCard(Map<String, String> appt,
      {required bool upcoming}) {
    final status    = appt['status']!;
    final statusClr = DC.statusColor(status);
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: DC.cardDecor(),
        child: Column(children: [
          Container(height: 4,
              decoration: BoxDecoration(
                  color: statusClr,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20)))),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                          color: DC.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.local_hospital_outlined,
                          color: DC.primary, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appt['service']!,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: DC.textDark)),
                        const SizedBox(height: 2),
                        const Text('Dr. Maria Santos',
                            style: TextStyle(
                                fontSize: 12, color: DC.textMuted)),
                      ])),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: statusClr.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(DC.statusLabel(status),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusClr))),
                ]),
                const SizedBox(height: 12),
                Divider(height: 1, color: DC.divider),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: DC.primary.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text('${appt['date']} at ${appt['time']}',
                      style: const TextStyle(
                          fontSize: 12, color: DC.textMuted)),
                ]),
                if (upcoming) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                            foregroundColor: DC.error,
                            side: const BorderSide(color: DC.error),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10)),
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 13)))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                            backgroundColor: DC.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10)),
                        child: const Text('Reschedule',
                            style: TextStyle(fontSize: 13)))),
                  ]),
                ],
              ])),
        ]));
  }

  Widget _buildBookingForm() {
    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(children: [
          // Service selection
          _bookCard(
              title: 'Select Service',
              child: Wrap(spacing: 10, runSpacing: 10,
                  children: _services.map((s) {
                    final sel = _selectedService == s;
                    return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedService = s),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                                color: sel ? DC.primary : DC.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: sel ? DC.primary : DC.fieldBdr)),
                            child: Text(s,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? Colors.white : DC.textDark))));
                  }).toList())),
          const SizedBox(height: 16),

          // Date selection
          _bookCard(
              title: 'Select Date',
              child: CalendarDatePicker(
                  initialDate: DateTime.now().add(
                      const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(
                      const Duration(days: 60)),
                  onDateChanged: (d) =>
                      setState(() => _selectedDate = d))),
          const SizedBox(height: 16),

          // Time slots
          _bookCard(
              title: 'Select Time',
              child: Wrap(spacing: 10, runSpacing: 10,
                  children: _times.map((t) {
                    final sel = _selectedTime == t;
                    return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedTime = t),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                                color: sel ? DC.primary : DC.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: sel ? DC.primary : DC.fieldBdr)),
                            child: Text(t,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? Colors.white : DC.textDark))));
                  }).toList())),
          const SizedBox(height: 16),

          // Reason
          _bookCard(
              title: 'Reason for Visit (Optional)',
              child: TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: DC.inputDecor('Describe your concern',
                      Icons.edit_note_rounded).copyWith(
                      hintText: 'e.g. Tooth pain, routine check-up...',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade400)))),
          const SizedBox(height: 28),

          // Confirm button
          SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: DC.primary,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: DC.primary.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  onPressed: () {
                    if (_selectedService == null ||
                        _selectedDate == null ||
                        _selectedTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: const Text(
                                  'Please select service, date and time.'),
                              backgroundColor: DC.error,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 16)));
                      return;
                    }
                    setState(() => _showBooking = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                '✅ Appointment booked! Waiting for confirmation.'),
                            backgroundColor: DC.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.fromLTRB(
                                16, 0, 16, 16)));
                  },
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('CONFIRM APPOINTMENT',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8, fontSize: 15)),
                        SizedBox(width: 8),
                        Icon(Icons.check_circle_outline_rounded,
                            size: 18),
                      ]))),
        ]));
  }

  Widget _bookCard({
    required String title,
    required Widget child}) {
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: DC.cardDecor(),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold,
                      color: DC.textDark)),
              const SizedBox(height: 14),
              child,
            ]));
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 3 — DENTAL RECORDS
// ═══════════════════════════════════════════════════════════════
class _PatientRecordsTab extends StatelessWidget {
  const _PatientRecordsTab();

  static const _records = [
    {'date': 'March 15, 2026', 'procedure': 'Tooth Filling',
      'diagnosis': 'Dental Caries – Tooth #14',
      'notes': 'Composite filling applied. Avoid hard foods for 24hrs.',
      'prescribed': 'Mefenamic Acid 500mg, 3x daily x3 days',
      'color': 0xFF1565C0},
    {'date': 'Feb 10, 2026', 'procedure': 'General Check-up',
      'diagnosis': 'Healthy — No cavities detected',
      'notes': 'Good oral hygiene. Continue regular brushing.',
      'prescribed': 'None',
      'color': 0xFF10B981},
    {'date': 'Jan 5, 2026', 'procedure': 'Teeth Cleaning',
      'diagnosis': 'Mild tartar buildup',
      'notes': 'Professional cleaning done. Use fluoride toothpaste.',
      'prescribed': 'Fluoride mouthwash — use daily',
      'color': 0xFF7B1FA2},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          itemCount: _records.length,
          itemBuilder: (ctx, i) =>
              _recordCard(ctx, _records[i]))),
    ]);
  }

  Widget _buildHeader() {
    return Container(
        decoration: DC.gradientDecor(
            radius: 0, colors: [DC.primary, DC.primaryMid]),
        child: SafeArea(bottom: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Row(children: [
                  const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dental Records',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.4)),
                        SizedBox(height: 2),
                        Text('Your treatment history',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ])),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('Export',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
                ]))));
  }

  Widget _recordCard(BuildContext context,
      Map<String, dynamic> r) {
    final color = Color(r['color'] as int);
    return GestureDetector(
        onTap: () => _showDetail(context, r),
        child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: DC.cardDecor(),
            child: Column(children: [
              Container(height: 4,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20)))),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.medical_services_outlined,
                            color: color, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['procedure'] as String,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: DC.textDark)),
                          const SizedBox(height: 3),
                          Text(r['date'] as String,
                              style: const TextStyle(
                                  fontSize: 12, color: DC.textMuted)),
                          const SizedBox(height: 4),
                          Text(r['diagnosis'] as String,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ])),
                    const Icon(Icons.chevron_right_rounded,
                        color: DC.textMuted, size: 20),
                  ])),
            ])));
  }

  void _showDetail(BuildContext context,
      Map<String, dynamic> r) {
    final color = Color(r['color'] as int);
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DraggableScrollableSheet(
            initialChildSize: 0.65,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, sc) => Container(
                decoration: const BoxDecoration(
                    color: DC.surface,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28))),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(width: 36, height: 4,
                          decoration: BoxDecoration(
                              color: DC.divider,
                              borderRadius: BorderRadius.circular(2)))),
                  Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [color, color.withOpacity(0.7)]),
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(13)),
                            child: const Icon(
                                Icons.medical_services_outlined,
                                color: Colors.white, size: 24)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['procedure'] as String,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(r['date'] as String,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12)),
                            ])),
                      ])),
                  Expanded(child: ListView(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(20,0,20,30),
                      children: [
                        _detailSection('Diagnosis',
                            r['diagnosis'] as String, color),
                        _detailSection('Treatment Notes',
                            r['notes'] as String, color),
                        _detailSection('Prescribed Medications',
                            r['prescribed'] as String, color),
                      ])),
                ]))));
  }

  Widget _detailSection(String title, String content,
      Color color) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(),
                  style: TextStyle(
                      color: color, fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: DC.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DC.divider)),
                  child: Text(content,
                      style: const TextStyle(
                          fontSize: 13, color: DC.textDark,
                          height: 1.5))),
            ]));
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 4 — NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════
class _PatientNotificationsTab extends StatefulWidget {
  const _PatientNotificationsTab();
  @override
  State<_PatientNotificationsTab> createState() =>
      _PatientNotificationsTabState();
}

class _PatientNotificationsTabState
    extends State<_PatientNotificationsTab> {

  final List<Map<String, dynamic>> _notifs = [
    {'title': 'Appointment Confirmed',
      'body': 'Your Teeth Cleaning on April 25 at 10:00 AM has been confirmed by Dr. Santos.',
      'time': 'Just now', 'icon': Icons.check_circle_rounded,
      'color': DC.success, 'read': false, 'type': 'Appointment'},
    {'title': 'Appointment Reminder',
      'body': 'Reminder: You have a Teeth Cleaning appointment tomorrow at 10:00 AM.',
      'time': '2 hours ago', 'icon': Icons.alarm_rounded,
      'color': DC.primary, 'read': false, 'type': 'Reminder'},
    {'title': 'Prescription Ready',
      'body': 'Dr. Santos has added a new prescription to your last visit record.',
      'time': 'Mar 15', 'icon': Icons.medication_rounded,
      'color': Color(0xFF7B1FA2), 'read': true, 'type': 'Prescription'},
    {'title': 'New Dental Record',
      'body': 'Your dental record for your March 15 visit has been updated.',
      'time': 'Mar 15', 'icon': Icons.folder_rounded,
      'color': Color(0xFF1565C0), 'read': true, 'type': 'Record'},
  ];

  int get _unread =>
      _notifs.where((n) => !(n['read'] as bool)).length;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
          decoration: DC.gradientDecor(
              radius: 0, colors: [DC.primary, DC.primaryMid]),
          child: SafeArea(bottom: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      20, 16, 20, 28),
                  child: Row(children: [
                    const Icon(Icons.notifications_rounded,
                        color: Colors.white, size: 26),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notifications',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.4)),
                          Text(_unread > 0
                              ? '$_unread unread notification${_unread > 1 ? 's' : ''}'
                              : 'All caught up!',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ])),
                    if (_unread > 0)
                      GestureDetector(
                          onTap: () => setState(() {
                            for (final n in _notifs) n['read'] = true;
                          }),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Text('Mark all read',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)))),
                  ])))),
      Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          itemCount: _notifs.length,
          itemBuilder: (_, i) {
            final n = _notifs[i];
            final isRead = n['read'] as bool;
            final color  = n['color'] as Color;
            return GestureDetector(
                onTap: () =>
                    setState(() => n['read'] = true),
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: isRead ? DC.surface
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: isRead ? DC.divider
                                : DC.primary.withOpacity(0.2),
                            width: isRead ? 1 : 1.5),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(
                                isRead ? 0.03 : 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4))]),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(13)),
                              child: Icon(n['icon'] as IconData,
                                  color: color, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: color.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(6)),
                                      child: Text(n['type'] as String,
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: color))),
                                  const Spacer(),
                                  Text(n['time'] as String,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: DC.textMuted)),
                                  if (!isRead) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                        width: 8, height: 8,
                                        decoration: BoxDecoration(
                                            color: DC.primary,
                                            shape: BoxShape.circle)),
                                  ],
                                ]),
                                const SizedBox(height: 6),
                                Text(n['title'] as String,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isRead
                                            ? FontWeight.w600
                                            : FontWeight.bold,
                                        color: DC.textDark)),
                                const SizedBox(height: 4),
                                Text(n['body'] as String,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: DC.textMuted,
                                        height: 1.4)),
                              ])),
                        ]));
            })),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 5 — PROFILE
// ═══════════════════════════════════════════════════════════════
class _PatientProfileTab extends StatelessWidget {
  final String patientName;
  final String email;

  const _PatientProfileTab({
    required this.patientName,
    required this.email});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
          decoration: DC.gradientDecor(
              radius: 0, colors: [DC.primary, DC.primaryMid]),
          child: SafeArea(bottom: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      20, 16, 20, 32),
                  child: Column(children: [
                    const Text('My Profile',
                        style: TextStyle(
                            color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2)),
                        child: Center(child: Text(
                            patientName.isNotEmpty
                                ? patientName[0].toUpperCase() : 'P',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 12),
                    Text(patientName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(email,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 10),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                            color: DC.success.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: DC.success.withOpacity(0.4))),
                        child: const Text('Patient',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12))),
                  ])))),
      Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            _profileCard('Personal Information', [
              _profileRow('Full Name', patientName),
              _profileRow('Email', email),
              _profileRow('Phone', '+63 912 345 6789'),
              _profileRow('Address', 'Brgy. Ugong, Valenzuela City'),
              _profileRow('Date of Birth', 'January 1, 1995'),
              _profileRow('Sex', 'Male'),
            ]),
            const SizedBox(height: 16),
            _profileCard('Dental History', [
              _profileRow('Allergies', 'None'),
              _profileRow('Existing Conditions', 'None'),
              _profileRow('Last Dental Visit', 'March 15, 2026'),
            ]),
            const SizedBox(height: 16),
            _profileCard('Emergency Contact', [
              _profileRow('Name', 'Maria Dela Cruz'),
              _profileRow('Phone', '+63 917 765 4321'),
              _profileRow('Relation', 'Mother'),
            ]),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const uKonekDentalLoginPage()),
                            (r) => false),
                    icon: const Icon(Icons.logout_rounded,
                        color: Colors.red, size: 20),
                    label: const Text('Log Out',
                        style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                            color: Colors.red.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))))),
          ]))),
    ]);
  }

  Widget _profileCard(String title, List<Widget> rows) {
    return Container(
        decoration: DC.cardDecor(),
        padding: const EdgeInsets.all(18),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold,
                      color: DC.primary)),
              const SizedBox(height: 10),
              Divider(height: 1, color: DC.divider),
              const SizedBox(height: 8),
              ...rows,
            ]));
  }

  Widget _profileRow(String label, String value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          SizedBox(width: 130,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: DC.textMuted,
                      fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          Expanded(child: Text(
              value.isNotEmpty ? value : '—',
              style: const TextStyle(
                  fontSize: 13, color: DC.textDark,
                  fontWeight: FontWeight.w600))),
        ]));
  }
}