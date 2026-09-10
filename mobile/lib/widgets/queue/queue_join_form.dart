import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/queue_ticket.dart';
import 'queue_service_picker.dart';

typedef _C = AppColors;

/// Form component for selecting healthcare service, priority category, entering visit details,
/// checking clinic queue limiter thresholds, and requesting a queue ticket.
class QueueJoinForm extends StatelessWidget {
  final Future<List<QueueServiceOption>> servicesFuture;
  final Future<QueueLimiterStatus> limiterStatusFuture;
  final QueueServiceOption? selectedService;
  final ValueChanged<QueueServiceOption?> onServiceSelected;
  final String citizenType;
  final ValueChanged<String> onCitizenTypeChanged;
  final TextEditingController reasonController;
  final TextEditingController symptomsController;
  final bool isSubmitting;
  final VoidCallback onJoin;

  const QueueJoinForm({
    super.key,
    required this.servicesFuture,
    required this.limiterStatusFuture,
    required this.selectedService,
    required this.onServiceSelected,
    required this.citizenType,
    required this.onCitizenTypeChanged,
    required this.reasonController,
    required this.symptomsController,
    required this.isSubmitting,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QueueServiceOption>>(
      future: servicesFuture,
      builder: (context, snapshot) {
        final services = snapshot.data ?? [];
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info strip ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _C.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.primary.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: _C.primaryMid, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Fill in your visit details below to get a queue number.',
                        style: TextStyle(fontSize: 12, color: _C.primaryMid, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Queue Limiter Status ────────────────────────────
              FutureBuilder<QueueLimiterStatus>(
                future: limiterStatusFuture,
                builder: (context, limiterSnapshot) {
                  final limiterStatus = limiterSnapshot.data;
                  if (limiterStatus == null) {
                    return const SizedBox.shrink();
                  }

                  // Show limit reached warning
                  if (limiterStatus.limitReached) {
                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDC2626),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.event_busy_rounded, color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Consultations Full',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF991B1B),
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Daily limit reached',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF991B1B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'We\'ve reached our daily consultation limit of ${limiterStatus.dailyLimit} patients for today due to high demand.',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF991B1B),
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'What you can do:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _buildLimiterTip(Icons.schedule_rounded, 'Try again tomorrow when slots reset'),
                                    _buildLimiterTip(Icons.phone_rounded, 'Call the clinic for scheduling assistance'),
                                    _buildLimiterTip(Icons.emergency_rounded, 'For emergencies, visit immediately'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }

                  // Show remaining slots info
                  if (limiterStatus.remainingSlots <= 5) {
                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF9C3),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFDE047)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFF854D0E), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Only ${limiterStatus.remainingSlots} consultation slots remaining today!',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF854D0E),
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }

                  // Show available slots info
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF166534), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${limiterStatus.remainingSlots} of ${limiterStatus.dailyLimit} consultation slots available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),

              _sectionLabel('HEALTHCARE SERVICE', Icons.medical_services_outlined),
              const SizedBox(height: 12),
              QueueServicePicker(
                services: services,
                selectedService: selectedService,
                onSelected: onServiceSelected,
              ),
              const SizedBox(height: 24),

              // ── Priority category ───────────────────────────────
              _sectionLabel('PRIORITY CATEGORY', Icons.accessibility_new_rounded),
              const SizedBox(height: 12),
              _buildTypeSelector(),
              const SizedBox(height: 24),

              // ── Medical details ─────────────────────────────────
              _sectionLabel('MEDICAL DETAILS', Icons.description_outlined),
              const SizedBox(height: 12),
              _buildTextField(reasonController, 'Reason for Visit *', 'e.g. Fever, headache, follow-up checkup...', 2, Icons.edit_note_rounded),
              const SizedBox(height: 12),
              _buildTextField(symptomsController, 'Symptoms (Optional)', 'Describe your symptoms if any...', 3, Icons.sick_outlined),
              const SizedBox(height: 32),

              // ── Submit button ───────────────────────────────────
              FutureBuilder<QueueLimiterStatus>(
                future: limiterStatusFuture,
                builder: (context, limiterSnapshot) {
                  final limiterStatus = limiterSnapshot.data;
                  final isLimitReached = limiterStatus?.limitReached ?? false;
                  final isDisabled = isSubmitting || isLimitReached;

                  return SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isDisabled ? null : onJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDisabled ? Colors.grey : _C.primary,
                        foregroundColor: Colors.white,
                        elevation: isDisabled ? 0 : 4,
                        shadowColor: _C.primary.withOpacity(0.35),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                      ),
                      child: isSubmitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(isLimitReached ? Icons.block_rounded : Icons.confirmation_number_rounded, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  isLimitReached ? 'LIMIT REACHED' : 'GET QUEUE NUMBER',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeSelector() {
    final types = [
      {'key': 'regular', 'label': 'Regular', 'icon': Icons.person_outline_rounded, 'desc': 'Standard'},
      {'key': 'pwd', 'label': 'PWD', 'icon': Icons.accessible_rounded, 'desc': 'Priority'},
      {'key': 'pregnant', 'label': 'Pregnant', 'icon': Icons.pregnant_woman_rounded, 'desc': 'Priority'},
    ];
    return Row(
      children: types.map((t) {
        final isSelected = citizenType == t['key'];
        return Expanded(
          child: GestureDetector(
            onTap: () => onCitizenTypeChanged(t['key'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? _C.primary : _C.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSelected ? _C.primary : _C.fieldBorder, width: isSelected ? 2 : 1),
                boxShadow: isSelected
                    ? [BoxShadow(color: _C.primary.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))]
                    : [const BoxShadow(color: _C.shadow, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Icon(t['icon'] as IconData, color: isSelected ? Colors.white : _C.textMuted, size: 22),
                  const SizedBox(height: 6),
                  Text(t['label'] as String, style: TextStyle(color: isSelected ? Colors.white : _C.textDark, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(t['desc'] as String, style: TextStyle(color: isSelected ? Colors.white70 : _C.textMuted, fontSize: 9)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, String hint, int maxLines, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.fieldBorder),
        boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, color: _C.textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(fontSize: 13, color: _C.textMuted),
          hintStyle: TextStyle(fontSize: 13, color: _C.textMuted.withOpacity(0.5)),
          prefixIcon: Padding(
            padding: EdgeInsets.only(bottom: maxLines > 1 ? 40 : 0),
            child: Icon(icon, color: _C.primary.withOpacity(0.6), size: 20),
          ),
          filled: true,
          fillColor: _C.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: _C.primaryMid, size: 14),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _C.textMuted, letterSpacing: 1.1)),
      ],
    );
  }

  Widget _buildLimiterTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF991B1B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF991B1B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
