import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'services/api_service.dart';
import 'uKonekJoinQueuePage.dart';

class _C {
  static const primary = Color(0xFF0A2E6E);
  static const primaryMid = Color(0xFF1565C0);
  static const bg = Color(0xFFF0F4FA);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1A2740);
  static const textMuted = Color(0xFF8A93A0);
  static const shadow = Color(0x0A000000);
}

class uKonekQueueTabPage extends StatefulWidget {
  const uKonekQueueTabPage({super.key});

  @override
  State<uKonekQueueTabPage> createState() => _uKonekQueueTabPageState();
}

class _uKonekQueueTabPageState extends State<uKonekQueueTabPage> {
  late Future<QueueDashboardSnapshot> _snapshotFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = ApiService.getMyQueueDashboard();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _snapshotFuture = ApiService.getMyQueueDashboard();
    });
  }

  String _queueNo(int? number) {
    if (number == null || number <= 0) return '--';
    return '#${number.toString().padLeft(3, '0')}';
  }

  String _formatMinutes(int minutes) {
    final value = minutes < 0 ? 0 : minutes;
    final h = value ~/ 60;
    final m = value % 60;
    if (h <= 0) return '$m min';
    if (m == 0) return '$h hr';
    return '$h hr $m min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        title: const Text('Queue'),
        backgroundColor: _C.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<QueueDashboardSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unable to load queue status.'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final queue = snapshot.data ?? QueueDashboardSnapshot.empty;
          if (!queue.hasActiveQueue) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'You are not currently in queue.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final joined = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const uKonekJoinQueuePage(),
                          ),
                        );
                        if (joined == true) _refresh();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.primaryMid,
                      ),
                      child: const Text('Join Queue'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: _C.shadow,
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      _queueNo(queue.myQueueNumber),
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: _C.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      queue.serviceLabel.isEmpty ? 'Queue' : queue.serviceLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _C.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (queue.isOnCall) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFFB923C)),
                        ),
                        child: const Text(
                          'ON CALL NOW',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFC2410C),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (queue.ticketCode.isNotEmpty)
                      QrImageView(
                        data: queue.ticketCode,
                        version: QrVersions.auto,
                        size: 180,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      queue.ticketCode.isEmpty ? '--' : queue.ticketCode,
                      style: const TextStyle(
                        color: _C.textDark,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _infoRow(
                      'Currently Serving',
                      _queueNo(queue.currentlyServingQueueNumber),
                    ),
                    _infoRow(
                      'Your Queue Number',
                      _queueNo(queue.myQueueNumber),
                    ),
                    _infoRow(
                      'Estimated Waiting Time',
                      _formatMinutes(queue.estimatedWaitMinutes),
                    ),
                    _infoRow(
                      'People Waiting',
                      '${queue.waitingCount}',
                    ),
                    _infoRow(
                      'On Call',
                      queue.isOnCall ? 'YES' : 'NO',
                    ),
                    _infoRow(
                      'Status',
                      queue.status.isEmpty ? '--' : queue.status.toUpperCase(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh Queue Status'),
              ),
            ],
          );
        },
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
}
