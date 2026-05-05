import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/analytics.dart';
import '../../../shared/widgets/glass_card.dart';

class StatusDonut extends StatelessWidget {
  final AnalyticsTotals totals;
  const StatusDonut({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    final segments = <_Segment>[
      _Segment('Completed', totals.completed, palette.success),
      _Segment('Running', totals.inProgress, palette.primary),
      _Segment('Failed', totals.failed, palette.danger),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status mix', style: theme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Distribution across the crash store',
            style: theme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 3,
                          centerSpaceRadius: 56,
                          startDegreeOffset: -90,
                          sections: [
                            for (final s in segments)
                              if (s.value > 0)
                                PieChartSectionData(
                                  value: s.value.toDouble(),
                                  color: s.color,
                                  title: '',
                                  radius: 18,
                                ),
                            if (segments.every((s) => s.value == 0))
                              PieChartSectionData(
                                value: 1,
                                color: palette.border,
                                radius: 18,
                                title: '',
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            totals.all.toString(),
                            style: AppTypography.counter(color: palette.text, size: 32),
                          ),
                          Text(
                            'crashes',
                            style: theme.labelMedium?.copyWith(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final s in segments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: s.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.label,
                                  style: theme.labelLarge?.copyWith(color: palette.text),
                                ),
                              ),
                              Text(
                                s.value.toString(),
                                style: theme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment {
  final String label;
  final int value;
  final Color color;
  _Segment(this.label, this.value, this.color);
}
