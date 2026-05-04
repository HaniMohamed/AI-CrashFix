import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/models/crash.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../shared/widgets/pipeline_strip.dart';
import '../../shared/widgets/status_pill.dart';

class CrashesListPage extends ConsumerStatefulWidget {
  const CrashesListPage({super.key});

  @override
  ConsumerState<CrashesListPage> createState() => _CrashesListPageState();
}

class _CrashesListPageState extends ConsumerState<CrashesListPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final query = ref.watch(crashesQueryProvider);
    final pageAsync = ref.watch(crashesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Filters(
            search: _search,
            current: query,
            onChanged: (q) =>
                ref.read(crashesQueryProvider.notifier).state = q,
          ),
          const SizedBox(height: AppSpacing.xl),
          GlassCard(
            padding: EdgeInsets.zero,
            child: pageAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      const LoadingShimmer(height: 36),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ErrorBanner(
                  message: 'Failed to load crashes: $e',
                  onRetry: () => ref.invalidate(crashesProvider),
                ),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                    child: const EmptyState(
                      icon: Icons.bug_report_outlined,
                      title: 'No crashes match these filters',
                      subtitle: 'Adjust filters or run the pipeline to ingest more crashes.',
                    ),
                  );
                }
                final filtered = _filterClient(page.items, _search.text);
                return Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: palette.surface1,
                        border: Border(
                          bottom: BorderSide(color: palette.border),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          _HeaderCell(label: 'Crash ID', flex: 4),
                          _HeaderCell(label: 'Status', flex: 2),
                          _HeaderCell(label: 'Pipeline', flex: 3),
                          _HeaderCell(label: 'Platform', flex: 2),
                          _HeaderCell(label: 'Updated', flex: 2),
                          _HeaderCell(label: '', flex: 1),
                        ],
                      ),
                    ),
                    ...filtered.map(_buildRow),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: _Pager(query: query, ref: ref, count: page.count),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Crash c) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.go('/crashes/${c.crashId}'),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                c.crashId,
                style: AppTypography.mono(color: palette.text, size: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(status: c.status, dense: true),
              ),
            ),
            Expanded(flex: 3, child: PipelineStrip(crash: c)),
            Expanded(
              flex: 2,
              child: Text(
                c.platform ?? '-',
                style: theme.bodyMedium?.copyWith(color: palette.text),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Fmt.relative(c.updatedAt),
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.chevron_right, color: palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Crash> _filterClient(List<Crash> items, String query) {
    if (query.trim().isEmpty) return items;
    final q = query.trim().toLowerCase();
    return items.where((c) => c.crashId.toLowerCase().contains(q)).toList();
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  const _HeaderCell({required this.label, required this.flex});
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.textMuted,
              letterSpacing: 1.0,
            ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final TextEditingController search;
  final CrashListQuery current;
  final ValueChanged<CrashListQuery> onChanged;
  const _Filters({
    required this.search,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final statuses = const [null, 'completed', 'in_progress', 'pending', 'failed'];
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: search,
              onChanged: (_) {
                // Force rebuild to apply client-side filter immediately.
                (context as Element).markNeedsBuild();
              },
              decoration: InputDecoration(
                hintText: 'Search by crash id…',
                prefixIcon: Icon(Icons.search, color: palette.textMuted, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          ...statuses.map(
            (s) => _StatusChip(
              label: s == null ? 'All' : s.replaceAll('_', ' '),
              selected: current.status == s,
              onTap: () => onChanged(current.copyWith(status: s, offset: 0).._reset()),
            ),
          ),
        ],
      ),
    );
  }
}

extension on CrashListQuery {
  void _reset() {}
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: AppRadii.all(AppRadii.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? palette.primary.withValues(alpha: 0.18) : palette.surface1,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(
            color: selected ? palette.primary : palette.border,
          ),
        ),
        child: Text(
          label,
          style: theme.labelMedium?.copyWith(
            color: selected ? palette.text : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  final CrashListQuery query;
  final WidgetRef ref;
  final int count;
  const _Pager({required this.query, required this.ref, required this.count});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final atStart = query.offset == 0;
    final hasNext = count >= query.limit;
    return Row(
      children: [
        Text(
          'Showing ${query.offset + 1} – ${query.offset + count}',
          style: theme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: atStart
              ? null
              : () {
                  ref.read(crashesQueryProvider.notifier).state =
                      query.copyWith(offset: (query.offset - query.limit).clamp(0, 1 << 31));
                },
          icon: const Icon(Icons.chevron_left, size: 16),
          label: const Text('Prev'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: !hasNext
              ? null
              : () {
                  ref.read(crashesQueryProvider.notifier).state =
                      query.copyWith(offset: query.offset + query.limit);
                },
          icon: const Icon(Icons.chevron_right, size: 16),
          label: const Text('Next'),
        ),
      ],
    );
  }
}
