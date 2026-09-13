import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dashboard_page.dart';
import 'join_queue_page.dart';
import 'profile_page.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/medicine_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/app_transitions.dart';

import 'core/theme/app_colors.dart';
import 'widgets/scheduler/scheduler_date_strip.dart';
import 'widgets/scheduler/late_intake_sheet.dart';
import 'widgets/scheduler/adherence_progress_card.dart';
import 'widgets/scheduler/consultation_history_tab.dart';
import 'widgets/scheduler/medicine_dose_card.dart';

typedef uKonekMedicineSchedulerPage = MedicineSchedulerPage;

class MedicineSchedulerPage extends StatefulWidget {
  final String username;
  final String citizenId;

  final bool isEmbeddedInShell;

  const MedicineSchedulerPage({
    super.key,
    required this.username,
    required this.citizenId,
    this.isEmbeddedInShell = false,
  });

  @override
  State<MedicineSchedulerPage> createState() => _MedicineSchedulerPageState();
}

class _MedicineSchedulerPageState extends State<MedicineSchedulerPage> with WidgetsBindingObserver {
  static const Color _primary    = AppColors.primary;
  static const Color _primaryMid = AppColors.primaryMid;
  static const Color _bg         = AppColors.bg;
  static const Color _textDark   = AppColors.textDark;
  static const Color _textMuted  = AppColors.textMuted;
  static const Color _fieldBdr   = AppColors.fieldBdr;

  int _selectedTab = 1;

  bool _loading = true;
  String? _error;
  List<ScheduledMedicine> _medicines = [];
  List<Consultation> _consultations = [];
  final Set<String> _takenDoses = {};
  final Map<String, String> _customDoseTimes = {};
  final Set<String> _manuallySetDoseTimes = {};
  final Map<String, DateTime> _takenTimestamps = {};
  final Map<String, String> _dateShiftedDoseTimes = {};
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

  Future<void> _load({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (forceRefresh) {
      await MedicineCacheService.invalidateScheduleCache(widget.citizenId);
    }

    // 1. Instant local load if cache is available
    final cachedMeds = await MedicineCacheService.loadCachedSchedule(widget.citizenId);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final cachedLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, dateKey);

    if (cachedMeds != null && cachedMeds.isNotEmpty && mounted) {
      // Clean any historical duplicate entries stored in local cache
      final cleanedCached = ApiService.deduplicateMedicines(cachedMeds);

      _persistedStartTimes.clear();
      _customDoseTimes.clear();
      _manuallySetDoseTimes.clear();
      _takenDoses.clear();
      _takenTimestamps.clear();
      _dateShiftedDoseTimes.clear();

      for (var med in cleanedCached) {
        String? start = prefs.getString('med_start_${med.prescriptionItemId}');
        if (start == null) {
          for (int i = 0; i < 4; i++) {
            final oldCustom = prefs.getString('med_dose_${med.prescriptionItemId}_$i');
            if (oldCustom != null) {
              start = oldCustom;
              prefs.setString('med_start_${med.prescriptionItemId}', start);
              break;
            }
          }
        }
        if (start != null) {
          _persistedStartTimes[med.prescriptionItemId] = start;
        }
        for (int i = 0; i < 12; i++) {
          final shiftKey = '${med.prescriptionItemId}_${i}_$dateKey';
          final shifted = prefs.getString('med_dose_shift_$shiftKey');
          if (shifted != null) {
            _dateShiftedDoseTimes[shiftKey] = shifted;
          }
        }
      }

      if (cachedLogs != null) {
        for (var log in cachedLogs) {
          final pid = log['prescription_item_id'];
          final doseIdx = log['dose_index'];
          final key = '${pid}_$doseIdx';
          _takenDoses.add(key);
          if (log['scheduled_time'] != null) {
            _takenDoses.add('${pid}_${log['scheduled_time']}');
          }
          final timeRaw = log['actual_time'] ?? log['created_at'];
          if (timeRaw != null) {
            final dt = DateTime.tryParse(timeRaw.toString())?.toLocal();
            if (dt != null) {
              _takenTimestamps[key] = dt;
              if (log['scheduled_time'] != null) {
                _takenTimestamps['${pid}_${log['scheduled_time']}'] = dt;
              }
            }
          }
        }
      }

      setState(() {
        _medicines = cleanedCached.where((m) => m.isDispensed).toList();
        _loading = false;
      });
      _scheduleNotifications();
    }

    // 2. Fetch fresh schedule from remote Supabase (stale-while-revalidate)
    try {
      MedicineCacheService.syncPendingIntakeLogs();
      final citizenIntId = int.tryParse(widget.citizenId);

      // Resilient isolated fetches: a failure in one call does NOT break the schedule
      final remoteMeds = await ApiService.getMedicineSchedule(citizenId: citizenIntId).catchError((e) {
        debugPrint('Error fetching remote medicine schedule: $e');
        return <ScheduledMedicine>[];
      });

      final cons = await ApiService.fetchConsultations().catchError((e) {
        debugPrint('Error fetching consultations: $e');
        return <Consultation>[];
      });

      final prescriptions = await ApiService.fetchPrescriptions(citizenId: citizenIntId).catchError((e) {
        debugPrint('Error fetching prescriptions: $e');
        return <PrescriptionRecord>[];
      });

      // Synthesize fallback items from prescriptions
      final synthesized = ApiService.synthesizeScheduledMedicinesFromPrescriptions(prescriptions);

      // Deduplicate: remoteMeds takes priority with real DB item IDs;
      // synthesized fills in any newly dispensed Rx missing from remoteMeds WITHOUT doubling.
      final meds = ApiService.deduplicateMedicines(remoteMeds, synthesized);

      // Cache cleaned schedule locally
      await MedicineCacheService.saveSchedule(widget.citizenId, meds);

      if (mounted) {
        _persistedStartTimes.clear();
        _customDoseTimes.clear();
        _manuallySetDoseTimes.clear();
        _dateShiftedDoseTimes.clear();
        final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
        for (var med in meds) {
          String? start = prefs.getString('med_start_${med.prescriptionItemId}');
          if (start == null) {
            for (int i = 0; i < 4; i++) {
              final oldCustom = prefs.getString('med_dose_${med.prescriptionItemId}_$i');
              if (oldCustom != null) {
                start = oldCustom;
                prefs.setString('med_start_${med.prescriptionItemId}', start);
                break;
              }
            }
          }
          if (start != null) {
            _persistedStartTimes[med.prescriptionItemId] = start;
          }
          for (int i = 0; i < 12; i++) {
            final shiftKey = '${med.prescriptionItemId}_${i}_$dateKey';
            final shifted = prefs.getString('med_dose_shift_$shiftKey');
            if (shifted != null) {
              _dateShiftedDoseTimes[shiftKey] = shifted;
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

    // 0. Load date-specific shifted dose times
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dateShiftedDoseTimes.clear();
        for (var med in _medicines) {
          for (int i = 0; i < 12; i++) {
            final shiftKey = '${med.prescriptionItemId}_${i}_$dateKey';
            final shifted = prefs.getString('med_dose_shift_$shiftKey');
            if (shifted != null) {
              _dateShiftedDoseTimes[shiftKey] = shifted;
            }
          }
        }
      });
    }

    // 1. Instant local logs load
    final localLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, dateKey);
    if (mounted && localLogs != null) {
      setState(() {
        _takenDoses.clear();
        _takenTimestamps.clear();
        for (var log in localLogs) {
          final pid = log['prescription_item_id'];
          final doseIdx = log['dose_index'];
          final key = '${pid}_$doseIdx';
          _takenDoses.add(key);
          if (log['scheduled_time'] != null) {
            _takenDoses.add('${pid}_${log['scheduled_time']}');
          }
          final timeRaw = log['actual_time'] ?? log['created_at'];
          if (timeRaw != null) {
            final dt = DateTime.tryParse(timeRaw.toString())?.toLocal();
            if (dt != null) {
              _takenTimestamps[key] = dt;
              if (log['scheduled_time'] != null) {
                _takenTimestamps['${pid}_${log['scheduled_time']}'] = dt;
              }
            }
          }
        }
      });
    }

    // 2. Fetch fresh logs from Supabase
    try {
      final logs = await ApiService.getIntakeLogsForDate(date, citizenId: int.tryParse(widget.citizenId));
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
            if (log['scheduled_time'] != null) {
              _takenDoses.add('${pid}_${log['scheduled_time']}');
            }
            final timeRaw = log['actual_time'] ?? log['created_at'];
            if (timeRaw != null) {
              final dt = DateTime.tryParse(timeRaw.toString())?.toLocal();
              if (dt != null) {
                _takenTimestamps[key] = dt;
                if (log['scheduled_time'] != null) {
                  _takenTimestamps['${pid}_${log['scheduled_time']}'] = dt;
                }
              }
            }
          }
        });
      }
    } catch (_) {}
  }

  bool _isItemTaken(ScheduledMedicine med, int doseIndex, [String? timeStr]) {
    final key = '${med.prescriptionItemId}_$doseIndex';
    if (_takenDoses.contains(key)) return true;
    if (timeStr != null && _takenDoses.contains('${med.prescriptionItemId}_$timeStr')) return true;
    return false;
  }

  Future<void> _markAsTaken(ScheduledMedicine med, int doseIndex, String scheduledTime) async {
    final key = '${med.prescriptionItemId}_$doseIndex';
    final timeKey = '${med.prescriptionItemId}_$scheduledTime';
    if (_isItemTaken(med, doseIndex, scheduledTime)) return;

    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Haptic feedback for satisfying confirmation
    HapticFeedback.mediumImpact();

    // 1. Optimistic immediate local UI update
    setState(() {
      _takenDoses.add(key);
      _takenDoses.add(timeKey);
      _takenTimestamps[key] = now;
      _takenTimestamps[timeKey] = now;
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
            onPressed: () => _undoMarkAsTaken(key, med: med, doseIndex: doseIndex, scheduledTime: scheduledTime),
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

    // Check for late intake safe-spacing adjustment on today's schedule
    if (DateUtils.isSameDay(_selectedDate, DateTime.now()) && med.dailyDoseCount > 1) {
      final rawTodayDoses = med.getDosesForDate(_selectedDate, customStartTime: _persistedStartTimes[med.prescriptionItemId]);
      if (doseIndex < rawTodayDoses.length - 1) {
        final scheduledMinutesList = <int>[];
        for (final d in rawTodayDoses) {
          final idx = d['doseIndex'] as int;
          final shiftKey = '${med.prescriptionItemId}_${idx}_$dateKey';
          if (_dateShiftedDoseTimes.containsKey(shiftKey)) {
            scheduledMinutesList.add(_parseTime(_dateShiftedDoseTimes[shiftKey]!));
          } else {
            scheduledMinutesList.add(d['mins'] as int);
          }
        }

        final nowMinutes = now.hour * 60 + now.minute;
        final shifts = med.computeLateIntakeShifts(
          takenDoseIndex: doseIndex,
          actualTakenMinutes: nowMinutes,
          currentScheduledMinutes: scheduledMinutesList,
        );

        if (shifts.isNotEmpty && mounted) {
          _showLateIntakeAdjustmentDialog(
            med: med,
            takenDoseIndex: doseIndex,
            actualTakenMinutes: nowMinutes,
            scheduledMinutesList: scheduledMinutesList,
            shifts: shifts,
            dateKey: dateKey,
          );
        }
      }
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

    if (DateUtils.isSameDay(_selectedDate, DateTime.now())) {
      for (var item in untaken) {
        final med = item['med'] as ScheduledMedicine;
        final doseIndex = item['doseIndex'] as int;
        final rawTodayDoses = med.getDosesForDate(_selectedDate, customStartTime: _persistedStartTimes[med.prescriptionItemId]);
        if (med.dailyDoseCount > 1 && doseIndex < rawTodayDoses.length - 1) {
          final scheduledMinutesList = <int>[];
          for (final d in rawTodayDoses) {
            final idx = d['doseIndex'] as int;
            final shiftKey = '${med.prescriptionItemId}_${idx}_$dateKey';
            if (_dateShiftedDoseTimes.containsKey(shiftKey)) {
              scheduledMinutesList.add(_parseTime(_dateShiftedDoseTimes[shiftKey]!));
            } else {
              scheduledMinutesList.add(d['mins'] as int);
            }
          }

          final nowMinutes = now.hour * 60 + now.minute;
          final shifts = med.computeLateIntakeShifts(
            takenDoseIndex: doseIndex,
            actualTakenMinutes: nowMinutes,
            currentScheduledMinutes: scheduledMinutesList,
          );

          if (shifts.isNotEmpty && mounted) {
            _showLateIntakeAdjustmentDialog(
              med: med,
              takenDoseIndex: doseIndex,
              actualTakenMinutes: nowMinutes,
              scheduledMinutesList: scheduledMinutesList,
              shifts: shifts,
              dateKey: dateKey,
            );
            break;
          }
        }
      }
    }
  }

  void _undoMarkAllAsTaken(List<Map<String, dynamic>> items) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var item in items) {
        final med = item['med'] as ScheduledMedicine;
        final doseIndex = item['doseIndex'] as int;
        final key = '${med.prescriptionItemId}_$doseIndex';
        _takenDoses.remove(key);
        _takenTimestamps.remove(key);
        for (int i = 0; i < med.doseTimes.length; i++) {
          final shiftKey = '${med.prescriptionItemId}_${i}_$dateKey';
          if (_dateShiftedDoseTimes.containsKey(shiftKey)) {
            _dateShiftedDoseTimes.remove(shiftKey);
            prefs.remove('med_dose_shift_$shiftKey');
          }
        }
      }
    });

    for (var item in items) {
      final med = item['med'] as ScheduledMedicine;
      final doseIndex = item['doseIndex'] as int;
      final key = '${med.prescriptionItemId}_$doseIndex';
      await MedicineCacheService.removeLocalIntake(
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

  void _undoMarkAsTaken(String key, {ScheduledMedicine? med, int? doseIndex, String? scheduledTime}) async {
    setState(() {
      _takenDoses.remove(key);
      _takenTimestamps.remove(key);
      if (med != null && scheduledTime != null) {
        final timeKey = '${med.prescriptionItemId}_$scheduledTime';
        _takenDoses.remove(timeKey);
        _takenTimestamps.remove(timeKey);
      }
    });
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    await MedicineCacheService.removeLocalIntake(
      widget.citizenId,
      prescriptionItemKey: key,
      dateKey: dateKey,
    );

    if (med != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        for (int i = 0; i < 12; i++) {
          final shiftKey = '${med.prescriptionItemId}_${i}_$dateKey';
          if (_dateShiftedDoseTimes.containsKey(shiftKey)) {
            _dateShiftedDoseTimes.remove(shiftKey);
            prefs.remove('med_dose_shift_$shiftKey');
          }
        }
      });
    }

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
    await _markAsTaken(med, doseIndex, _formatTimeOfDay(picked.hour, picked.minute));
  }

  Future<void> _scheduleNotifications() async {
    try {
      // Only cancel medicine reminders, not clinic alerts
      await NotificationService.cancelMedicineReminders();
      // Always schedule alarms for today's active schedule regardless of selected date
      final now = DateTime.now();
      final grouped = _getGroupedDosesForDate(now);
      int id = NotificationService.medicineIdOffset;
      
      // Load today's actual intake keys so alarms are never desynced by viewing other dates
      final todayKey = DateFormat('yyyy-MM-dd').format(now);
      final todayLogs = await MedicineCacheService.loadCachedIntakeLogs(widget.citizenId, todayKey);
      final todayTakenKeys = (todayLogs ?? []).map((l) => '${l['prescription_item_id']}_${l['dose_index']}').toSet();

      final nowMins = now.hour * 60 + now.minute;

      for (var entry in grouped.entries) {
        final timeStr = entry.key;
        final items = entry.value;
        if (timeStr == 'Setup Required' || timeStr == 'As Needed') continue;
        
        // Doses that are untaken today
        final untakenToday = items.where((i) => 
          !todayTakenKeys.contains('${(i['med'] as ScheduledMedicine).prescriptionItemId}_${i['doseIndex']}')
        ).toList();
        
        final t = _parseTime(timeStr);
        final bool allTakenToday = untakenToday.isEmpty;
        
        // For late night/midnight bedtime doses (12:00 AM), effective timeline minute is 1440
        final effectiveT = (t == 0 && (timeStr.startsWith('12') || timeStr.contains('12:00'))) ? 1440 : t;

        // If all taken today, or the intake time + grace period (120 mins) has already passed today,
        // we schedule daily recurring notifications starting tomorrow so taking today's dose never cancels tomorrow's alarms!
        final DateTime? reminderStartDate = (allTakenToday || nowMins > effectiveT + 120)
            ? DateTime(now.year, now.month, now.day).add(const Duration(days: 1))
            : null;

        final displayItems = (allTakenToday || reminderStartDate != null) ? items : untakenToday;
        final medsStr = displayItems.map((i) => (i['med'] as ScheduledMedicine).medicineName).toSet().join(', ');
        final bodyStr = displayItems.map((i) => '${(i['med'] as ScheduledMedicine).medicineName}: ${(i['med'] as ScheduledMedicine).dosage}').toSet().join('\n');

        // 1. 30-Minute Heads-up Reminder (with midnight rollover support)
        if (id < NotificationService.medicineIdOffset + NotificationService.maxMedicineNotifications) {
          final targetMins = (effectiveT - 30 + 1440) % 1440;
          final h30 = (targetMins ~/ 60) % 24;
          final m30 = targetMins % 60;
          
          DateTime? headsUpStartDate = reminderStartDate;
          if (reminderStartDate == null && nowMins > targetMins) {
            // Heads-up time has already passed for today, begin recurring reminder starting tomorrow
            headsUpStartDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
          }

          await NotificationService.scheduleMedicineReminder(
            id: id++,
            title: 'Upcoming Meds: $medsStr',
            body: 'Heads up! Your $timeStr intake is in 30 minutes:\n$bodyStr',
            hour: h30,
            minute: m30,
            startDate: headsUpStartDate,
            payload: '{"action":"medicine","username":"${widget.username}","citizenId":"${widget.citizenId}"}',
          );
        }

        // 2. Exact Intake Time Reminder
        if (id < NotificationService.medicineIdOffset + NotificationService.maxMedicineNotifications) {
          final hExact = (t ~/ 60) % 24;
          final mExact = t % 60;
          
          DateTime? exactStartDate = reminderStartDate;
          if (exactStartDate == null && effectiveT != 1440 && nowMins > t + 120) {
            exactStartDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
          }

          await NotificationService.scheduleMedicineReminder(
            id: id++,
            title: 'Medication Time: $medsStr',
            body: 'It is time for your $timeStr intake right now:\n$bodyStr',
            hour: hExact,
            minute: mExact,
            startDate: exactStartDate,
            payload: '{"action":"medicine","username":"${widget.username}","citizenId":"${widget.citizenId}"}',
          );
        }
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
        allDoses.add({'med': med, 'time': 'As Needed', 'doseIndex': 0, 'mins': 99999});
      } else {
        final startSaved = _persistedStartTimes[med.prescriptionItemId];
        final targetDateKey = DateFormat('yyyy-MM-dd').format(targetDate);
        final rawDoses = med.getDosesForDate(targetDate, customStartTime: startSaved);

        for (final d in rawDoses) {
          final doseIndex = d['doseIndex'] as int;
          final shiftKey = '${med.prescriptionItemId}_${doseIndex}_$targetDateKey';
          String time = d['time'] as String;
          int mins = d['mins'] as int;
          bool isShifted = false;

          if (_dateShiftedDoseTimes.containsKey(shiftKey)) {
            time = _dateShiftedDoseTimes[shiftKey]!;
            mins = _parseTime(time);
            isShifted = true;
          }

          allDoses.add({
            'med': med,
            'time': time,
            'doseIndex': doseIndex,
            'globalDoseIndex': d['globalDoseIndex'],
            'mins': mins,
            'isShifted': isShifted,
          });
        }
      }
    }

    int getSortMins(Map<String, dynamic> d) {
      final mins = d['mins'] as int;
      final timeStr = d['time'] as String;
      final doseIndex = (d['doseIndex'] as int?) ?? 0;
      if (mins == 0 && (timeStr.startsWith('12') || timeStr.contains('12:00')) && doseIndex > 0) {
        return 1440;
      }
      return mins;
    }

    // Final deduplication safeguard: ensure no two items have identical (med.prescriptionItemId, doseIndex)
    final Set<String> seenDoseKeys = {};
    final uniqueDoses = <Map<String, dynamic>>[];
    for (final d in allDoses) {
      final med = d['med'] as ScheduledMedicine;
      final doseIdx = d['doseIndex'];
      final doseKey = '${med.prescriptionItemId}_$doseIdx';
      if (!seenDoseKeys.contains(doseKey)) {
        seenDoseKeys.add(doseKey);
        uniqueDoses.add(d);
      }
    }

    // Sort chronologically (00:00 to 24:00)
    uniqueDoses.sort((a, b) => getSortMins(a).compareTo(getSortMins(b)));

    // Grouping logic
    for (var dose in uniqueDoses) {
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

      final mins = getSortMins(dose);
      String? targetGroup;
      
      // Look for an existing group within 10 minutes
      for (var existingTime in groups.keys) {
        if (existingTime == 'Setup Required' || existingTime == 'As Needed') continue;
        int groupMins = _parseTime(existingTime);
        if (groupMins == 0 && (existingTime.startsWith('12') || existingTime.contains('12:00'))) {
          groupMins = 1440;
        }
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
      int aM = _parseTime(a);
      int bM = _parseTime(b);
      if (aM == 0 && (a.startsWith('12') || a.contains('12:00'))) aM = 1440;
      if (bM == 0 && (b.startsWith('12') || b.contains('12:00'))) bM = 1440;
      return aM.compareTo(bM);
    });

    final sortedGroups = <String, List<Map<String, dynamic>>>{};
    for (var t in sortedTimes) {
      sortedGroups[t] = groups[t]!;
    }
    return sortedGroups;
  }

  String _formatTimeOfDay(int hour, int minute) {
    final h = (hour % 24 + 24) % 24;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = (h % 12 == 0) ? 12 : (h % 12);
    final minuteStr = minute.toString().padLeft(2, '0');
    return '${displayHour.toString().padLeft(2, '0')}:$minuteStr $period';
  }

  String _formatMinutes(int minutes) {
    final norm = (minutes % 1440 + 1440) % 1440;
    return _formatTimeOfDay(norm ~/ 60, norm % 60);
  }

  int _parseTime(String t) {
    try {
      final clean = t.trim().replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
      final match = RegExp(r'(\d{1,2}):(\d{2})(?:\s*([AP]M?|[ap]m?))?', caseSensitive: false).firstMatch(clean);
      if (match != null) {
        int h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final period = match.group(3)?.toUpperCase().replaceAll('.', '');
        if (period == 'PM' || period == 'P') {
          if (h != 12) h += 12;
        } else if (period == 'AM' || period == 'A') {
          if (h == 12) h = 0;
        }
        return (h % 24) * 60 + m;
      }
      final simpleMatch = RegExp(r'(\d{1,2})\s*([AP]M?|[ap]m?)', caseSensitive: false).firstMatch(clean);
      if (simpleMatch != null) {
        int h = int.parse(simpleMatch.group(1)!);
        final period = simpleMatch.group(2)!.toUpperCase().replaceAll('.', '');
        if ((period == 'PM' || period == 'P') && h != 12) h += 12;
        if ((period == 'AM' || period == 'A') && h == 12) h = 0;
        return (h % 24) * 60;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Computes status for a scheduled dose time string on the selected date.
  /// Returns one of: 'TAKEN', 'UPCOMING', 'DUE', 'LATE'.
  /// Correctly handles circular midnight comparisons so late-night doses are never falsely overdue in the daytime.
  String _getIntakeStatus({
    required String timeStr,
    required bool allTaken,
    required bool isToday,
    required bool isFuture,
    required bool isPast,
    required int nowMins,
  }) {
    if (allTaken) return 'TAKEN';
    if (isFuture) return 'UPCOMING';
    if (isPast) return 'LATE';

    int tMins = _parseTime(timeStr);
    if (tMins == 0 && (timeStr.startsWith('12') || timeStr.contains('12:00'))) {
      tMins = 1440;
    }

    int diff;
    if (tMins == 1440 && nowMins < 240) {
      diff = 1440 - (1440 + nowMins);
    } else {
      diff = tMins - nowMins;
    }

    if (diff <= 30 && diff >= -120) {
      return 'DUE';
    } else if (diff > 30) {
      return 'UPCOMING';
    } else {
      return 'LATE';
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
                onRefresh: () => _load(forceRefresh: true),
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
                              _load(forceRefresh: true);
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
    if (!DateUtils.isSameDay(_selectedDate, DateTime.now())) return null;

    final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
    Map<String, dynamic>? dueNowCandidate;
    Map<String, dynamic>? overdueCandidate;
    Map<String, dynamic>? upcomingCandidate;

    for (var entry in grouped.entries) {
      if (entry.key == 'Setup Required' || entry.key == 'As Needed') continue;
      final untaken = entry.value.where((d) => 
        !_isItemTaken(d['med'] as ScheduledMedicine, d['doseIndex'] as int, entry.key)
      ).toList();
      
      if (untaken.isEmpty) continue;

      final status = _getIntakeStatus(
        timeStr: entry.key,
        allTaken: false,
        isToday: true,
        isFuture: false,
        isPast: false,
        nowMins: nowMins,
      );

      if (status == 'DUE') {
        dueNowCandidate ??= {
          'time': entry.key,
          'items': entry.value,
          'untaken': untaken,
          'status': 'DUE NOW',
        };
      } else if (status == 'LATE') {
        overdueCandidate ??= {
          'time': entry.key,
          'items': entry.value,
          'untaken': untaken,
          'status': 'OVERDUE',
        };
      } else if (status == 'UPCOMING') {
        upcomingCandidate ??= {
          'time': entry.key,
          'items': entry.value,
          'untaken': untaken,
          'status': 'UPCOMING',
        };
      }
    }

    // Priority: 1. Due Now, 2. Overdue, 3. Upcoming
    return dueNowCandidate ?? overdueCandidate ?? upcomingCandidate;
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
        if (_isItemTaken(med, d['doseIndex'] as int, entry.key)) {
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
    final status = next['status'] as String? ?? 'UPCOMING';
    
    final medNames = untaken.map((i) => (i['med'] as ScheduledMedicine).medicineName).join(', ');
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    // Only lock future dates. Today's doses are fully actionable even if taken early.
    final isLocked = !isToday;

    Color badgeColor;
    Color iconBgColor;
    IconData headerIcon;
    String badgeText;
    String headline;
    List<Color> gradientColors;
    Color borderColor;

    if (status == 'OVERDUE') {
      badgeColor = Colors.orange.shade800;
      iconBgColor = Colors.orange.shade700;
      headerIcon = Icons.warning_amber_rounded;
      badgeText = 'OVERDUE DOSE';
      headline = 'Missed scheduled time for $medNames';
      gradientColors = const [Color(0xFFFFF8E1), Color(0xFFFFFDF5)];
      borderColor = Colors.orange.withOpacity(0.25);
    } else if (status == 'DUE NOW') {
      badgeColor = _primary;
      iconBgColor = _primary;
      headerIcon = Icons.access_time_filled_rounded;
      badgeText = 'DUE NOW';
      headline = 'Time to take your $medNames';
      gradientColors = const [Color(0xFFEDFBF2), Color(0xFFF7FFF9)];
      borderColor = _primary.withOpacity(0.12);
    } else {
      badgeColor = const Color(0xFF007BFF);
      iconBgColor = const Color(0xFF007BFF);
      headerIcon = Icons.schedule_rounded;
      badgeText = 'UPCOMING DOSE';
      headline = 'Next scheduled: $medNames';
      gradientColors = const [Color(0xFFF0F7FF), Color(0xFFF9FBFF)];
      borderColor = const Color(0xFF007BFF).withOpacity(0.15);
    }

    final buttonLabel = status == 'OVERDUE'
        ? (untaken.length > 1 ? "Take all ${untaken.length} overdue meds" : "Take overdue dose")
        : (untaken.length > 1 ? "Take all ${untaken.length} meds" : "I've taken it");
    final buttonColor = status == 'OVERDUE' ? Colors.orange.shade800 : _primary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15, bottom: -15,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.medication_liquid_rounded,
                  size: 72,
                  color: badgeColor.withOpacity(0.18),
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
                      decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
                      child: Icon(headerIcon, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(badgeText, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 220,
                  child: Text(headline,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textDark, height: 1.2)),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _handleTimeBoxTap(context, items, time),
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
                      label: Text(buttonLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor, 
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
    return MedicineDoseCard(
      time: time,
      items: items,
      selectedDate: _selectedDate,
      isItemTaken: _isItemTaken,
      takenTimestamps: _takenTimestamps,
      onMarkAsTaken: (med, doseIndex, timeStr) => _markAsTaken(med, doseIndex, timeStr),
      onMarkAllAsTaken: (itemList, timeStr) => _markAllAsTaken(itemList, timeStr),
      onSetupAndMarkTaken: (med, doseIndex, picked) => _setupAndMarkTaken(med, doseIndex, picked),
      onPickTime: (med, doseIndex, currentStr) => _pickTime(context, med, doseIndex, currentStr),
      onTimeBoxTap: (itemList, timeStr) => _handleTimeBoxTap(context, itemList, timeStr),
    );
  }

  Widget _buildProgressCard(double completion) {
    return AdherenceProgressCard(completion: completion);
  }


  Widget _buildDateStrip() {
    return SchedulerDateStrip(
      selectedDate: _selectedDate,
      onDateSelected: (date) => _loadDateLogs(date),
      medicines: _medicines,
      consultations: _consultations,
      scrollController: _dateScrollController,
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
    return FollowupCheckupCard(consultation: c);
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
    final key = '${med.prescriptionItemId}_$doseIndex';
    final timeStr = _formatTimeOfDay(picked.hour, picked.minute);
    _manuallySetDoseTimes.add(key);

    final prefs = await SharedPreferences.getInstance();
    final targetDateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final isStartDay = DateUtils.isSameDay(_selectedDate, med.startDate);

    // If changing on start day or dose 0, update start anchor and re-project continuous rolling timeline
    if (isStartDay || doseIndex == 0) {
      await prefs.setString('med_start_${med.prescriptionItemId}', timeStr);
      // Clean up any stale old per-index keys for this medicine
      for (int i = 0; i < 6; i++) {
        await prefs.remove('med_dose_${med.prescriptionItemId}_$i');
      }
      if (mounted) {
        setState(() {
          _persistedStartTimes[med.prescriptionItemId] = timeStr;
        });
      }
    } else {
      // Shifting a specific dose on a specific date
      final shiftKey = '${med.prescriptionItemId}_${doseIndex}_$targetDateKey';
      await prefs.setString('med_dose_shift_$shiftKey', timeStr);
      if (mounted) {
        setState(() {
          _dateShiftedDoseTimes[shiftKey] = timeStr;
        });
      }
    }

    if (mounted) {
      setState(() {});
      _scheduleNotifications();
    }
  }

  Future<TimeOfDay?> _showTimePickerFor(BuildContext context, String currentTime) async {
    final totalMins = _parseTime(currentTime);
    final initialH = (totalMins ~/ 60) % 24;
    final initialM = totalMins % 60;

    return await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialH, minute: initialM),
    );
  }

  Future<void> _pickTime(BuildContext context, ScheduledMedicine med, int doseIndex, String currentTime) async {
    final picked = await _showTimePickerFor(context, currentTime);
    if (picked != null) {
      _applyTimeChange(med, doseIndex, picked);
    }
  }

  Future<void> _handleTimeBoxTap(BuildContext context, List<Map<String, dynamic>> items, String currentTime) async {
    final untakenItems = items.where((i) => 
      !_isItemTaken(i['med'] as ScheduledMedicine, i['doseIndex'] as int, currentTime)
    ).toList();

    if (untakenItems.isEmpty) return;

    if (untakenItems.length == 1) {
      final item = untakenItems.first;
      await _pickTime(context, item['med'] as ScheduledMedicine, item['doseIndex'] as int, currentTime);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _fieldBdr, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Reschedule Intake ($currentTime)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _textDark)),
            const SizedBox(height: 6),
            const Text('Which medication would you like to adjust?', style: TextStyle(fontSize: 13, color: _textMuted)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.schedule_rounded, color: _primary),
              ),
              title: const Text('All medicines in this slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text('${untakenItems.length} medications', style: const TextStyle(fontSize: 12, color: _textMuted)),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _showTimePickerFor(context, currentTime);
                if (picked != null) {
                  for (var item in untakenItems) {
                    _applyTimeChange(item['med'] as ScheduledMedicine, item['doseIndex'] as int, picked);
                  }
                }
              },
            ),
            const Divider(height: 20),
            ...untakenItems.map((item) {
              final med = item['med'] as ScheduledMedicine;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _primaryMid.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.medication_rounded, color: _primaryMid),
                ),
                title: Text(med.medicineName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(med.dosage.isNotEmpty ? med.dosage : 'Dose ${item['doseIndex'] + 1}', style: const TextStyle(fontSize: 12, color: _textMuted)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickTime(context, med, item['doseIndex'] as int, currentTime);
                },
              );
            }),
          ],
        ),
      ),
    );
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

  Future<void> _showLateIntakeAdjustmentDialog({
    required ScheduledMedicine med,
    required int takenDoseIndex,
    required int actualTakenMinutes,
    required List<int> scheduledMinutesList,
    required Map<int, int> shifts,
    required String dateKey,
  }) async {
    final accepted = await LateIntakeSheet.show(
      context: context,
      med: med,
      takenDoseIndex: takenDoseIndex,
      actualTakenMinutes: actualTakenMinutes,
      scheduledMinutesList: scheduledMinutesList,
      shifts: shifts,
      formatMinutes: _formatMinutes,
    );

    if (accepted == true) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        for (var entry in shifts.entries) {
          final shiftKey = '${med.prescriptionItemId}_${entry.key}_$dateKey';
          final timeStr = _formatMinutes(entry.value);
          _dateShiftedDoseTimes[shiftKey] = timeStr;
          prefs.setString('med_dose_shift_$shiftKey', timeStr);
        }
      });
      _scheduleNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Today's doses shifted for safe spacing"),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: _primaryMid,
          ),
        );
      }
    }
  }
}