import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/motion.dart';
import '../../app/theme/spacing.dart';

/// Shared interactive list row used by crashes, MRs, and logs.
class AuroraListTile extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AuroraListTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          padding: padding,
          decoration: BoxDecoration(
            color: palette.panel.withValues(alpha: 0.55),
            borderRadius: AppRadii.all(AppRadii.md),
            border: Border.all(color: palette.border.withValues(alpha: 0.8)),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.titleSmall!.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                          ),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: palette.textSecondary,
                            ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
