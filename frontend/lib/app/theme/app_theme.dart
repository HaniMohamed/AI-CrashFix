import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

/// Custom design tokens carried on [ThemeData] via [ThemeExtension].
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color secondary;
  final Color success;
  final Color warning;
  final Color danger;
  final LinearGradient brandGradient;
  final LinearGradient cardGradient;

  const AppPalette({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.secondary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.brandGradient,
    required this.cardGradient,
  });

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface1,
    Color? surface2,
    Color? border,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
    Color? primary,
    Color? secondary,
    Color? success,
    Color? warning,
    Color? danger,
    LinearGradient? brandGradient,
    LinearGradient? cardGradient,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      brandGradient: brandGradient ?? this.brandGradient,
      cardGradient: cardGradient ?? this.cardGradient,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      brandGradient: t < 0.5 ? brandGradient : other.brandGradient,
      cardGradient: t < 0.5 ? cardGradient : other.cardGradient,
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final palette = AppPalette(
      bg: AppColors.darkBg,
      surface1: AppColors.darkSurface1,
      surface2: AppColors.darkSurface2,
      border: AppColors.darkBorder,
      text: AppColors.darkText,
      textSecondary: AppColors.darkTextSecondary,
      textMuted: AppColors.darkTextMuted,
      primary: AppColors.indigo,
      secondary: AppColors.cyan,
      success: AppColors.teal,
      warning: AppColors.amber,
      danger: AppColors.rose,
      brandGradient: AppColors.brandGradient,
      cardGradient: AppColors.cardGradient,
    );

    final colorScheme = ColorScheme.dark(
      primary: AppColors.indigo,
      secondary: AppColors.cyan,
      surface: palette.surface1,
      error: AppColors.rose,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: palette.text,
      onError: Colors.white,
    );

    return _build(palette, colorScheme, brightness: Brightness.dark);
  }

  static ThemeData light() {
    final palette = AppPalette(
      bg: AppColors.lightBg,
      surface1: AppColors.lightSurface1,
      surface2: AppColors.lightSurface2,
      border: AppColors.lightBorder,
      text: AppColors.lightText,
      textSecondary: AppColors.lightTextSecondary,
      textMuted: AppColors.lightTextMuted,
      primary: AppColors.indigo,
      secondary: AppColors.cyan,
      success: AppColors.teal,
      warning: AppColors.amber,
      danger: AppColors.rose,
      brandGradient: AppColors.brandGradient,
      cardGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9)],
      ),
    );

    final colorScheme = ColorScheme.light(
      primary: AppColors.indigo,
      secondary: AppColors.cyan,
      surface: palette.surface1,
      error: AppColors.rose,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: palette.text,
      onError: Colors.white,
    );

    return _build(palette, colorScheme, brightness: Brightness.light);
  }

  static ThemeData _build(
    AppPalette palette,
    ColorScheme colorScheme, {
    required Brightness brightness,
  }) {
    final textTheme = AppTypography.build(
      text: palette.text,
      textSecondary: palette.textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [palette],
      cardTheme: CardThemeData(
        color: palette.surface2,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.lg)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: palette.textSecondary, size: 18),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.md)),
          textStyle: textTheme.labelLarge,
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.md)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface1,
        hoverColor: palette.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.md),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.md),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.md),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(palette.text),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.primary;
          return palette.border;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.text,
        unselectedLabelColor: palette.textSecondary,
        indicatorColor: palette.primary,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: AppRadii.all(AppRadii.sm),
          border: Border.all(color: palette.border),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: palette.text),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.border,
        circularTrackColor: palette.border,
      ),
    );
  }
}
