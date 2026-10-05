import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/api/endpoints.dart';
import '../../core/providers/api_provider.dart';

class DiffStats {
  final int filesChanged;
  final int additions;
  final int deletions;

  const DiffStats({
    required this.filesChanged,
    required this.additions,
    required this.deletions,
  });

  factory DiffStats.fromJson(Map<String, dynamic> j) => DiffStats(
        filesChanged: (j['files_changed'] as num?)?.toInt() ?? 0,
        additions: (j['additions'] as num?)?.toInt() ?? 0,
        deletions: (j['deletions'] as num?)?.toInt() ?? 0,
      );
}

class DiffLine {
  final String type;
  final int? oldNo;
  final int? newNo;
  final String text;

  const DiffLine({
    required this.type,
    this.oldNo,
    this.newNo,
    required this.text,
  });

  factory DiffLine.fromJson(Map<String, dynamic> j) => DiffLine(
        type: (j['type'] ?? 'context').toString(),
        oldNo: (j['old_no'] as num?)?.toInt(),
        newNo: (j['new_no'] as num?)?.toInt(),
        text: (j['text'] ?? '').toString(),
      );

  bool get isAdd => type == 'add';
  bool get isDel => type == 'del';
}

class DiffHunk {
  final String header;
  final List<DiffLine> lines;

  const DiffHunk({required this.header, required this.lines});

  factory DiffHunk.fromJson(Map<String, dynamic> j) => DiffHunk(
        header: (j['header'] ?? '').toString(),
        lines: (j['lines'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => DiffLine.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class FileDiff {
  final String path;
  final String? oldPath;
  final int additions;
  final int deletions;
  final List<DiffHunk> hunks;

  const FileDiff({
    required this.path,
    this.oldPath,
    required this.additions,
    required this.deletions,
    required this.hunks,
  });

  factory FileDiff.fromJson(Map<String, dynamic> j) => FileDiff(
        path: (j['path'] ?? '').toString(),
        oldPath: j['old_path'] as String?,
        additions: (j['additions'] as num?)?.toInt() ?? 0,
        deletions: (j['deletions'] as num?)?.toInt() ?? 0,
        hunks: (j['hunks'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => DiffHunk.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  String get wholeFileText {
    final buf = StringBuffer();
    buf.writeln('--- ${oldPath ?? path}');
    buf.writeln('+++ $path');
    for (final hunk in hunks) {
      buf.writeln(hunk.header);
      for (final line in hunk.lines) {
        final prefix = switch (line.type) {
          'add' => '+',
          'del' => '-',
          _ => ' ',
        };
        buf.writeln('$prefix${line.text}');
      }
    }
    return buf.toString();
  }
}

class CrashDiff {
  final List<FileDiff> files;
  final DiffStats stats;

  const CrashDiff({required this.files, required this.stats});

  factory CrashDiff.fromJson(Map<String, dynamic> j) => CrashDiff(
        files: (j['files'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => FileDiff.fromJson(e.cast<String, dynamic>()))
            .toList(),
        stats: DiffStats.fromJson(
          (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}

final crashDiffProvider =
    FutureProvider.autoDispose.family<CrashDiff, String>((ref, crashId) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getJson(Endpoints.crashDiff(crashId));
  return CrashDiff.fromJson((res as Map).cast<String, dynamic>());
});

/// Renders a parsed `{files, stats}` diff payload as a header stat bar plus
/// collapsible per-file hunks, monospace and colored by line type.
class DiffViewer extends StatelessWidget {
  final CrashDiff diff;
  const DiffViewer({super.key, required this.diff});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final stats = diff.stats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: palette.surface1.withValues(alpha: 0.65),
            borderRadius: AppRadii.all(AppRadii.md),
            border: Border.all(color: palette.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.difference_outlined, size: 18, color: palette.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '+${stats.additions} −${stats.deletions} across ${stats.filesChanged} '
                'file${stats.filesChanged == 1 ? '' : 's'}',
                style: theme.titleSmall?.copyWith(color: palette.text),
              ),
              const Spacer(),
              Text(
                '+${stats.additions}',
                style: AppTypography.mono(color: palette.success, size: 13),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '−${stats.deletions}',
                style: AppTypography.mono(color: palette.danger, size: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (diff.files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(
              child: Text(
                'No files changed.',
                style: theme.bodyMedium?.copyWith(color: palette.textMuted),
              ),
            ),
          )
        else
          for (final file in diff.files) ...[
            _FileSection(file: file),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

class _FileSection extends StatefulWidget {
  final FileDiff file;
  const _FileSection({required this.file});

  @override
  State<_FileSection> createState() => _FileSectionState();
}

class _FileSectionState extends State<_FileSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final file = widget.file;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.72),
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: AppRadii.all(AppRadii.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.mono(color: palette.text, size: 13),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '+${file.additions}',
                    style: AppTypography.mono(color: palette.success, size: 12.5),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '−${file.deletions}',
                    style: AppTypography.mono(color: palette.danger, size: 12.5),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Tooltip(
                    message: 'Copy whole-file diff',
                    child: IconButton(
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.copy_rounded, color: palette.textMuted),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: file.wholeFileText),
                        );
                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Diff copied to clipboard')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: palette.border.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final hunk in file.hunks) ...[
                    _HunkView(hunk: hunk),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (file.hunks.isEmpty)
                    Text(
                      'No hunks parsed for this file.',
                      style: theme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HunkView extends StatelessWidget {
  final DiffHunk hunk;
  const _HunkView({required this.hunk});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bg.withValues(alpha: 0.35),
        borderRadius: AppRadii.all(AppRadii.sm),
        border: Border.all(color: palette.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hunk.header.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              child: Text(
                hunk.header,
                style: AppTypography.mono(color: palette.textMuted, size: 12),
              ),
            ),
          for (final line in hunk.lines) _DiffLineRow(line: line),
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final DiffLine line;
  const _DiffLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = line.isAdd
        ? palette.success.withValues(alpha: 0.12)
        : line.isDel
            ? palette.danger.withValues(alpha: 0.12)
            : Colors.transparent;
    final fg = line.isAdd
        ? palette.success
        : line.isDel
            ? palette.danger
            : palette.textMuted;
    final prefix = line.isAdd ? '+' : (line.isDel ? '-' : ' ');

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              line.oldNo?.toString() ?? '',
              style: AppTypography.mono(color: palette.textMuted, size: 11.5),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              line.newNo?.toString() ?? '',
              style: AppTypography.mono(color: palette.textMuted, size: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              '$prefix${line.text}',
              softWrap: true,
              style: AppTypography.mono(color: fg, size: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
