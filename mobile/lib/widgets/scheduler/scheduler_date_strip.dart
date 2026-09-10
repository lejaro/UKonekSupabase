import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../core/theme/app_colors.dart';

typedef _C = AppColors;

/// Horizontal calendar date selector strip with auto-scrolling and medication/followup badges.
class SchedulerDateStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final List<ScheduledMedicine> medicines;
  final List<Consultation> consultations;
  final ScrollController? scrollController;

  const SchedulerDateStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.medicines = const [],
    this.consultations = const [],
    this.scrollController,
  });

  @override
  State<SchedulerDateStrip> createState() => _SchedulerDateStripState();
}

class _SchedulerDateStripState extends State<SchedulerDateStrip> {
  late ScrollController _scrollController;
  bool _internalController = false;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _internalController = true;
    }
  }

  @override
  void dispose() {
    if (_internalController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _scrollToSelectedDate(List<DateTime> dates) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final index = dates.indexWhere((d) => DateUtils.isSameDay(d, widget.selectedDate));
      if (index != -1) {
        // item width = 60 + 12 margin = 72
        final targetOffset = (index * 72.0) - 100.0;
        final clampedOffset = targetOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime minDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 3)); // Show 3 days past
    DateTime maxDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));   // Show 14 days future

    // Smart adjustment based on actual prescriptions
    if (widget.medicines.isNotEmpty) {
      for (var m in widget.medicines) {
        final start = DateTime(m.startDate.year, m.startDate.month, m.startDate.day);
        final end   = DateTime(m.endDate.year, m.endDate.month, m.endDate.day);
        if (start.isBefore(minDate)) minDate = start;
        if (end.isAfter(maxDate)) maxDate = end;
      }
    }

    // Sanity check for range (max 60 days to prevent performance issues)
    if (maxDate.difference(minDate).inDays > 60) {
      maxDate = minDate.add(const Duration(days: 60));
    }

    final daysCount = maxDate.difference(minDate).inDays + 1;
    final List<DateTime> dates = List.generate(daysCount, (index) => minDate.add(Duration(days: index)));

    _scrollToSelectedDate(dates);

    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = DateUtils.isSameDay(date, widget.selectedDate);
          final isToday = DateUtils.isSameDay(date, now);

          bool isStart = false;
          bool isFinal = false;
          bool isOngoing = false;
          for (var m in widget.medicines) {
            final start = DateTime(m.startDate.year, m.startDate.month, m.startDate.day);
            final end   = DateTime(m.endDate.year, m.endDate.month, m.endDate.day);
            if (DateUtils.isSameDay(date, start)) {
              isStart = true;
            } else if (DateUtils.isSameDay(date, end)) {
              isFinal = true;
            } else if (date.isAfter(start) && date.isBefore(end)) {
              isOngoing = true;
            }
          }

          bool hasFollowup = false;
          for (var c in widget.consultations) {
            if (c.followupDate != null && DateUtils.isSameDay(date, c.followupDate!)) {
              hasFollowup = true;
              break;
            }
          }

          return GestureDetector(
            onTap: () => widget.onDateSelected(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? _C.primary : (isToday ? _C.primary.withOpacity(0.08) : Colors.white),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isSelected ? _C.primary : _C.fieldBdr.withOpacity(0.6)),
                boxShadow: isSelected ? [BoxShadow(color: _C.primary.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))] : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date).toUpperCase(), 
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, 
                    color: isSelected ? Colors.white.withOpacity(0.8) : _C.textMuted, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(date.day.toString(), 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, 
                    color: isSelected ? Colors.white : _C.textDark)),
                  if (isToday && !isSelected && !isStart && !isFinal && !isOngoing && !hasFollowup) 
                    Container(margin: const EdgeInsets.only(top: 4), width: 4, height: 4, 
                      decoration: const BoxDecoration(color: _C.primary, shape: BoxShape.circle)),
                  if (hasFollowup)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white24 : Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FOLLOW UP',
                        style: TextStyle(
                          fontSize: 7, 
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.teal.shade800,
                          letterSpacing: 0.1,
                        ),
                      ),
                    )
                  else if (isStart || isFinal || isOngoing)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white24 : (isStart ? Colors.green.shade100 : (isFinal ? Colors.red.shade100 : Colors.blue.shade50)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isStart ? 'START' : (isFinal ? 'FINAL' : 'MEDS'),
                        style: TextStyle(
                          fontSize: 8, 
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : (isStart ? Colors.green.shade800 : (isFinal ? Colors.red.shade800 : Colors.blue.shade800)),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
