import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/run_request.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/run_session_provider.dart';

/// Confirms, then closes the existing MR, fully rewrites the Jira ticket, and
/// kicks off a brand-new fix cycle (new branch, new commits) for a crash that
/// already has a completed fix. Shared by the crash detail page and MR cards.
Future<void> confirmAndForceRestart(
  BuildContext context,
  WidgetRef ref, {
  required String crashId,
  required bool skipJiraCreation,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ForceRestartConfirmDialog(crashId: crashId),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final api = ref.read(apiClientProvider);
    await api.postJson(Endpoints.crashRestart(crashId));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restart fix cycle: $e')),
      );
    }
    return;
  }

  if (!context.mounted) return;
  final req = RunRequest(
    mode: RunMode.single,
    crashId: crashId,
    mock: false,
    skipJiraCreation: skipJiraCreation,
  );
  ref.read(runSessionProvider.notifier).start(req);
  GoRouter.of(context).go('/runs/live');
}

class _ForceRestartConfirmDialog extends StatelessWidget {
  final String crashId;
  const _ForceRestartConfirmDialog({required this.crashId});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: palette.danger, size: 28),
      title: const Text('Force restart this fix cycle?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            crashId,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontFamily: 'monospace',
                ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This discards the current attempt and starts completely over:',
          ),
          const SizedBox(height: 12),
          _bullet(context, 'Closes the existing merge request'),
          _bullet(context, 'Fully updates the Jira ticket (removes the stale MR link)'),
          _bullet(context, 'Creates a new branch with new commits from a fresh fix'),
          const SizedBox(height: 12),
          Text(
            'This cannot be undone.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.danger, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: palette.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Force restart'),
        ),
      ],
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 5, color: palette.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
