/// Utility to prevent rapid repeated taps, double-clicks, and spamming across buttons and navigation.
class AntiSpam {
  static int _lastTapTime = 0;

  /// Returns true if at least [cooldownMs] has elapsed since the last accepted tap.
  /// Otherwise returns false and rejects the tap.
  static bool allowTap([int cooldownMs = 600]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTapTime < cooldownMs) {
      return false;
    }
    _lastTapTime = now;
    return true;
  }
}
