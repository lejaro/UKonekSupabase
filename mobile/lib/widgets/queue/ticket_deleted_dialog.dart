import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

typedef _C = AppColors;

/// Modal dialog presented to a citizen when their active queue ticket is deleted
/// or cancelled by clinic staff.
class TicketDeletedDialog extends StatelessWidget {
  final String serviceLabel;
  final int queueNumber;
  final String ticketCode;
  final VoidCallback onDismiss;
  final VoidCallback? onRejoin;

  const TicketDeletedDialog({
    super.key,
    required this.serviceLabel,
    required this.queueNumber,
    required this.ticketCode,
    required this.onDismiss,
    this.onRejoin,
  });

  /// Displays the ticket deleted / cancelled modal.
  static Future<void> show({
    required BuildContext context,
    required String serviceLabel,
    required int queueNumber,
    required String ticketCode,
    required VoidCallback onDismiss,
    VoidCallback? onRejoin,
  }) async {
    HapticFeedback.heavyImpact();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: TicketDeletedDialog(
              serviceLabel: serviceLabel,
              queueNumber: queueNumber,
              ticketCode: ticketCode,
              onDismiss: () {
                Navigator.of(dialogCtx).pop();
                onDismiss();
              },
              onRejoin: onRejoin != null
                  ? () {
                      Navigator.of(dialogCtx).pop();
                      onRejoin();
                    }
                  : null,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Warning/Alert icon container
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFECACA), width: 2),
            ),
            child: const Center(
              child: Icon(
                Icons.event_busy_rounded,
                color: Color(0xFFDC2626),
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title
          const Text(
            'Ticket Cancelled',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _C.textDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle
          const Text(
            'Your queue ticket has been removed or cancelled from the queue by the clinic staff.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _C.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Ticket Details Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Service',
                      style: TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600),
                    ),
                    Flexible(
                      child: Text(
                        serviceLabel.isNotEmpty ? serviceLabel : 'General Consultation',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _C.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (queueNumber > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Queue Number',
                        style: TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${queueNumber.toString().padLeft(3, '0')}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFC2410C)),
                        ),
                      ),
                    ],
                  ),
                ],
                if (ticketCode.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ticket Code',
                        style: TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        ticketCode,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          color: _C.textDark,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(fontSize: 12, color: _C.textMuted, fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'CANCELLED / REMOVED',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Reassurance Note
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'If you still require medical attention, you may join the queue again or speak directly with the triage nurse.',
                  style: TextStyle(fontSize: 11.5, color: _C.textMuted, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Actions
          if (onRejoin != null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRejoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Rejoin Queue',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: _C.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDismiss,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primaryMid,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'Understood',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
