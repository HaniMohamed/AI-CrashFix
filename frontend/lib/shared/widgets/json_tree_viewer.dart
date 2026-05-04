import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/typography.dart';

/// Expandable JSON / Dart-value tree (maps, lists, primitives) with syntax-style
/// coloring. Uses [SelectionArea] for selection across rows.
class JsonTreeView extends StatelessWidget {
  final Object? value;
  /// Nesting levels that start expanded (0 = only root row headers; 1 = one more level; …).
  final int expandToDepth;

  const JsonTreeView({
    super.key,
    required this.value,
    this.expandToDepth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (value == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          'null',
          style: AppTypography.mono(color: palette.textMuted, size: 12),
        ),
      );
    }
    return SelectionArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: _JsonRootBody(
          value: value,
          expandToDepth: expandToDepth,
        ),
      ),
    );
  }
}

class _JsonRootBody extends StatelessWidget {
  final Object? value;
  final int expandToDepth;

  const _JsonRootBody({
    required this.value,
    required this.expandToDepth,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final root = value;
    if (root is Map) {
      final m = _asStringKeyedMap(root);
      if (m.isEmpty) {
        return Text(
          '{ }',
          style: AppTypography.mono(color: palette.textSecondary, size: 12),
        );
      }
      final keys = m.keys.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < keys.length; i++)
            _JsonFieldRow(
              label: _quotedKey(keys[i]),
              value: m[keys[i]],
              depth: 0,
              expandToDepth: expandToDepth,
            ),
        ],
      );
    }
    if (root is List) {
      final list = List<Object?>.from(root);
      if (list.isEmpty) {
        return Text(
          '[ ]',
          style: AppTypography.mono(color: palette.textSecondary, size: 12),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < list.length; i++)
            _JsonFieldRow(
              label: '[$i]',
              value: list[i],
              depth: 0,
              expandToDepth: expandToDepth,
              quoteLabel: false,
            ),
        ],
      );
    }
    return _JsonLeaf(value: root, palette: palette);
  }
}

Map<String, Object?> _asStringKeyedMap(Map map) {
  return Map<String, Object?>.fromEntries(
    map.entries.map((e) => MapEntry(e.key.toString(), e.value)),
  );
}

String _quotedKey(String k) {
  final escaped = k.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

class _JsonFieldRow extends StatefulWidget {
  final String label;
  final Object? value;
  final int depth;
  final int expandToDepth;
  final bool quoteLabel;

  const _JsonFieldRow({
    required this.label,
    required this.value,
    required this.depth,
    required this.expandToDepth,
    this.quoteLabel = true,
  });

  @override
  State<_JsonFieldRow> createState() => _JsonFieldRowState();
}

class _JsonFieldRowState extends State<_JsonFieldRow> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.depth < widget.expandToDepth;
  }

  bool get _isExpandableMap => widget.value is Map && _asStringKeyedMap(widget.value as Map).isNotEmpty;

  bool get _isExpandableList => widget.value is List && (widget.value as List).isNotEmpty;

  bool get _canExpand => _isExpandableMap || _isExpandableList;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mono = AppTypography.mono(color: palette.text, size: 12);

    final labelStyle = AppTypography.mono(
      color: widget.quoteLabel ? palette.primary : palette.secondary,
      size: 12,
    );
    final colon = TextSpan(
      text: ': ',
      style: AppTypography.mono(color: palette.textSecondary, size: 12),
    );

    if (!_canExpand) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 22, height: 22),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: mono,
                  children: [
                    TextSpan(text: widget.label, style: labelStyle),
                    colon,
                    ..._leafTextSpans(widget.value, palette),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final summary = _isExpandableMap
        ? '{ ${_asStringKeyedMap(widget.value as Map).length} keys }'
        : '[ ${(widget.value as List).length} items ]';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 22,
              height: 22,
              child: Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: widget.label, style: labelStyle),
                        colon,
                        if (!_expanded)
                          TextSpan(
                            text: summary,
                            style: AppTypography.mono(color: palette.textMuted, size: 12),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  Padding(
                    padding: EdgeInsets.only(left: 12 + widget.depth * 8, top: 2),
                    child: _JsonChildren(
                      value: widget.value,
                      depth: widget.depth + 1,
                      expandToDepth: widget.expandToDepth,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JsonChildren extends StatelessWidget {
  final Object? value;
  final int depth;
  final int expandToDepth;

  const _JsonChildren({
    required this.value,
    required this.depth,
    required this.expandToDepth,
  });

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final m = _asStringKeyedMap(value as Map);
      final keys = m.keys.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in keys)
            _JsonFieldRow(
              label: _quotedKey(k),
              value: m[k],
              depth: depth,
              expandToDepth: expandToDepth,
            ),
        ],
      );
    }
    if (value is List) {
      final list = List<Object?>.from(value as List);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < list.length; i++)
            _JsonFieldRow(
              label: '[$i]',
              value: list[i],
              depth: depth,
              expandToDepth: expandToDepth,
              quoteLabel: false,
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

List<InlineSpan> _leafTextSpans(Object? v, AppPalette palette) {
  if (v == null) {
    return [
      TextSpan(
        text: 'null',
        style: AppTypography.mono(color: palette.textMuted, size: 12),
      ),
    ];
  }
  if (v is bool) {
    return [
      TextSpan(
        text: '$v',
        style: AppTypography.mono(color: palette.secondary, size: 12),
      ),
    ];
  }
  if (v is num) {
    return [
      TextSpan(
        text: '$v',
        style: AppTypography.mono(color: palette.warning, size: 12),
      ),
    ];
  }
  if (v is String) {
    return [
      TextSpan(
        text: '"${_escapeString(v)}"',
        style: AppTypography.mono(color: palette.success, size: 12),
      ),
    ];
  }
  if (v is Map && v.isEmpty) {
    return [
      TextSpan(
        text: '{ }',
        style: AppTypography.mono(color: palette.textSecondary, size: 12),
      ),
    ];
  }
  if (v is List && v.isEmpty) {
    return [
      TextSpan(
        text: '[ ]',
        style: AppTypography.mono(color: palette.textSecondary, size: 12),
      ),
    ];
  }
  return [
    TextSpan(
      text: v.toString(),
      style: AppTypography.mono(color: palette.text, size: 12),
    ),
  ];
}

String _escapeString(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

class _JsonLeaf extends StatelessWidget {
  final Object? value;
  final AppPalette palette;

  const _JsonLeaf({required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _leafTextSpans(value, palette)),
    );
  }
}
