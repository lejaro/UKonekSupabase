import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'notification_service.dart';

/// Service responsible for managing and scheduling patient follow-up consultation reminders.
/// Follow-up reminders are scheduled strictly two (2) times:
/// 1. Exactly 1 day before the consultation at 7:00 AM local time.
/// 2. On the day of the consultation at 7:00 AM local time.
class FollowupNotificationService {
  /// Synchronizes and schedules native device notifications for upcoming follow-up consultations.
  /// If [cachedConsultations] is provided, uses them to avoid redundant network calls.
  /// Otherwise, fetches the patient's consultations via [ApiService.fetchConsultations].
  static Future<void> syncAndScheduleFollowupReminders([
    List<Consultation>? cachedConsultations,
  ]) async {
    try {
      // 1. Cancel previous follow-up notifications to prevent stale or duplicate alarms
      await NotificationService.cancelFollowupReminders();

      // 2. Obtain consultations
      List<Consultation> consultations;
      if (cachedConsultations != null && cachedConsultations.isNotEmpty) {
        consultations = cachedConsultations;
      } else {
        consultations = await ApiService.fetchConsultations().catchError((e) {
          debugPrint('[FollowupNotificationService] Error fetching consultations: $e');
          return <Consultation>[];
        });
      }

      if (consultations.isEmpty) return;

      for (var con in consultations) {
        if (con.followupDate == null) continue;

        final followDate = DateTime(
          con.followupDate!.year,
          con.followupDate!.month,
          con.followupDate!.day,
        );

        // Doctor name fallback
        final docName = (con.doctorName != null && con.doctorName!.trim().isNotEmpty)
            ? con.doctorName!.trim()
            : 'your doctor';
        final formattedDateStr = DateFormat('MMMM d, yyyy').format(followDate);

        // --- Notification 1: Exactly 1 Day Before at 7:00 AM ---
        final dayBeforeDate = followDate.subtract(const Duration(days: 1));
        final idDayBefore = NotificationService.followupIdOffset +
            ((con.id * 2) % NotificationService.maxFollowupNotifications);

        final dayBeforePayload = jsonEncode({
          'action': 'followup',
          'consultation_id': con.id,
          'followup_date': DateFormat('yyyy-MM-dd').format(followDate),
          'type': 'day_before',
        });

        await NotificationService.scheduleFollowupReminder(
          id: idDayBefore,
          title: 'Upcoming Follow-up Consultation Tomorrow',
          body: 'Friendly reminder: Your follow-up consultation with $docName is scheduled for tomorrow, $formattedDateStr.',
          date: dayBeforeDate,
          hour: 7,
          minute: 0,
          payload: dayBeforePayload,
        );

        // --- Notification 2: On the Day of Consultation at 7:00 AM ---
        final idDayOf = NotificationService.followupIdOffset +
            ((con.id * 2 + 1) % NotificationService.maxFollowupNotifications);

        final dayOfPayload = jsonEncode({
          'action': 'followup',
          'consultation_id': con.id,
          'followup_date': DateFormat('yyyy-MM-dd').format(followDate),
          'type': 'day_of',
        });

        await NotificationService.scheduleFollowupReminder(
          id: idDayOf,
          title: 'Follow-up Consultation Today',
          body: 'Your follow-up consultation with $docName is scheduled for today! You can join the clinic queue now.',
          date: followDate,
          hour: 7,
          minute: 0,
          payload: dayOfPayload,
        );
      }

      debugPrint('[FollowupNotificationService] Successfully synchronized follow-up reminders.');
    } catch (e, stack) {
      debugPrint('[FollowupNotificationService] Error scheduling follow-up reminders: $e\n$stack');
    }
  }
}
