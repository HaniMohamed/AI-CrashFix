import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/crash.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/config_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/utils/crashlytics_console_url.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/diff_viewer.dart';
import '../../shared/widgets/error_banner.dart';
import '../mrs/generated_mrs_page.dart';

final fixedCrashesProvider = FutureProvider.autoDispose<List<Crash>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final repo = ref.watch(repoRegistryProvider).valueOrNull?.active;
  final res = await api.getJson(Endpoints.crashes, query: {
    'limit': 500,
    'offset': 0,
    'include_result': 1,
    if (repo != null) 'repo_key': repo.repoKey,
  });
  final j = (res as Map).cast<String, dynamic>();
  final items = (j['items'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Crash.fromJson(e.cast<String, dynamic>()))
      .where((c) => c.mrCreated)
      .toList();

  int cmp(Crash a, Crash b) {
    final at = a.updatedAt ?? a.createdAt;
    final bt = b.updatedAt ?? b.createdAt;
    if (at == null || bt == null) return 0;
    return bt.compareTo(at);
  }

  items.sort(cmp);
  return items;
});

enum MrStatusFilter { all, pending, merged, closed }

enum ReleaseFilter { all, inRelease, notInRelease }

enum ReopenedFilter { all, reopened, notReopened }

final mrStatusFilterProvider = StateProvider.autoDispose<MrStatusFilter>(
  (ref) => MrStatusFilter.all,
);

final releaseFilterProvider = StateProvider.autoDispose<ReleaseFilter>(
  (ref) => ReleaseFilter.all,
);

final reopenedFilterProvider = StateProvider.autoDispose<ReopenedFilter>(
  (ref) => ReopenedFilter.all,
);

bool _matchesMrStatusFilter(Crash c, MrStatusFilter filter) {
  switch (filter) {
    case MrStatusFilter.all:
      return true;
    case MrStatusFilter.pending:
      return c.mrStatus == null || c.mrStatus == 'pending';
    case MrStatusFilter.merged:
      return c.mrStatus == 'merged';
    case MrStatusFilter.closed:
      return c.mrStatus == 'closed';
  }
}

bool _matchesReleaseFilter(Crash c, ReleaseFilter filter) {
  switch (filter) {
    case ReleaseFilter.all:
      return true;
    case ReleaseFilter.inRelease:
      return c.fixedMarkedAt != null;
    case ReleaseFilter.notInRelease:
      return c.fixedMarkedAt == null;
  }
}

bool _matchesReopenedFilter(Crash c, ReopenedFilter filter) {
  switch (filter) {
    case ReopenedFilter.all:
      return true;
    case ReopenedFilter.reopened:
      return c.reopened;
    case ReopenedFilter.notReopened:
      return !c.reopened;
  }
}

class FixedCrashesPage extends ConsumerStatefulWidget {
  const FixedCrashesPage({super.key});

  @override
  ConsumerState<FixedCrashesPage> createState() => _FixedCrashesPageState();
}

class _FixedCrashesPageState extends ConsumerState<FixedCrashesPage> {
  bool _refreshingAll = false;

  Future<void> _refreshAll() async {
    final items = ref.read(fixedCrashesProvider).valueOrNull ?? const <Crash>[];
    final candidates = items.where(
      (c) => c.mrCreated && c.mrStatus != 'merged' && c.mrStatus != 'closed',
    );
    setState(() => _refreshingAll = true);
    try {
      final api = ref.read(apiClientProvider);
      await Future.wait([
        for (final c in candidates)
          api
              .postJson(Endpoints.crashSyncMrStatus(c.crashId))
              .catchError((_) => null),
      ]);
      ref.invalidate(fixedCrashesProvider);
    } finally {
      if (mounted) setState(() => _refreshingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(fixedCrashesProvider);
    final mrStatusFilter = ref.watch(mrStatusFilterProvider);
    final releaseFilter = ref.watch(releaseFilterProvider);
    final reopenedFilter = ref.watch(reopenedFilterProvider);
    final allItems = async.valueOrNull ?? const <Crash>[];
    final mrStatusCounts = <MrStatusFilter, int>{
      for (final f in MrStatusFilter.values)
        f: allItems.where((c) => _matchesMrStatusFilter(c, f)).length,
    };
    final releaseCounts = <ReleaseFilter, int>{
      for (final f in ReleaseFilter.values)
        f: allItems.where((c) => _matchesReleaseFilter(c, f)).length,
    };
    final reopenedCounts = <ReopenedFilter, int>{
      for (final f in ReopenedFilter.values)
        f: allItems.where((c) => _matchesReopenedFilter(c, f)).length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface1,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fixed Crashes',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Crashes with a merge request. Track MR status, mark release versions, and watch for reopens.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: palette.textSecondary,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  async.maybeWhen(
                    data: (items) => _CountChip(count: items.length),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  IconButton(
                    tooltip: 'Sync MR status for all & refresh',
                    onPressed: _refreshingAll ? null : _refreshAll,
                    icon: _refreshingAll
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.textSecondary,
                            ),
                          )
                        : Icon(Icons.refresh_rounded, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: palette.border.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _FilterChipGroup<MrStatusFilter>(
                    label: 'MR status',
                    value: mrStatusFilter,
                    options: const {
                      MrStatusFilter.all: 'All',
                      MrStatusFilter.pending: 'Pending',
                      MrStatusFilter.merged: 'Merged',
                      MrStatusFilter.closed: 'Closed',
                    },
                    counts: mrStatusCounts,
                    onChanged: (v) =>
                        ref.read(mrStatusFilterProvider.notifier).state = v,
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: palette.border.withValues(alpha: 0.5),
                  ),
                  _FilterChipGroup<ReleaseFilter>(
                    label: 'Release',
                    value: releaseFilter,
                    options: const {
                      ReleaseFilter.all: 'All',
                      ReleaseFilter.inRelease: 'In release',
                      ReleaseFilter.notInRelease: 'Not yet',
                    },
                    counts: releaseCounts,
                    onChanged: (v) =>
                        ref.read(releaseFilterProvider.notifier).state = v,
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: palette.border.withValues(alpha: 0.5),
                  ),
                  _FilterChipGroup<ReopenedFilter>(
                    label: 'Reopened',
                    value: reopenedFilter,
                    options: const {
                      ReopenedFilter.all: 'All',
                      ReopenedFilter.reopened: 'Reopened',
                      ReopenedFilter.notReopened: 'Not reopened',
                    },
                    counts: reopenedCounts,
                    onChanged: (v) =>
                        ref.read(reopenedFilterProvider.notifier).state = v,
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: palette.border.withValues(alpha: 0.5)),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorBanner(
                  message: 'Failed to load fixed crashes: $e',
                  onRetry: () => ref.invalidate(fixedCrashesProvider),
                ),
                data: (allItems) {
                  final items = allItems
                      .where((c) => _matchesMrStatusFilter(c, mrStatusFilter))
                      .where((c) => _matchesReleaseFilter(c, releaseFilter))
                      .where((c) => _matchesReopenedFilter(c, reopenedFilter))
                      .toList();
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Text(
                          allItems.isEmpty
                              ? 'No fixed crashes yet.'
                              : 'No crashes match the selected filters.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xxl,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.xl),
                    itemBuilder: (ctx, i) => _FixedCrashCard(crash: items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Color mapping mirrors `_MetaChip`'s emphasize treatment (success) extended
/// with warning/danger for the two other MR lifecycle states.
({Color fg, Color bg, Color border, IconData icon, String label}) _mrStatusStyle(
  AppPalette palette,
  String? mrStatus,
) {
  switch (mrStatus) {
    case 'merged':
      return (
        fg: palette.success,
        bg: palette.success.withValues(alpha: 0.12),
        border: palette.success.withValues(alpha: 0.35),
        icon: Icons.check_circle_outline_rounded,
        label: 'Merged',
      );
    case 'closed':
      return (
        fg: palette.danger,
        bg: palette.danger.withValues(alpha: 0.12),
        border: palette.danger.withValues(alpha: 0.35),
        icon: Icons.cancel_outlined,
        label: 'Closed',
      );
    case 'pending':
    default:
      return (
        fg: palette.warning,
        bg: palette.warning.withValues(alpha: 0.12),
        border: palette.warning.withValues(alpha: 0.35),
        icon: Icons.hourglass_top_rounded,
        label: mrStatus == null ? 'Unknown' : 'Pending',
      );
  }
}

class _FixedCrashCard extends ConsumerStatefulWidget {
  final Crash crash;
  const _FixedCrashCard({required this.crash});

  @override
  ConsumerState<_FixedCrashCard> createState() => _FixedCrashCardState();
}

class _FixedCrashCardState extends ConsumerState<_FixedCrashCard> {
  bool _expanded = false;
  bool _insightExpanded = false;
  bool _syncing = false;
  bool _unmarking = false;
  List<Map<String, dynamic>>? _insights;
  bool _loadingInsights = false;
  String? _insightsError;
  String? _mrStatusOverride;
  String? _updatedAtOverride;
  int _detailTab = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.crash;
    final palette = context.palette;
    final theme = Theme.of(context);
    final prUrl = c.effectivePrUrl;
    final configAsync = ref.watch(configProvider);
    final crashlyticsUri = configAsync.when(
      data: (cfg) => crashlyticsIssueUri(c, cfg.section('crashlytics')),
      loading: () => null,
      error: (_, _) => null,
    );
    final rawTitle = c.prTitle ?? 'Merge request';
    final headline = mrDisplayHeadline(rawTitle);
    final branch = c.prBranch;
    final body = c.prBody;
    final whenIso = _updatedAtOverride ?? c.updatedAt ?? c.createdAt;
    final whenLabel = Fmt.relative(whenIso);
    final whenExact = Fmt.readableDateTime(whenIso);
    final raisedIso = c.mrCreatedAt ?? c.createdAt;
    final raisedLabel = Fmt.relative(raisedIso);
    final raisedExact = Fmt.readableDateTime(raisedIso);
    final statusStyle = _mrStatusStyle(palette, _mrStatusOverride ?? c.mrStatus);

    return Material(
      color: palette.panel.withValues(alpha: 0.72),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(AppRadii.xl),
        side: BorderSide(color: palette.border.withValues(alpha: 0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: AppRadii.all(AppRadii.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: palette.brandGradient,
                        borderRadius: AppRadii.all(AppRadii.md),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.task_alt_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (whenLabel.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Tooltip(
                              message: whenExact.isNotEmpty
                                  ? 'Updated $whenExact'
                                  : whenLabel,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 15,
                                    color: palette.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      whenLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: palette.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (raisedLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Tooltip(
                              message: raisedExact.isNotEmpty
                                  ? 'MR raised $raisedExact'
                                  : raisedLabel,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.call_made_rounded,
                                    size: 15,
                                    color: palette.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Raised $raisedLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: palette.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          SelectableText(
                            c.crashId,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.textMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _StatusChip(
                                label: statusStyle.label,
                                icon: statusStyle.icon,
                                fg: statusStyle.fg,
                                bg: statusStyle.bg,
                                border: statusStyle.border,
                              ),
                              if (branch != null)
                                _MetaChip(
                                  label: branch,
                                  icon: Icons.call_split_rounded,
                                  tooltip: branch,
                                  maxLabelWidth: 260,
                                ),
                              if (c.reopened)
                                _StatusChip(
                                  label: 'Reopened ×${c.reopenCount}',
                                  icon: Icons.warning_amber_rounded,
                                  fg: palette.danger,
                                  bg: palette.danger.withValues(alpha: 0.12),
                                  border: palette.danger.withValues(alpha: 0.35),
                                ),
                              if (c.fixedMarkedAt != null &&
                                  (c.fixedInVersionAndroid?.isNotEmpty ?? false))
                                _MetaChip(
                                  label: 'Android v${c.fixedInVersionAndroid}',
                                  icon: Icons.android_rounded,
                                ),
                              if (c.fixedMarkedAt != null &&
                                  (c.fixedInVersionIos?.isNotEmpty ?? false))
                                _MetaChip(
                                  label: 'iOS v${c.fixedInVersionIos}',
                                  icon: Icons.apple_rounded,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      children: [
                        Icon(
                          _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: palette.textMuted,
                          size: 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _expanded ? 'Hide' : 'PR body',
                          style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface1.withValues(alpha: 0.55),
                borderRadius: AppRadii.all(AppRadii.md),
                border: Border.all(color: palette.border.withValues(alpha: 0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.go('/crashes/${c.crashId}'),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Crash Details'),
                    ),
                    if (c.reopenedFromCrashId != null)
                      TextButton.icon(
                        onPressed: () =>
                            context.go('/crashes/${c.reopenedFromCrashId}'),
                        icon: const Icon(Icons.north_east_rounded, size: 18),
                        label: const Text('View original crash'),
                      ),
                    TextButton.icon(
                      onPressed: _syncing ? null : () => _syncMrStatus(context),
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Sync MR Status'),
                    ),
                    if (c.fixedMarkedAt == null)
                      FilledButton.tonalIcon(
                        onPressed: () => _showMarkFixedDialog(context),
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text('Mark Fixed in Release'),
                      )
                    else
                      TextButton.icon(
                        onPressed: _unmarking ? null : () => _confirmUnmarkFixed(context),
                        icon: _unmarking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Unmark Fixed'),
                      ),
                    const Spacer(),
                    FilledButton.tonalIcon(
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
                      icon: const Icon(Icons.local_fire_department_rounded, size: 18),
                      label: const Text('Open in Firebase'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: prUrl == null
                          ? null
                          : () async {
                              final uri = Uri.tryParse(prUrl);
                              if (uri == null) return;
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open in GitLab'),
                    ),
                  ],
                ),
              ),
            ),
            if (c.reopened) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildInsightSection(context, palette, theme),
            ],
            if (_expanded) ...[
              const SizedBox(height: AppSpacing.lg),
              Divider(height: 1, color: palette.border.withValues(alpha: 0.45)),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _DetailTabButton(
                    label: 'PR Body',
                    icon: Icons.description_outlined,
                    selected: _detailTab == 0,
                    onTap: () => setState(() => _detailTab = 0),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _DetailTabButton(
                    label: 'Changes',
                    icon: Icons.difference_outlined,
                    selected: _detailTab == 1,
                    onTap: () => setState(() => _detailTab = 1),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_detailTab == 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.bg.withValues(alpha: 0.35),
                    borderRadius: AppRadii.all(AppRadii.md),
                    border: Border.all(color: palette.border.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: body == null
                        ? Text(
                            'No PR body was stored for this merge request.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                          )
                        : DefaultTextStyle.merge(
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: palette.text,
                              height: 1.5,
                            ),
                            child: MarkdownBody(
                              data: body,
                              selectable: true,
                              styleSheet: mrMarkdownStyleSheet(theme, palette).copyWith(
                                blockquoteDecoration: BoxDecoration(
                                  color: palette.surface2,
                                  borderRadius: AppRadii.all(AppRadii.sm),
                                  border: Border.all(color: palette.border),
                                ),
                              ),
                            ),
                          ),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.bg.withValues(alpha: 0.35),
                    borderRadius: AppRadii.all(AppRadii.md),
                    border: Border.all(color: palette.border.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: _buildChangesTab(context, palette, theme, c.crashId),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChangesTab(
    BuildContext context,
    AppPalette palette,
    ThemeData theme,
    String crashId,
  ) {
    final async = ref.watch(crashDiffProvider(crashId));
    return async.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => ErrorBanner(
        message: 'Failed to load changes: $e',
        onRetry: () => ref.invalidate(crashDiffProvider(crashId)),
      ),
      data: (diff) => DiffViewer(diff: diff),
    );
  }

  Widget _buildInsightSection(BuildContext context, AppPalette palette, ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.06),
        borderRadius: AppRadii.all(AppRadii.md),
        border: Border.all(color: palette.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: AppRadii.all(AppRadii.md),
            onTap: () => _toggleInsights(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 18, color: palette.danger),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'AI Insight: why this crash reopened',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _insightExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_insightExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: _loadingInsights
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _insightsError != null
                      ? Text(
                          'Failed to load insight: $_insightsError',
                          style: theme.textTheme.bodySmall?.copyWith(color: palette.danger),
                        )
                      : (_insights == null || _insights!.isEmpty)
                          ? Text(
                              'No AI insight recorded for this reopen yet.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: palette.textMuted),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final insight in _insights!) ...[
                                  DefaultTextStyle.merge(
                                    style: theme.textTheme.bodyMedium!.copyWith(
                                      color: palette.text,
                                      height: 1.5,
                                    ),
                                    child: MarkdownBody(
                                      data: (insight['message'] ?? '').toString(),
                                      selectable: true,
                                      styleSheet: mrMarkdownStyleSheet(theme, palette),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                ],
                              ],
                            ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleInsights(BuildContext context) async {
    final willExpand = !_insightExpanded;
    setState(() => _insightExpanded = willExpand);
    if (!willExpand || _insights != null || _loadingInsights) return;
    setState(() {
      _loadingInsights = true;
      _insightsError = null;
    });
    try {
      final api = ProviderScope.containerOf(context).read(apiClientProvider);
      final res = await api.getJson(Endpoints.crashReopenInsight(widget.crash.crashId));
      final j = (res as Map).cast<String, dynamic>();
      final items = (j['insights'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _insights = items;
        _loadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _insightsError = e.toString();
        _loadingInsights = false;
      });
    }
  }

  Future<void> _syncMrStatus(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    setState(() => _syncing = true);
    try {
      final api = container.read(apiClientProvider);
      final res = await api.postJson(Endpoints.crashSyncMrStatus(widget.crash.crashId));
      final map = res as Map?;
      final updatedStatus = map?['mr_status'] as String?;
      final updatedAt = map?['updated_at'] as String?;
      if (mounted) {
        setState(() {
          if (updatedStatus != null) _mrStatusOverride = updatedStatus;
          if (updatedAt != null) _updatedAtOverride = updatedAt;
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sync MR status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmUnmarkFixed(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.undo_rounded, color: context.palette.warning, size: 28),
        title: const Text('Unmark Fixed in Release?'),
        content: const Text(
          'This clears the recorded Android/iOS release versions for this crash. '
          'You can mark it fixed again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unmark Fixed'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final container = ProviderScope.containerOf(context);
    setState(() => _unmarking = true);
    try {
      final api = container.read(apiClientProvider);
      await api.postJson(Endpoints.crashUnmarkFixed(widget.crash.crashId));
      container.invalidate(fixedCrashesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unmark fixed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _unmarking = false);
    }
  }

  Future<void> _showMarkFixedDialog(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _MarkFixedDialog(crashId: widget.crash.crashId),
    );
    if (result == true) {
      container.invalidate(fixedCrashesProvider);
    }
  }
}

class _MarkFixedDialog extends ConsumerStatefulWidget {
  final String crashId;
  const _MarkFixedDialog({required this.crashId});

  @override
  ConsumerState<_MarkFixedDialog> createState() => _MarkFixedDialogState();
}

class _MarkFixedDialogState extends ConsumerState<_MarkFixedDialog> {
  final _androidController = TextEditingController();
  final _iosController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _androidController.dispose();
    _iosController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final android = _androidController.text.trim();
    final ios = _iosController.text.trim();
    if (android.isEmpty && ios.isEmpty) {
      setState(() => _error = 'Enter at least one version.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.postJson(Endpoints.crashMarkFixed(widget.crashId), body: {
        if (android.isNotEmpty) 'android_version': android,
        if (ios.isNotEmpty) 'ios_version': ios,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to mark fixed: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      icon: Icon(Icons.verified_rounded, color: palette.success, size: 28),
      title: const Text('Mark Fixed in Release'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.crashId,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontFamily: 'monospace',
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _androidController,
            decoration: const InputDecoration(
              labelText: 'Android version',
              hintText: 'e.g. 2.3.1',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _iosController,
            decoration: const InputDecoration(
              labelText: 'iOS version',
              hintText: 'e.g. 2.3.0',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mark Fixed'),
        ),
      ],
    );
  }
}

class _FilterChipGroup<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> options;
  final Map<T, int>? counts;
  final ValueChanged<T> onChanged;

  const _FilterChipGroup({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          label,
          style: theme.labelMedium?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 2),
        for (final entry in options.entries)
          ChoiceChip(
            label: Text(
              counts == null ? entry.value : '${entry.value} (${counts![entry.key] ?? 0})',
            ),
            selected: value == entry.key,
            onSelected: (_) => onChanged(entry.key),
            labelStyle: theme.labelMedium?.copyWith(
              color: value == entry.key ? palette.primary : palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            selectedColor: palette.primary.withValues(alpha: 0.14),
            backgroundColor: palette.surface2,
            side: BorderSide(
              color: value == entry.key
                  ? palette.primary.withValues(alpha: 0.5)
                  : palette.border.withValues(alpha: 0.55),
            ),
            shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.pill)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}

class _DetailTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DetailTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? palette.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(
            color: selected
                ? palette.primary.withValues(alpha: 0.5)
                : palette.border.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? palette.primary : palette.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.labelMedium?.copyWith(
                color: selected ? palette.primary : palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  const _CountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        '$count fixed',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? tooltip;
  final double? maxLabelWidth;

  const _MetaChip({
    required this.label,
    required this.icon,
    this.tooltip,
    this.maxLabelWidth,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    final child = Container(
      constraints: BoxConstraints(maxWidth: (maxLabelWidth ?? 180) + 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface1.withValues(alpha: 0.9),
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.border.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: palette.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.labelLarge?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (tooltip != null && tooltip != label) {
      return Tooltip(message: tooltip!, child: child);
    }
    return Tooltip(message: label, child: child);
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
