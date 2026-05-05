import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/models/crash.dart';
import '../../core/providers/config_provider.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/models/run_request.dart';
import '../../core/providers/run_session_provider.dart';
import '../../core/utils/crashlytics_console_url.dart';
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
        if (c.status.toLowerCase() == 'failed') ...[
          _GraphFailureTile(crash: c),
          const SizedBox(height: AppSpacing.lg),
        ],
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

/// Red rounded tile at the top of crash detail when the row failed; expands to show [Crash.graphError].
class _GraphFailureTile extends StatelessWidget {
  final Crash crash;
  const _GraphFailureTile({required this.crash});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    final rose = AppColors.rose;
    final message = crash.graphError?.trim().isNotEmpty == true
        ? crash.graphError!.trim()
        : 'No error details were recorded.';

    return Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.md),
            side: BorderSide(color: rose.withValues(alpha: 0.55)),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.md),
            side: BorderSide(color: rose.withValues(alpha: 0.55)),
          ),
          backgroundColor: rose.withValues(alpha: 0.12),
          collapsedBackgroundColor: rose.withValues(alpha: 0.12),
          iconColor: rose,
          collapsedIconColor: rose,
          title: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: rose, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Pipeline failed',
                  style: theme.titleSmall?.copyWith(
                    color: rose,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                message,
                style: AppTypography.mono(color: palette.text, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final Crash c;
  const _Header({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    final configAsync = ref.watch(configProvider);
    final crashlyticsUri = configAsync.when(
      data: (cfg) => crashlyticsIssueUri(c, cfg.section('crashlytics')),
      loading: () => null,
      error: (_, _) => null,
    );
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CopyableText(text: c.crashId, size: 16),
                    const SizedBox(width: 2),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: crashlyticsUri != null
                          ? 'Open issue in Firebase Crashlytics'
                          : configAsync.isLoading
                              ? 'Loading configuration…'
                              : 'Cannot build link: set Firebase project id and Android package / iOS bundle '
                                  '(from Crashlytics export or CRASHLYTICS_ANDROID_PACKAGE / CRASHLYTICS_IOS_BUNDLE_ID in .env).',
                      onPressed: crashlyticsUri == null
                          ? null
                          : () async {
                              final ok = await launchUrl(
                                crashlyticsUri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!context.mounted || ok) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open Crashlytics link'),
                                ),
                              );
                            },
                      icon: Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: crashlyticsUri != null ? palette.primary : palette.textMuted,
                      ),
                    ),
                  ],
                ),
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
                  onTap: () async {
                    final uri = Uri.tryParse(c.prUrl!);
                    if (uri == null) return;
                    final ok = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!context.mounted || ok) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open MR link')),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              GradientButton(
                label: 'Re-run this crash',
                icon: Icons.refresh,
                onPressed: c.status.toLowerCase() == 'failed'
                    ? () {
                        final req = RunRequest(
                          mode: RunMode.single,
                          crashId: c.crashId,
                          mock: false,
                          skipJiraCreation: true,
                        );
                        ref.read(runSessionProvider.notifier).start(req);
                        context.go('/runs/live');
                      }
                    : null,
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
        if (c.graphRunStartTime != null ||
            c.graphRunEndTime != null ||
            c.graphRunDurationSeconds != null) ...[
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Graph run', style: theme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (c.graphRunStartTime != null)
                      _overviewKv(context, 'Started', c.graphRunStartTime!),
                    if (c.graphRunEndTime != null)
                      _overviewKv(context, 'Ended', c.graphRunEndTime!),
                    if (c.graphRunDurationSeconds != null)
                      _overviewKv(
                        context,
                        'Duration',
                        Fmt.duration(c.graphRunDurationSeconds!),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
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

  Widget _overviewKv(BuildContext context, String label, String value) {
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
          SelectableText(value, style: theme.labelLarge?.copyWith(color: palette.text)),
        ],
      ),
    );
  }
}
