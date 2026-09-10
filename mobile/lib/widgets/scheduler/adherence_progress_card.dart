import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Card widget showing the patient's daily medication adherence completion ring & motivational badge.
class AdherenceProgressCard extends StatelessWidget {
  final double completion;

  const AdherenceProgressCard({
    super.key,
    required this.completion,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = completion.clamp(0.0, 1.0);
    final isFull = clamped >= 1.0;
    final isHalf = clamped >= 0.5;
    final Color progressColor = isFull
        ? AppColors.primary
        : (isHalf ? const Color(0xFF00897B) : const Color(0xFF1976D2));
    final String statusBadge = isFull
        ? '🎉 100% COMPLETE'
        : (isHalf ? '⚡ IN PROGRESS' : '📋 TO DO');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: progressColor.withOpacity(0.2), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1B2E1E),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: progressColor.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFull ? Icons.verified_rounded : Icons.pie_chart_rounded,
              color: progressColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: progressColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusBadge,
                    style: TextStyle(
                      color: progressColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isFull
                      ? "Fantastic! You've taken all your meds today."
                      : (isHalf
                          ? "Great job! You're halfway through today's doses."
                          : "Keep it up! Let's stay on schedule."),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: CircularProgressIndicator(
                      value: clamped,
                      strokeWidth: 7,
                      backgroundColor: Colors.grey.shade100,
                      color: progressColor,
                    ),
                  ),
                  Text(
                    '${(clamped * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: progressColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Daily Goal',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
