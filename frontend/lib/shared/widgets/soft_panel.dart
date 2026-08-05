import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

/// Non-card content panel with soft surface fill — prefer over GlassCard when
/// the content is not a primary interactive data cluster.
class SoftPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool bordered;

  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.radius = AppRadii.lg,
    this.color,
    this.bordered = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.panel.withValues(alpha: 0.82),
        borderRadius: AppRadii.all(radius),
        border: bordered ? Border.all(color: palette.border.withValues(alpha: 0.85)) : null,
      ),
      child: child,
    );
  }
}
