import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/run_event.dart';
import '../../../core/providers/run_session_provider.dart';
import '../../../shared/widgets/glass_card.dart';

class CrashRunCard extends StatefulWidget {
  final CrashRunState state;
  const CrashRunCard({super.key, required this.state});

  @override
  State<CrashRunCard> createState() => _CrashRunCardState();
}

class _CrashRunCardState extends State<CrashRunCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final s = widget.state;
    final running = !s.completed && s.failure == null;

    Color statusColor;
    String statusLabel;
    if (s.failure != null) {
      statusColor = palette.danger;
      statusLabel = 'FAILED';
    } else if (s.completed) {
      statusColor = palette.success;
      statusLabel = 'COMPLETED';
    } else {
      statusColor = palette.primary;
      statusLabel = 'RUNNING';
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: AppRadii.all(AppRadii.lg),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  if (running)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: statusColor,
                      ),
                    )
                  else
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    s.crashId,
                    style: AppTypography.mono(color: palette.text),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.13),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                      borderRadius: AppRadii.all(AppRadii.pill),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.labelSmall?.copyWith(
                        color: statusColor,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${s.events.length} events',
                    style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Container(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _Timeline(state: s),
            ),
            if (s.failure != null) ...[
              Container(height: 1, color: palette.border),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: palette.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SelectableText(
                        s.failure!,
                        style: AppTypography.mono(color: palette.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final CrashRunState state;
  const _Timeline({required this.state});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final visible = state.events.where(_isInteresting).toList();

    if (visible.isEmpty) {
      return Text(
        'Waiting for first event…',
        style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visible.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: _eventRow(context, visible[i]),
          ).animate().fadeIn(duration: 220.ms).slideX(begin: -0.05),
      ],
    );
  }

  bool _isInteresting(RunEvent ev) {
    return ev is NodeStartedEvent ||
        ev is NodeCompletedEvent ||
        ev is RouterEvent ||
        ev is StateSnapshotEvent ||
        ev is NodeErrorEvent ||
        ev is CrashFailedEvent ||
        ev is CrashCompletedEvent;
  }

  Widget _eventRow(BuildContext context, RunEvent ev) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final (IconData icon, Color color, String label, String? meta) = switch (ev) {
      NodeStartedEvent(:final node) => (
          Icons.play_arrow_rounded,
          palette.primary,
          node,
          'started',
        ),
      NodeCompletedEvent(:final node, :final durationMs, :final added, :final changed, :final removed) => (
          Icons.check_circle_outline,
          palette.success,
          node,
          '${durationMs}ms · +$added ~$changed -$removed',
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
      StateSnapshotEvent(:final afterNode, :final state) => (
          Icons.layers_outlined,
          palette.warning,
          afterNode ?? 'initial',
          '${state.length} keys in state',
        ),
      CrashCompletedEvent() => (
          Icons.flag_circle_outlined,
          palette.success,
          'crash_completed',
          'pipeline finished',
        ),
      CrashFailedEvent() => (
          Icons.flag_circle_outlined,
          palette.danger,
          'crash_failed',
          'pipeline failed',
        ),
      _ => (Icons.bolt, palette.textMuted, ev.type, null),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Text(label, style: AppTypography.mono(color: palette.text, size: 12.5)),
              const SizedBox(width: 8),
              if (meta != null)
                Text(
                  meta,
                  style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
            ],
          ),
        ),
        if (ev is StateSnapshotEvent && (ev.state).isNotEmpty)
          IconButton(
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            tooltip: 'Inspect state',
            onPressed: () => _showState(context, ev.state),
            icon: const Icon(Icons.open_in_new),
          ),
      ],
    );
  }

  void _showState(BuildContext context, Map<String, dynamic> state) {
    final palette = context.palette;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: palette.surface2,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.lg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('CrashState snapshot', style: Theme.of(ctx).textTheme.headlineSmall),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _pretty(state),
                      style: AppTypography.mono(color: palette.text, size: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _pretty(Map<String, dynamic> state) {
    final keys = state.keys.toList()..sort();
    if (keys.isEmpty) {
      return '(empty state)';
    }

    final keyCol = keys.map((k) => k.length).fold<int>(0, (a, b) => a > b ? a : b).clamp(4, 36);
    final values = keys.map((k) => _compact(state[k])).toList(growable: false);
    final rawValWidth = values.map((s) => s.length).fold<int>(12, (a, b) => a > b ? a : b);
    final valCol = rawValWidth.clamp(12, 72);

    final buf = StringBuffer();
    final keyLabel = keys.length == 1 ? 'key' : 'keys';
    buf.writeln('State snapshot · ${keys.length} $keyLabel');
    buf.writeln('┌${'─' * (keyCol + 2)}┬${'─' * (valCol + 2)}┐');

    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final truncated = k.length > keyCol ? '${k.substring(0, keyCol - 1)}…' : k;
      final rowKey = truncated.padRight(keyCol);
      final v = values[i];
      final cell = v.length <= valCol ? v.padRight(valCol) : '${v.substring(0, valCol - 1)}…';
      buf.writeln('│ $rowKey │ $cell │');
    }
    buf.write('└${'─' * (keyCol + 2)}┴${'─' * (valCol + 2)}┘');
    return buf.toString();
  }

  String _compact(Object? v) {
    if (v == null) return 'null';
    if (v is String) {
      return v.length > 200 ? '"${v.substring(0, 200)}…"' : '"$v"';
    }
    if (v is num || v is bool) return '$v';
    if (v is List) return '[${v.length} items]';
    if (v is Map) return '{${v.length} keys}';
    return v.toString();
  }
}
