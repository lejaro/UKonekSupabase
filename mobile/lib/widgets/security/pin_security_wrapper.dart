import 'package:flutter/material.dart';
import '../../core/security/pin_security_service.dart';
import '../../core/session/patient_session.dart';
import 'pin_lock_screen.dart';

/// Top-level app wrapper that intercepts lifecycle events to auto-lock the screen
/// and overlays [PinLockScreen] when PIN security is triggered.
class PinSecurityWrapper extends StatefulWidget {
  final Widget? child;

  const PinSecurityWrapper({super.key, required this.child});

  @override
  State<PinSecurityWrapper> createState() => _PinSecurityWrapperState();
}

class _PinSecurityWrapperState extends State<PinSecurityWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PinSecurityService.instance.handleLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PinSecurityService.instance.isLockedNotifier,
      builder: (context, isLocked, _) {
        final content = widget.child ?? const SizedBox.shrink();

        // Only enforce PIN lock if an authenticated patient session is active
        final hasSession = PatientSessionState.session != null;
        if (!isLocked || !hasSession) {
          return content;
        }

        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            // Underlying application content (preserved in memory)
            content,
            // Security overlay
            const Positioned.fill(
              child: PinLockScreen(),
            ),
          ],
        );
      },
    );
  }
}
