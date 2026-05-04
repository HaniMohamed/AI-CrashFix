import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../core/models/analytics.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/glass_card.dart';

class PipelineFunnel extends StatelessWidget {
  final Analytics analytics;
  const PipelineFunnel({super.key, required this.analytics});

  static const _ordered = [
    ('analysis_done', 'Analysis'),
    ('fix_generated', 'Fix generated'),
    ('fix_validated', 'Validated'),
    ('diff_applied', 'Diff applied'),
    ('branch_created', 'Branch'),
    ('mr_created', 'MR opened'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    final total = analytics.totals.all;
    final maxVal = _ordered
        .map((e) => analytics.pipelineFunnel[e.$1] ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Pipeline funnel', style: theme.headlineSmall),
              const Spacer(),
              Text(
                'jira: ${analytics.pipelineFunnel['jira_created'] ?? 0}/$total',
                style: theme.labelMedium?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Step-by-step conversion across the LangGraph pipeline.',
            style: theme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (var i = 0; i < _ordered.length; i++)
            _FunnelRow(
              label: _ordered[i].$2,
              count: analytics.pipelineFunnel[_ordered[i].$1] ?? 0,
              total: total,
              maxVal: maxVal,
              index: i,
            ),
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final int maxVal;
  final int index;
  const _FunnelRow({
    required this.label,
    required this.count,
    required this.total,
    required this.maxVal,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final ratio = (maxVal == 0) ? 0.0 : count / maxVal;
    final percent = total == 0 ? 0.0 : count / total;
    final accent = Color.lerp(palette.primary, palette.secondary, index / 5) ?? palette.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: theme.labelLarge),
              const Spacer(),
              Text(
                '$count',
                style: theme.titleMedium?.copyWith(color: palette.text),
              ),
              const SizedBox(width: 8),
              Text(
                Fmt.percent(percent),
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppRadii.all(AppRadii.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: palette.surface1,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}
