import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';

class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return GlassCard(
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
            child: _Blob(color: palette.primary.withValues(alpha: 0.35), size: 260),
          ),
          Positioned(
            right: 40,
            bottom: -90,
            child: _Blob(color: palette.secondary.withValues(alpha: 0.25), size: 200),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: palette.brandGradient,
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                      child: Text(
                        'AI \u00B7 LANGGRAPH \u00B7 LIVE',
                        style: theme.labelSmall?.copyWith(color: Colors.white, letterSpacing: 1.4),
                      ),
                    ).animate().fade(duration: 400.ms).slideY(begin: -0.4),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Crashes \u2192 fixes, on autopilot.',
                      style: theme.displaySmall?.copyWith(height: 1.05),
                    ).animate().fade(delay: 80.ms, duration: 400.ms).slideY(begin: 0.2),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Real-time analytics across every Crashlytics issue running through the pipeline. Trigger new fixes, watch each node tick by, and ship MRs without leaving this view.',
                      style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
                    ).animate().fade(delay: 200.ms, duration: 500.ms),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        GradientButton(
                          label: 'Start a new run',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => context.go('/runs/new'),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.bug_report_outlined, size: 18),
                          label: const Text('Browse crashes'),
                          onPressed: () => context.go('/crashes'),
                        ),
                      ],
                    ),
                  ],
                ),
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
    return IgnorePointer(
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
      ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
            duration: 3200.ms,
            begin: 1,
            end: 1.08,
            curve: Curves.easeInOut,
          ),
    );
  }
}
