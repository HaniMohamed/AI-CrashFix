import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/providers/run_session_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/status_pill.dart';
import 'widgets/crash_run_card.dart';
import 'widgets/live_summary_strip.dart';

class RunLivePage extends ConsumerStatefulWidget {
  const RunLivePage({super.key});

  @override
  ConsumerState<RunLivePage> createState() => _RunLivePageState();
}

class _RunLivePageState extends ConsumerState<RunLivePage> {
  /// Crash cards we've already shown at least once in this screen lifecycle.
  /// Used to avoid replaying the "new card" animation when scrolling.
  final Set<String> _seenCrashIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(runSessionProvider);
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    if (session.status == RunStatus.idle) {
      return Center(
        child: EmptyState(
          icon: Icons.play_circle_outline,
          title: 'No live run yet',
          subtitle: 'Trigger a run to watch each LangGraph node tick by in real time.',
          action: GradientButton(
            label: 'Start a new run',
            icon: Icons.bolt,
            onPressed: () => context.go('/runs/new'),
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.lg,
          ),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Text('Live run', style: theme.displaySmall),
                  const SizedBox(width: AppSpacing.md),
                  if (session.runId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: palette.surface2,
                        border: Border.all(color: palette.border),
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                      child: Text(
                        session.runId!,
                        style: AppTypography.mono(color: palette.text, size: 12),
                      ),
                    ),
                  const Spacer(),
                  if (session.status == RunStatus.completed)
                    StatusPill(status: 'completed')
                  else if (session.status == RunStatus.failed)
                    StatusPill(status: 'failed')
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Running', style: theme.labelLarge),
                      ],
                    ),
                  const SizedBox(width: AppSpacing.md),
                  if (session.isActive)
                    OutlinedButton.icon(
                      onPressed: () => ref.read(runSessionProvider.notifier).cancel(),
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('Cancel'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        ref.read(runSessionProvider.notifier).reset();
                        context.go('/runs/new');
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New run'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              LiveSummaryStrip(session: session),
              if (session.error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _ErrorCard(message: session.error!),
              ],
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            0,
            AppSpacing.xxl,
            AppSpacing.xxxl,
          ),
          sliver: SliverList.builder(
            itemCount: session.crashOrder.length,
            itemBuilder: (ctx, i) {
              final crashId = session.crashOrder[i];
              final crashState = session.perCrash[crashId];
              if (crashState == null) return const SizedBox.shrink();
              final firstTime = _seenCrashIds.add(crashId);
              final card = Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: CrashRunCard(key: ValueKey(crashId), state: crashState),
              );
              // Animate only truly newly-added cards (not rebuild/scroll).
              return firstTime
                  ? card.animate().fade(duration: 250.ms).slideY(begin: 0.1)
                  : card;
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.08),
        border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
        borderRadius: AppRadii.all(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: palette.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: SelectableText(message)),
        ],
      ),
    );
  }
}
