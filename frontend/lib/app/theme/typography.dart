import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale: Manrope for headlines / numbers, Inter for body, JetBrains
/// Mono for crash ids, JSON, and code-like content.
class AppTypography {
  AppTypography._();

  static TextTheme build({required Color text, required Color textSecondary}) {
    final manropeBold = GoogleFonts.manrope(
      fontWeight: FontWeight.w700,
      color: text,
      letterSpacing: -0.5,
    );
    final manropeSemi = GoogleFonts.manrope(
      fontWeight: FontWeight.w600,
      color: text,
      letterSpacing: -0.2,
    );
    final inter = GoogleFonts.inter(color: text);

    return TextTheme(
      displayLarge: manropeBold.copyWith(fontSize: 40, height: 1.1),
      displayMedium: manropeBold.copyWith(fontSize: 32, height: 1.15),
      displaySmall: manropeBold.copyWith(fontSize: 28, height: 1.2),
      headlineLarge: manropeBold.copyWith(fontSize: 24, height: 1.25),
      headlineMedium: manropeSemi.copyWith(fontSize: 20, height: 1.3),
      headlineSmall: manropeSemi.copyWith(fontSize: 18, height: 1.3),
      titleLarge: manropeSemi.copyWith(fontSize: 17, height: 1.3),
      titleMedium: manropeSemi.copyWith(fontSize: 15, height: 1.3),
      titleSmall: manropeSemi.copyWith(fontSize: 13, color: textSecondary),
      bodyLarge: inter.copyWith(fontSize: 15, height: 1.45, fontWeight: FontWeight.w400),
      bodyMedium: inter.copyWith(fontSize: 14, height: 1.5, fontWeight: FontWeight.w400),
      bodySmall: inter.copyWith(fontSize: 12, color: textSecondary, height: 1.45),
      labelLarge: inter.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: inter.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
      labelSmall: inter.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary, letterSpacing: 0.6),
    );
  }

  static TextStyle mono({Color? color, double size = 13, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color);

  static TextStyle counter({required Color color, double size = 44}) => GoogleFonts.manrope(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.05,
        letterSpacing: -1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
