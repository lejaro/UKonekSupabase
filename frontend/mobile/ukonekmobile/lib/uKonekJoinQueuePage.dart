import 'package:flutter/material.dart';

class _C {
  static const primary    = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const bg         = Color(0xFFF0F4FA);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1A2740);
  static const textMuted  = Color(0xFF8A93A0);
  static const divider    = Color(0xFFEEF1F6);
  static const success    = Color(0xFF10B981);
  static const shadow     = Color(0x0A000000);
  static const fieldBg    = Color(0xFFF8FAFF);
  static const fieldBorder= Color(0xFFDDE3F0);
}

class uKonekJoinQueuePage extends StatefulWidget {
  const uKonekJoinQueuePage({super.key});

  @override
  State<uKonekJoinQueuePage> createState() =>
      _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState
    extends State<uKonekJoinQueuePage> {
  String? _selectedService;
  String  _priorityType = 'Regular';
  bool    _isJoined     = false;

  final List<Map<String, dynamic>> _services = [
    {'id': 'gen', 'label': 'General Con.',
      'icon': Icons.medical_services_outlined,   'color': const Color(0xFF1565C0)},
    {'id': 'den', 'label': 'Dental',
      'icon': Icons.health_and_safety,            'color': const Color(0xFF10B981)},
    {'id': 'chk', 'label': 'Check-up',
      'icon': Icons.monitor_heart_outlined,       'color': const Color(0xFFE53935)},
    {'id': 'vax', 'label': 'Vaccination',
      'icon': Icons.vaccines_outlined,            'color': const Color(0xFF7B1FA2)},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _isJoined
                ? _buildSuccessState()
                : _buildEntryForm(),
          ),
        ),
      ]),
      bottomNavigationBar:
      !_isJoined ? _buildBottomAction() : null,
    );
  }

  // ── Header ───────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid],
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
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _isJoined ? 'Queue Status' : 'Join Queue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    )),
                Text(
                    _isJoined
                        ? 'Keep track of your turn'
                        : 'This will only take a few seconds',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  // ── Entry Form ───────────────────────────────────────────────
  Widget _buildEntryForm() {
    return SingleChildScrollView(
      key: const ValueKey('form'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _sectionLabel('Select a Service'),
          const SizedBox(height: 14),
          _buildServiceGrid(),
          const SizedBox(height: 28),
          _sectionLabel('Additional Details'),
          const SizedBox(height: 14),
          _buildDropdownField(),
          const SizedBox(height: 14),
          _buildReasonField(),
          const SizedBox(height: 24),
          _buildConfirmationSummary(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildServiceGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   2,
        crossAxisSpacing: 14,
        mainAxisSpacing:  14,
        childAspectRatio: 1.3,
      ),
      itemCount: _services.length,
      itemBuilder: (_, index) {
        final s          = _services[index];
        final isSelected = _selectedService == s['id'];
        final color      = s['color'] as Color;
        return GestureDetector(
          onTap: () => setState(
                  () => _selectedService = s['id'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? _C.primaryMid : _C.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? _C.primaryMid : _C.fieldBorder,
                width: isSelected ? 0 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? _C.primaryMid.withOpacity(0.25)
                      : _C.shadow,
                  blurRadius: isSelected ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(s['icon'] as IconData,
                      color: isSelected ? Colors.white : color,
                      size: 26),
                ),
                const SizedBox(height: 10),
                Text(s['label'] as String,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : _C.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value:    _priorityType,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: _C.textMuted),
          items: ['Regular', 'Senior Citizen', 'PWD', 'Pregnant']
              .map((e) => DropdownMenuItem(
            value: e,
            child: Row(children: [
              Icon(_priorityIcon(e),
                  color: _C.primaryMid, size: 18),
              const SizedBox(width: 10),
              Text(e, style: const TextStyle(
                  fontSize: 14, color: _C.textDark)),
            ]),
          ))
              .toList(),
          onChanged: (v) =>
              setState(() => _priorityType = v!),
        ),
      ),
    );
  }

  IconData _priorityIcon(String type) {
    switch (type) {
      case 'Senior Citizen': return Icons.elderly_rounded;
      case 'PWD':            return Icons.accessible_rounded;
      case 'Pregnant':       return Icons.child_friendly_rounded;
      default:               return Icons.person_outline_rounded;
    }
  }

  Widget _buildReasonField() {
    return TextField(
      style: const TextStyle(fontSize: 14, color: _C.textDark),
      decoration: InputDecoration(
        hintText:    'Reason for visit (e.g. Fever, Cough)',
        hintStyle:   const TextStyle(
            color: _C.textMuted, fontSize: 13),
        prefixIcon:  const Icon(Icons.edit_note_rounded,
            color: _C.primaryMid, size: 20),
        filled:      true,
        fillColor:   _C.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _C.fieldBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _C.fieldBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
                color: _C.primaryMid, width: 1.8)),
      ),
    );
  }

  Widget _buildConfirmationSummary() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.primaryMid.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _C.primaryMid.withOpacity(0.12)),
      ),
      child: Column(children: [
        _summaryRow(Icons.local_hospital_outlined,
            'Health Center', 'Brgy. Ugong Health Center'),
        const SizedBox(height: 10),
        _summaryRow(Icons.calendar_today_outlined,
            'Date', 'March 28, 2026'),
        const SizedBox(height: 10),
        _summaryRow(Icons.timer_outlined,
            'Est. Wait', '10–15 minutes'),
      ]),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, color: _C.primaryMid, size: 16),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
              color: _C.textMuted, fontSize: 13)),
      const Spacer(),
      Text(value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: _C.textDark,
            fontSize: 13,
          )),
    ]);
  }

  // ── Success / Ticket ─────────────────────────────────────────
  Widget _buildSuccessState() {
    return SingleChildScrollView(
      key: const ValueKey('success'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          // Ticket card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(
                color: _C.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              )],
            ),
            child: Column(children: [
              // Ticket header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_C.primary, _C.primaryMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft:  Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Queue Ticket',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        )),
                    const SizedBox(height: 2),
                    Text(
                        DateTime.now()
                            .toString()
                            .split(' ')[0],
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              // Dashed separator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List.generate(
                    18,
                        (i) => Expanded(
                      child: Container(
                        height: 1,
                        color: i.isEven
                            ? _C.divider
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              // Queue number
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  const Text('YOUR QUEUE NUMBER',
                      style: TextStyle(
                        color: _C.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      )),
                  const SizedBox(height: 10),
                  Text('#12',
                      style: const TextStyle(
                        color: _C.primary,
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3,
                      )),
                  const SizedBox(height: 24),
                  // Status rows
                  _ticketRow('Status',      'You are next', _C.success),
                  const SizedBox(height: 10),
                  _ticketRow('Wait Time',   'Est. 10 mins', _C.primaryMid),
                  const SizedBox(height: 10),
                  _ticketRow('Ahead of you','2 People',     _C.textDark),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 28),

          // SMS toggle
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(
                  color: _C.shadow, blurRadius: 12)],
            ),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _C.primaryMid.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sms_outlined,
                    color: _C.primaryMid, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Notify me via SMS',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _C.textDark,
                  ))),
              Switch(
                value: true,
                activeColor: _C.primaryMid,
                onChanged: (v) {},
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Leave queue
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _isJoined = false),
              icon: const Icon(Icons.exit_to_app_rounded,
                  color: Colors.red, size: 18),
              label: const Text('Leave Queue',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  )),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                    color: Colors.red.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticketRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: _C.textMuted, fontSize: 14)),
        Text(value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            )),
      ],
    );
  }

  // ── Bottom Action ────────────────────────────────────────────
  Widget _buildBottomAction() {
    final canJoin = _selectedService != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      decoration: BoxDecoration(
        color: _C.surface,
        boxShadow: [BoxShadow(
          color: _C.shadow,
          blurRadius: 16,
          offset: const Offset(0, -4),
        )],
      ),
      child: ElevatedButton(
        onPressed: canJoin
            ? () => setState(() => _isJoined = true)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canJoin ? _C.primaryMid : Colors.grey.shade200,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          elevation: canJoin ? 4 : 0,
          shadowColor: _C.primaryMid.withOpacity(0.3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'CONFIRM & JOIN QUEUE',
              style: TextStyle(
                color: canJoin ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (canJoin) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: _C.textDark,
        letterSpacing: -0.2,
      ));
}