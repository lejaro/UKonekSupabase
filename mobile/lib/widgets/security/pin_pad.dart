import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable 4-digit PIN Pad with dot indicators and numeric keypad.
class PinPad extends StatefulWidget {
  final ValueChanged<String> onPinComplete;
  final String? errorMessage;
  final bool isThrottled;
  final int throttleSeconds;

  const PinPad({
    super.key,
    required this.onPinComplete,
    this.errorMessage,
    this.isThrottled = false,
    this.throttleSeconds = 0,
  });

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  static const int _pinLength = 4;
  String _enteredPin = '';

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void triggerShake() {
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0.0).then((_) {
      _shakeController.reverse();
    });
    setState(() {
      _enteredPin = '';
    });
  }

  void clear() {
    setState(() {
      _enteredPin = '';
    });
  }

  void _onDigitPressed(String digit) {
    if (widget.isThrottled || _enteredPin.length >= _pinLength) return;

    HapticFeedback.lightImpact();
    final newPin = '$_enteredPin$digit';
    setState(() {
      _enteredPin = newPin;
    });

    if (newPin.length == _pinLength) {
      widget.onPinComplete(newPin);
    }
  }

  void _onBackspacePressed() {
    if (widget.isThrottled || _enteredPin.isEmpty) return;

    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 4 PIN Dots Indicator with Shake Animation ──
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            final offset = _shakeAnimation.value *
                (_shakeController.value < 0.5 ? 1 : -1);
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (index) {
              final isFilled = index < _enteredPin.length;
              final hasError = widget.errorMessage != null;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                width: isFilled ? 18 : 16,
                height: isFilled ? 18 : 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? (hasError ? const Color(0xFFDC2626) : const Color(0xFF059669))
                      : Colors.transparent,
                  border: Border.all(
                    color: hasError
                        ? const Color(0xFFDC2626)
                        : (isFilled ? const Color(0xFF059669) : const Color(0xFF94A3B8)),
                    width: 2.2,
                  ),
                  boxShadow: isFilled
                      ? [
                          BoxShadow(
                            color: (hasError
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF059669))
                                .withAlpha(60),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 18),

        // Error message / throttle notice
        if (widget.errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isThrottled
                    ? const Color(0xFFB45309)
                    : const Color(0xFFDC2626),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          const SizedBox(height: 18),

        const SizedBox(height: 24),

        // ── Numeric Keypad ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: [
              _buildRow(['1', '2', '3']),
              const SizedBox(height: 18),
              _buildRow(['4', '5', '6']),
              const SizedBox(height: 18),
              _buildRow(['7', '8', '9']),
              const SizedBox(height: 18),
              _buildBottomRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((digit) => _buildKeyButton(digit)).toList(),
    );
  }

  Widget _buildBottomRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Left spacer or clear button
        SizedBox(
          width: 68,
          height: 68,
          child: _enteredPin.isNotEmpty
              ? TextButton(
                  onPressed: clear,
                  style: TextButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        ),
        _buildKeyButton('0'),
        // Backspace button
        SizedBox(
          width: 68,
          height: 68,
          child: IconButton(
            onPressed: _onBackspacePressed,
            splashRadius: 32,
            icon: const Icon(
              Icons.backspace_outlined,
              color: Color(0xFF475569),
              size: 26,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyButton(String digit) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onDigitPressed(digit),
        borderRadius: BorderRadius.circular(40),
        splashColor: const Color(0xFF059669).withAlpha(35),
        highlightColor: const Color(0xFF059669).withAlpha(20),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }
}
