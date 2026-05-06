import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/crash.dart';
import '../../../core/providers/config_provider.dart';
import '../../../core/models/run_event.dart';
import '../../../core/providers/run_session_provider.dart';
import '../../../core/utils/crashlytics_console_url.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/json_tree_viewer.dart';

class CrashRunCard extends ConsumerStatefulWidget {
  final CrashRunState state;
  const CrashRunCard({super.key, required this.state});

  @override
  ConsumerState<CrashRunCard> createState() => _CrashRunCardState();
}

class _CrashRunCardState extends ConsumerState<CrashRunCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final s = widget.state;
    final running = !s.completed && s.failure == null;
    final configAsync = ref.watch(configProvider);
    final crashlyticsCfg = configAsync.when(
      data: (cfg) => cfg.section('crashlytics'),
      loading: () => null,
      error: (_, _) => null,
    );
    final configLoading = configAsync.isLoading;
    final stateMap = (s.latestState ?? s.initialState);
    final crashForLink = Crash(
      crashId: s.crashId,
      status: running ? 'in_progress' : (s.failure != null ? 'failed' : 'completed'),
      result: stateMap == null ? null : Map<String, dynamic>.from(stateMap),
    );
    final crashlyticsUri =
        crashlyticsCfg == null ? null : crashlyticsIssueUri(crashForLink, crashlyticsCfg);

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
                  const SizedBox(width: 6),
                  Tooltip(
                    message: crashlyticsUri != null
                        ? 'Open issue in Firebase Crashlytics'
                        : configLoading
                            ? 'Loading configuration…'
                            : 'Cannot build link: set Firebase project id and Android package / iOS bundle '
                                '(from Crashlytics export or CRASHLYTICS_ANDROID_PACKAGE / CRASHLYTICS_IOS_BUNDLE_ID in .env).',
                    child: IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: crashlyticsUri == null
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await launchUrl(
                                crashlyticsUri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!context.mounted || ok) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open Crashlytics link'),
                                ),
                              );
                            },
                      icon: Icon(
                        Icons.open_in_new,
                        color: crashlyticsUri != null
                            ? palette.primary
                            : palette.textMuted,
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
        ev is CrashSkippedEvent ||
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
      CrashSkippedEvent(:final reason) => (
          Icons.flag_circle_outlined,
          palette.textMuted,
          'crash_skipped',
          (reason == null || reason.trim().isEmpty) ? 'skipped' : reason.trim(),
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
    final pretty = const JsonEncoder.withIndent('  ').convert(state);
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
                    IconButton(
                      tooltip: 'Copy JSON',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: pretty)),
                    ),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: JsonTreeView(value: state, expandToDepth: 2),
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

}
