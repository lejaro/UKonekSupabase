import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekProfilePage.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/medicine_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/app_transitions.dart';

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

class _uKonekMedicineSchedulerPageState extends State<uKonekMedicineSchedulerPage> with WidgetsBindingObserver {
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
  final ScrollController _dateScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      // If date rolled over across midnight while backgrounded, auto-advance to Today
      final now = DateTime.now();
      if (!DateUtils.isSameDay(_selectedDate, now) && _selectedDate.isBefore(now)) {
        _selectedDate = now;
        _load();
      }
    }
  }

  Future<void> _checkPermissions() async {
    final enabled = await NotificationService.areNotificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  final Set<int> _startedPrescriptions = {};

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Instant local load if cache is available
    final cachedMeds = await MedicineCacheService.loadCachedSchedule(widget.citizenId);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final cachedLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, dateKey);

    if (cachedMeds != null && cachedMeds.isNotEmpty && mounted) {
      _persistedStartTimes.clear();
      _customDoseTimes.clear();
      _takenDoses.clear();
      _takenTimestamps.clear();

      for (var med in cachedMeds) {
        final start = prefs.getString('med_start_${med.prescriptionItemId}');
        if (start != null) {
          _persistedStartTimes[med.prescriptionItemId] = start;
        }
        for (int i = 0; i < med.doseTimes.length; i++) {
          final custom = prefs.getString('med_dose_${med.prescriptionItemId}_$i');
          if (custom != null) {
            _customDoseTimes['${med.prescriptionItemId}_$i'] = custom;
          }
        }
      }

      if (cachedLogs != null) {
        for (var log in cachedLogs) {
          final key = '${log['prescription_item_id']}_${log['dose_index']}';
          _takenDoses.add(key);
          final timeRaw = log['actual_time'] ?? log['created_at'];
          if (timeRaw != null) {
            final dt = DateTime.tryParse(timeRaw.toString())?.toLocal();
            if (dt != null) _takenTimestamps[key] = dt;
          }
        }
      }

      setState(() {
        _medicines = cachedMeds.where((m) => m.isDispensed).toList();
        _loading = false;
      });
      _scheduleNotifications();
    }

    // 2. If schedule cache is fresh, quietly load consultations and sync queue in background
    final isFresh = await MedicineCacheService.isScheduleCacheFresh(widget.citizenId);
    if (isFresh && cachedMeds != null && cachedMeds.isNotEmpty) {
      try {
        MedicineCacheService.syncPendingIntakeLogs();
        final consultations = await ApiService.fetchConsultations();
        if (mounted) {
          setState(() {
            _consultations = consultations;
          });
        }
      } catch (_) {}
      return;
    }

    // 3. Otherwise, fetch fresh schedule from remote Supabase
    try {
      MedicineCacheService.syncPendingIntakeLogs();

      final results = await Future.wait([
        ApiService.getMedicineSchedule(),
        ApiService.fetchConsultations(),
      ]);

      final meds = results[0] as List<ScheduledMedicine>;
      final cons = results[1] as List<Consultation>;

      // Cache schedule & logs locally
      await MedicineCacheService.saveSchedule(widget.citizenId, meds);

      if (mounted) {
        _persistedStartTimes.clear();
        _customDoseTimes.clear();
        for (var med in meds) {
          final start = prefs.getString('med_start_${med.prescriptionItemId}');
          if (start != null) {
            _persistedStartTimes[med.prescriptionItemId] = start;
          }
          for (int i = 0; i < med.doseTimes.length; i++) {
            final custom = prefs.getString('med_dose_${med.prescriptionItemId}_$i');
            if (custom != null) {
              _customDoseTimes['${med.prescriptionItemId}_$i'] = custom;
            }
          }
        }

        setState(() {
          _medicines = meds.where((m) => m.isDispensed).toList();
          _consultations = cons;
          _loading = false;
        });

        // Background load remote logs for today
        _loadDateLogs(_selectedDate, silent: true);
        _scheduleNotifications();
      }
    } catch (e) {
      if (mounted && _medicines.isEmpty) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadDateLogs(DateTime date, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _selectedDate = date;
      });
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    // 1. Instant local logs load
    final localLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, dateKey);
    if (mounted && localLogs != null) {
      setState(() {
        _takenDoses.clear();
        _takenTimestamps.clear();
        for (var log in localLogs) {
          final key = '${log['prescription_item_id']}_${log['dose_index']}';
          _takenDoses.add(key);
          final timeRaw = log['actual_time'] ?? log['created_at'];
          if (timeRaw != null) {
            final dt = DateTime.tryParse(timeRaw.toString())?.toLocal();
            if (dt != null) _takenTimestamps[key] = dt;
          }
        }
      });
    }

    // 2. Fetch fresh logs from Supabase
    try {
      final logs = await ApiService.getIntakeLogsForDate(date);
      await MedicineCacheService.saveIntakeLogs(widget.citizenId, dateKey, logs);

      if (mounted && DateUtils.isSameDay(_selectedDate, date)) {
        setState(() {
          _takenDoses.clear();
          _takenTimestamps.clear();
          for (var log in logs) {
            final pid = (log['prescription_item_id'] as num).toInt();
            final doseIdx = (log['dose_index'] as num?)?.toInt() ?? 0;
            final key = '${pid}_$doseIdx';
            _takenDoses.add(key);
            final timeRaw = log['actual_time'] ?? log['created_at'];
            if (timeRaw != null) {
              final dt = DateTime.tryParse(timeRaw.toString())?.toLocal();
              if (dt != null) _takenTimestamps[key] = dt;
            }
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
    });

    // 2. Persist locally and queue for background sync
    await MedicineCacheService.recordLocalIntake(
      widget.citizenId,
      prescriptionItemId: med.prescriptionItemId,
      scheduledTime: scheduledTime,
      doseIndex: doseIndex,
      dateKey: dateKey,
      actualTime: now,
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
            onPressed: () => _undoMarkAsTaken(key, med: med, doseIndex: doseIndex),
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
        intakeDate: dateKey,
      );
    } catch (e) {
      debugPrint('Intake stored locally, will sync when online: $e');
    }
  }

  Future<void> _markAllAsTaken(List<Map<String, dynamic>> items, String scheduledTime) async {
    final untaken = items.where((i) => 
      !_takenDoses.contains('${(i['med'] as ScheduledMedicine).prescriptionItemId}_${i['doseIndex']}')
    ).toList();
    if (untaken.isEmpty) return;

    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    HapticFeedback.mediumImpact();

    setState(() {
      for (var item in untaken) {
        final med = item['med'] as ScheduledMedicine;
        final doseIndex = item['doseIndex'] as int;
        final key = '${med.prescriptionItemId}_$doseIndex';
        _takenDoses.add(key);
        _takenTimestamps[key] = now;
        _startedPrescriptions.add(med.prescriptionItemId);
      }
    });

    for (var item in untaken) {
      final med = item['med'] as ScheduledMedicine;
      final doseIndex = item['doseIndex'] as int;
      await MedicineCacheService.recordLocalIntake(
        widget.citizenId,
        prescriptionItemId: med.prescriptionItemId,
        scheduledTime: scheduledTime,
        doseIndex: doseIndex,
        dateKey: dateKey,
        actualTime: now,
      );
    }

    _scheduleNotifications();

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final msg = untaken.length == 1
          ? '${(untaken.first['med'] as ScheduledMedicine).medicineName} marked as taken'
          : '${untaken.length} medicines marked as taken';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () => _undoMarkAllAsTaken(untaken),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: _primaryMid,
        ),
      );
    }

    for (var item in untaken) {
      final med = item['med'] as ScheduledMedicine;
      final doseIndex = item['doseIndex'] as int;
      try {
        await ApiService.logMedicineIntake(
          prescriptionItemId: med.prescriptionItemId,
          scheduledTime: scheduledTime,
          doseIndex: doseIndex,
          citizenId: int.tryParse(widget.citizenId),
          intakeDate: dateKey,
        );
      } catch (e) {
        debugPrint('Intake stored locally, will sync when online: $e');
      }
    }
  }

  void _undoMarkAllAsTaken(List<Map<String, dynamic>> items) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    setState(() {
      for (var item in items) {
        final med = item['med'] as ScheduledMedicine;
        final doseIndex = item['doseIndex'] as int;
        final key = '${med.prescriptionItemId}_$doseIndex';
        _takenDoses.remove(key);
        _takenTimestamps.remove(key);
      }
    });

    for (var item in items) {
      final med = item['med'] as ScheduledMedicine;
      final doseIndex = item['doseIndex'] as int;
      final key = '${med.prescriptionItemId}_$doseIndex';
      MedicineCacheService.removeLocalIntake(
        widget.citizenId,
        prescriptionItemKey: key,
        dateKey: dateKey,
      );
    }

    _scheduleNotifications();

    for (var item in items) {
      final med = item['med'] as ScheduledMedicine;
      final doseIndex = item['doseIndex'] as int;
      try {
        await ApiService.deleteMedicineIntakeLog(
          prescriptionItemId: med.prescriptionItemId,
          doseIndex: doseIndex,
          intakeDate: dateKey,
          citizenId: int.tryParse(widget.citizenId),
        );
      } catch (e) {
        debugPrint('Error deleting intake log on undo: $e');
      }
    }
  }

  void _undoMarkAsTaken(String key, {ScheduledMedicine? med, int? doseIndex}) async {
    setState(() {
      _takenDoses.remove(key);
      _takenTimestamps.remove(key);
    });
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    MedicineCacheService.removeLocalIntake(
      widget.citizenId,
      prescriptionItemKey: key,
      dateKey: dateKey,
    );
    _scheduleNotifications();

    if (med != null && doseIndex != null) {
      try {
        await ApiService.deleteMedicineIntakeLog(
          prescriptionItemId: med.prescriptionItemId,
          doseIndex: doseIndex,
          intakeDate: dateKey,
          citizenId: int.tryParse(widget.citizenId),
        );
      } catch (e) {
        debugPrint('Error deleting intake log on undo: $e');
      }
    }
  }

  Future<void> _setupAndMarkTaken(ScheduledMedicine med, int doseIndex, TimeOfDay picked) async {
    _applyTimeChange(med, doseIndex, picked);
    await _markAsTaken(med, doseIndex, picked.format(context));
  }

  Future<void> _scheduleNotifications() async {
    try {
      // Only cancel medicine reminders, not clinic alerts
      await NotificationService.cancelMedicineReminders();
      // Always schedule alarms for today's active schedule regardless of selected date
      final grouped = _getGroupedDosesForDate(DateTime.now());
      int id = NotificationService.medicineIdOffset;
      
      // Load today's actual intake keys so alarms are never desynced by viewing other dates
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final todayLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, todayKey);
      final todayTakenKeys = (todayLogs ?? []).map((l) => '${l['prescription_item_id']}_${l['dose_index']}').toSet();

      for (var entry in grouped.entries) {
        final timeStr = entry.key;
        final items = entry.value;
        if (timeStr == 'Setup Required' || timeStr == 'As Needed') continue;
        
        // ONLY schedule if there's at least one untaken med in this group today
        final untaken = items.where((i) => 
          !todayTakenKeys.contains('${(i['med'] as ScheduledMedicine).prescriptionItemId}_${i['doseIndex']}')
        ).toList();
        
        if (untaken.isEmpty) continue;
        
        // Combine names of untaken meds
        final medsStr = untaken.map((i) => (i['med'] as ScheduledMedicine).medicineName).join(', ');
        final bodyStr = untaken.map((i) => '${(i['med'] as ScheduledMedicine).medicineName}: ${(i['med'] as ScheduledMedicine).dosage}').join('\n');
        
        final t = _parseTime(timeStr);

        // 1. 30-Minute Heads-up Reminder (only if scheduled for at least 30 mins after midnight)
        if (t >= 30) {
          if (id >= NotificationService.medicineIdOffset + NotificationService.maxMedicineNotifications) break;
          final targetMins = t - 30;
          final h30 = (targetMins ~/ 60) % 24;
          final m30 = targetMins % 60;

          await NotificationService.scheduleMedicineReminder(
            id: id++,
            title: 'Upcoming Meds: $medsStr',
            body: 'Heads up! Your $timeStr intake is in 30 minutes:\n$bodyStr',
            hour: h30,
            minute: m30,
            payload: '{"action":"medicine","username":"${widget.username}","citizenId":"${widget.citizenId}"}',
          );
        }

        // 2. Exact Intake Time Reminder
        if (id >= NotificationService.medicineIdOffset + NotificationService.maxMedicineNotifications) break;
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

  Map<String, List<Map<String, dynamic>>> get _groupedTodayDoses => _getGroupedDosesForDate(_selectedDate);

  Map<String, List<Map<String, dynamic>>> _getGroupedDosesForDate(DateTime targetDate) {
    final groups = <String, List<Map<String, dynamic>>>{};
    
    // Filter to only active meds for this date
    final activeMeds = _medicines.where((m) => m.isActiveOn(targetDate)).toList();

    // Cluster doses that are within 10 minutes of each other
    final allDoses = <Map<String, dynamic>>[];
    for (final med in activeMeds) {
      if (med.dailyDoseCount == 0) {
        // PRN (as-needed) medicines go into a separate group
        allDoses.add({'med': med, 'time': 'As Needed', 'doseIndex': 0, 'mins': 9999});
      } else {
        for (int i = 0; i < med.doseTimes.length; i++) {
          final key = '${med.prescriptionItemId}_$i';
          String time;
          int mins;
          if (_customDoseTimes.containsKey(key)) {
            time = _customDoseTimes[key]!;
            mins = _parseTime(time);
          } else {
            time = med.doseTimes[i];
            mins = _parseTime(time);
          }
          allDoses.add({'med': med, 'time': time, 'doseIndex': i, 'mins': mins});
        }
      }
    }

    // Sort chronologically by minutes (00:00 to 23:59)
    allDoses.sort((a, b) {
      final aMin = a['mins'] as int;
      final bMin = b['mins'] as int;
      return aMin.compareTo(bMin);
    });

    // Grouping logic
    for (var dose in allDoses) {
      if (dose['time'] == 'Setup Required') {
        groups.putIfAbsent('Setup Required', () => []);
        groups['Setup Required']!.add(dose);
        continue;
      }
      if (dose['time'] == 'As Needed') {
        groups.putIfAbsent('As Needed', () => []);
        groups['As Needed']!.add(dose);
        continue;
      }

      final mins = dose['mins'] as int;
      String? targetGroup;
      
      // Look for an existing group within 10 minutes
      for (var existingTime in groups.keys) {
        if (existingTime == 'Setup Required' || existingTime == 'As Needed') continue;
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
    
    // Sort keys chronologically, keeping Setup Required at top and As Needed at bottom
    final sortedTimes = groups.keys.toList()..sort((a, b) {
      if (a == 'As Needed') return 1;
      if (b == 'As Needed') return -1;
      if (a == 'Setup Required') return -1;
      if (b == 'Setup Required') return 1;
      return _parseTime(a).compareTo(_parseTime(b));
    });

    final sortedGroups = <String, List<Map<String, dynamic>>>{};
    for (var t in sortedTimes) {
      sortedGroups[t] = groups[t]!;
    }
    return sortedGroups;
  }

  int _parseTime(String t) {
    try {
      final clean = t.trim().replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
      final match = RegExp(r'(\d{1,2}):(\d{2})(?:\s*([AP]M?|[ap]m?))?', caseSensitive: false).firstMatch(clean);
      if (match != null) {
        int h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final period = match.group(3)?.toUpperCase().replaceAll('.', '');
        if ((period == 'PM' || period == 'P') && h != 12) h += 12;
        if ((period == 'AM' || period == 'A') && h == 12) h = 0;
        return h * 60 + m;
      }
      final simpleMatch = RegExp(r'(\d{1,2})\s*([AP]M?|[ap]m?)', caseSensitive: false).firstMatch(clean);
      if (simpleMatch != null) {
        int h = int.parse(simpleMatch.group(1)!);
        final period = simpleMatch.group(2)!.toUpperCase().replaceAll('.', '');
        if ((period == 'PM' || period == 'P') && h != 12) h += 12;
        if ((period == 'AM' || period == 'A') && h == 12) h = 0;
        return h * 60;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dateScrollController.dispose();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    super.dispose();
  }

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
        final med = d['med'] as ScheduledMedicine;
        if (d['doseIndex'] != -1 && med.dailyDoseCount > 0) {
          totalDoses++;
        }
      }
    }
    final showProgress = totalDoses > 0 && (isToday || isPast);

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
                      isToday ? 'No medicines scheduled today' : 'No medicines scheduled for this date',
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
        final med = d['med'] as ScheduledMedicine;
        // Skip setup required and PRN (as-needed) medicines from daily scheduled adherence goal
        if (d['doseIndex'] == -1 || med.dailyDoseCount == 0) continue;
        total++;
        if (_takenDoses.contains('${med.prescriptionItemId}_${d['doseIndex']}')) {
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
                  : DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                  style: TextStyle(fontSize: isToday ? 24 : 20, fontWeight: FontWeight.w900, color: _textDark)),
              const SizedBox(height: 4),
              Text(isToday 
                  ? "Let's stay on track with your health."
                  : "Medication schedule for this date.",
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
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    // Only lock future dates. Today's doses are fully actionable even if taken early.
    final isLocked = !isToday;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDFBF2), Color(0xFFF7FFF9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primary.withOpacity(0.1)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15, bottom: -15,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.medication_liquid_rounded,
                  size: 72,
                  color: _primary.withOpacity(0.18),
                ),
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
                      decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                      child: const Icon(Icons.access_time_filled_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    const Text('NEXT DOSE', style: TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: Text('Time to take your $medNames',
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
                      onPressed: isLocked ? null : () => _markAllAsTaken(untaken, time),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(untaken.length > 1 ? "Take all ${untaken.length} meds" : "I've taken it"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary, 
                        foregroundColor: Colors.white,
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
    
    bool isLocked = isFuture; // Only lock future dates! Today and past dates can be marked.
    String status = 'PENDING';
    Color statusColor = _textMuted;

    if (allTaken) {
      status = 'TAKEN';
      statusColor = _primary;
    } else if (isFuture) {
      status = 'UPCOMING';
      statusColor = const Color(0xFF007BFF);
      isLocked = true;
    } else if (isPast || (isToday && nowMins > tMins + 240)) {
      status = 'LATE';
      statusColor = Colors.orange;
      isLocked = false;
    } else {
      status = 'DUE';
      statusColor = _primary;
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
                child: Builder(
                  builder: (_) {
                    final timeParts = time.trim().split(' ');
                    final timeMain = timeParts.isNotEmpty ? timeParts[0] : time;
                    final timePeriod = timeParts.length > 1 ? timeParts[1] : '';
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(timeMain, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: allTaken ? _primary : (isLocked ? _textMuted : _textDark))),
                        if (timePeriod.isNotEmpty)
                          Text(timePeriod, style: TextStyle(fontSize: 10, color: allTaken ? _primary : _textMuted)),
                      ],
                    );
                  },
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                                      child: Text('Duration: ${_formatDuration(med.duration)}', style: TextStyle(fontSize: 10, color: isLocked ? _textMuted.withOpacity(0.4) : _primary.withOpacity(0.7), fontWeight: FontWeight.w500)),
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
                          onPressed: isLocked ? null : () => _markAllAsTaken(items, time),
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

    _scrollToSelectedDate(dates);

    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        controller: _dateScrollController,
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

  void _scrollToSelectedDate(List<DateTime> dates) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_dateScrollController.hasClients) return;
      final index = dates.indexWhere((d) => DateUtils.isSameDay(d, _selectedDate));
      if (index != -1) {
        // item width = 60 + 12 margin = 72
        final targetOffset = (index * 72.0) - 100.0;
        final clampedOffset = targetOffset.clamp(
          0.0,
          _dateScrollController.position.maxScrollExtent,
        );
        _dateScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
    final updatedCustomTimes = <String, String>{};
    final key = '${med.prescriptionItemId}_$doseIndex';
    updatedCustomTimes[key] = timeStr;

    final intervalMins = med.doseIntervalMinutes;
    if (intervalMins > 0 && doseIndex == 0) {
      int runningMins = picked.hour * 60 + picked.minute;
      for (int i = 1; i < med.doseTimes.length; i++) {
        final nextKey = '${med.prescriptionItemId}_$i';
        runningMins += intervalMins;

        // Only cascade to subsequent doses if the user hasn't explicitly set a custom time for them
        if (!_customDoseTimes.containsKey(nextKey)) {
          final nextH = (runningMins ~/ 60) % 24;
          final nextM = runningMins % 60;
          final nextTimeStr = TimeOfDay(hour: nextH, minute: nextM).format(context);
          updatedCustomTimes[nextKey] = nextTimeStr;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('med_dose_${med.prescriptionItemId}_$doseIndex', timeStr);
    
    // If it is the first dose, persist it as the global start time for this medication
    if (doseIndex == 0) {
      await prefs.setString('med_start_${med.prescriptionItemId}', timeStr);
      if (mounted) {
        setState(() {
          _persistedStartTimes[med.prescriptionItemId] = timeStr;
        });
      }
    }
    
    for (final entry in updatedCustomTimes.entries) {
      final idx = entry.key.split('_')[1];
      await prefs.setString('med_dose_${med.prescriptionItemId}_$idx', entry.value);
    }

    if (mounted) {
      setState(() {
        _customDoseTimes.addAll(updatedCustomTimes);
      });
      _scheduleNotifications();
    }
  }

  Future<void> _pickTime(BuildContext context, ScheduledMedicine med, int doseIndex, String currentTime) async {
    final totalMins = _parseTime(currentTime);
    final initialH = (totalMins ~/ 60) % 24;
    final initialM = totalMins % 60;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialH, minute: initialM),
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
                  if (med.duration.isNotEmpty) _rxRow('Duration', _formatDuration(med.duration)),
                  _rxRow('Status', med.dispensingStatus == 'partial' ? 'Partially Dispensed' : (med.isDispensed ? 'Dispensed' : 'Pending')),
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

  String _formatDuration(String duration) {
    final d = duration.trim();
    if (d.isEmpty) return '';
    if (RegExp(r'^\d+$').hasMatch(d)) {
      return '$d ${int.tryParse(d) == 1 ? "day" : "days"}';
    }
    return d;
  }

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
               if (med.duration.isNotEmpty) _formatDuration(med.duration),
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
                decoration: BoxDecoration(
                  color: med.dispensingStatus == 'partial' ? Colors.orange.withOpacity(0.08) : _primary.withOpacity(0.08), 
                  borderRadius: BorderRadius.circular(6), 
                  border: Border.all(color: med.dispensingStatus == 'partial' ? Colors.orange.withOpacity(0.3) : _primary.withOpacity(0.2)),
                ),
                child: Text(
                  med.dispensingStatus == 'partial' ? 'PARTIALLY DISPENSED' : 'DISPENSED / GIVEN', 
                  style: TextStyle(
                    color: med.dispensingStatus == 'partial' ? Colors.orange.shade800 : _primary, 
                    fontSize: 9, 
                    fontWeight: FontWeight.w800, 
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _fieldBdr),
        ]),
      ),
    );
  }
}