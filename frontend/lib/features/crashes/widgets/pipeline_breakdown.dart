import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../core/models/crash.dart';
import '../../../shared/widgets/glass_card.dart';

class PipelineBreakdown extends StatelessWidget {
  final Crash crash;
  const PipelineBreakdown({super.key, required this.crash});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final steps = crash.pipelineSteps;
    return ListView(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pipeline progress', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Each crash flows through these LangGraph nodes. Filled circles indicate the step finished successfully.',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (var i = 0; i < steps.length; i++)
                _Step(
                  index: i,
                  total: steps.length,
                  label: steps[i].label,
                  done: steps[i].done,
                  isLast: i == steps.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final int total;
  final String label;
  final bool done;
  final bool isLast;
  const _Step({
    required this.index,
    required this.total,
    required this.label,
    required this.done,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final color = done ? palette.success : palette.textMuted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: done ? palette.success.withValues(alpha: 0.2) : palette.surface1,
                  border: Border.all(color: color, width: 1.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  done ? Icons.check : Icons.circle_outlined,
                  size: 14,
                  color: color,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: palette.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.titleMedium),
                Text(
                  done ? 'Completed' : 'Pending',
                  style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
