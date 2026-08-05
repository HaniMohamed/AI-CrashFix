import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import 'fixora_mark.dart';

/// Brand-led page hero for auth / onboarding / dashboard first viewport.
class PageHero extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBrand;
  final bool compact;

  const PageHero({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.showBrand = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBrand) ...[
          Row(
            children: [
              const FixoraMark(size: 36),
              const SizedBox(width: AppSpacing.md),
              Text(
                kProductName,
                style: (compact ? theme.headlineMedium : theme.displaySmall)?.copyWith(
                  letterSpacing: -1.0,
                ),
              ),
            ],
          ),
          if (title != null || subtitle != null) const SizedBox(height: AppSpacing.xl),
        ],
        if (title != null)
          Text(
            title!,
            style: (compact ? theme.headlineMedium : theme.headlineLarge)?.copyWith(
              color: palette.text,
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: theme.bodyLarge?.copyWith(color: palette.textSecondary, height: 1.45),
          ),
        ],
        if (trailing != null) ...[
          const SizedBox(height: AppSpacing.xl),
          trailing!,
        ],
      ],
    );
  }
}
