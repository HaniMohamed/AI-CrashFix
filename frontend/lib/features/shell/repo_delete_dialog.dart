import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/repo_registry_provider.dart';

class DeleteRepoDialog extends ConsumerStatefulWidget {
  final String repoKey;
  final String repoName;
  const DeleteRepoDialog({super.key, required this.repoKey, required this.repoName});

  @override
  ConsumerState<DeleteRepoDialog> createState() => _DeleteRepoDialogState();
}

class _DeleteRepoDialogState extends ConsumerState<DeleteRepoDialog> {
  late final TextEditingController _ctrl;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: palette.surface2,
      title: Text('Delete repository', style: theme.titleLarge),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will delete the repository entry and ALL related local data '
              '(cloned workspace + crash database).',
              style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              'Type the repo name to confirm:',
              style: theme.labelMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              enabled: !_deleting,
              decoration: InputDecoration(hintText: widget.repoName),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: theme.bodySmall?.copyWith(color: palette.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _deleting
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  if (_ctrl.text.trim() != widget.repoName.trim()) {
                    setState(() => _error = 'Name did not match.');
                    return;
                  }
                  setState(() {
                    _deleting = true;
                    _error = null;
                  });
                  try {
                    await ref.read(repoRegistryProvider.notifier).deleteRepo(
                          repoKey: widget.repoKey,
                          confirmName: widget.repoName,
                        );
                    if (!mounted) return;
                    nav.pop();
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _deleting = false;
                      _error = e.toString();
                    });
                  }
                },
          child: Text(_deleting ? 'Deleting…' : 'Delete'),
        ),
      ],
    );
  }
}

