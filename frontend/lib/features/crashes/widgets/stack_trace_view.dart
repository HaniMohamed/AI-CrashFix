import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_card.dart';

class StackTraceView extends StatelessWidget {
  final List<dynamic> stacktrace;
  const StackTraceView({super.key, required this.stacktrace});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;

    if (stacktrace.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.layers_outlined,
          title: 'No stacktrace available',
          subtitle: 'Crashlytics did not provide stack frames for this crash.',
        ),
      );
    }

    return ListView(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stack frames', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              for (var i = 0; i < stacktrace.length; i++)
                _Frame(index: i, frame: stacktrace[i]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  final int index;
  final dynamic frame;
  const _Frame({required this.index, required this.frame});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final map = frame is Map ? frame.cast<String, dynamic>() : <String, dynamic>{};
    final symbol = map['symbol']?.toString() ?? frame.toString();
    final file = map['file']?.toString();
    final line = map['line']?.toString();
    final mapped = map['mapped'] == true || map.containsKey('mapped_path');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface1,
        border: Border.all(color: palette.border),
        borderRadius: AppRadii.all(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#${index.toString().padLeft(2, '0')}',
            style: AppTypography.mono(color: palette.textMuted, size: 12),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(symbol, style: AppTypography.mono(color: palette.text)),
                if (file != null || line != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$file${line != null ? ':$line' : ''}',
                      style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          if (mapped)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.13),
                border: Border.all(color: palette.success.withValues(alpha: 0.4)),
                borderRadius: AppRadii.all(AppRadii.pill),
              ),
              child: Text(
                'mapped',
                style: theme.labelSmall?.copyWith(color: palette.success),
              ),
            ),
        ],
      ),
    );
  }
}
