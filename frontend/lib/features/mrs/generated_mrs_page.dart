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
import '../../shared/widgets/error_banner.dart';

/// Strips boilerplate prefixes and leading crash hashes so titles read like a headline.
String mrDisplayHeadline(String rawTitle) {
  var s = rawTitle.trim();
  if (s.isEmpty) return 'Merge request';

  s = s.replaceFirst(
    RegExp(r'^AI\s+CRASH[_\s-]*FIX\s+PR:\s*', caseSensitive: false),
    '',
  );
  s = s.replaceFirst(
    RegExp(r'^([a-fA-F0-9]{16,})\s*[-–—:]?\s*'),
    '',
  );
  s = s.trim();
  return s.isEmpty ? rawTitle.trim() : s;
}

/// Short crash id for dense rows (full id still on detail / tooltip).
String shortCrashId(String id) {
  final t = id.trim();
  if (t.length <= 18) return t;
  return '${t.substring(0, 8)}…${t.substring(t.length - 6)}';
}

/// Markdown defaults omit text color on `strong` / `em` / table headers, which reads as black on dark UI.
MarkdownStyleSheet mrMarkdownStyleSheet(ThemeData theme, AppPalette palette) {
  final body = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  final onSurface = palette.text;
  final secondary = palette.textSecondary;
  final base = MarkdownStyleSheet.fromTheme(theme);
  return base.copyWith(
    p: body.copyWith(color: onSurface, height: 1.5),
    h1: base.h1?.copyWith(color: onSurface),
    h2: base.h2?.copyWith(color: onSurface),
    h3: base.h3?.copyWith(color: onSurface),
    h4: base.h4?.copyWith(color: onSurface),
    h5: base.h5?.copyWith(color: onSurface),
    h6: base.h6?.copyWith(color: onSurface),
    strong: TextStyle(fontWeight: FontWeight.w700, color: onSurface),
    em: TextStyle(fontStyle: FontStyle.italic, color: onSurface),
    del: TextStyle(
      decoration: TextDecoration.lineThrough,
      color: palette.textMuted,
    ),
    listBullet: body.copyWith(color: onSurface),
    checkbox: body.copyWith(
      color: palette.text,
      fontSize: (body.fontSize ?? 14) * 1.35,
    ),
    tableHead: (base.tableHead ?? const TextStyle(fontWeight: FontWeight.w600))
        .copyWith(color: onSurface),
    tableBody: body.copyWith(color: onSurface),
    blockquote: body.copyWith(color: secondary),
    a: base.a?.copyWith(color: palette.primary) ??
        TextStyle(color: palette.primary, decoration: TextDecoration.underline),
    code: body.copyWith(
      color: onSurface,
      fontFamily: 'monospace',
      backgroundColor: palette.surface2,
    ),
    img: base.img?.copyWith(color: onSurface),
  );
}

final generatedMrsProvider = FutureProvider.autoDispose<List<Crash>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getJson(Endpoints.crashes, query: {
    'limit': 500,
    'offset': 0,
    'include_result': 1,
  });
  final j = (res as Map).cast<String, dynamic>();
  final items = (j['items'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Crash.fromJson(e.cast<String, dynamic>()))
      .where((c) => c.mrCreated || (c.effectivePrUrl?.isNotEmpty ?? false))
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

class GeneratedMrsPage extends ConsumerWidget {
  const GeneratedMrsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(generatedMrsProvider);
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
                          'Generated MRs',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Merge requests created by the pipeline. Stored in the local crash database.',
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
                    tooltip: 'Refresh',
                    onPressed: () => ref.invalidate(generatedMrsProvider),
                    icon: Icon(Icons.refresh_rounded, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: palette.border.withValues(alpha: 0.5)),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorBanner(
                  message: 'Failed to load generated MRs: $e',
                  onRetry: () => ref.invalidate(generatedMrsProvider),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Text(
                          'No generated MRs yet.',
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
                    itemBuilder: (ctx, i) => _MrCard(crash: items[i]),
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

class _MrCard extends StatefulWidget {
  final Crash crash;
  const _MrCard({required this.crash});

  @override
  State<_MrCard> createState() => _MrCardState();
}

class _MrCardState extends State<_MrCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.crash;
    final palette = context.palette;
    final theme = Theme.of(context);
    final prUrl = c.effectivePrUrl;
    final rawTitle = c.prTitle ?? 'Merge request';
    final headline = mrDisplayHeadline(rawTitle);
    final branch = c.prBranch;
    final body = c.prBody;
    final statusLower = c.status.toLowerCase();
    final statusDone = statusLower == 'completed' || statusLower == 'done';

    return Material(
      color: palette.surface2,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.all(AppRadii.xl),
        side: BorderSide(color: palette.border.withValues(alpha: 0.55)),
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
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.merge_type_rounded, color: Colors.white, size: 22),
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
                          if (headline != rawTitle.trim()) ...[
                            const SizedBox(height: 4),
                            Tooltip(
                              message: rawTitle,
                              child: Text(
                                rawTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.textMuted,
                                  fontFamily: 'monospace',
                                ),
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
                              _MetaChip(
                                label: shortCrashId(c.crashId),
                                icon: Icons.tag_rounded,
                                tooltip: 'Crash id: ${c.crashId}',
                              ),
                              if (branch != null)
                                _MetaChip(
                                  label: branch,
                                  icon: Icons.call_split_rounded,
                                  tooltip: branch,
                                  maxLabelWidth: 260,
                                ),
                              if (c.status.isNotEmpty)
                                _MetaChip(
                                  label: c.status,
                                  icon: statusDone
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.info_outline_rounded,
                                  emphasize: statusDone,
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
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => context.go('/crashes/${c.crashId}'),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Crash Details'),
                      ),
                      const Spacer(),
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
              if (_expanded) ...[
                const SizedBox(height: AppSpacing.lg),
                Divider(height: 1, color: palette.border.withValues(alpha: 0.45)),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Description',
                    style: theme.textTheme.labelLarge?.copyWith(color: palette.textSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
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
                ),
              ],
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
        '$count MR${count == 1 ? '' : 's'}',
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
  final bool emphasize;

  const _MetaChip({
    required this.label,
    required this.icon,
    this.tooltip,
    this.maxLabelWidth,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final bg = emphasize
        ? palette.success.withValues(alpha: 0.12)
        : palette.surface1.withValues(alpha: 0.9);
    final border = emphasize
        ? palette.success.withValues(alpha: 0.35)
        : palette.border.withValues(alpha: 0.55);

    final child = Container(
      constraints: BoxConstraints(maxWidth: (maxLabelWidth ?? 180) + 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: emphasize ? palette.success : palette.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.labelLarge?.copyWith(
                color: emphasize ? palette.text : palette.textSecondary,
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
