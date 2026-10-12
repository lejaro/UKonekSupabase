import 'package:flutter/material.dart';
import '../../core/security/pin_security_service.dart';
import 'pin_pad.dart';

enum PinSetupStep {
  create,
  confirm,
  verifyCurrentForChange,
  verifyCurrentForRemove,
  createNewAfterVerify,
  confirmNewAfterVerify,
}

/// Bottom sheet dialog to create, change, or remove the 4-digit security PIN.
class PinSetupSheet extends StatefulWidget {
  final VoidCallback? onPinChanged;

  const PinSetupSheet({super.key, this.onPinChanged});

  static Future<void> show(BuildContext context, {VoidCallback? onPinChanged}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PinSetupSheet(onPinChanged: onPinChanged),
    );
  }

  @override
  State<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<PinSetupSheet> {
  final GlobalKey<PinPadState> _pinPadKey = GlobalKey<PinPadState>();

  bool _isLoading = true;
  bool _isConfigured = false;

  PinSetupStep _currentStep = PinSetupStep.create;
  String _firstEnteredPin = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final configured = await PinSecurityService.instance.isPinConfigured();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isConfigured = configured;
      _currentStep = configured ? PinSetupStep.verifyCurrentForChange : PinSetupStep.create;
    });
  }

  void _onPinComplete(String pin) async {
    switch (_currentStep) {
      case PinSetupStep.create:
        setState(() {
          _firstEnteredPin = pin;
          _currentStep = PinSetupStep.confirm;
          _errorMessage = null;
        });
        _pinPadKey.currentState?.clear();
        break;

      case PinSetupStep.confirm:
        if (pin == _firstEnteredPin) {
          await PinSecurityService.instance.setPin(pin: pin);
          if (!mounted) return;
          widget.onPinChanged?.call();
          Navigator.pop(context);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text('4-Digit Security PIN set successfully!'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'PINs did not match. Please try again.';
            _currentStep = PinSetupStep.create;
            _firstEnteredPin = '';
          });
          _pinPadKey.currentState?.triggerShake();
        }
        break;

      case PinSetupStep.verifyCurrentForChange:
        final verified = await PinSecurityService.instance.verifyPin(pin: pin);
        if (!mounted) return;
        if (verified) {
          setState(() {
            _currentStep = PinSetupStep.createNewAfterVerify;
            _errorMessage = null;
          });
          _pinPadKey.currentState?.clear();
        } else {
          setState(() => _errorMessage = 'Incorrect current PIN.');
          _pinPadKey.currentState?.triggerShake();
        }
        break;

      case PinSetupStep.verifyCurrentForRemove:
        final verified = await PinSecurityService.instance.verifyPin(pin: pin);
        if (!mounted) return;
        if (verified) {
          await PinSecurityService.instance.removePin();
          if (!mounted) return;
          widget.onPinChanged?.call();
          Navigator.pop(context);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text('Security PIN removed.'),
              backgroundColor: const Color(0xFF64748B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          setState(() => _errorMessage = 'Incorrect current PIN.');
          _pinPadKey.currentState?.triggerShake();
        }
        break;

      case PinSetupStep.createNewAfterVerify:
        setState(() {
          _firstEnteredPin = pin;
          _currentStep = PinSetupStep.confirmNewAfterVerify;
          _errorMessage = null;
        });
        _pinPadKey.currentState?.clear();
        break;

      case PinSetupStep.confirmNewAfterVerify:
        if (pin == _firstEnteredPin) {
          await PinSecurityService.instance.setPin(pin: pin);
          if (!mounted) return;
          widget.onPinChanged?.call();
          Navigator.pop(context);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text('4-Digit Security PIN updated successfully!'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'PINs did not match. Try again.';
            _currentStep = PinSetupStep.createNewAfterVerify;
            _firstEnteredPin = '';
          });
          _pinPadKey.currentState?.triggerShake();
        }
        break;
    }
  }

  String _getTitle() {
    switch (_currentStep) {
      case PinSetupStep.create:
        return 'Create Security PIN';
      case PinSetupStep.confirm:
        return 'Confirm Your PIN';
      case PinSetupStep.verifyCurrentForChange:
        return 'Enter Current PIN';
      case PinSetupStep.verifyCurrentForRemove:
        return 'Verify Current PIN';
      case PinSetupStep.createNewAfterVerify:
        return 'Enter New PIN';
      case PinSetupStep.confirmNewAfterVerify:
        return 'Confirm New PIN';
    }
  }

  String _getSubtitle() {
    switch (_currentStep) {
      case PinSetupStep.create:
        return 'Enter a 4-digit PIN to secure your app';
      case PinSetupStep.confirm:
        return 'Re-enter your 4-digit PIN to confirm';
      case PinSetupStep.verifyCurrentForChange:
        return 'Enter your current PIN to change it';
      case PinSetupStep.verifyCurrentForRemove:
        return 'Enter current PIN to confirm removal';
      case PinSetupStep.createNewAfterVerify:
        return 'Choose a new 4-digit security PIN';
      case PinSetupStep.confirmNewAfterVerify:
        return 'Re-enter your new PIN to confirm';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF059669))),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              ),
              Text(
                _getTitle(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 48), // Spacer to balance close button
            ],
          ),

          Text(
            _getSubtitle(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),

          const SizedBox(height: 24),

          // Pin Pad
          PinPad(
            key: _pinPadKey,
            onPinComplete: _onPinComplete,
            errorMessage: _errorMessage,
          ),

          const SizedBox(height: 16),

          // Action buttons if already configured
          if (_isConfigured &&
              (_currentStep == PinSetupStep.verifyCurrentForChange ||
                  _currentStep == PinSetupStep.verifyCurrentForRemove)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_currentStep == PinSetupStep.verifyCurrentForChange)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentStep = PinSetupStep.verifyCurrentForRemove;
                        _errorMessage = null;
                      });
                      _pinPadKey.currentState?.clear();
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 18),
                    label: const Text('Remove PIN', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                  )
                else
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentStep = PinSetupStep.verifyCurrentForChange;
                        _errorMessage = null;
                      });
                      _pinPadKey.currentState?.clear();
                    },
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF64748B), size: 18),
                    label: const Text('Back to Change PIN', style: TextStyle(color: Color(0xFF64748B))),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
