import 'package:flutter/material.dart';

/// Aurora Obsidian color tokens for the Fixora UI.
///
/// Dark-mode-first; the light variant mirrors the same accents over cool slate
/// surfaces. Tokens here are referenced through [AppTheme] / [AppPalette]
/// rather than imported directly by widgets.
class AppColors {
  AppColors._();

  // Brand / accents (shared across modes) — Aurora Obsidian
  static const Color teal = Color(0xFF2DD4BF);
  static const Color lime = Color(0xFFA3E635);
  static const Color glow = Color(0xFF5EEAD4);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color success = Color(0xFF14B8A6);
  static const Color amber = Color(0xFFF59E0B);
  static const Color rose = Color(0xFFEF4444);
  static const Color slate = Color(0xFF64748B);

  /// Legacy aliases kept so older call sites compile during migration.
  static const Color indigo = teal;
  static const Color violet = lime;

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, lime],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141C27), Color(0xFF0C1219)],
  );

  // Dark surfaces (obsidian)
  static const Color darkBg = Color(0xFF070A0F);
  static const Color darkSurface1 = Color(0xFF0C1219);
  static const Color darkSurface2 = Color(0xFF141C27);
  static const Color darkBorder = Color(0xFF1E2A3A);
  static const Color darkText = Color(0xFFE8EEF5);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);
  static const Color darkPanel = Color(0xFF0F1620);

  // Light surfaces (cool slate)
  static const Color lightBg = Color(0xFFF4F7FA);
  static const Color lightSurface1 = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFF0F4F8);
  static const Color lightBorder = Color(0xFFD8E0EA);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);
  static const Color lightPanel = Color(0xFFFFFFFF);
}

/// Status-aware color helpers used by pills/strips/funnels.
class StatusColors {
  StatusColors._();

  static Color forStatus(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'in_progress':
        return AppColors.teal;
      case 'skipped':
        return AppColors.slate;
      case 'failed':
        return AppColors.rose;
      default:
        return AppColors.teal;
    }
  }
}
