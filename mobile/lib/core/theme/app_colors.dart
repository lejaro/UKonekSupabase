import 'package:flutter/material.dart';

/// Centralized Design System Colors for U-Konek+ Mobile.
/// Single source of truth for branding, surfaces, typography, and status indicators.
class AppColors {
  AppColors._();

  // ── Brand & Theme (Medical Emerald) ─────────────────────────────
  static const Color primary      = Color(0xFF059669); // Emerald 600
  static const Color primaryMid   = Color(0xFF064E3B); // Forest Emerald 900
  static const Color primaryLight = Color(0xFFECFDF5); // Mint 50
  static const Color accent       = Color(0xFF10B981); // Mint Accent

  // ── Neutral Surfaces & Backgrounds ──────────────────────────────
  static const Color bg           = Color(0xFFF8FAFC); // Slate 50
  static const Color surface      = Colors.white;
  static const Color card         = Colors.white;
  static const Color fieldBg      = Color(0xFFF8FAFC);
  static const Color fieldBorder  = Color(0xFFE2E8F0); // Slate 200
  static const Color fieldBdr     = Color(0xFFE2E8F0); // Alias for legacy screens
  static const Color divider      = Color(0xFFE2E8F0); // Slate 200

  // ── Typography ──────────────────────────────────────────────────
  static const Color textDark     = Color(0xFF0F172A); // Slate 900
  static const Color textMuted    = Color(0xFF64748B); // Slate 500
  static const Color textSubtle   = Color(0xFF94A3B8); // Slate 400

  // ── Semantic Status & Alerts ────────────────────────────────────
  static const Color success      = Color(0xFF10B981); // Emerald/Mint
  static const Color warning      = Color(0xFFF59E0B); // Amber
  static const Color danger       = Color(0xFFDC3545); // Crimson
  static const Color info         = Color(0xFF0284C7); // Sky Blue

  // ── Elevation & Shadows ─────────────────────────────────────────
  static const Color shadow       = Color(0x080F172A);
  static const Color shadowMd     = Color(0x140F172A);
}
