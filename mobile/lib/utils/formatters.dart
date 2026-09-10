/// Shared formatting utilities for U-Konek+ Mobile.
library;

/// Formats a doctor's name cleanly, stripping redundant 'Dr.', 'Dr', 'Doctor' prefixes
/// and returning a single standardized 'Dr. [Clean Name]'.
String formatDoctorName(String? raw) {
  if (raw == null) return 'Doctor';
  var n = raw.trim();
  if (n.isEmpty) return 'Doctor';

  // Remove any repeated prefixes like "Dr.", "Dr", "Doctor" at the beginning, case-insensitive
  final drPrefix = RegExp(r'^(dr\.?|doctor)\s*', caseSensitive: false);
  while (drPrefix.hasMatch(n)) {
    n = n.replaceFirst(drPrefix, '').trim();
  }
  if (n.isEmpty) return 'Doctor';
  return 'Dr. $n';
}
