// ═══════════════════════════════════════════════════════════════
// dental_theme.dart — Shared design tokens for Dental Clinic App
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

class DC {
  // ── Colors ───────────────────────────────────────────────────
  static const primary    = Color(0xFF0077B6); // dental blue
  static const primaryMid = Color(0xFF0096C7);
  static const primaryLight=Color(0xFF00B4D8);
  static const accent     = Color(0xFF48CAE4);
  static const bg         = Color(0xFFF0F7FA);
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1A2740);
  static const textMuted  = Color(0xFF8A93A0);
  static const divider    = Color(0xFFE8EEF4);
  static const success    = Color(0xFF10B981);
  static const warning    = Color(0xFFF59E0B);
  static const error      = Color(0xFFEF4444);
  static const shadow     = Color(0x0A000000);
  static const fieldBg    = Color(0xFFF8FAFF);
  static const fieldBdr   = Color(0xFFDDE3F0);

  // ── Text styles ──────────────────────────────────────────────
  static const titleLarge = TextStyle(
      fontSize: 22, fontWeight: FontWeight.bold,
      color: textDark, letterSpacing: -0.5);

  static const titleMedium = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w700,
      color: textDark, letterSpacing: -0.3);

  static const bodyMedium = TextStyle(
      fontSize: 14, color: textDark);

  static const caption = TextStyle(
      fontSize: 12, color: textMuted);

  // ── Decoration helpers ───────────────────────────────────────
  static BoxDecoration cardDecor({
    double radius = 20,
    Color color   = surface,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [BoxShadow(
        color: shadow, blurRadius: 14,
        offset: Offset(0, 5))],
  );

  static BoxDecoration gradientDecor({
    double radius = 20,
    List<Color> colors = const [primary, primaryMid],
  }) => BoxDecoration(
    gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [BoxShadow(
        color: primary.withOpacity(0.28),
        blurRadius: 16, offset: const Offset(0, 6))],
  );

  static InputDecoration inputDecor(String label, IconData icon) =>
      InputDecoration(
        labelText:  label,
        labelStyle: TextStyle(
            fontSize: 13, color: Colors.grey.shade500),
        prefixIcon: Icon(icon,
            color: primary.withOpacity(0.6), size: 20),
        filled:     true,
        fillColor:  fieldBg,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: fieldBdr)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: fieldBdr)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
                color: primaryMid, width: 1.8)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: error)),
      );

  // ── Status color helpers ─────────────────────────────────────
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':   return const Color(0xFF1565C0);
      case 'pending':     return warning;
      case 'completed':   return success;
      case 'cancelled':   return error;
      case 'no_show':     return Colors.grey;
      case 'in_progress': return const Color(0xFF7B1FA2);
      default:            return textMuted;
    }
  }

  static String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'in_progress': return 'In Progress';
      case 'no_show':     return 'No Show';
      default:
        return status[0].toUpperCase() + status.substring(1);
    }
  }
}