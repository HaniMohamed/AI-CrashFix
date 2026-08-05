import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/brand.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/spacing.dart';
import '../../../shared/widgets/fixora_mark.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';

class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final reduce = AppMotion.reduceMotion(context);

    return GlassCard(
      glow: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -120,
            top: -80,
            child: _Blob(color: palette.primary.withValues(alpha: 0.32), size: 260),
          ),
          Positioned(
            right: 40,
            bottom: -90,
            child: _Blob(color: palette.secondary.withValues(alpha: 0.18), size: 200),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FixoraMark(size: 28, radius: 8, elevated: false),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    kProductName,
                    style: theme.headlineMedium?.copyWith(letterSpacing: -0.8),
                  ),
                ],
              )
                  .animate(target: reduce ? 0 : 1)
                  .fade(duration: 400.ms)
                  .slideY(begin: -0.3),
              const SizedBox(height: AppSpacing.lg),
              Text(
                kProductTagline,
                style: theme.displaySmall?.copyWith(height: 1.05),
              )
                  .animate(target: reduce ? 0 : 1)
                  .fade(delay: 80.ms, duration: 400.ms)
                  .slideY(begin: 0.15),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Watch Crashlytics issues flow through the pipeline, then ship reviewed fixes.',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ).animate(target: reduce ? 0 : 1).fade(delay: 160.ms, duration: 450.ms),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  GradientButton(
                    label: 'Start a new run',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => context.go('/runs/new'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.bug_report_outlined, size: 18),
                    label: const Text('Browse crashes'),
                    onPressed: () => context.go('/crashes'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduceMotion(context);
    final child = IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
    if (reduce) return child;
    return child.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
          duration: 3200.ms,
          begin: 1,
          end: 1.08,
        );
  }
}
