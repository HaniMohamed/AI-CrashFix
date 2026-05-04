import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool dense;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disabled = onPressed == null || loading;
    final gradient = palette.brandGradient;
    final text = Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.white);

    final padding = EdgeInsets.symmetric(
      horizontal: dense ? 14 : 22,
      vertical: dense ? 10 : 14,
    );

    return Opacity(
      opacity: disabled ? 0.65 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.all(AppRadii.md),
          onTap: disabled ? null : onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: AppRadii.all(AppRadii.md),
              boxShadow: [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, size: 18, color: Colors.white),
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
