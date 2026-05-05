import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/crash.dart';
import '../../../core/models/run_request.dart';
import '../../../core/providers/run_session_provider.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/pipeline_strip.dart';
import '../../../shared/widgets/status_pill.dart';

class RecentActivity extends ConsumerWidget {
  final List<Crash> items;
  const RecentActivity({super.key, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Recent activity', style: theme.headlineSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.go('/crashes'),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.bug_report_outlined,
                title: 'No crashes yet',
                subtitle: 'Run the pipeline to start seeing crashes here.',
              ),
            )
          else
            ...items.map((c) => _Row(c: c, ref: ref)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Crash c;
  final WidgetRef ref;
  const _Row({required this.c, required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    return InkWell(
      borderRadius: AppRadii.all(AppRadii.md),
      onTap: () => context.go('/crashes/${c.crashId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: Text(
                c.crashId,
                style: AppTypography.mono(color: palette.text, size: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            StatusPill(status: c.status, dense: true),
            if (c.status.toLowerCase() == 'failed' && (c.graphError?.isNotEmpty ?? false)) ...[
              const SizedBox(width: AppSpacing.sm),
              Tooltip(
                message: c.graphError!,
                child: Icon(Icons.error_outline, size: 16, color: palette.danger),
              ),
            ],
            const SizedBox(width: AppSpacing.md),
            PipelineStrip(crash: c),
            const Spacer(),
            if (c.status.toLowerCase() == 'failed')
              Tooltip(
                message: 'Re-run pipeline for this crash',
                child: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final req = RunRequest(
                      mode: RunMode.single,
                      crashId: c.crashId,
                      mock: false,
                      skipJiraCreation: true,
                    );
                    ref.read(runSessionProvider.notifier).start(req);
                    context.go('/runs/live');
                  },
                  icon: Icon(Icons.refresh, color: palette.primary),
                ),
              ),
            Text(
              Fmt.relative(c.updatedAt),
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(width: AppSpacing.md),
            Icon(Icons.chevron_right, color: palette.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
