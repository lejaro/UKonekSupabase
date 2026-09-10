import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/navigation/shell_navigation.dart';

class NotificationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  /// Callback allowing UI/Router layers to handle notification clicks customly.
  static void Function(Map<String, dynamic> payload)? onNotificationAction;

  static Future<void> init() async {
    if (kIsWeb) return;

    tz.initializeTimeZones();
    try {
      final now = DateTime.now();
      final offsetHours = now.timeZoneOffset.inHours;
      // If the device is in UTC+8 (Manila standard time), use Asia/Manila directly
      if (offsetHours == 8) {
        tz.setLocalLocation(tz.getLocation('Asia/Manila'));
      } else {
        final tzName = now.timeZoneName;
        try {
          final loc = tz.getLocation(tzName);
          final tzOffset = tz.TZDateTime.now(loc).timeZoneOffset.inHours;
          if (tzOffset == offsetHours) {
            tz.setLocalLocation(loc);
          } else {
            tz.setLocalLocation(tz.getLocation('Asia/Manila'));
          }
        } catch (_) {
          tz.setLocalLocation(tz.getLocation('Asia/Manila'));
        }
      }
    } catch (_) {
      try {
        tz.setLocalLocation(tz.local);
      } catch (e) {
        debugPrint('Timezone fallback error: $e');
      }
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const LinuxInitializationSettings initializationSettingsLinux =
    LinuxInitializationSettings(defaultActionName: 'Open notification');

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      linux: Platform.isLinux ? initializationSettingsLinux : null,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationPayload(payload);
        }
      },
    );

    // Handle cold start app launch from notification
    final launchDetails = await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 600), () {
          _handleNotificationPayload(payload);
        });
      }
    }

    // Request permissions for Android 13+
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  static void _handleNotificationPayload(String payload) {
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) {
        if (onNotificationAction != null) {
          onNotificationAction!(data);
          return;
        }

        // Default navigation fallback: switch to the medicine scheduler tab
        if (data['action'] == 'medicine') {
          ShellNavigation.switchTab(ShellNavigation.tabMedicineScheduler);
        }
      }
    } catch (e) {
      debugPrint('Error parsing notification payload: $e');
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      return await androidImplementation.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  static Future<void> scheduleMedicineReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    DateTimeComponents? matchDateTimeComponents = DateTimeComponents.time,
    String? payload,
    DateTime? startDate,
  }) async {
    if (kIsWeb) return;
    if (Platform.isLinux) return; // Linux has no real scheduling support

    final now = tz.TZDateTime.now(tz.local);
    final baseDate = startDate != null
        ? tz.TZDateTime.from(startDate, tz.local)
        : now;
    var scheduledDate = tz.TZDateTime(
      tz.local,
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
    );

    if (startDate == null && scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medicine_reminders',
          'Medicine Reminders',
          channelDescription: 'Notifications for medicine intake',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchDateTimeComponents,
      payload: payload,
    );
  }

  static Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'clinic_alerts',
          'Clinic Alerts',
          channelDescription: 'Notifications for immediate clinic updates',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// ID offset for medicine reminders. Medicine IDs use range 1000-1099.
  static const int medicineIdOffset = 1000;
  static const int maxMedicineNotifications = 100;

  /// Cancel only medicine reminder notifications (IDs 1000-1099)
  /// without affecting clinic alerts or other notification channels.
  static Future<void> cancelMedicineReminders() async {
    if (kIsWeb) return;
    final futures = <Future<void>>[];
    for (int i = 0; i < maxMedicineNotifications; i++) {
      futures.add(_notificationsPlugin.cancel(id: medicineIdOffset + i));
    }
    await Future.wait(futures);
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _notificationsPlugin.cancelAll();
  }
}