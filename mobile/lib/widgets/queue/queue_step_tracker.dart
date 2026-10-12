import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/queue_ticket.dart';

typedef _C = AppColors;

/// 3-step horizontal queue tracker indicating progress:
/// Step 1: Ticket Issued -> Step 2: Vitals / Triage -> Step 3: Doctor Consultation.
class QueueStepTracker extends StatelessWidget {
  final QueueDashboardSnapshot queue;
  final bool isOnCall;
  final bool isTurn;

  const QueueStepTracker({
    super.key,
    required this.queue,
    required this.isOnCall,
    required this.isTurn,
  });

  @override
  Widget build(BuildContext context) {
    final status = queue.status.toLowerCase().trim();
    final bool isCompleted = queue.isCompleted;

    // A ticket is on-call if explicitly on call, or if queue.isOnCallStatus
    final bool isTicketOnCall = !isCompleted && (isOnCall || queue.isOnCallStatus || status == 'on_call');

    // Consult is only active ("Now Serving") when the patient card is actually serving
    final bool isNowServing = !isCompleted && !isTicketOnCall && (queue.isServing || status == 'serving' || (queue.isCurrentlyBeingServed && !queue.isOnCallStatus));

    // 1. Vitals is marked completed ONLY when:
    //    - vitals have actually been recorded in the database (queue.hasVitals == true)
    //    - OR the ticket has legitimately progressed to Now Serving / Completed (and is not waiting or on call)
    //    If the ticket is in 'waiting' or placed on call without recorded vitals, vitalsDone MUST be false!
    final bool vitalsDone = queue.hasVitals || (!isTicketOnCall && status != 'waiting' && (isNowServing || isCompleted));
    final bool vitalsActive = !vitalsDone && isTicketOnCall;

    // 2. Consult must only be active and glow lightly when the patient card is in "Now Serving"
    final bool consultActive = isNowServing && !isCompleted;
    final bool consultDone = isCompleted;

    // Clean 3-stage Visit Progression
    final stepStates = [
      {
        'label': 'Ticket',
        'desc': 'Issued',
        'icon': Icons.confirmation_number_outlined,
        'isDone': true,
        'isCurrent': !vitalsActive && !vitalsDone && !consultActive && !isCompleted,
      },
      {
        'label': 'Vitals',
        'desc': vitalsDone ? 'Completed' : (vitalsActive ? 'On Call' : 'Pending'),
        'icon': Icons.monitor_heart_outlined,
        'isDone': vitalsDone,
        'isCurrent': vitalsActive,
      },
      {
        'label': 'Consult',
        'desc': consultDone
            ? 'Completed'
            : (consultActive ? 'Now Serving' : (vitalsDone ? 'Waiting Dr.' : 'Queueing')),
        'icon': Icons.medical_services_outlined,
        'isDone': consultDone,
        'isCurrent': consultActive,
      },
    ];

    String stepBadgeText = 'Step 1 of 3';
    if (consultDone) {
      stepBadgeText = 'Step 3 of 3 (Complete)';
    } else if (consultActive) {
      stepBadgeText = 'Step 3 of 3 (Now Serving)';
    } else if (vitalsDone) {
      stepBadgeText = 'Step 2 of 3 (Vitals Taken)';
    } else if (vitalsActive) {
      stepBadgeText = 'Step 2 of 3 (On Call)';
    } else {
      stepBadgeText = 'Step 1 of 3 (Ticket Issued)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.fieldBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _C.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VISIT PROGRESSION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _C.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _C.primaryMid.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stepBadgeText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryMid,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final double totalWidth = constraints.maxWidth;
              final double colWidth = totalWidth / 3;
              const double circleRadius = 19.0; // 38px / 2
              final double circleCenter = colWidth / 2;

              // Line 1: from Ticket (circle 0) right edge to Vitals (circle 1) left edge
              final double line1Left = circleCenter + circleRadius;
              final double line1Width = colWidth - (circleRadius * 2);

              // Line 2: from Vitals (circle 1) right edge to Consult (circle 2) left edge
              final double line2Left = circleCenter + colWidth + circleRadius;
              final double line2Width = colWidth - (circleRadius * 2);

              final Color line1Color = vitalsDone
                  ? _C.success
                  : (vitalsActive ? _C.warning : Colors.grey.shade300);

              final Color line2Color = consultDone
                  ? _C.success
                  : (consultActive ? _C.primaryMid : Colors.grey.shade300);

              return Stack(
                children: [
                  // Connector Line 1: Ticket -> Vitals
                  Positioned(
                    top: 18,
                    left: line1Left,
                    width: line1Width > 0 ? line1Width : 0,
                    child: Container(
                      height: 2,
                      color: line1Color,
                    ),
                  ),
                  // Connector Line 2: Vitals -> Consult
                  Positioned(
                    top: 18,
                    left: line2Left,
                    width: line2Width > 0 ? line2Width : 0,
                    child: Container(
                      height: 2,
                      color: line2Color,
                    ),
                  ),
                  // 3 Proportionally Centered Step Columns
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(stepStates.length, (i) {
                      final item = stepStates[i];
                      final bool isDone = item['isDone'] as bool;
                      final bool isCurrent = item['isCurrent'] as bool;

                      final Color stepColor = isDone
                          ? _C.success
                          : (isCurrent
                              ? (vitalsActive ? _C.warning : _C.primaryMid)
                              : Colors.grey.shade400);

                      return Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isDone
                                    ? _C.success
                                    : (isCurrent
                                        ? stepColor.withValues(alpha: 0.10)
                                        : Colors.white),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isCurrent
                                      ? stepColor
                                      : (isDone ? _C.success : Colors.grey.shade300),
                                  width: isCurrent ? 2.0 : 1.2,
                                ),
                                boxShadow: isCurrent
                                    ? [
                                        BoxShadow(
                                          color: stepColor.withValues(alpha: 0.18),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Icon(
                                isDone ? Icons.check_rounded : (item['icon'] as IconData),
                                size: isDone ? 20 : 17,
                                color: isDone ? Colors.white : stepColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: (isCurrent || isDone) ? FontWeight.w800 : FontWeight.w600,
                                color: isDone ? _C.textDark : (isCurrent ? _C.textDark : _C.textMuted),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              item['desc'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                color: isCurrent
                                    ? stepColor
                                    : (isDone ? _C.success : _C.textMuted.withValues(alpha: 0.7)),
                                fontWeight: (isCurrent || isDone) ? FontWeight.w700 : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
