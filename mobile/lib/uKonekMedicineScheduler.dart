import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekProfilePage.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/app_transitions.dart';
import 'uKonekMainShellPage.dart';

class uKonekMedicineSchedulerPage extends StatefulWidget {
  final String username;
  final String citizenId;

  final bool isEmbeddedInShell;

  const uKonekMedicineSchedulerPage({
    super.key,
    required this.username,
    required this.citizenId,
    this.isEmbeddedInShell = false,
  });

  @override
  State<uKonekMedicineSchedulerPage> createState() => _uKonekMedicineSchedulerPageState();
}

class _uKonekMedicineSchedulerPageState extends State<uKonekMedicineSchedulerPage> {
  static const Color _primary    = Color(0xFF28A745);
  static const Color _primaryMid = Color(0xFF1B5E20);
  static const Color _bg         = Color(0xFFF8FCF9);
  static const Color _textDark   = Color(0xFF1B2E1E);
  static const Color _textMuted  = Color(0xFF637367);
  static const Color _fieldBdr   = Color(0xFFE2E9E3);

  int _selectedTab = 1;

  bool _loading = true;
  String? _error;
  List<ScheduledMedicine> _medicines = [];
  List<Consultation> _consultations = [];
  final Set<String> _takenDoses = {};
  final Map<String, String> _customDoseTimes = {};
  final Map<String, DateTime> _takenTimestamps = {};
  final List<Map<String, dynamic>> _manualIntakes = [];
  bool _notificationsEnabled = true;
  DateTime _selectedDate = DateTime.now();
  final Map<int, String> _persistedStartTimes = {};

  @override
  void initState() {
    super.initState();
    _load();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final enabled = await NotificationService.areNotificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  final Set<int> _startedPrescriptions = {};

  Future<void> _load() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Prune old cached logs in the background (R5)
    MedicineCacheService.pruneOldLogs(widget.citizenId);

    // 1. Instant local load if cache is available
    final cachedMeds = await MedicineCacheService.loadCachedSchedule(widget.citizenId);
    final cachedLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, dateKey);
    final prefs = await SharedPreferences.getInstance();

    if (cachedMeds != null && cachedMeds.isNotEmpty && mounted) {
      _persistedStartTimes.clear();
      for (var med in cachedMeds) {
        final stored = prefs.getString('med_start_${med.prescriptionItemId}');
        if (stored != null) _persistedStartTimes[med.prescriptionItemId] = stored;
      }
      setState(() {
        _medicines = cachedMeds.where((m) => m.isDispensed || m.dispensingStatus == 'dispensed').toList();
        if (cachedLogs != null) {
          _takenDoses.clear();
          _startedPrescriptions.clear();
          for (var log in cachedLogs) {
            final pid = (log['prescription_item_id'] as num).toInt();
            _takenDoses.add('${pid}_${log['dose_index']}');
            _startedPrescriptions.add(pid);
          }
        }
        _loading = false;
        _error = null;
      });
      _scheduleNotifications();
    } else {
      setState(() { _loading = true; _error = null; });
    }

    // 2. Skip network fetch if cache is fresh (A4)
    final isFresh = await MedicineCacheService.isScheduleCacheFresh(widget.citizenId);
    if (isFresh && cachedMeds != null && cachedMeds.isNotEmpty) return;

    // 3. Fetch fresh data from network & sync offline queue
    try {
      MedicineCacheService.syncPendingIntakeLogs();

      final results = await Future.wait<dynamic>([
        ApiService.getMedicineSchedule(),
        ApiService.getIntakeLogsForDate(_selectedDate),
        ApiService.fetchConsultations(),
      ]);

      final meds = results[0] as List<ScheduledMedicine>;
      final logs = results[1] as List<Map<String, dynamic>>;
      final consultations = results[2] as List<Consultation>;

      // Cache schedule & logs locally
      await MedicineCacheService.saveSchedule(widget.citizenId, meds);
      await MedicineCacheService.saveIntakeLogs(widget.citizenId, dateKey, logs);

      _persistedStartTimes.clear();
      for (var med in meds) {
        final stored = prefs.getString('med_start_${med.prescriptionItemId}');
        if (stored != null) {
          _persistedStartTimes[med.prescriptionItemId] = stored;
        }
      }

      if (mounted) {
        setState(() {
          _medicines = meds.where((m) => m.isDispensed || m.dispensingStatus == 'dispensed').toList();
          _consultations = consultations;
          _takenDoses.clear();
          _startedPrescriptions.clear();
          for (var log in logs) {
            final pid = (log['prescription_item_id'] as num).toInt();
            _takenDoses.add('${pid}_${log['dose_index']}');
            _startedPrescriptions.add(pid);
          }
          _loading = false;
        });
        _scheduleNotifications();
      }
    } catch (e) {
      if (_medicines.isEmpty && mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _loadDateLogs(DateTime date) async {
    setState(() => _selectedDate = date);
    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    // Instant local intake logs for selected date
    final cachedLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, dateKey);
    if (cachedLogs != null && mounted) {
      setState(() {
        _takenDoses.clear();
        _startedPrescriptions.clear();
        for (var log in cachedLogs) {
          final pid = (log['prescription_item_id'] as num).toInt();
          _takenDoses.add('${pid}_${log['dose_index']}');
          _startedPrescriptions.add(pid);
        }
      });
    }

    // Refresh logs in background
    try {
      final logs = await ApiService.getIntakeLogsForDate(date, citizenId: int.tryParse(widget.citizenId));
      await MedicineCacheService.saveIntakeLogs(widget.citizenId, dateKey, logs);
      if (mounted && DateUtils.isSameDay(_selectedDate, date)) {
        setState(() {
          _takenDoses.clear();
          for (var log in logs) {
            final pid = (log['prescription_item_id'] as num).toInt();
            _takenDoses.add('${pid}_${log['dose_index']}');
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _markAsTaken(ScheduledMedicine med, int doseIndex, String scheduledTime) async {
    final key = '${med.prescriptionItemId}_$doseIndex';
    if (_takenDoses.contains(key)) return;

    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Haptic feedback for satisfying confirmation
    HapticFeedback.mediumImpact();

    // 1. Optimistic immediate local UI update
    setState(() {
      _takenDoses.add(key);
      _takenTimestamps[key] = now;
      _startedPrescriptions.add(med.prescriptionItemId);

      final intervalMins = med.doseIntervalMinutes;
      if (intervalMins > 0) {
        int runningMins = now.hour * 60 + now.minute;
        for (int i = doseIndex + 1; i < med.doseTimes.length; i++) {
          final nextKey = '${med.prescriptionItemId}_$i';
          runningMins += intervalMins;
          final nextH = (runningMins ~/ 60) % 24;
          final nextM = runningMins % 60;
          _customDoseTimes[nextKey] = TimeOfDay(hour: nextH, minute: nextM).format(context);
        }
      }
    });

    // 2. Persist locally and queue for background sync
    await MedicineCacheService.recordLocalIntake(
      widget.citizenId,
      prescriptionItemId: med.prescriptionItemId,
      scheduledTime: scheduledTime,
      doseIndex: doseIndex,
      dateKey: dateKey,
    );

    _scheduleNotifications();

    // Show undo SnackBar (U1)
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${med.medicineName} marked as taken'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () => _undoMarkAsTaken(key),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: _primaryMid,
        ),
      );
    }

    // 3. Attempt background sync (citizenId passed to avoid redundant profile fetch)
    try {
      await ApiService.logMedicineIntake(
        prescriptionItemId: med.prescriptionItemId,
        scheduledTime: scheduledTime,
        doseIndex: doseIndex,
        citizenId: int.tryParse(widget.citizenId),
      );
    } catch (e) {
      debugPrint('Intake stored locally, will sync when online: $e');
    }
  }

  void _undoMarkAsTaken(String key) {
    setState(() {
      _takenDoses.remove(key);
      _takenTimestamps.remove(key);
    });
    // Note: local cache will be overwritten on next _load().
    // The server record (if synced) will remain, but will be re-synced on next intake.
    _scheduleNotifications();
  }

  Future<void> _setupAndMarkTaken(ScheduledMedicine med, int doseIndex, TimeOfDay picked) async {
    _applyTimeChange(med, doseIndex, picked);
    await _markAsTaken(med, doseIndex, picked.format(context));
  }

  Future<void> _scheduleNotifications() async {
    try {
      // Bug #7: Only cancel medicine reminders, not clinic alerts
      await NotificationService.cancelMedicineReminders();
      final grouped = _groupedTodayDoses;
      // Bug #6: Use offset IDs to avoid collisions with other notification types
      int id = NotificationService.medicineIdOffset;
      
      for (var entry in grouped.entries) {
        final timeStr = entry.key;
        final items = entry.value;
        if (timeStr == 'Setup Required') continue;
        
        // ONLY schedule if there's at least one untaken med in this group
        final untaken = items.where((i) => 
          !_takenDoses.contains('${(i['med'] as ScheduledMedicine).prescriptionItemId}_${i['doseIndex']}')
        ).toList();
        
        if (untaken.isEmpty) continue;
        
        // Combine names of untaken meds
        final medsStr = untaken.map((i) => (i['med'] as ScheduledMedicine).medicineName).join(', ');
        final bodyStr = untaken.map((i) => '${(i['med'] as ScheduledMedicine).medicineName}: ${(i['med'] as ScheduledMedicine).dosage}').join('\n');
        
        final t = _parseTime(timeStr);
        final targetMins = t - 30;
        final adjustedMins = targetMins < 0 ? targetMins + (24 * 60) : targetMins;
        final h30 = (adjustedMins ~/ 60) % 24;
        final m30 = adjustedMins % 60;

        // 1. 30-Minute Heads-up Reminder
        await NotificationService.scheduleMedicineReminder(
          id: id++,
          title: 'Upcoming Meds: $medsStr',
          body: 'Heads up! Your $timeStr intake is in 30 minutes:\n$bodyStr',
          hour: h30,
          minute: m30,
          payload: '{"action":"medicine","username":"${widget.username}","citizenId":"${widget.citizenId}"}',
        );

        // 2. Exact Intake Time Reminder
        final hExact = t ~/ 60;
        final mExact = t % 60;
        
        await NotificationService.scheduleMedicineReminder(
          id: id++,
          title: 'Medication Time: $medsStr',
          body: 'It is time for your $timeStr intake right now:\n$bodyStr',
          hour: hExact,
          minute: mExact,
          payload: '{"action":"medicine","username":"${widget.username}","citizenId":"${widget.citizenId}"}',
        );
      }
    } catch (e) {
      debugPrint('Error scheduling notifications: $e');
    }
  }

  Map<String, List<Map<String, dynamic>>> get _groupedTodayDoses {
    final groups = <String, List<Map<String, dynamic>>>{};
    
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    
    // Filter to only active meds for this date
    final activeMeds = _medicines.where((m) => m.isActiveOn(_selectedDate)).toList();

    // Cluster doses that are within 10 minutes of each other
    final allDoses = <Map<String, dynamic>>[];
    for (final med in activeMeds) {
      final persistedStart = _persistedStartTimes[med.prescriptionItemId];
      final isStarted = persistedStart != null || _startedPrescriptions.contains(med.prescriptionItemId);
      
      if (!isStarted && isToday) {
        // First-time setup only shown for today
        allDoses.add({'med': med, 'time': 'Setup Required', 'doseIndex': -1, 'mins': -1});
      } else if (med.dailyDoseCount == 0) {
        // R2: PRN (as-needed) medicines go into a separate group
        allDoses.add({'med': med, 'time': 'As Needed', 'doseIndex': 0, 'mins': 9999});
      } else if (isStarted || !isToday) {
        final intervalMins = med.doseIntervalMinutes;
        final baseTime = persistedStart ?? med.doseTimes.first;
        
        for (int i = 0; i < med.doseTimes.length; i++) {
          String time;
          int mins;
          if (i == 0) {
            time = baseTime;
            mins = _parseTime(baseTime);
          } else {
            final startMins = _parseTime(baseTime);
            mins = (startMins + (i * intervalMins)) % (24 * 60);
            final tod = TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
            time = tod.format(context);
          }
          allDoses.add({'med': med, 'time': time, 'doseIndex': i, 'mins': mins});
        }
      }
    }

    // Sort by minutes, handling midnight-crossing doses correctly
    // Doses after midnight (< 6 AM) from late-night schedules should come after 11 PM doses
    allDoses.sort((a, b) {
      final aMin = a['mins'] as int;
      final bMin = b['mins'] as int;
      // Treat early-morning hours (0-359 = midnight to 5:59 AM) as next-day if mixed with evening
      final aAdj = (aMin < 360 && allDoses.any((d) => (d['mins'] as int) > 720)) ? aMin + 1440 : aMin;
      final bAdj = (bMin < 360 && allDoses.any((d) => (d['mins'] as int) > 720)) ? bMin + 1440 : bMin;
      return aAdj.compareTo(bAdj);
    });

    // Grouping logic
    for (var dose in allDoses) {
      if (dose['time'] == 'Setup Required') {
        groups.putIfAbsent('Setup Required', () => []);
        groups['Setup Required']!.add(dose);
        continue;
      }

      final mins = dose['mins'] as int;
      String? targetGroup;
      
      // Look for an existing group within 10 minutes
      for (var existingTime in groups.keys) {
        if (existingTime == 'Setup Required') continue;
        final groupMins = _parseTime(existingTime);
        if ((mins - groupMins).abs() <= 10) {
          targetGroup = existingTime;
          break;
        }
      }

      final finalGroup = targetGroup ?? dose['time'];
      groups.putIfAbsent(finalGroup, () => []);
      groups[finalGroup]!.add(dose);
    }
    
    // Sort keys by time
    final sortedTimes = groups.keys.toList()..sort((a, b) => _parseTime(a).compareTo(_parseTime(b)));
    final sortedGroups = <String, List<Map<String, dynamic>>>{};
    for (var t in sortedTimes) {
      sortedGroups[t] = groups[t]!;
    }
    return sortedGroups;
  }

  int _parseTime(String t) {
    try {
      final clean = t.trim().replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
      final p = clean.split(' ');
      final hm = p[0].split(':');
      int h = int.parse(hm[0]);
      final m = int.parse(hm[1]);
      if (p.length > 1) {
        final period = p[1].toUpperCase().replaceAll('.', '');
        if ((period == 'PM' || period == 'P') && h != 12) h += 12;
        if ((period == 'AM' || period == 'A') && h == 12) h = 0;
      }
      return h * 60 + m;
    } catch (_) { return 0; }
  }

  @override
  void dispose() { super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedTodayDoses;
    final nextDose = _getNextDose(grouped);
    final completion = _getCompletionRate(grouped);
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final isPast = _selectedDate.isBefore(DateTime.now()) && !isToday;
    
    int totalDoses = 0;
    for (var entry in grouped.entries) {
      for (var d in entry.value) {
        if (d['doseIndex'] != -1) {
          totalDoses++;
        }
      }
    }
    final showProgress = totalDoses > 0 && completion >= 1.0 && (isToday || isPast);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildDateStrip(),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : _error != null ? _buildError()
            : RefreshIndicator(
                color: _primary,
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (nextDose != null && DateUtils.isSameDay(_selectedDate, DateTime.now())) ...[
                      _buildNextDoseCard(nextDose),
                      const SizedBox(height: 32),
                    ],
                    
                    if (!_notificationsEnabled) ...[
                      _buildNotificationWarning(),
                      const SizedBox(height: 24),
                    ],
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionHeader(DateUtils.isSameDay(_selectedDate, DateTime.now()) 
                          ? "Today's schedule" 
                          : "Schedule for ${DateFormat('MMM d').format(_selectedDate)}"),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedDate = DateTime.now();
                              _load();
                            });
                          }, 
                          child: Text(DateUtils.isSameDay(_selectedDate, DateTime.now()) ? 'Refresh' : 'Today', 
                            style: const TextStyle(color: _primary, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Follow-up Checkups for selectedDate ─────────────────────
                    ..._consultations
                        .where((c) => c.followupDate != null && DateUtils.isSameDay(c.followupDate!, _selectedDate))
                        .map((c) => _buildFollowupCheckupCard(c)),

                    if (grouped.isEmpty && !_consultations.any((c) => c.followupDate != null && DateUtils.isSameDay(c.followupDate!, _selectedDate))) _buildEmptyState(
                      Icons.event_available_rounded,
                      'No medicines scheduled today',
                      'Dispensed prescriptions will appear here',
                    ) else ...[
                      ...grouped.entries.map((entry) => _scheduleCardItem(
                        entry.key,
                        entry.value,
                      )),
                    ],

                    if (showProgress) ...[
                      const SizedBox(height: 32),
                      _buildProgressCard(completion),
                      const SizedBox(height: 32),
                      _buildTipCard(),
                    ],
                    
                    const SizedBox(height: 32),
                    _sectionHeader('My Prescriptions'),
                    const SizedBox(height: 16),
                    if (_medicines.isEmpty) _buildEmptyState(
                      Icons.receipt_long_rounded,
                      'No prescriptions found',
                      'Active prescriptions will appear here',
                    ) else ..._medicines.map((m) => _prescriptionCard(m)),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
          ),
        ]),
      ),
      bottomNavigationBar: widget.isEmbeddedInShell ? null : _buildBottomNav(),
    );
  }

  Widget _buildNotificationWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_off_rounded, color: Colors.orange.shade800, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Notifications are currently turned off. Please enable notifications to receive medicine reminders.',
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please go to device Settings > Apps > Notifications and turn them on for uKonek+.')),
                );
              },
              icon: Icon(Icons.settings_rounded, color: Colors.orange.shade800, size: 18),
              label: Text('Open Settings', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _getNextDose(Map<String, List<Map<String, dynamic>>> grouped) {
    for (var entry in grouped.entries) {
      if (entry.key == 'Setup Required') continue;
      final untaken = entry.value.where((d) => 
        !_takenDoses.contains('${(d['med'] as ScheduledMedicine).prescriptionItemId}_${d['doseIndex']}')
      ).toList();
      
      if (untaken.isNotEmpty) {
        return {
          'time': entry.key,
          'items': entry.value,
          'untaken': untaken,
        };
      }
    }
    return null;
  }

  double _getCompletionRate(Map<String, List<Map<String, dynamic>>> grouped) {
    int total = 0;
    int taken = 0;
    for (var entry in grouped.entries) {
      for (var d in entry.value) {
        if (d['doseIndex'] == -1) continue;
        total++;
        if (_takenDoses.contains('${(d['med'] as ScheduledMedicine).prescriptionItemId}_${d['doseIndex']}')) {
          taken++;
        }
      }
    }
    if (total == 0) return 1.0;
    return taken / total;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildHeader() {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isToday 
                  ? "${_getGreeting()}, ${widget.username.split(' ')[0]} 👋"
                  : DateFormat('MMMM yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _textDark)),
              const SizedBox(height: 4),
              Text(isToday 
                  ? "Let's stay on track with your health."
                  : "Daily medication summary.",
                  style: const TextStyle(fontSize: 14, color: _textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextDoseCard(Map<String, dynamic> next) {
    final time = next['time'] as String;
    final items = next['items'] as List<Map<String, dynamic>>;
    final untaken = next['untaken'] as List<Map<String, dynamic>>;
    
    final medNames = untaken.map((i) => (i['med'] as ScheduledMedicine).medicineName).join(', ');
    final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
    final tMins = _parseTime(time);
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    // Time window: only lock if it's not today or if it's too early (more than 30 mins before scheduled time)
    // Past doses should still be actionable so users can record late intakes
    final isLocked = !isToday || nowMins < tMins - 30;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLocked 
            ? [const Color(0xFFF1F6FF), const Color(0xFFF9FBFF)]
            : [const Color(0xFFEDFBF2), const Color(0xFFF7FFF9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isLocked ? Colors.blue.withOpacity(0.1) : _primary.withOpacity(0.1)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20, bottom: -10,
            child: Opacity(
              opacity: 0.9,
              child: kIsWeb 
                ? Container(
                    width: 160, height: 160,
                    decoration: BoxDecoration(color: (isLocked ? Colors.blue : _primary).withOpacity(0.05), shape: BoxShape.circle),
                    child: Icon(isLocked ? Icons.upcoming_rounded : Icons.medication_liquid_rounded, size: 80, color: (isLocked ? Colors.blue : _primary).withOpacity(0.2)),
                  )
                : Image.file(
                    File('C:\\Users\\Jose Lejaro\\.gemini\\antigravity\\brain\\8a5ad9a4-598c-4004-8718-6490394a1e44\\medicine_scheduler_header_illustration_1778691349074.png'),
                    width: 160, height: 160, fit: BoxFit.contain,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: isLocked ? Colors.blue : _primary, shape: BoxShape.circle),
                      child: Icon(isLocked ? Icons.calendar_today_rounded : Icons.access_time_filled_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(isLocked ? 'UPCOMING DOSE' : 'NEXT DOSE', style: TextStyle(color: isLocked ? Colors.blue : _primary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: Text(isLocked ? 'Upcoming: $medNames' : 'Time to take your $medNames',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textDark, height: 1.2)),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    // Pick time for the first item, others will follow if they share the time
                    final first = items.first;
                    _pickTime(context, first['med'] as ScheduledMedicine, first['doseIndex'] as int, time);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$time • Today', style: const TextStyle(color: _textMuted, fontSize: 15, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed)),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_calendar_rounded, size: 14, color: _textMuted),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: isLocked ? null : () {
                        for (var item in untaken) {
                          _markAsTaken(item['med'] as ScheduledMedicine, item['doseIndex'] as int, time);
                        }
                      },
                      icon: Icon(isLocked ? Icons.lock_clock_rounded : Icons.check_circle_rounded, size: 18),
                      label: Text(isLocked 
                        ? "Upcoming" 
                        : (untaken.length > 1 ? "Take all ${untaken.length} meds" : "I've taken it")),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isLocked ? _fieldBdr : _primary, 
                        foregroundColor: isLocked ? _textMuted : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleCardItem(String time, List<Map<String, dynamic>> items) {
    if (time == 'Setup Required') {
      return Column(
        children: items.map((item) {
          final med = item['med'] as ScheduledMedicine;
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle), child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18)),
                  const SizedBox(width: 12),
                  const Text('First-time Setup Required', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF856404))),
                ]),
                const SizedBox(height: 16),
                Text(
                  'Please enter the time when you first took ${med.medicineName} today. This will be used to automatically organize your next medication schedules and reminders.',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF856404), height: 1.5),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _setupAndMarkTaken(med, 0, TimeOfDay.now()),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('Current Time'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white, foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked != null) {
                            _setupAndMarkTaken(med, 0, picked);
                          }
                        },
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: const Text('Pick Time'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    // R2: PRN (as-needed) medicines
    if (time == 'As Needed') {
      final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.teal.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                child: const Icon(Icons.medication_liquid_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Text('Take as needed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal.shade800)),
            ]),
            const SizedBox(height: 12),
            ...items.map((item) {
              final med = item['med'] as ScheduledMedicine;
              final key = '${med.prescriptionItemId}_${item['doseIndex']}';
              final taken = _takenDoses.contains(key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.medication_rounded, color: taken ? _primary : Colors.teal.shade300, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(med.medicineName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: taken ? _primary.withOpacity(0.6) : _textDark)),
                          if (med.dosage.isNotEmpty) Text(med.dosage, style: const TextStyle(fontSize: 11, color: _textMuted)),
                          if (med.instructions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(med.instructions, style: TextStyle(fontSize: 10, color: _textMuted.withOpacity(0.8), fontStyle: FontStyle.italic)),
                            ),
                        ],
                      ),
                    ),
                    if (!taken && isToday) TextButton.icon(
                      onPressed: () => _markAsTaken(med, item['doseIndex'] as int, 'PRN'),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Take', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: Colors.teal.withOpacity(0.1),
                      ),
                    ) else if (taken) Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: _primary, size: 20),
                        if (_takenTimestamps.containsKey(key))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              DateFormat('h:mm a').format(_takenTimestamps[key]!),
                              style: const TextStyle(fontSize: 8, color: _primary, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    final allTaken = items.every((i) => _takenDoses.contains('${(i['med'] as ScheduledMedicine).prescriptionItemId}_${i['doseIndex']}'));
    final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
    final tMins = _parseTime(time);
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final isFuture = _selectedDate.isAfter(DateTime.now()) && !isToday;
    final isPast = _selectedDate.isBefore(DateTime.now()) && !isToday;
    
    bool isLocked = true;
    String status = 'PENDING';
    Color statusColor = _textMuted;

    if (allTaken) {
      status = 'TAKEN';
      statusColor = _primary;
    } else if (isFuture || (isToday && nowMins < tMins - 30)) {
      status = 'UPCOMING';
      statusColor = const Color(0xFF007BFF);
    } else if (isPast || (isToday && nowMins > tMins + 240)) {
      // Past the window — show as LATE but still allow user to mark as taken
      status = 'LATE';
      statusColor = Colors.orange;
      isLocked = false;
    } else {
      isLocked = false;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: (allTaken || isLocked) ? null : () {
                final first = items.first;
                _pickTime(context, first['med'] as ScheduledMedicine, first['doseIndex'] as int, time);
              },
              child: Container(
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: allTaken ? _primary.withOpacity(0.05) : (isLocked ? _bg : Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: allTaken ? _primary.withOpacity(0.1) : (isLocked ? _fieldBdr.withOpacity(0.3) : _fieldBdr.withOpacity(0.5))),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(time.split(' ')[0], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: allTaken ? _primary : (isLocked ? _textMuted : _textDark))),
                    Text(time.split(' ')[1], style: TextStyle(fontSize: 10, color: allTaken ? _primary : _textMuted)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: _textDark.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    ...items.map((item) {
                      final med = item['med'] as ScheduledMedicine;
                      final key = '${med.prescriptionItemId}_${item['doseIndex']}';
                      final taken = _takenDoses.contains(key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.medication_rounded, color: taken ? _primary : (isLocked ? _textMuted.withOpacity(0.2) : _textMuted.withOpacity(0.4)), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(med.medicineName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: taken ? _primary.withOpacity(0.6) : (isLocked ? _textMuted : _textDark))),
                                  if (med.dosage.isNotEmpty)
                                    Text(med.dosage, style: const TextStyle(fontSize: 11, color: _textMuted)),
                                  if (!taken && med.duration.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text('Duration: ${med.duration}', style: TextStyle(fontSize: 10, color: isLocked ? _textMuted.withOpacity(0.4) : _primary.withOpacity(0.7), fontWeight: FontWeight.w500)),
                                    ),
                                  if (!taken && med.instructions.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(med.instructions, style: TextStyle(fontSize: 10, color: _textMuted.withOpacity(0.8), fontStyle: FontStyle.italic)),
                                    ),
                                ],
                              ),
                            ),
                            if (!taken) IconButton(
                              onPressed: isLocked ? null : () => _markAsTaken(med, item['doseIndex'] as int, time),
                              icon: Icon(Icons.check_circle_outline_rounded, color: isLocked ? _textMuted.withOpacity(0.2) : _primary, size: 22),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ) else Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: _primary, size: 20),
                                if (_takenTimestamps.containsKey(key))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      DateFormat('h:mm a').format(_takenTimestamps[key]!),
                                      style: const TextStyle(fontSize: 8, color: _primary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    if (!allTaken && items.length > 1) ...[
                      const Divider(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: isLocked ? null : () async {
                            for (var item in items) {
                              await _markAsTaken(item['med'] as ScheduledMedicine, item['doseIndex'] as int, time);
                            }
                          },
                          child: Text('Mark all as taken', style: TextStyle(color: isLocked ? _textMuted.withOpacity(0.3) : _primary, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(double completion) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFF007BFF), shape: BoxShape.circle),
            child: const Icon(Icons.show_chart_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your progress', style: TextStyle(color: Color(0xFF0056B3), fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text(completion >= 1.0 ? "Fantastic! You've taken all your meds." : completion >= 0.5 ? "Great job! You're doing amazing." : "Keep it up! Let's hit 100%.",
                    style: const TextStyle(fontSize: 14, color: _textDark, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 60, height: 60,
                    child: CircularProgressIndicator(
                      value: completion,
                      strokeWidth: 8,
                      backgroundColor: Colors.white,
                      color: const Color(0xFF007BFF),
                    ),
                  ),
                  Text('${(completion * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _textDark)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('This day', style: TextStyle(fontSize: 10, color: _textMuted, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateStrip() {
    final now = DateTime.now();
    DateTime minDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 3)); // Show 3 days past by default
    DateTime maxDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));   // Show 14 days future by default

    // Smart adjustment based on actual prescriptions
    if (_medicines.isNotEmpty) {
      for (var m in _medicines) {
        final start = DateTime(m.startDate.year, m.startDate.month, m.startDate.day);
        final end   = DateTime(m.endDate.year, m.endDate.month, m.endDate.day);
        if (start.isBefore(minDate)) minDate = start;
        if (end.isAfter(maxDate)) maxDate = end;
      }
    }

    // Sanity check for range (max 60 days to prevent performance issues)
    if (maxDate.difference(minDate).inDays > 60) {
      maxDate = minDate.add(const Duration(days: 60));
    }

    final daysCount = maxDate.difference(minDate).inDays + 1;
    final List<DateTime> dates = List.generate(daysCount, (index) => minDate.add(Duration(days: index)));

    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = DateUtils.isSameDay(date, _selectedDate);
          final isToday = DateUtils.isSameDay(date, now);

          bool isStart = false;
          bool isFinal = false;
          bool isOngoing = false;
          for (var m in _medicines) {
            final start = DateTime(m.startDate.year, m.startDate.month, m.startDate.day);
            final end   = DateTime(m.endDate.year, m.endDate.month, m.endDate.day);
            if (DateUtils.isSameDay(date, start)) isStart = true;
            else if (DateUtils.isSameDay(date, end)) isFinal = true;
            else if (date.isAfter(start) && date.isBefore(end)) isOngoing = true;
          }

          bool hasFollowup = false;
          for (var c in _consultations) {
            if (c.followupDate != null && DateUtils.isSameDay(date, c.followupDate!)) {
              hasFollowup = true;
              break;
            }
          }

          return GestureDetector(
            onTap: () => _loadDateLogs(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? _primary : (isToday ? _primary.withOpacity(0.08) : Colors.white),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isSelected ? _primary : _fieldBdr.withOpacity(0.6)),
                boxShadow: isSelected ? [BoxShadow(color: _primary.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))] : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date).toUpperCase(), 
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, 
                    color: isSelected ? Colors.white.withOpacity(0.8) : _textMuted, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(date.day.toString(), 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, 
                    color: isSelected ? Colors.white : _textDark)),
                  if (isToday && !isSelected && !isStart && !isFinal && !isOngoing && !hasFollowup) 
                    Container(margin: const EdgeInsets.only(top: 4), width: 4, height: 4, 
                      decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle)),
                  if (hasFollowup)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white24 : Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FOLLOW UP',
                        style: TextStyle(
                          fontSize: 7, 
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.teal.shade800,
                          letterSpacing: 0.1,
                        ),
                      ),
                    )
                  else if (isStart || isFinal || isOngoing)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white24 : (isStart ? Colors.green.shade100 : (isFinal ? Colors.red.shade100 : Colors.blue.shade50)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isStart ? 'START' : (isFinal ? 'FINAL' : 'MEDS'),
                        style: TextStyle(
                          fontSize: 8, 
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : (isStart ? Colors.green.shade800 : (isFinal ? Colors.red.shade800 : Colors.blue.shade800)),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1FF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF7B3AF5), size: 20),
                    const SizedBox(width: 8),
                    const Text('Tip of the day', style: TextStyle(color: Color(0xFF5A16D1), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Try setting reminders a few minutes early to stay on track.',
                    style: TextStyle(fontSize: 14, color: _textDark, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF7B3AF5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tips_and_updates_rounded, color: Color(0xFF7B3AF5), size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowupCheckupCard(Consultation c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade50, Colors.teal.shade50.withOpacity(0.5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.teal.shade600,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'FOLLOW UP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.teal.shade900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      'All Day',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Follow-up Checkup',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF00302C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.doctorName != null ? 'With ${c.doctorName}' : 'With your consulting doctor',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (c.diagnosis.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: ${c.diagnosis}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade900.withOpacity(0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String sub) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _fieldBdr.withOpacity(0.5)),
    ),
    child: Column(children: [
      Icon(icon, size: 48, color: _primary.withOpacity(0.2)),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 15)),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(fontSize: 13, color: _textMuted), textAlign: TextAlign.center),
    ]),
  );

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 48),
      const SizedBox(height: 12),
      const Text('Failed to load schedule', style: TextStyle(fontWeight: FontWeight.w700, color: _textDark)),
      const SizedBox(height: 6),
      Text(_error!, style: const TextStyle(fontSize: 12, color: _textMuted), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
      ),
    ]),
  ));

  void _applyTimeChange(ScheduledMedicine med, int doseIndex, TimeOfDay picked) async {
    final timeStr = picked.format(context);
    
    // If it is the first dose, persist it as the global start time for this medication
    if (doseIndex == 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('med_start_${med.prescriptionItemId}', timeStr);
      
      setState(() {
        _persistedStartTimes[med.prescriptionItemId] = timeStr;
      });
    }
    final key = '${med.prescriptionItemId}_$doseIndex';
    setState(() {
      _customDoseTimes[key] = timeStr;

      final intervalMins = med.doseIntervalMinutes;
      if (intervalMins > 0) {
        int runningMins = picked.hour * 60 + picked.minute;
        for (int i = doseIndex + 1; i < med.doseTimes.length; i++) {
          final nextKey = '${med.prescriptionItemId}_$i';
          runningMins += intervalMins;

          final nextH = (runningMins ~/ 60) % 24;
          final nextM = runningMins % 60;
          _customDoseTimes[nextKey] = TimeOfDay(hour: nextH, minute: nextM).format(context);
        }
      }
      _scheduleNotifications();
    });
  }

  Future<void> _pickTime(BuildContext context, ScheduledMedicine med, int doseIndex, String currentTime) async {
    // Normalize non-ASCII spaces (\u202f narrow no-break space, \u00a0 no-break space) for locale compatibility
    final clean = currentTime.trim().replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
    final parts = clean.split(' ');
    final hm = parts[0].split(':');
    int h = int.parse(hm[0]);
    final m = int.parse(hm[1]);
    if (parts.length > 1) {
      final period = parts[1].toUpperCase().replaceAll('.', '');
      if ((period == 'PM' || period == 'P') && h != 12) h += 12;
      if ((period == 'AM' || period == 'A') && h == 12) h = 0;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
    );

    if (picked != null) {
      _applyTimeChange(med, doseIndex, picked);
    }
  }

  void _showRxModal(ScheduledMedicine med) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: _fieldBdr, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(children: [
                Container(width: 48, height: 48,
                  decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                  child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 26)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('UKonek Clinic', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _primaryMid)),
                  const Text('Digital Prescription', style: TextStyle(fontSize: 11, color: _textMuted)),
                ]),
              ]),
              const SizedBox(height: 16),
              const Divider(color: _fieldBdr),
              const SizedBox(height: 12),
              const Text('PATIENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _primary, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(widget.username, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark)),
              Text('ID: ${widget.citizenId}', style: const TextStyle(fontSize: 12, color: _textMuted)),
              const SizedBox(height: 4),
              Text('Prescribed by: ${med.displayDoctorName}',
                  style: const TextStyle(fontSize: 12, color: _textMuted)),
              Text('Issued: ${DateFormat('MMM d, yyyy').format(med.issuedAt)}',
                  style: const TextStyle(fontSize: 12, color: _textMuted)),
              const SizedBox(height: 20),
              const Text('℞', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _primaryMid, height: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: _fieldBdr)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(med.medicineName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _textDark)),
                  if (med.dosage.isNotEmpty)
                    Text(med.dosage, style: const TextStyle(fontSize: 13, color: _primary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  const Divider(color: _fieldBdr),
                  const SizedBox(height: 10),
                  if (med.duration.isNotEmpty) _rxRow('Duration', med.duration),
                  _rxRow('Status', med.isDispensed ? 'Given' : 'Pending'),
                  _rxRow('Quantity', '${med.quantity}${med.unit.isNotEmpty ? " ${med.unit}" : ""}'),
                  _rxRow('Prescription ID', med.prescriptionCode),
                  if (med.dispensedAt != null)
                    _rxRow('Dispensed', DateFormat('MMM d, yyyy').format(med.dispensedAt!)),
                  if (med.instructions.isNotEmpty) ...[const SizedBox(height: 10), const Divider(color: _fieldBdr), const SizedBox(height: 8),
                    const Text('DOCTOR\'S INSTRUCTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textMuted)),
                    const SizedBox(height: 6),
                    Text(med.instructions, style: const TextStyle(fontSize: 13, color: _textDark, height: 1.5)),
                  ],
                  if (med.additionalInfo.isNotEmpty) ...[const SizedBox(height: 8),
                    const Text('ADDITIONAL INFO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textMuted)),
                    const SizedBox(height: 4),
                    Text(med.additionalInfo, style: const TextStyle(fontSize: 12, color: _textMuted, height: 1.4)),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
              Center(child: QrImageView(
                data: med.prescriptionCode.isNotEmpty ? med.prescriptionCode : 'RX-${widget.citizenId}',
                version: QrVersions.auto, size: 140.0,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _primaryMid),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _primaryMid),
              )),
              const SizedBox(height: 8),
              Center(child: Text(med.prescriptionCode,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primaryMid, letterSpacing: 1, fontFamily: 'monospace'))),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: _primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rxRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
    ]),
  );

// ═══════════════════════════════════════════════════════════════
// 2. MEDICINE SCHEDULER PAGE — uKonekMedicineScheduler.dart
// ═══════════════════════════════════════════════════════════════

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded,                'label': 'Home'},
      {'icon': Icons.event_note_rounded,          'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded,      'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,                              // was _C.surface
        borderRadius: const BorderRadius.only(
          topLeft:  Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [BoxShadow(color: _textDark.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -4))],
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
                  setState(() => _selectedTab = i);
                  if (i == 0) {
                    Navigator.push(context, _pageRoute(
                      uKonekDashboardPage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    )).then((_) {
                      if (mounted) setState(() => _selectedTab = 1);
                    });
                  } else if (i == 1) {
                    _load(); // Already here — just refresh
                  } else if (i == 2) {
                    Navigator.push(context, _pageRoute(
                      uKonekJoinQueuePage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                      ),
                    )).then((_) {
                      _load();
                      if (mounted) setState(() => _selectedTab = 1);
                    });
                  } else if (i == 3) {
                    Navigator.push(context, _pageRoute(
                      uKonekProfilePage(
                        username:  widget.username,
                        citizenId: widget.citizenId,
                        fullName:  widget.username,
                      ),
                    )).then((_) {
                      if (mounted) setState(() => _selectedTab = 1);
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryMid.withOpacity(0.10) : Colors.transparent,  // was _C.primaryMid
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _primaryMid : Colors.grey.shade400,              // was _C.primaryMid
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(height: 4),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color:      _primaryMid,                                          // was _C.primaryMid
                            fontSize:   10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }  Route _pageRoute(Widget page) =>
  AppPageRoute.slideRight(page);


  Widget _sectionHeader(String title) => Text(title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark));

  Widget _prescriptionCard(ScheduledMedicine med) {
    return GestureDetector(
      onTap: () => _showRxModal(med),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _fieldBdr),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: _primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.medication_rounded, color: _primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(med.medicineName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _textDark)),
            Text(
              [if (med.dosage.isNotEmpty) med.dosage,
               if (med.frequency.isNotEmpty) med.frequency,
               if (med.duration.isNotEmpty) med.duration,
               if (med.quantity > 0) '×${med.quantity}${med.unit.isNotEmpty ? " ${med.unit}" : ""}']
                  .join(' • '),
              style: const TextStyle(fontSize: 12, color: _textMuted),
            ),
            Text(med.prescriptionCode,
                style: const TextStyle(fontSize: 11, color: _primaryMid,
                    fontWeight: FontWeight.w600, fontFamily: 'monospace')),
            if (med.isDispensed)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _primary.withOpacity(0.08), borderRadius: BorderRadius.circular(6), border: Border.all(color: _primary.withOpacity(0.2))),
                child: const Text('DISPENSED / GIVEN', style: TextStyle(color: _primary, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _fieldBdr),
        ]),
      ),
    );
  }
}