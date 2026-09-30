import 'package:flutter/material.dart';

/// Centralized Design System Colors for U-Konek+ Mobile.
/// Single source of truth for branding, surfaces, typography, and status indicators.
class AppColors {
  AppColors._();

  // ── Brand & Theme (Unified Motif) ───────────────────────────────
  static const Color primary      = Color(0xFF2D5A27); // Forest Green
  static const Color primaryMid   = Color(0xFF1E3D1A); // Forest Green Dark
  static const Color primaryLight = Color(0xFFF0FDF4); // Forest Subtle
  static const Color accent       = Color(0xFF16A34A); // Action Emerald

  // ── Neutral Surfaces & Backgrounds ──────────────────────────────
  static const Color bg           = Color(0xFFF8FAFC); // Slate 50
  static const Color surface      = Colors.white; 
  static const Color card         = Colors.white;
  static const Color fieldBg      = Color(0xFFF8FAFC);
  static const Color fieldBorder  = Color(0xFFCBD5E1); // Slate 300 (Web unified)
  static const Color fieldBdr     = Color(0xFFCBD5E1); // Alias for legacy screens
  static const Color divider      = Color(0xFFE2E8F0); // Slate 200

  // ── Typography ──────────────────────────────────────────────────
  static const Color textDark     = Color(0xFF0F172A); // Slate 900
  static const Color textMuted    = Color(0xFF64748B); // Slate 500
  static const Color textSubtle   = Color(0xFF94A3B8); // Slate 400

  // ── Semantic Status & Alerts ────────────────────────────────────
  static const Color success      = Color(0xFF16A34A); // Action Emerald
  static const Color warning      = Color(0xFFF59E0B); // Amber
  static const Color danger       = Color(0xFFEF4444); // Unified Red
  static const Color info         = Color(0xFF0284C7); // Sky Blue

  // ── Elevation & Shadows ─────────────────────────────────────────
  static const Color shadow       = Color(0x080F172A);
  static const Color shadowMd     = Color(0x140F172A);

  // ── Standard Border Radiuses ────────────────────────────────────
  static const double btnRadius   = 10.0;
  static const double inputRadius = 10.0;
  static const double cardRadius  = 14.0;
  static const double cardRadiusLg = 18.0;
}
