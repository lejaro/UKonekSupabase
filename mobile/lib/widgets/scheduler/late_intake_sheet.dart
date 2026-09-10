import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/scheduled_medicine.dart';

/// Modal bottom sheet displaying clinical late-intake warning & subsequent dose shifts.
class LateIntakeSheet {
  LateIntakeSheet._();

  static Future<bool?> show({
    required BuildContext context,
    required ScheduledMedicine med,
    required int takenDoseIndex,
    required int actualTakenMinutes,
    required List<int> scheduledMinutesList,
    required Map<int, int> shifts,
    required String Function(int) formatMinutes,
  }) {
    final scheduledMinutes = scheduledMinutesList[takenDoseIndex];
    final delay = actualTakenMinutes - scheduledMinutes;
    final delayStr = delay >= 60
        ? '${delay ~/ 60}h ${delay % 60 > 0 ? '${delay % 60}m' : ''}'
        : '${delay}m';

    final nextIndex = takenDoseIndex + 1;
    final nextOriginalTime = formatMinutes(scheduledMinutesList[nextIndex]);
    int currentGap = scheduledMinutesList[nextIndex] - actualTakenMinutes;
    if (currentGap < 0) currentGap = 0;
    final currentGapStr = currentGap >= 60
        ? '${currentGap ~/ 60}h ${currentGap % 60 > 0 ? '${currentGap % 60}m' : ''}'
        : '${currentGap}m';

    final safeGapMinutes = med.minSafeGapMinutes;
    final safeGapStr = safeGapMinutes >= 60
        ? '${safeGapMinutes ~/ 60}h ${safeGapMinutes % 60 > 0 ? '${safeGapMinutes % 60}m' : ''}'
        : '${safeGapMinutes}m';

    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.fieldBdr,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFFE65100),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Late Intake Detected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          med.medicineName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB78103)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dose logged $delayStr late',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Color(0xFF795548),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Taking your next dose at $nextOriginalTime would be only $currentGapStr later. A safe spacing of at least $safeGapStr is recommended to avoid taking doses too close together.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF5D4037),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Suggested Today's Schedule:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.fieldBdr),
                ),
                child: Column(
                  children: shifts.entries.map((entry) {
                    final dIdx = entry.key;
                    final oldTime = formatMinutes(scheduledMinutesList[dIdx]);
                    final newTime = formatMinutes(entry.value);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            'Dose ${dIdx + 1}:',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            oldTime,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted.withOpacity(0.8),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              newTime,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lock_reset_rounded, size: 14, color: AppColors.textMuted.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'Applies today only. Tomorrow resets to standard times.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted.withOpacity(0.8)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Adjust Today's Schedule",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Keep Original Schedule',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
