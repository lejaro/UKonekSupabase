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

/// Formats a DateTime as standard ISO YYYY-MM-DD for database query parameters.
String formatDateIso(DateTime value) {
  final d = DateTime(value.year, value.month, value.day);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}
