import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/analytics.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';

class KpiStrip extends StatelessWidget {
  final Analytics? analytics;
  final bool loading;
  const KpiStrip({super.key, this.analytics, this.loading = false});

  @override
  Widget build(BuildContext context) {
    if (loading || analytics == null) {
      return Row(
        children: List.generate(
          4,
          (_) => const Expanded(child: ShimmerCard(height: 132))
              .animate()
              .fadeIn(duration: 400.ms),
        ).expand((w) sync* {
          yield w;
          yield const SizedBox(width: AppSpacing.lg);
        }).toList()..removeLast(),
      );
    }
    final a = analytics!;
    final palette = context.palette;
    final cards = <Widget>[
      _Kpi(
        title: 'Total processed',
        value: a.totals.all,
        accent: palette.primary,
        icon: Icons.bug_report_outlined,
        caption:
            '${a.totals.completed} completed \u00B7 ${a.totals.failed} failed',
      ),
      _Kpi(
        title: 'Pipeline completion',
        value: (a.completionRate * 100).round(),
        suffix: '%',
        accent: palette.success,
        icon: Icons.check_circle_outline,
        caption: '${a.totals.pipelineComplete}/${a.totals.all} crashes shipped',
      ),
      _Kpi(
        title: 'Avg duration',
        valueText: Fmt.duration(a.avgPipelineDurationSeconds),
        accent: palette.secondary,
        icon: Icons.timer_outlined,
        caption: a.avgPipelineDurationSeconds > 0
            ? 'Across completed runs'
            : 'No completed runs yet',
      ),
      _Kpi(
        title: 'Currently running',
        value: a.totals.inProgress,
        accent: palette.warning,
        icon: Icons.bolt_outlined,
        caption: a.totals.failed > 0
            ? '${a.totals.failed} failed lifetime'
            : 'No failures lifetime',
      ),
    ];

    final w = MediaQuery.sizeOf(context).width;
    if (w < 920) {
      return GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.6,
        children: cards,
      );
    }
    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          Expanded(child: cards[i]),
          if (i != cards.length - 1) const SizedBox(width: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String title;
  final int? value;
  final String? valueText;
  final String? suffix;
  final IconData icon;
  final Color accent;
  final String? caption;
  const _Kpi({
    required this.title,
    this.value,
    this.valueText,
    this.suffix,
    required this.icon,
    required this.accent,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: AppRadii.all(AppRadii.sm),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.labelLarge?.copyWith(color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (valueText != null)
            Text(valueText!, style: AppTypography.counter(color: palette.text, size: 36))
                .animate()
                .fade(duration: 350.ms)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedFlipCounter(
                  value: value ?? 0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  textStyle: AppTypography.counter(color: palette.text, size: 40),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  Text(suffix!, style: AppTypography.counter(color: palette.textSecondary, size: 24)),
                ],
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          if (caption != null)
            Text(
              caption!,
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1);
  }
}
