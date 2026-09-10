import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/queue_ticket.dart';

typedef _C = AppColors;

/// 4-step horizontal queue tracker indicating progress from Ticket Issued -> Vitals Taken -> Doctor Consultation -> Completed.
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
    final status = queue.status.toLowerCase();
    final bool vitalsDone = queue.hasVitals || status == 'serving' || status == 'completed';
    final bool vitalsActive = !vitalsDone && (isOnCall || status == 'on_call');
    final bool consultDone = status == 'completed';
    final bool consultActive = status == 'serving';
    final bool allDone = status == 'completed';

    // Step states:
    // Step 0: Ticket (Issued) -> Always completed for an active ticket
    // Step 1: Vitals (Nurse)  -> Completed ONLY when vitals are recorded or consultation started
    // Step 2: Consult (Doctor)-> Completed ONLY when consultation finishes
    // Step 3: Done (Rx/Exit)  -> Completed when ticket is marked completed
    final stepStates = [
      {
        'label': 'Ticket',
        'desc': 'Issued',
        'icon': Icons.confirmation_number_outlined,
        'isDone': true,
        'isCurrent': !vitalsActive && !vitalsDone && status == 'waiting',
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
        'desc': consultDone ? 'Completed' : (consultActive ? 'Serving' : (vitalsDone ? 'Waiting Dr.' : 'Queueing')),
        'icon': Icons.medical_services_outlined,
        'isDone': consultDone,
        'isCurrent': consultActive,
      },
      {
        'label': 'Done',
        'desc': allDone ? 'Finished' : 'Rx / Exit',
        'icon': Icons.task_alt_rounded,
        'isDone': allDone,
        'isCurrent': false,
      },
    ];

    String stepBadgeText = 'Step 1 of 4';
    if (allDone) {
      stepBadgeText = 'Step 4 of 4 (Complete)';
    } else if (consultActive) {
      stepBadgeText = 'Step 3 of 4 (Consultation)';
    } else if (vitalsDone) {
      stepBadgeText = 'Step 2 of 4 (Vitals Taken)';
    } else if (vitalsActive) {
      stepBadgeText = 'Step 2 of 4 (On Call)';
    } else {
      stepBadgeText = 'Step 1 of 4 (Ticket Issued)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.fieldBorder, width: 1.2),
        boxShadow: const [
          BoxShadow(color: _C.shadow, blurRadius: 14, offset: Offset(0, 4)),
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
                    color: _C.primaryMid.withOpacity(0.08),
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
          Row(
            children: List.generate(stepStates.length, (i) {
              final item = stepStates[i];
              final bool isDone = item['isDone'] as bool;
              final bool isCurrent = item['isCurrent'] as bool;
              final Color stepColor = isDone
                  ? _C.success
                  : (isCurrent
                      ? (vitalsActive ? _C.warning : _C.primaryMid)
                      : _C.textMuted.withOpacity(0.35));

              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? _C.success
                                  : (isCurrent
                                      ? stepColor.withOpacity(0.12)
                                      : Colors.grey.shade100),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCurrent ? stepColor : (isDone ? _C.success : Colors.grey.shade300),
                                width: isCurrent ? 2 : 1.2,
                              ),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                        color: stepColor.withOpacity(0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Icon(
                              isDone ? Icons.check_rounded : (item['icon'] as IconData),
                              size: isDone ? 18 : 16,
                              color: isDone ? Colors.white : stepColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: (isCurrent || isDone) ? FontWeight.w800 : FontWeight.w600,
                              color: isDone ? _C.textDark : (isCurrent ? _C.textDark : _C.textMuted),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            item['desc'] as String,
                            style: TextStyle(
                              fontSize: 8,
                              color: isCurrent ? stepColor : (isDone ? _C.success : _C.textMuted.withOpacity(0.7)),
                              fontWeight: (isCurrent || isDone) ? FontWeight.w700 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (i < stepStates.length - 1)
                      Container(
                        width: 14,
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 24),
                        color: (i == 0 && vitalsDone) ||
                               (i == 1 && consultDone) ||
                               (i == 2 && allDone)
                            ? _C.success
                            : Colors.grey.shade300,
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
