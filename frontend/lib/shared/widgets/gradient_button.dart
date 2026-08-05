import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

enum GradientButtonVariant { primary, secondary, ghost, destructive }

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool dense;
  final GradientButtonVariant variant;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.dense = false,
    this.variant = GradientButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disabled = onPressed == null || loading;
    final padding = EdgeInsets.symmetric(
      horizontal: dense ? 14 : 22,
      vertical: dense ? 10 : 14,
    );

    final Color fg;
    final Decoration decoration;

    switch (variant) {
      case GradientButtonVariant.primary:
        fg = Theme.of(context).colorScheme.onPrimary;
        decoration = BoxDecoration(
          gradient: palette.brandGradient,
          borderRadius: AppRadii.all(AppRadii.md),
          boxShadow: [
            BoxShadow(
              color: palette.primary.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        );
      case GradientButtonVariant.secondary:
        fg = palette.text;
        decoration = BoxDecoration(
          color: palette.surface2,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.border),
        );
      case GradientButtonVariant.ghost:
        fg = palette.primary;
        decoration = BoxDecoration(
          color: palette.primary.withValues(alpha: 0.08),
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
        );
      case GradientButtonVariant.destructive:
        fg = Colors.white;
        decoration = BoxDecoration(
          color: palette.danger,
          borderRadius: AppRadii.all(AppRadii.md),
          boxShadow: [
            BoxShadow(
              color: palette.danger.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        );
    }

    final text = Theme.of(context).textTheme.labelLarge!.copyWith(color: fg);

    return Opacity(
      opacity: disabled ? 0.65 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.all(AppRadii.md),
          onTap: disabled ? null : onPressed,
          child: Ink(
            decoration: decoration,
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  else if (icon != null)
                    Icon(icon, size: 18, color: fg),
                  if (icon != null || loading) const SizedBox(width: 10),
                  Text(label, style: text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
