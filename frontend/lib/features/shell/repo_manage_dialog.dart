import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/repo_registry_provider.dart';

class ManageReposDialog extends ConsumerStatefulWidget {
  final Future<void> Function(String repoKey, String repoName) onDelete;
  const ManageReposDialog({super.key, required this.onDelete});

  @override
  ConsumerState<ManageReposDialog> createState() => _ManageReposDialogState();
}

class _ManageReposDialogState extends ConsumerState<ManageReposDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _refCtrl;
  late final TextEditingController _firebaseProjectIdCtrl;
  late final TextEditingController _tokenCtrl;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _urlCtrl = TextEditingController();
    _refCtrl = TextEditingController();
    _firebaseProjectIdCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _refCtrl.dispose();
    _firebaseProjectIdCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final async = ref.watch(repoRegistryProvider);
    final repos = async.valueOrNull?.repos ?? const [];

    return AlertDialog(
      backgroundColor: palette.surface2,
      title: Text('Manage repositories', style: theme.titleLarge),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Existing repos',
                style: theme.labelLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 8),
              if (async.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else if (repos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No repos saved yet.',
                    style: theme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                )
              else ...[
                for (final r in repos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name, style: theme.bodyMedium),
                              Text(
                                r.repoUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.labelSmall?.copyWith(color: palette.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: _saving ? null : () => widget.onDelete(r.repoKey, r.name),
                          icon: Icon(Icons.delete_outline, color: palette.danger),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Divider(height: 1, color: palette.border.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Add / update repo',
                style: theme.labelLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Remote repo URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _refCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Git ref (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _firebaseProjectIdCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Firebase project ID',
                  hintText: 'Used for Crashlytics/BigQuery',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tokenCtrl,
                enabled: !_saving,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Access token (optional)',
                  hintText: 'For private repos',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'On save, the backend clones the repo first. If cloning fails, nothing is stored.',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: theme.bodySmall?.copyWith(color: palette.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    await ref.read(repoRegistryProvider.notifier).upsertRepo(
                          name: _nameCtrl.text.trim(),
                          repoUrl: _urlCtrl.text.trim(),
                          repoRef: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
                          firebaseProjectId: _firebaseProjectIdCtrl.text.trim().isEmpty
                              ? null
                              : _firebaseProjectIdCtrl.text.trim(),
                          accessToken:
                              _tokenCtrl.text.trim().isEmpty ? null : _tokenCtrl.text.trim(),
                        );
                    if (!mounted) return;
                    nav.pop();
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _saving = false;
                      _error = e.toString();
                    });
                  }
                },
          child: Text(_saving ? 'Cloning…' : 'Save'),
        ),
      ],
    );
  }
}

