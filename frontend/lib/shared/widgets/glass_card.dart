import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/motion.dart';
import '../../app/theme/spacing.dart';

/// Standard surface for interactive / data clusters.
/// Optional [glow] adds a subtle aurora-edge highlight.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool gradient;
  final bool glow;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.radius = AppRadii.lg,
    this.gradient = true,
    this.glow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final card = AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.easeOut,
      decoration: BoxDecoration(
        gradient: gradient ? palette.cardGradient : null,
        color: gradient ? null : palette.surface2,
        borderRadius: AppRadii.all(radius),
        border: Border.all(
          color: glow ? palette.primary.withValues(alpha: 0.35) : palette.border.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          if (glow)
            BoxShadow(
              color: palette.primary.withValues(alpha: 0.12),
              blurRadius: 24,
              spreadRadius: -2,
            ),
        ],
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(radius),
        child: card,
      ),
    );
  }
}
