import 'package:flutter/material.dart';

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
  final List<Map<String, dynamic>> _notifications = [
    {
      'title': 'Appointment Reminder',
      'body': 'You have a dental check-up scheduled for tomorrow at 9:00 AM.',
      'time': '2 hours ago',
      'type': 'reminder',
      'isRead': false,
    },
    {
      'title': 'Queue Update',
      'body': 'Your number #042 is now being called at Station 1.',
      'time': '5 hours ago',
      'type': 'queue',
      'isRead': true,
    },
    {
      'title': 'New Medical Record',
      'body': 'Your recent Dental Prophylaxis results are now available.',
      'time': 'Yesterday',
      'type': 'record',
      'isRead': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _notifications.isEmpty
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notifications',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.4)),
                    SizedBox(height: 2),
                    Text('Stay updated with your clinic visits', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
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
        return _buildNotificationCard(item);
      },
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> item) {
    bool isRead = item['isRead'];
    return Container(
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
                    Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.textDark)),
                    if (!isRead)
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFF5252), shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item['body'], style: const TextStyle(color: _C.textMuted, fontSize: 12, height: 1.4)),
                const SizedBox(height: 8),
                Text(item['time'], style: TextStyle(color: _C.textMuted.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
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
          const Text('We\'ll notify you when something comes up.', style: TextStyle(color: _C.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'reminder': return Icons.alarm_on_rounded;
      case 'queue': return Icons.confirmation_number_rounded;
      case 'record': return Icons.assignment_turned_in_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'reminder': return const Color(0xFFF59E0B);
      case 'queue': return _C.primaryMid;
      case 'record': return const Color(0xFF17A2B8);
      default: return _C.textMuted;
    }
  }

  Color _getIconBgColor(String type) {
    return _getIconColor(type).withOpacity(0.1);
  }
}