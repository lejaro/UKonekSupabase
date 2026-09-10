import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

typedef _C = AppColors;

/// Modal dialog shown to citizen when their consultation has been completed by clinic staff.
class ConsultationCompletedDialog extends StatelessWidget {
  final String serviceLabel;
  final int queueNumber;
  final String ticketCode;
  final VoidCallback onReturnToMainMenu;

  const ConsultationCompletedDialog({
    super.key,
    required this.serviceLabel,
    required this.queueNumber,
    required this.ticketCode,
    required this.onReturnToMainMenu,
  });

  /// Displays the consultation completion celebration modal.
  static Future<void> show({
    required BuildContext context,
    required String serviceLabel,
    required int queueNumber,
    required String ticketCode,
    required VoidCallback onReturnToMainMenu,
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
            child: ConsultationCompletedDialog(
              serviceLabel: serviceLabel,
              queueNumber: queueNumber,
              ticketCode: ticketCode,
              onReturnToMainMenu: () {
                Navigator.of(dialogCtx).pop();
                onReturnToMainMenu();
              },
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
            color: _C.primaryMid.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated celebratory green icon
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _C.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFA7F3D0), width: 2),
            ),
            child: const Center(
              child: Icon(
                Icons.check_circle_rounded,
                color: _C.primary,
                size: 46,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title
          const Text(
            'Consultation Done!',
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
            'Your consultation has been successfully completed by the clinic doctor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _C.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FCF9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E9E3)),
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
                    Text(
                      serviceLabel,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _C.textDark),
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
                          color: _C.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${queueNumber.toString().padLeft(3, '0')}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _C.primaryMid),
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
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'COMPLETED',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Health records note
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: _C.primaryMid),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prescriptions and instructions have been updated in your records.',
                  style: TextStyle(fontSize: 11.5, color: _C.textMuted, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Primary Button -> Return to Main Menu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onReturnToMainMenu,
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.home_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Back to Main Menu',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
