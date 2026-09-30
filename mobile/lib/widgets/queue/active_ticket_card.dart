import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../models/queue_ticket.dart';
import 'queue_step_tracker.dart';

typedef _C = AppColors;

/// View displaying the user's active queue ticket, live status banner, step progress, QR code, and cancellation action.
class ActiveTicketCard extends StatelessWidget {
  final QueueDashboardSnapshot queue;
  final bool isSubmitting;
  final VoidCallback onCancel;

  const ActiveTicketCard({
    super.key,
    required this.queue,
    required this.isSubmitting,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isFinished = queue.isCompleted;
    final isCancelled = queue.isCancelled;
    final isServing = queue.isCurrentlyBeingServed;
    final isOnCall = !isFinished && !isCancelled && queue.isOnCallStatus;
    final isNext = !isFinished && !isCancelled && !isServing && !isOnCall && queue.isNextInLine;
    final isTurn = isServing || isNext;
    final int ahead = queue.peopleAheadCount;

    final Color statusColor = isFinished
        ? _C.success
        : (isOnCall
            ? _C.warning
            : (isServing
                ? _C.success
                : _C.primaryMid));

    final String statusMsg = isFinished
        ? 'Your consultation has been completed. Prescriptions & instructions are ready.'
        : (isOnCall
            ? 'Please proceed to the nurse station for vital signs assessment'
            : (isServing
                ? 'It\'s your turn! Please proceed to the doctor\'s office'
                : (isNext
                    ? (queue.hasServingAhead
                        ? 'You\'re next in line! Doctor is currently serving #${queue.currentlyServingQueueNumber!.toString().padLeft(3, '0')}.'
                        : 'You\'re next in line! Station is preparing to call your number.')
                    : '$ahead ${ahead == 1 ? 'person' : 'people'} ahead of you in line')));

    final IconData statusIcon = isFinished
        ? Icons.task_alt_rounded
        : (isOnCall
            ? Icons.campaign_rounded
            : (isServing
                ? Icons.check_circle_rounded
                : (isNext ? Icons.notifications_active_rounded : Icons.groups_rounded)));

    final String headerStatusTitle = isFinished
        ? 'CONSULTATION COMPLETED'
        : (isOnCall
            ? 'YOU ARE ON CALL'
            : (isServing
                ? 'YOU ARE NOW SERVING'
                : (isNext
                    ? 'YOU ARE NEXT IN LINE'
                    : (queue.currentlyServingQueueNumber != null && queue.currentlyServingQueueNumber! > 0
                        ? 'NOW SERVING #${queue.currentlyServingQueueNumber!.toString().padLeft(3, '0')}'
                        : 'STATION ACTIVE'))));

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        children: [
          // ── Status banner ─────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerStatusTitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusMsg,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOnCall)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _C.warning, borderRadius: BorderRadius.circular(8)),
                    child: const Text('ON CALL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                if (isFinished)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _C.success, borderRadius: BorderRadius.circular(8)),
                    child: const Text('DONE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Step Progress Tracker ────────────────────────────
          QueueStepTracker(queue: queue, isOnCall: isOnCall, isTurn: isTurn),
          const SizedBox(height: 16),

          // ── Ticket card ───────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _C.primaryMid.withOpacity(0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Ticket header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [_C.primary, _C.primaryMid]),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'YOUR QUEUE TICKET',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        queue.serviceLabel.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Queue number + QR
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      // Queue number badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withOpacity(0.20), width: 2),
                        ),
                        child: Text(
                          '#${(queue.myQueueNumber ?? 0).toString().padLeft(3, '0')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                            letterSpacing: -2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'YOUR NUMBER',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _C.textMuted.withOpacity(0.6),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Divider with dots (ticket stub look)
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _C.bg,
                              shape: BoxShape.circle,
                              border: Border.all(color: _C.fieldBorder),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: List.generate(
                                  18,
                                  (i) => Expanded(
                                    child: Container(
                                      height: 1,
                                      color: i.isEven ? _C.fieldBorder : Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _C.bg,
                              shape: BoxShape.circle,
                              border: Border.all(color: _C.fieldBorder),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // QR Code
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _C.bg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _C.fieldBorder),
                        ),
                        child: QrImageView(
                          data: queue.ticketCode,
                          size: 160,
                          eyeStyle: const QrEyeStyle(color: _C.primaryMid, eyeShape: QrEyeShape.square),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _C.primaryMid),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        queue.ticketCode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _C.textMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Stats row
                      Row(
                        children: [
                          _statChip(
                            Icons.timer_outlined,
                            'Est. Wait',
                            queue.formattedWaitTime,
                            _C.primaryMid,
                          ),
                          const SizedBox(width: 12),
                          _statChip(
                            Icons.people_outline_rounded,
                            'People Ahead',
                            (isFinished || isServing || isOnCall) ? '0' : '$ahead',
                            _C.primaryMid,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Cancel button (Hidden when On Call, Serving, or Finished)
                      if (!isOnCall && !isServing && !isFinished)
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: isSubmitting ? null : onCancel,
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: _C.danger),
                                  )
                                : const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('LEAVE QUEUE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _C.danger,
                              side: BorderSide(color: _C.danger.withValues(alpha: 0.5), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color.withValues(alpha: 0.75), size: 14),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
