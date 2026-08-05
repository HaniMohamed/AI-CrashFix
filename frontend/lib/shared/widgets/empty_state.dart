import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/motion.dart';
import '../../app/theme/spacing.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final reduce = AppMotion.reduceMotion(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(color: palette.primary.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Icon(icon, size: 28, color: palette.primary),
            ).fadeSlideUp(enabled: !reduce),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.headlineSmall, textAlign: TextAlign.center)
                .fadeSlideUp(delay: const Duration(milliseconds: 40), enabled: !reduce),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ).fadeSlideUp(delay: const Duration(milliseconds: 80), enabled: !reduce),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!.fadeSlideUp(delay: const Duration(milliseconds: 120), enabled: !reduce),
            ],
          ],
        ),
      ),
    );
  }
}
