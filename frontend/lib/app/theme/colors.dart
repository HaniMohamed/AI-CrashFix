import 'package:flutter/material.dart';

/// Color tokens for the AI Crash Fix UI.
///
/// Dark-mode-first; the light variant mirrors the same accents over light
/// surfaces. Tokens here are referenced through [AppTheme] / [AppPalette]
/// rather than imported directly by widgets.
class AppColors {
  AppColors._();

  // Brand / accents (shared across modes)
  static const Color indigo = Color(0xFF6366F1);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color teal = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color rose = Color(0xFFEF4444);
  static const Color slate = Color(0xFF64748B);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, violet],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF181F38), Color(0xFF131A2E)],
  );

  // Dark surfaces
  static const Color darkBg = Color(0xFF0A0E1A);
  static const Color darkSurface1 = Color(0xFF0F1525);
  static const Color darkSurface2 = Color(0xFF171F36);
  static const Color darkBorder = Color(0xFF1F2A4A);
  static const Color darkText = Color(0xFFE5E7EB);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // Light surfaces
  static const Color lightBg = Color(0xFFF7F8FB);
  static const Color lightSurface1 = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);
}

/// Status-aware color helpers used by pills/strips/funnels.
class StatusColors {
  StatusColors._();

  static Color forStatus(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed':
        return AppColors.teal;
      case 'in_progress':
        return AppColors.indigo;
      case 'skipped':
        return AppColors.slate;
      case 'failed':
        return AppColors.rose;
      default:
        return AppColors.indigo;
    }
  }
}
