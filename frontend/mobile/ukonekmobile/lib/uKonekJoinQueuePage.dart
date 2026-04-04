import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'services/api_service.dart';

class _C {
  static const primary = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const bg = Color(0xFFF0F4FA);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1A2740);
  static const textMuted = Color(0xFF8A93A0);
  static const divider = Color(0xFFEEF1F6);
  static const success = Color(0xFF10B981);
  static const shadow = Color(0x0A000000);
  static const fieldBorder = Color(0xFFDDE3F0);
}

class uKonekJoinQueuePage extends StatefulWidget {
  const uKonekJoinQueuePage({super.key});

  @override
  State<uKonekJoinQueuePage> createState() => _uKonekJoinQueuePageState();
}

class _uKonekJoinQueuePageState extends State<uKonekJoinQueuePage> {
  late Future<List<QueueServiceOption>> _servicesFuture;

  final _reasonController = TextEditingController();
  final _symptomsController = TextEditingController();

  QueueServiceOption? _selectedService;
  String _citizenType = 'regular';
  bool _isSubmitting = false;

  QueueTicket? _ticket;
  QueueDashboardSnapshot? _dashboard;

  @override
  void initState() {
    super.initState();
    _servicesFuture = ApiService.listAvailableQueueServices();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }

  Future<void> _submitJoinQueue() async {
    if (_isSubmitting) return;
    if (_selectedService == null) {
      _showSnack('Please select a healthcare service.');
      return;
    }

    final reason = _reasonController.text.trim();
    final symptoms = _symptomsController.text.trim();

    if (reason.isEmpty) {
      _showSnack('Please enter your reason for visit.');
      return;
    }
    if (symptoms.isEmpty) {
      _showSnack('Please enter your current condition/symptoms.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final ticket = await ApiService.joinQueue(
        QueueJoinRequest(
          serviceKey: _selectedService!.serviceKey,
          serviceLabel: _selectedService!.serviceLabel,
          citizenType: _citizenType,
          reason: reason,
          symptoms: symptoms,
        ),
      );

      final snapshot = await ApiService.getMyQueueDashboard();

      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _dashboard = snapshot;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _citizenLabel(String key) {
    switch (key) {
      case 'pwd':
        return 'PWD';
      case 'pregnant':
        return 'Pregnant';
      default:
        return 'Regular';
    }
  }

  String _formatMinutes(int minutes) {
    final value = minutes < 0 ? 0 : minutes;
    final h = value ~/ 60;
    final m = value % 60;
    if (h <= 0) return '$m min';
    if (m == 0) return '$h hr';
    return '$h hr $m min';
  }

  String _queueNo(int? number) {
    if (number == null || number <= 0) return '--';
    return '#${number.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasTicket = _ticket != null;
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(hasTicket ? 'Queue Confirmation' : 'Join Queue'),
      ),
      body: hasTicket ? _buildTicketView() : _buildJoinForm(),
      bottomNavigationBar: hasTicket ? null : _buildBottomAction(),
    );
  }

  Widget _buildJoinForm() {
    return FutureBuilder<List<QueueServiceOption>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final services = snapshot.data ?? const <QueueServiceOption>[];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            if (loading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Loading available services for today...'),
                    ],
                  ),
                ),
              )
            else if (snapshot.hasError)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Unable to load available services.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _servicesFuture =
                                ApiService.listAvailableQueueServices();
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (services.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No healthcare services available today.'),
                ),
              )
            else
              _buildServiceList(services),
            const SizedBox(height: 16),
            _sectionLabel('Citizen Type'),
            const SizedBox(height: 8),
            _buildCitizenTypeSelector(),
            const SizedBox(height: 16),
            _sectionLabel('Reason for Visit'),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 2,
              decoration: _inputDecoration('Enter reason for visit'),
            ),
            const SizedBox(height: 16),
            _sectionLabel('Symptoms / Current Condition'),
            const SizedBox(height: 8),
            TextField(
              controller: _symptomsController,
              maxLines: 3,
              decoration: _inputDecoration('Describe your current condition'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServiceList(List<QueueServiceOption> services) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Available Services Today'),
        const SizedBox(height: 8),
        ...services.map((service) {
          final selected = _selectedService?.serviceKey == service.serviceKey;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: selected ? _C.primaryMid.withOpacity(0.08) : _C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _C.primaryMid : _C.fieldBorder,
                width: selected ? 1.4 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: _C.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ListTile(
              onTap: () {
                setState(() {
                  _selectedService = service;
                });
              },
              title: Text(
                service.serviceLabel,
                style: const TextStyle(
                  color: _C.textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${service.doctorCount} doctor(s) available',
                style: const TextStyle(color: _C.textMuted),
              ),
              trailing: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? _C.primaryMid : _C.textMuted,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCitizenTypeSelector() {
    final values = ['regular', 'pwd', 'pregnant'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((value) {
        final selected = _citizenType == value;
        return ChoiceChip(
          selected: selected,
          label: Text(_citizenLabel(value)),
          onSelected: (_) {
            setState(() => _citizenType = value);
          },
        );
      }).toList(),
    );
  }

  Widget _buildTicketView() {
    final ticket = _ticket!;
    final dashboard = _dashboard ?? QueueDashboardSnapshot.empty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: _C.shadow, blurRadius: 14, offset: Offset(0, 5)),
            ],
          ),
          child: Column(
            children: [
              Text(
                'Queue Number ${_queueNo(ticket.queueNumber)}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _C.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ticket.serviceLabel,
                style: const TextStyle(
                  fontSize: 14,
                  color: _C.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: ticket.ticketCode,
                version: QrVersions.auto,
                size: 180,
              ),
              const SizedBox(height: 10),
              Text(
                ticket.ticketCode,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: _C.textDark,
                ),
              ),
              const SizedBox(height: 12),
              _infoRow(
                'Currently Serving',
                _queueNo(dashboard.currentlyServingQueueNumber),
              ),
              _infoRow(
                'Your Queue Number',
                _queueNo(dashboard.myQueueNumber ?? ticket.queueNumber),
              ),
              _infoRow(
                'Estimated Waiting Time',
                _formatMinutes(
                  dashboard.estimatedWaitMinutes > 0
                      ? dashboard.estimatedWaitMinutes
                      : ticket.estimatedWaitMinutes,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _C.primaryMid),
            child: const Text('DONE'),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
    final canSubmit = _selectedService != null && !_isSubmitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
      decoration: const BoxDecoration(
        color: _C.surface,
        boxShadow: [
          BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, -3)),
        ],
      ),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: canSubmit ? _submitJoinQueue : null,
          style: ElevatedButton.styleFrom(backgroundColor: _C.primaryMid),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('CONFIRM & JOIN QUEUE'),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: _C.textMuted, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: _C.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.textMuted),
      filled: true,
      fillColor: _C.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.primaryMid, width: 1.5),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _C.textDark,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
