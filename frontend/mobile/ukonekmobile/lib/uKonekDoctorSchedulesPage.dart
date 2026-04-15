import 'package:flutter/material.dart';
import 'services/api_service.dart';

class uKonekDoctorSchedulesPage extends StatefulWidget {
  const uKonekDoctorSchedulesPage({super.key});

  @override
  State<uKonekDoctorSchedulesPage> createState() => _uKonekDoctorSchedulesPageState();
}

class _uKonekDoctorSchedulesPageState extends State<uKonekDoctorSchedulesPage> {
  bool _loading = true;
  String? _error;
  List<DoctorSchedule> _allSchedules = const [];
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiService.listAvailableDoctorSchedules();
      if (!mounted) return;
      setState(() {
        _allSchedules = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  List<DoctorSchedule> get _visibleSchedules {
    if (_selectedDate == null) return _allSchedules;
    return _allSchedules.where((s) {
      return s.scheduleDate.year == _selectedDate!.year &&
          s.scheduleDate.month == _selectedDate!.month &&
          s.scheduleDate.day == _selectedDate!.day;
    }).toList(growable: false);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return hhmmss;
    final h24 = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1].padLeft(2, '0');
    final isPm = h24 >= 12;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final meridiem = isPm ? 'PM' : 'AM';
    return '$h12:$minute $meridiem';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
    );

    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Schedules'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadSchedules,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: ElevatedButton(
                          onPressed: _loadSchedules,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(
                                  _selectedDate == null
                                      ? 'All upcoming dates'
                                      : _formatDate(_selectedDate!),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (_selectedDate != null)
                              IconButton(
                                tooltip: 'Clear date filter',
                                onPressed: () => setState(() => _selectedDate = null),
                                icon: const Icon(Icons.clear),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _visibleSchedules.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 100),
                                  Center(
                                    child: Text(
                                      'No available schedules found.',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                                itemCount: _visibleSchedules.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _visibleSchedules[index];
                                  final specialization = item.specialization.isEmpty
                                      ? 'General Practice'
                                      : item.specialization;

                                  return Card(
                                    elevation: 1.5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            specialization,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              const Icon(Icons.event_outlined, size: 18, color: Color(0xFF1565C0)),
                                              const SizedBox(width: 6),
                                              Text(_formatDate(item.scheduleDate)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.schedule_outlined, size: 18, color: Color(0xFF1565C0)),
                                              const SizedBox(width: 6),
                                              Text('${_formatTime(item.startTime)} - ${_formatTime(item.endTime)}'),
                                            ],
                                          ),
                                          if ((item.notes ?? '').isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              item.notes!,
                                              style: const TextStyle(color: Colors.black54),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
