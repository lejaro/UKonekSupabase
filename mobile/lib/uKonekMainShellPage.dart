import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'uKonekDashboardPage.dart';
import 'uKonekMedicineScheduler.dart';
import 'uKonekJoinQueuePage.dart';
import 'uKonekProfilePage.dart';

/// Unified persistent App Shell for uKonek.
/// Hosts Dashboard, Medicine Scheduler, Queue, and Profile tabs without route pushing.
class uKonekMainShellPage extends StatefulWidget {
  final String username;
  final String citizenId;
  final String fullname;
  final String email;
  final String phone;
  final String address;
  final int initialTab;

  const uKonekMainShellPage({
    super.key,
    required this.username,
    required this.citizenId,
    this.fullname = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.initialTab = 0,
  });

  /// Helper to allow child widgets to switch tabs in the shell
  static void switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_uKonekMainShellPageState>();
    state?.selectTab(index);
  }

  @override
  State<uKonekMainShellPage> createState() => _uKonekMainShellPageState();
}

class _uKonekMainShellPageState extends State<uKonekMainShellPage> {
  static const Color _primary = Color(0xFF28A745);
  static const Color _primaryMid = Color(0xFF1B5E20);
  static const Color _textDark = Color(0xFF1B2E1E);
  static const Color _shadow = Color(0x0D1B2E1E);

  late int _selectedTab;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;

    _pages = [
      uKonekDashboardPage(
        username: widget.username,
        citizenId: widget.citizenId,
        fullname: widget.fullname,
        email: widget.email,
        phone: widget.phone,
        address: widget.address,
        isEmbeddedInShell: true,
      ),
      uKonekMedicineSchedulerPage(
        username: widget.username,
        citizenId: widget.citizenId,
        isEmbeddedInShell: true,
      ),
      uKonekJoinQueuePage(
        username: widget.username,
        citizenId: widget.citizenId,
        isEmbeddedInShell: true,
      ),
      uKonekProfilePage(
        username: widget.username,
        citizenId: widget.citizenId,
        fullName: widget.fullname.isNotEmpty ? widget.fullname : widget.username,
        email: widget.email,
        phone: widget.phone,
        address: widget.address,
        isEmbeddedInShell: true,
      ),
    ];
  }

  void selectTab(int index) {
    if (index == _selectedTab) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTab = index;
    });
  }

  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedTab != 0) {
          selectTab(0);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Press back again to exit'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: _textDark,
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedTab,
          children: _pages,
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.event_note_rounded, 'label': 'Medicine'},
      {'icon': Icons.confirmation_number_rounded, 'label': 'Queue'},
      {'icon': Icons.person_outline_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: _shadow,
            blurRadius: 20,
            offset: Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = _selectedTab == i;
              return GestureDetector(
                onTap: () => selectTab(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _primaryMid.withOpacity(0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i]['icon'] as IconData,
                        color: isSelected ? _primaryMid : Colors.grey.shade400,
                        size: 22,
                      ),
                      if (isSelected) ...[
                        const SizedBox(height: 4),
                        Text(
                          tabs[i]['label'] as String,
                          style: const TextStyle(
                            color: _primaryMid,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
