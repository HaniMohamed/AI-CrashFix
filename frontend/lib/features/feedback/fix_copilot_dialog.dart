import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/models/crash.dart';
import '../../core/models/run_event.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/providers/feedback_session_provider.dart';
import '../../shared/widgets/diff_viewer.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/loading_shimmer.dart';

/// Below this width the chat and changes panels stack instead of sitting side by side.
const double _kTwoPanelBreakpoint = 960;

/// Opens the AI fix-refinement conversation (chat + live changes) as a
/// dismissible dialog over whatever page the user is already on.
Future<void> showFixCopilotDialog(BuildContext context, {required String crashId}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => FixCopilotDialog(crashId: crashId),
  );
}

class FixCopilotDialog extends ConsumerWidget {
  final String crashId;
  const FixCopilotDialog({super.key, required this.crashId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final crashAsync = ref.watch(crashDetailProvider(crashId));
    final media = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: palette.bg,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.xl)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1200,
          maxHeight: media.height - 2 * AppSpacing.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: palette.primary, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Fix Copilot', style: theme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              crashAsync.when(
                loading: () => const ShimmerCard(height: 90),
                error: (e, _) => ErrorBanner(
                  message: 'Failed to load crash $crashId: $e',
                  onRetry: () => ref.invalidate(crashDetailProvider(crashId)),
                ),
                data: (c) => _FeedbackHeader(crash: c),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final chat = _FeedbackChat(crashId: crashId);
                    final changes = _ChangesPanel(crashId: crashId);
                    if (constraints.maxWidth >= _kTwoPanelBreakpoint) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: chat),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(flex: 2, child: changes),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: chat),
                        const SizedBox(height: AppSpacing.lg),
                        Expanded(flex: 2, child: changes),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackHeader extends StatelessWidget {
  final Crash crash;
  const _FeedbackHeader({required this.crash});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  crash.crashId,
                  style: AppTypography.mono(color: palette.text, size: 13),
                ),
                if (crash.rootCause != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    crash.rootCause!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _HeaderChip(
                icon: Icons.history_rounded,
                label: 'Revision ${crash.feedbackIterationCount}',
              ),
              if (crash.jiraIssueId != null)
                _HeaderChip(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Jira: ${crash.jiraIssueId}',
                ),
              if (crash.effectivePrUrl != null)
                _HeaderChip(icon: Icons.merge_outlined, label: 'MR linked'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface1,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.text),
          ),
        ],
      ),
    );
  }
}

class _ChangesPanel extends ConsumerWidget {
  final String crashId;
  const _ChangesPanel({required this.crashId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final async = ref.watch(crashDiffProvider(crashId));

    // Pull the latest diff as soon as a regeneration finishes, so this panel
    // stays in sync with the chat without the user navigating away.
    ref.listen(feedbackSessionProvider(crashId), (prev, next) {
      final justFinished = prev?.status != FeedbackStreamStatus.done &&
          next.status == FeedbackStreamStatus.done;
      if (justFinished) ref.invalidate(crashDiffProvider(crashId));
    });

    return Container(
      decoration: BoxDecoration(
        color: palette.surface1.withValues(alpha: 0.5),
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(Icons.difference_outlined, size: 16, color: palette.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Changes',
                    style: theme.labelLarge?.copyWith(color: palette.text, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref.invalidate(crashDiffProvider(crashId)),
                  icon: Icon(Icons.refresh_rounded, size: 18, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border.withValues(alpha: 0.5)),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ErrorBanner(
                  message: 'Failed to load changes: $e',
                  onRetry: () => ref.invalidate(crashDiffProvider(crashId)),
                ),
              ),
              data: (diff) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: DiffViewer(diff: diff),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackChat extends ConsumerStatefulWidget {
  final String crashId;
  const _FeedbackChat({required this.crashId});

  @override
  ConsumerState<_FeedbackChat> createState() => _FeedbackChatState();
}

class _FeedbackChatState extends ConsumerState<_FeedbackChat> {
  final _noteCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final note = _noteCtrl.text.trim();
    if (note.isEmpty) return;
    _noteCtrl.clear();
    await ref.read(feedbackSessionProvider(widget.crashId).notifier).sendNote(note);
    if (mounted) {
      ref.invalidate(crashFeedbackHistoryProvider(widget.crashId));
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final historyAsync = ref.watch(crashFeedbackHistoryProvider(widget.crashId));
    final session = ref.watch(feedbackSessionProvider(widget.crashId));
    final locked = historyAsync.valueOrNull?.feedbackLocked == true || session.isActive;

    ref.listen(feedbackSessionProvider(widget.crashId), (prev, next) {
      _scrollToBottom();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface1.withValues(alpha: 0.5),
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: palette.border.withValues(alpha: 0.5)),
            ),
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorBanner(
                message: 'Failed to load feedback history: $e',
                onRetry: () => ref.invalidate(crashFeedbackHistoryProvider(widget.crashId)),
              ),
              data: (history) {
                final messages = [...history.messages, ...session.messages];
                return ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (messages.isEmpty && session.progressEvents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Center(
                          child: Text(
                            'Describe what\'s wrong or missing and the AI will validate '
                            'your note before regenerating the fix.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: palette.textMuted),
                          ),
                        ),
                      ),
                    for (final m in messages)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: _ChatBubble(message: m),
                      ),
                    // Keep the step-by-step trail once the stream ends (not just while
                    // active) — otherwise a finished regeneration leaves no trace in the
                    // chat besides the validation verdict.
                    if (session.isActive || session.progressEvents.isNotEmpty) ...[
                      if (session.isActive)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: _RegeneratingIndicator(),
                        ),
                      for (final ev in session.progressEvents)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                            horizontal: AppSpacing.lg,
                          ),
                          child: _ProgressBubble(event: ev),
                        ),
                    ],
                    if (session.status == FeedbackStreamStatus.failed &&
                        session.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: ErrorBanner(message: session.error!),
                      ),
                    if (session.status == FeedbackStreamStatus.done)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: session.summary != null
                            ? _RegenerationResultCard(summary: session.summary!)
                            : Text(
                                'Regeneration finished.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: palette.textMuted),
                              ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _noteCtrl,
                enabled: !locked,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: locked
                      ? 'Regenerating fix…'
                      : 'What\'s wrong or missing with this fix?',
                ),
                onSubmitted: (_) => locked ? null : _send(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: locked ? null : _send,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final FeedbackMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final isUser = message.isUser;

    final IconData? leading = message.isAi
        ? (message.isInvalid ? Icons.cancel_outlined : Icons.check_circle_outline)
        : null;
    final leadingColor =
        message.isInvalid ? palette.danger : palette.success;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isUser ? palette.primary.withValues(alpha: 0.14) : palette.surface2,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(
          color: isUser
              ? palette.primary.withValues(alpha: 0.35)
              : palette.border.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            Icon(leading, size: 16, color: leadingColor),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              message.message,
              style: theme.bodyMedium?.copyWith(color: palette.text, height: 1.4),
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [bubble],
    );
  }
}

class _RegeneratingIndicator extends StatelessWidget {
  const _RegeneratingIndicator();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Regenerating fix…',
          style: theme.labelLarge?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

/// Reuses the node-by-node progress label mapping from the live-run UI
/// (`run_live_page.dart` / `crash_run_card.dart`) for inline chat bubbles.
class _ProgressBubble extends StatelessWidget {
  final RunEvent event;
  const _ProgressBubble({required this.event});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final (IconData icon, Color color, String label, String? meta) = switch (event) {
      NodeStartedEvent(:final node) => (
          Icons.play_arrow_rounded,
          palette.primary,
          node,
          'started',
        ),
      NodeCompletedEvent(:final node, :final durationMs) => (
          Icons.check_circle_outline,
          palette.success,
          node,
          '${durationMs}ms',
        ),
      NodeErrorEvent(:final node, :final durationMs) => (
          Icons.error_outline,
          palette.danger,
          node,
          '${durationMs}ms · error',
        ),
      RouterEvent(:final router, :final route) => (
          Icons.alt_route,
          palette.secondary,
          router,
          'route → $route',
        ),
      StateSnapshotEvent(:final afterNode) => (
          Icons.layers_outlined,
          palette.warning,
          afterNode ?? 'state',
          'snapshot',
        ),
      CrashCompletedEvent() => (
          Icons.flag_circle_outlined,
          palette.success,
          'done',
          'regeneration finished',
        ),
      CrashFailedEvent() => (
          Icons.flag_circle_outlined,
          palette.danger,
          'failed',
          'regeneration failed',
        ),
      _ => (Icons.bolt, palette.textMuted, event.type, null),
    };

    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.mono(color: palette.text, size: 12)),
        if (meta != null) ...[
          const SizedBox(width: 8),
          Text(meta, style: theme.bodySmall?.copyWith(color: palette.textSecondary)),
        ],
      ],
    );
  }
}

class _RegenerationResultCard extends StatelessWidget {
  final FeedbackRegenerationSummary summary;
  const _RegenerationResultCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: palette.success, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('Fix regenerated', style: theme.titleSmall?.copyWith(color: palette.text)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              const _ResultChip(icon: Icons.merge_outlined, label: 'MR updated'),
              const _ResultChip(icon: Icons.confirmation_number_outlined, label: 'Jira updated'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ResultChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.success.withValues(alpha: 0.12),
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.success),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.text),
          ),
        ],
      ),
    );
  }
}
