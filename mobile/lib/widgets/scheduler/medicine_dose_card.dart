import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../models/scheduled_medicine.dart';

/// Card component representing a scheduled dose time slot with its associated medications,
/// status indicator pills, and intake confirmation actions.
class MedicineDoseCard extends StatelessWidget {
  final String time;
  final List<Map<String, dynamic>> items;
  final DateTime selectedDate;
  final bool Function(ScheduledMedicine med, int doseIndex, [String? timeStr]) isItemTaken;
  final Map<String, DateTime> takenTimestamps;
  final void Function(ScheduledMedicine med, int doseIndex, String time) onMarkAsTaken;
  final void Function(List<Map<String, dynamic>> items, String time) onMarkAllAsTaken;
  final void Function(ScheduledMedicine med, int doseIndex, TimeOfDay picked) onSetupAndMarkTaken;
  final void Function(ScheduledMedicine med, int doseIndex, String currentTime) onPickTime;
  final void Function(List<Map<String, dynamic>> items, String time) onTimeBoxTap;

  const MedicineDoseCard({
    super.key,
    required this.time,
    required this.items,
    required this.selectedDate,
    required this.isItemTaken,
    required this.takenTimestamps,
    required this.onMarkAsTaken,
    required this.onMarkAllAsTaken,
    required this.onSetupAndMarkTaken,
    required this.onPickTime,
    required this.onTimeBoxTap,
  });

  static int parseTime(String timeStr) {
    try {
      final match = RegExp(r'(\d+):(\d+)\s*(AM|PM|am|pm)', caseSensitive: false).firstMatch(timeStr);
      if (match != null) {
        int h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final period = match.group(3)!.toUpperCase();
        if (period == 'PM' && h != 12) h += 12;
        if (period == 'AM' && h == 12) h = 0;
        return (h % 24) * 60 + m;
      }
      final simpleMatch = RegExp(r'(\d+)\s*(AM|PM|am|pm|a\.m\.|p\.m\.)', caseSensitive: false).firstMatch(timeStr);
      if (simpleMatch != null) {
        int h = int.parse(simpleMatch.group(1)!);
        final period = simpleMatch.group(2)!.toUpperCase().replaceAll('.', '');
        if ((period == 'PM' || period == 'P') && h != 12) h += 12;
        if ((period == 'AM' || period == 'A') && h == 12) h = 0;
        return (h % 24) * 60;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  String _getIntakeStatus({
    required String timeStr,
    required bool allTaken,
    required bool isToday,
    required bool isFuture,
    required bool isPast,
    required int nowMins,
  }) {
    if (allTaken) return 'TAKEN';
    if (isFuture) return 'UPCOMING';
    if (isPast) return 'LATE';

    int tMins = parseTime(timeStr);
    if (tMins == 0 && (timeStr.startsWith('12') || timeStr.contains('12:00'))) {
      tMins = 1440;
    }

    int diff;
    if (tMins == 1440 && nowMins < 240) {
      diff = 1440 - (1440 + nowMins);
    } else {
      diff = tMins - nowMins;
    }

    if (diff <= 30 && diff >= -120) {
      return 'DUE';
    } else if (diff > 30) {
      return 'UPCOMING';
    } else {
      return 'LATE';
    }
  }

  String _formatDuration(String duration) {
    final d = duration.trim();
    if (d.isEmpty) return '';
    if (RegExp(r'^\d+$').hasMatch(d)) {
      return '$d ${int.tryParse(d) == 1 ? "day" : "days"}';
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Setup Required Slot
    if (time == 'Setup Required') {
      return Column(
        children: items.map((item) {
          final med = item['med'] as ScheduledMedicine;
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'First-time Setup Required',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF856404),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Please enter the time when you first took ${med.medicineName} today. This will be used to automatically organize your next medication schedules and reminders.',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF856404), height: 1.5),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => onSetupAndMarkTaken(med, 0, TimeOfDay.now()),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('Current Time'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked != null) {
                            onSetupAndMarkTaken(med, 0, picked);
                          }
                        },
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: const Text('Pick Time'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    // 2. PRN (As-needed) Slot
    if (time == 'As Needed') {
      final isToday = DateUtils.isSameDay(selectedDate, DateTime.now());
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.teal.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                  child: const Icon(Icons.medication_liquid_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  'Take as needed (PRN)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal.shade800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final med = item['med'] as ScheduledMedicine;
              final prnKeys = takenTimestamps.keys
                  .where((k) => k.startsWith('${med.prescriptionItemId}_'))
                  .toList()
                ..sort((a, b) {
                  final tA = takenTimestamps[a] ?? DateTime(2000);
                  final tB = takenTimestamps[b] ?? DateTime(2000);
                  return tA.compareTo(tB);
                });
              final takenCount = prnKeys.length;
              final hasTakenAny = takenCount > 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.medication_rounded,
                          color: hasTakenAny ? AppColors.primary : Colors.teal.shade400,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                med.medicineName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: hasTakenAny ? AppColors.primaryMid : AppColors.textDark,
                                ),
                              ),
                              if (med.dosage.isNotEmpty)
                                Text(med.dosage, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              if (med.instructions.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    med.instructions,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textMuted.withOpacity(0.8),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isToday)
                          ElevatedButton.icon(
                            onPressed: () => onMarkAsTaken(med, takenCount, 'PRN'),
                            icon: Icon(hasTakenAny ? Icons.add_rounded : Icons.check_rounded, size: 16),
                            label: Text(
                              hasTakenAny ? '+ Take another' : 'Take dose',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),
                    if (hasTakenAny) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: prnKeys.map((k) {
                            final dt = takenTimestamps[k];
                            final timeStr = dt != null ? DateFormat('h:mm a').format(dt) : 'Taken';
                            final doseIdx = int.tryParse(k.split('_')[1]) ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.primaryMid),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Dose ${doseIdx + 1}: $timeStr',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryMid),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    // 3. Standard Time Slot
    final allTaken = items.every((i) => isItemTaken(i['med'] as ScheduledMedicine, i['doseIndex'] as int, time));
    final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
    final isToday = DateUtils.isSameDay(selectedDate, DateTime.now());
    final isFuture = selectedDate.isAfter(DateTime.now()) && !isToday;
    final isPast = selectedDate.isBefore(DateTime.now()) && !isToday;

    final bool isLocked = isFuture;
    final status = _getIntakeStatus(
      timeStr: time,
      allTaken: allTaken,
      isToday: isToday,
      isFuture: isFuture,
      isPast: isPast,
      nowMins: nowMins,
    );

    Color statusColor;
    if (status == 'TAKEN') {
      statusColor = AppColors.primary;
    } else if (status == 'DUE') {
      statusColor = AppColors.primary;
    } else if (status == 'UPCOMING') {
      statusColor = const Color(0xFF007BFF);
    } else {
      statusColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: (allTaken || isLocked) ? null : () => onTimeBoxTap(items, time),
              child: Container(
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: allTaken ? AppColors.primary.withOpacity(0.05) : (isLocked ? AppColors.bg : Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: allTaken
                        ? AppColors.primary.withOpacity(0.1)
                        : (isLocked ? AppColors.fieldBdr.withOpacity(0.3) : AppColors.fieldBdr.withOpacity(0.5)),
                  ),
                ),
                child: Builder(
                  builder: (_) {
                    final timeParts = time.trim().split(' ');
                    final timeMain = timeParts.isNotEmpty ? timeParts[0] : time;
                    final timePeriod = timeParts.length > 1 ? timeParts[1] : '';
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeMain,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: allTaken ? AppColors.primary : (isLocked ? AppColors.textMuted : AppColors.textDark),
                          ),
                        ),
                        if (timePeriod.isNotEmpty)
                          Text(
                            timePeriod,
                            style: TextStyle(fontSize: 10, color: allTaken ? AppColors.primary : AppColors.textMuted),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textDark.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (items.any((it) => it['isShifted'] == true))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFFCC80), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.sync_rounded, size: 11, color: Color(0xFFE65100)),
                                SizedBox(width: 3),
                                Text(
                                  'Shifted',
                                  style: TextStyle(
                                    color: Color(0xFFE65100),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...items.map((item) {
                      final med = item['med'] as ScheduledMedicine;
                      final key = '${med.prescriptionItemId}_${item['doseIndex']}';
                      final timeKey = '${med.prescriptionItemId}_$time';
                      final taken = isItemTaken(med, item['doseIndex'] as int, time);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.medication_rounded,
                              color: taken
                                  ? AppColors.primary
                                  : (isLocked ? AppColors.textMuted.withOpacity(0.2) : AppColors.textMuted.withOpacity(0.4)),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    med.medicineName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: taken
                                          ? AppColors.primary.withOpacity(0.6)
                                          : (isLocked ? AppColors.textMuted : AppColors.textDark),
                                    ),
                                  ),
                                  if (med.dosage.isNotEmpty)
                                    Text(med.dosage, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  if (!taken && med.duration.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Duration: ${_formatDuration(med.duration)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isLocked ? AppColors.textMuted.withOpacity(0.4) : AppColors.primary.withOpacity(0.7),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  if (!taken && med.instructions.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        med.instructions,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textMuted.withOpacity(0.8),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (!taken && items.length > 1)
                              IconButton(
                                onPressed: isLocked
                                    ? null
                                    : () => onPickTime(med, item['doseIndex'] as int, item['time'] as String? ?? time),
                                icon: const Icon(Icons.edit_calendar_rounded, size: 18, color: AppColors.textMuted),
                                tooltip: 'Adjust time for ${med.medicineName}',
                              ),
                            if (!taken)
                              IconButton(
                                onPressed: isLocked ? null : () => onMarkAsTaken(med, item['doseIndex'] as int, time),
                                icon: Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: isLocked ? AppColors.textMuted.withOpacity(0.2) : AppColors.primary,
                                  size: 22,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              )
                            else
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                                  if (takenTimestamps.containsKey(key) || takenTimestamps.containsKey(timeKey))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        DateFormat('h:mm a').format(takenTimestamps[key] ?? takenTimestamps[timeKey]!),
                                        style: const TextStyle(fontSize: 8, color: AppColors.primary, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }),
                    if (!allTaken && items.length > 1) ...[
                      const Divider(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: isLocked ? null : () => onMarkAllAsTaken(items, time),
                          child: Text(
                            'Mark all as taken',
                            style: TextStyle(
                              color: isLocked ? AppColors.textMuted.withOpacity(0.3) : AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
