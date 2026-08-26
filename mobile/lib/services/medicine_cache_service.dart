import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class MedicineCacheService {
  static const String _schedulePrefix = 'cached_med_schedule_';
  static const String _scheduleSyncedPrefix = 'cached_med_schedule_synced_';
  static const String _logsPrefix = 'cached_med_logs_';
  static const String _pendingQueueKey = 'pending_intake_logs_queue';

  /// Save medicine schedule locally
  static Future<void> saveSchedule(String citizenId, List<ScheduledMedicine> medicines) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = medicines.map((m) => m.toMap()).toList();
      await prefs.setString('$_schedulePrefix$citizenId', jsonEncode(jsonList));
      await prefs.setInt('$_scheduleSyncedPrefix$citizenId', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving schedule to cache: $e');
    }
  }

  /// Load cached medicine schedule
  static Future<List<ScheduledMedicine>?> loadCachedSchedule(String citizenId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_schedulePrefix$citizenId');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ScheduledMedicine.fromMap)
          .toList();
    } catch (e) {
      debugPrint('Error loading schedule from cache: $e');
      return null;
    }
  }

  /// Check if schedule cache is still fresh
  static Future<bool> isScheduleCacheFresh(String citizenId, {Duration maxAge = const Duration(hours: 6)}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSynced = prefs.getInt('$_scheduleSyncedPrefix$citizenId');
      if (lastSynced == null) return false;
      final diff = DateTime.now().millisecondsSinceEpoch - lastSynced;
      return diff < maxAge.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Save intake logs for a specific date (format: YYYY-MM-DD)
  static Future<void> saveIntakeLogs(String citizenId, String dateKey, List<Map<String, dynamic>> logs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_logsPrefix}${citizenId}_$dateKey', jsonEncode(logs));
    } catch (e) {
      debugPrint('Error saving intake logs to cache: $e');
    }
  }

  /// Load cached intake logs for a specific date
  static Future<List<Map<String, dynamic>>?> loadCachedIntakeLogs(String citizenId, String dateKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${_logsPrefix}${citizenId}_$dateKey');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error loading cached intake logs: $e');
      return null;
    }
  }

  /// Optimistically record an intake locally and queue for background sync
  static Future<void> recordLocalIntake(
    String citizenId, {
    required int prescriptionItemId,
    required String scheduledTime,
    required int doseIndex,
    required String dateKey,
    DateTime? actualTime,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Update local date log cache
      final existing = await loadCachedIntakeLogs(citizenId, dateKey) ?? [];
      final now = actualTime ?? DateTime.now();
      final newLog = {
        'prescription_item_id': prescriptionItemId,
        'scheduled_time': scheduledTime,
        'dose_index': doseIndex,
        'status': 'taken',
        'actual_time': now.toUtc().toIso8601String(),
      };
      
      // Avoid duplicate local entries
      final key = '${prescriptionItemId}_$doseIndex';
      final alreadyExists = existing.any((l) => '${l['prescription_item_id']}_${l['dose_index']}' == key);
      if (!alreadyExists) {
        existing.add(newLog);
        await saveIntakeLogs(citizenId, dateKey, existing);
      }

      // 2. Append to offline sync queue (avoid duplicate pending sync requests)
      final queueRaw = prefs.getString(_pendingQueueKey);
      final queue = queueRaw != null ? (jsonDecode(queueRaw) as List<dynamic>).whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
      
      final queueItem = {
        'citizen_id': citizenId,
        'prescription_item_id': prescriptionItemId,
        'scheduled_time': scheduledTime,
        'dose_index': doseIndex,
        'intake_date': dateKey,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final alreadyInQueue = queue.any((item) =>
        (item['prescription_item_id'] as num?)?.toInt() == prescriptionItemId &&
        (item['dose_index'] as num?)?.toInt() == doseIndex &&
        item['intake_date'] == dateKey
      );

      if (!alreadyInQueue) {
        queue.add(queueItem);
        await prefs.setString(_pendingQueueKey, jsonEncode(queue));
      }
    } catch (e) {
      debugPrint('Error recording local intake: $e');
    }
  }

  /// Flush/sync pending intake logs to Supabase
  static Future<void> syncPendingIntakeLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueRaw = prefs.getString(_pendingQueueKey);
      if (queueRaw == null || queueRaw.isEmpty) return;

      final queue = (jsonDecode(queueRaw) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      if (queue.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final item in queue) {
        try {
          await ApiService.logMedicineIntake(
            prescriptionItemId: (item['prescription_item_id'] as num).toInt(),
            scheduledTime: item['scheduled_time'] as String,
            doseIndex: (item['dose_index'] as num).toInt(),
            citizenId: int.tryParse(item['citizen_id']?.toString() ?? ''),
            intakeDate: item['intake_date'] as String?,
          );
        } catch (e) {
          debugPrint('Sync failed for item, keeping in queue: $e');
          remaining.add(item);
        }
      }

      if (remaining.isEmpty) {
        await prefs.remove(_pendingQueueKey);
      } else {
        await prefs.setString(_pendingQueueKey, jsonEncode(remaining));
      }
    } catch (e) {
      debugPrint('Error syncing pending intake logs: $e');
    }
  }

  /// Clear user's cache (e.g. on logout)
  static Future<void> clearUserCache(String citizenId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_schedulePrefix$citizenId');
      await prefs.remove('$_scheduleSyncedPrefix$citizenId');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Prune intake log cache entries older than [maxAge] to prevent
  /// unbounded SharedPreferences growth.
  static Future<void> pruneOldLogs(String citizenId, {Duration maxAge = const Duration(days: 30)}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final prefix = '${_logsPrefix}${citizenId}_';
      final cutoff = DateTime.now().subtract(maxAge);

      for (final key in allKeys) {
        if (!key.startsWith(prefix)) continue;
        // Key format: cached_med_logs_{citizenId}_{yyyy-MM-dd}
        final dateStr = key.substring(prefix.length);
        final date = DateTime.tryParse(dateStr);
        if (date != null && date.isBefore(cutoff)) {
          await prefs.remove(key);
          debugPrint('Pruned old intake log cache: $key');
        }
      }
    } catch (e) {
      debugPrint('Error pruning old logs: $e');
    }
  }

  /// Bug #6 fix: Remove an intake record from local cache and pending queue (for undo)
  static Future<void> removeLocalIntake(
    String citizenId, {
    required String prescriptionItemKey,
    required String dateKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Remove from cached date logs
      final existing = await loadCachedIntakeLogs(citizenId, dateKey) ?? [];
      existing.removeWhere((l) =>
        '${l['prescription_item_id']}_${l['dose_index']}' == prescriptionItemKey
      );
      await saveIntakeLogs(citizenId, dateKey, existing);

      // 2. Remove from pending sync queue specifically for this date
      final queueRaw = prefs.getString(_pendingQueueKey);
      if (queueRaw != null) {
        final queue = (jsonDecode(queueRaw) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
        queue.removeWhere((item) =>
          '${item['prescription_item_id']}_${item['dose_index']}' == prescriptionItemKey &&
          (item['intake_date'] == null || item['intake_date'] == dateKey)
        );
        if (queue.isEmpty) {
          await prefs.remove(_pendingQueueKey);
        } else {
          await prefs.setString(_pendingQueueKey, jsonEncode(queue));
        }
      }
    } catch (e) {
      debugPrint('Error removing local intake: $e');
    }
  }
}
