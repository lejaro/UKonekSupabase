import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../core/theme/app_colors.dart';

typedef _C = AppColors;

/// Modular searchable service picker card and bottom sheet modal for queue joining.
class QueueServicePicker extends StatelessWidget {
  final List<QueueServiceOption> services;
  final QueueServiceOption? selectedService;
  final ValueChanged<QueueServiceOption> onSelected;

  const QueueServicePicker({
    super.key,
    required this.services,
    required this.selectedService,
    required this.onSelected,
  });

  void _showModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ServiceSearchSheet(
        services: services,
        onSelected: (svc) {
          onSelected(svc);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showModal(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.fieldBorder),
          boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.medical_services_outlined, size: 16, color: _C.primaryMid),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedService?.serviceLabel ?? 'Choose a healthcare service',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selectedService != null ? FontWeight.w600 : FontWeight.normal,
                  color: selectedService != null ? _C.textDark : _C.textMuted.withOpacity(0.6),
                ),
              ),
            ),
            const Icon(Icons.search_rounded, color: _C.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ServiceSearchSheet extends StatefulWidget {
  final List<QueueServiceOption> services;
  final ValueChanged<QueueServiceOption> onSelected;

  const _ServiceSearchSheet({
    required this.services,
    required this.onSelected,
  });

  @override
  State<_ServiceSearchSheet> createState() => _ServiceSearchSheetState();
}

class _ServiceSearchSheetState extends State<_ServiceSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<QueueServiceOption> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.services;
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.services;
      } else {
        _filtered = widget.services.where((s) => s.serviceLabel.toLowerCase().contains(query)).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;

    return Container(
      height: mq.size.height * 0.7 + bottomInset,
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: _C.divider, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Healthcare Service',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _C.textDark),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search service name...',
              hintStyle: TextStyle(color: _C.textMuted.withOpacity(0.6), fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: _C.primaryMid),
              filled: true,
              fillColor: _C.bg,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching services found.',
                      style: TextStyle(color: _C.textMuted.withOpacity(0.8), fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1, color: _C.divider),
                    itemBuilder: (ctx, i) {
                      final svc = _filtered[i];
                      return ListTile(
                        onTap: () => widget.onSelected(svc),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _C.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.medical_services_outlined, size: 18, color: _C.primaryMid),
                        ),
                        title: Text(
                          svc.serviceLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _C.textDark),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: _C.textMuted, size: 20),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
