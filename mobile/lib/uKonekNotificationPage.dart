import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class _C {
  static const primary    = Color(0xFF1B5E20);
  static const primaryMid = Color(0xFF28A745);
  static const bg         = Color(0xFFF8FCF9);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1B2E1E);
  static const textMuted  = Color(0xFF637367);
  static const divider    = Color(0xFFE2E9E3);
  static const shadow     = Color(0x0A000000);
}

class uKonekNotificationPage extends StatefulWidget {
  final String username;
  final String fullname;

  const uKonekNotificationPage({
    super.key,
    required this.username,
    required this.fullname
  });

  @override
  State<uKonekNotificationPage> createState() => _uKonekNotificationPageState();
}

class _uKonekNotificationPageState extends State<uKonekNotificationPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _updateLastViewed();
  }

  Future<void> _updateLastViewed() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await prefs.setString('last_viewed_notifications', now);
  }

  Future<void> _clearAllNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notifications_cleared_at', DateTime.now().toIso8601String());
    await _updateLastViewed();
    setState(() {
      _notifications.clear();
    });
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    
    try {
      final results = await Future.wait([
        ApiService.fetchAnnouncements(),
        ApiService.getMyQueueDashboard(),
        ApiService.getMedicineSchedule(),
        ApiService.getIntakeLogsForDate(DateTime.now()),
        SharedPreferences.getInstance(),
        ApiService.fetchConsultations(),
      ]);

      final announcements = results[0] as List<Announcement>;
      final queue = results[1] as QueueDashboardSnapshot;
      final schedules = results[2] as List<ScheduledMedicine>;
      final logs = results[3] as List<Map<String, dynamic>>;
      final prefs = results[4] as SharedPreferences;
      final consultations = results[5] as List<Consultation>;

      final List<Map<String, dynamic>> notifications = [];
      
      // 1. Announcements
      for (var a in announcements) {
        notifications.add({
          'id': 'ann_${a.id}',
          'title': a.title,
          'body': a.content,
          'time': _formatTime(a.createdAt.toIso8601String()),
          'type': 'announcement',
          'isRead': false,
          'rawDate': a.createdAt,
        });
      }

      // 2. Queue Notifications
      if (queue.hasActiveQueue) {
        String body = 'Your current position is #${queue.waitingCount}.';
        if (queue.status.toLowerCase() == 'on_call') {
          body = 'You are being called! Please proceed to the nurse station.';
        }
        notifications.add({
          'id': 'queue_${queue.queueId}',
          'title': 'Queue Status: ${queue.status.toUpperCase()}',
          'body': body,
          'time': 'Active Now',
          'type': 'queue',
          'isRead': false,
          'rawDate': DateTime.now(),
        });
      }

      // 3. Medicine Reminders (Missed doses from today)
      final takenKeys = logs.map((l) => '${l['prescription_item_id']}_${l['dose_index']}').toSet();
      final now = DateTime.now();
      final nowMins = now.hour * 60 + now.minute;

      for (var med in schedules) {
        // Only active, dispensed scheduled prescriptions for today
        if (!med.isDispensed || !med.isActiveOn(now) || med.dailyDoseCount <= 0) continue;

        for (int i = 0; i < med.doseTimes.length; i++) {
          final key = '${med.prescriptionItemId}_$i';
          if (!takenKeys.contains(key)) {
            final customTime = prefs.getString('med_dose_${med.prescriptionItemId}_$i');
            final doseTimeStr = customTime ?? med.doseTimes[i];
            final tMins = _parseTime(doseTimeStr);
            if (nowMins > tMins + 15) { // 15 mins past due
               notifications.add({
                'id': 'med_${med.prescriptionItemId}_$i',
                'title': 'Missed Dose: ${med.medicineName}',
                'body': 'You missed your $doseTimeStr intake. Please take it as soon as possible.',
                'time': '$doseTimeStr Today',
                'type': 'reminder',
                'isRead': false,
                'rawDate': DateTime.now().subtract(const Duration(minutes: 5)), // Recent
              });
            }
          }
        }
      }

      // 4. Follow-up Checkup Date Notifications
      final todayDate = DateTime(now.year, now.month, now.day);
      final tomorrowDate = todayDate.add(const Duration(days: 1));

      for (var con in consultations) {
        if (con.followupDate != null) {
          final followDate = DateTime(con.followupDate!.year, con.followupDate!.month, con.followupDate!.day);

          // A. Standard Notification (scheduled date information)
          notifications.add({
            'id': 'followup_sched_${con.id}',
            'title': 'Follow-up Checkup Scheduled',
            'body': 'You have a follow-up checkup scheduled with ${con.doctorName ?? 'your doctor'} on ${DateFormat('MMMM d, yyyy').format(con.followupDate!)}.',
            'time': 'Consulted on ${DateFormat('MM/dd/yyyy').format(con.consultedAt)}',
            'type': 'followup',
            'isRead': false,
            'rawDate': con.consultedAt,
          });

          // B. Tomorrow's Reminder (1 day before)
          if (followDate.isAtSameMomentAs(tomorrowDate)) {
            notifications.add({
              'id': 'followup_tomorrow_${con.id}',
              'title': 'Follow-up Consultation Tomorrow',
              'body': 'Friendly reminder: Your follow-up consultation with ${con.doctorName ?? 'your doctor'} is scheduled for tomorrow, ${DateFormat('MMMM d, yyyy').format(con.followupDate!)}.',
              'time': 'Reminder',
              'type': 'followup',
              'isRead': false,
              'rawDate': now.subtract(const Duration(seconds: 1)),
            });
          }

          // C. Today's Reminder (Same day)
          if (followDate.isAtSameMomentAs(todayDate)) {
            notifications.add({
              'id': 'followup_today_${con.id}',
              'title': 'Follow-up Consultation Today',
              'body': 'Your follow-up consultation with ${con.doctorName ?? 'your doctor'} is scheduled for today! You can join the queue today.',
              'time': 'Active Now',
              'type': 'followup',
              'isRead': false,
              'rawDate': now,
            });
          }
        }
      }

      // Filter out notifications cleared before this timestamp
      final clearedAtStr = prefs.getString('notifications_cleared_at');
      if (clearedAtStr != null) {
        final clearedAt = DateTime.parse(clearedAtStr);
        notifications.removeWhere((n) => (n['rawDate'] as DateTime).isBefore(clearedAt));
      }

      // Sort by date (newest first)
      notifications.sort((a, b) => (b['rawDate'] as DateTime).compareTo(a['rawDate'] as DateTime));

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      setState(() => _isLoading = false);
    }
  }

  int _parseTime(String t) {
    try {
      final clean = t.trim().replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
      final parts = clean.split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      int m = int.parse(hm[1]);
      if (parts.length > 1) {
        final period = parts[1].toUpperCase().replaceAll('.', '');
        if ((period == 'PM' || period == 'P') && h != 12) h += 12;
        if ((period == 'AM' || period == 'A') && h == 12) h = 0;
      }
      return h * 60 + m;
    } catch (_) { return 0; }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return 'Recently';
    
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 60) {
        return '${diff.inMinutes} min ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return 'Recently';
    }
  }

  void _dismissNotification(int index) {
    setState(() {
      _notifications.removeAt(index);
    });
  }

  void _dismissAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to remove all notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _clearAllNotifications();
              Navigator.pop(context);
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _C.primaryMid))
                : _notifications.isEmpty
                    ? _buildEmptyState()
                    : _buildNotificationList(),
          ),
        ],
      ),
    );
  }

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
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Notifications',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.4)),
                    const SizedBox(height: 2),
                    Text('${_notifications.length} announcement${_notifications.length != 1 ? 's' : ''}', 
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              if (_notifications.isNotEmpty)
                GestureDetector(
                  onTap: _dismissAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Clear All',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final item = _notifications[index];
        return _buildNotificationCard(item, index);
      },
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> item, int index) {
    bool isRead = item['isRead'];
    return Dismissible(
      key: Key('notification_${item['id']}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      onDismissed: (direction) {
        _dismissNotification(index);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item['title']} dismissed'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? _C.surface.withOpacity(0.7) : _C.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 10, offset: Offset(0, 4))],
          border: isRead ? Border.all(color: _C.divider) : Border.all(color: _C.primaryMid.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _getIconBgColor(item['type']),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_getIcon(item['type']), color: _getIconColor(item['type']), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(item['title'], 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
                      ),
                      GestureDetector(
                        onTap: () => _dismissNotification(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, size: 18, color: _C.textMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item['body'], 
                      style: const TextStyle(color: _C.textMuted, fontSize: 12, height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(item['time'], 
                      style: TextStyle(color: _C.textMuted.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 64, color: _C.textMuted.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('No notifications yet', style: TextStyle(color: _C.textDark, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('We\'ll notify you when something comes up.', 
              style: TextStyle(color: _C.textMuted, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'announcement': return Icons.campaign_rounded;
      case 'reminder': return Icons.alarm_on_rounded;
      case 'queue': return Icons.confirmation_number_rounded;
      case 'record': return Icons.assignment_turned_in_rounded;
      case 'followup': return Icons.event_note_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'announcement': return const Color(0xFF3B82F6);
      case 'reminder': return const Color(0xFFF59E0B);
      case 'queue': return _C.primaryMid;
      case 'record': return const Color(0xFF17A2B8);
      case 'followup': return Colors.teal;
      default: return _C.textMuted;
    }
  }

  Color _getIconBgColor(String type) {
    return _getIconColor(type).withOpacity(0.1);
  }
}