import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/models/crash.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/copyable_text.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../shared/widgets/status_pill.dart';
import 'widgets/json_viewer.dart';
import 'widgets/pipeline_breakdown.dart';
import 'widgets/stack_trace_view.dart';

class CrashDetailPage extends ConsumerWidget {
  final String crashId;
  const CrashDetailPage({super.key, required this.crashId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(crashDetailProvider(crashId));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ),
      child: async.when(
        loading: () => const ShimmerCard(height: 220),
        error: (e, _) => ErrorBanner(
          message: 'Failed to load crash $crashId: $e',
          onRetry: () => ref.invalidate(crashDetailProvider(crashId)),
        ),
        data: (c) => _Body(crash: c),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final Crash crash;
  const _Body({required this.crash});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with TickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.crash;
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => context.go('/crashes'),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to crashes'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Header(c: c),
        const SizedBox(height: AppSpacing.xl),
        Container(
          decoration: BoxDecoration(
            color: palette.surface1,
            borderRadius: AppRadii.all(AppRadii.md),
            border: Border.all(color: palette.border),
          ),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Pipeline'),
              Tab(text: 'State JSON'),
              Tab(text: 'Stacktrace'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 800,
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(c: c),
              PipelineBreakdown(crash: c),
              JsonViewer(value: c.result ?? const {}),
              StackTraceView(stacktrace: (c.result?['stacktrace'] as List?) ?? const []),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Crash c;
  const _Header({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(status: c.status),
                    const SizedBox(width: AppSpacing.md),
                    if (c.pipelineComplete)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.success.withValues(alpha: 0.13),
                          border: Border.all(color: palette.success.withValues(alpha: 0.5)),
                          borderRadius: AppRadii.all(AppRadii.pill),
                        ),
                        child: Text(
                          'Pipeline complete',
                          style: theme.labelSmall?.copyWith(color: palette.success),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                CopyableText(text: c.crashId, size: 16),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _meta(context, 'platform', c.platform ?? '-'),
                    _meta(context, 'app version', c.appVersion ?? '-'),
                    _meta(context, 'device', c.deviceLabel.isEmpty ? '-' : c.deviceLabel),
                    _meta(context, 'created', Fmt.relative(c.createdAt)),
                    _meta(context, 'updated', Fmt.relative(c.updatedAt)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (c.jiraIssueId != null) ...[
                _ExternalChip(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Jira: ${c.jiraIssueId}',
                  onTap: null,
                ),
                const SizedBox(height: 8),
              ],
              if (c.prUrl != null) ...[
                _ExternalChip(
                  icon: Icons.merge_outlined,
                  label: 'Open MR',
                  onTap: () => Clipboard.setData(ClipboardData(text: c.prUrl!)),
                ),
                const SizedBox(height: 8),
              ],
              GradientButton(
                label: 'Re-run this crash',
                icon: Icons.refresh,
                onPressed: () {
                  context.go('/runs/new?prefill=${c.crashId}');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, String label, String value) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface1,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.labelSmall?.copyWith(color: palette.textMuted, letterSpacing: 1),
          ),
          const SizedBox(width: 8),
          Text(value, style: theme.labelLarge?.copyWith(color: palette.text)),
        ],
      ),
    );
  }
}

class _ExternalChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ExternalChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: AppRadii.all(AppRadii.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: palette.surface1,
          border: Border.all(color: palette.border),
          borderRadius: AppRadii.all(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.text),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy, size: 13, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Crash c;
  const _OverviewTab({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    final state = c.result ?? const {};
    return ListView(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exception', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                c.exception?.isNotEmpty == true ? c.exception! : '—',
                style: AppTypography.mono(color: palette.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Root cause', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                c.rootCause?.isNotEmpty == true ? c.rootCause! : 'No analysis yet.',
                style: theme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Suggested fix', style: theme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                c.fixSuggestion?.isNotEmpty == true ? c.fixSuggestion! : '—',
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generated diff', style: theme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              if ((state['generated_fix'] as String?)?.isNotEmpty == true)
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface1,
                    borderRadius: AppRadii.all(AppRadii.md),
                    border: Border.all(color: palette.border),
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SelectableText(
                    state['generated_fix'].toString(),
                    style: AppTypography.mono(color: palette.text, size: 12),
                  ),
                )
              else
                Text(
                  'No diff produced yet.',
                  style: theme.bodyMedium?.copyWith(color: palette.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
