import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/repo_registry_provider.dart';

class ManageReposDialog extends ConsumerStatefulWidget {
  final Future<void> Function(String repoKey, String repoName) onDelete;
  final bool allowClose;
  const ManageReposDialog({
    super.key,
    required this.onDelete,
    this.allowClose = true,
  });

  @override
  ConsumerState<ManageReposDialog> createState() => _ManageReposDialogState();
}

class _ManageReposDialogState extends ConsumerState<ManageReposDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _refCtrl;
  late final TextEditingController _firebaseProjectIdCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _packagesDirsCtrl;
  late final TextEditingController _crashBackendCtrl;
  late final TextEditingController _bqDatasetCtrl;
  late final TextEditingController _bqAndroidTableCtrl;
  late final TextEditingController _bqIosTableCtrl;
  late final TextEditingController _jiraProjectKeyCtrl;
  late final TextEditingController _gitlabProjectCtrl;

  bool _saving = false;
  bool _refreshing = false;
  bool _advancedOpen = false;
  bool _showToken = false;
  String? _error;
  String? _editingRepoKey;
  Map<String, dynamic>? _repoStatus;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _urlCtrl = TextEditingController();
    _refCtrl = TextEditingController();
    _firebaseProjectIdCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    _packagesDirsCtrl = TextEditingController();
    _crashBackendCtrl = TextEditingController();
    _bqDatasetCtrl = TextEditingController();
    _bqAndroidTableCtrl = TextEditingController();
    _bqIosTableCtrl = TextEditingController();
    _jiraProjectKeyCtrl = TextEditingController();
    _gitlabProjectCtrl = TextEditingController();

    void onEdit() {
      if (!mounted) return;
      setState(() {
        _error = null;
      });
    }

    _nameCtrl.addListener(onEdit);
    _urlCtrl.addListener(onEdit);
    _refCtrl.addListener(onEdit);
    _firebaseProjectIdCtrl.addListener(onEdit);
    _tokenCtrl.addListener(onEdit);
    _packagesDirsCtrl.addListener(onEdit);
    _crashBackendCtrl.addListener(onEdit);
    _bqDatasetCtrl.addListener(onEdit);
    _bqAndroidTableCtrl.addListener(onEdit);
    _bqIosTableCtrl.addListener(onEdit);
    _jiraProjectKeyCtrl.addListener(onEdit);
    _gitlabProjectCtrl.addListener(onEdit);
  }

  String? _validate() {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final fpid = _firebaseProjectIdCtrl.text.trim();

    if (name.isEmpty) return 'Display name is required.';
    if (url.isEmpty) return 'Remote repo URL is required.';
    final looksLikeHttp = url.startsWith('http://') || url.startsWith('https://');
    final looksLikeSsh = url.startsWith('git@');
    if (!looksLikeHttp && !looksLikeSsh) {
      return 'Repo URL should start with https://, http://, or git@';
    }
    if (fpid.isEmpty) return 'Firebase project ID is required.';
    // Firebase/GCP project ids are lowercase letters/digits/hyphen, typically 6–30+ chars.
    final ok = RegExp(r'^[a-z0-9-]+$').hasMatch(fpid);
    if (!ok) return 'Firebase project ID should be lowercase letters, digits, and hyphens only.';
    return null;
  }

  void _prefillFromRepo(dynamic r) {
    // dynamic to avoid importing the model directly; `r` is a RepoEntry.
    setState(() {
      _error = null;
      _editingRepoKey = (r.repoKey ?? '').toString();
      _nameCtrl.text = (r.name ?? '').toString();
      _urlCtrl.text = (r.repoUrl ?? '').toString();
      _refCtrl.text = (r.repoRef ?? '').toString();
      _firebaseProjectIdCtrl.text = (r.firebaseProjectId ?? '').toString();
      _tokenCtrl.text = '';
      final dirs = (r.packagesDirs as List?) ?? const [];
      _packagesDirsCtrl.text = dirs.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).join(', ');
      _crashBackendCtrl.text = (r.crashlyticsFetchBackend ?? '').toString();
      _bqDatasetCtrl.text = (r.bqDataset ?? '').toString();
      _bqAndroidTableCtrl.text = (r.bqCrashlyticsAndroidTable ?? '').toString();
      _bqIosTableCtrl.text = (r.bqCrashlyticsIosTable ?? '').toString();
      _jiraProjectKeyCtrl.text = (r.jiraProjectKey ?? '').toString();
      _gitlabProjectCtrl.text = (r.gitlabProject ?? '').toString();
      _advancedOpen = (r.repoRef != null && (r.repoRef as String).trim().isNotEmpty) || r.hasToken == true;
    });
    _loadRepoStatus();
  }

  List<String> _parsePackagesDirs() => _packagesDirsCtrl.text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  Future<void> _loadRepoStatus() async {
    final key = (_editingRepoKey ?? '').trim();
    if (key.isEmpty) return;
    try {
      final s = await ref.read(repoRegistryProvider.notifier).fetchRepoStatus(key);
      if (!mounted) return;
      setState(() => _repoStatus = s);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _refreshRepo() async {
    final key = (_editingRepoKey ?? '').trim();
    if (key.isEmpty || _refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final s = await ref.read(repoRegistryProvider.notifier).refreshRepo(key);
      if (!mounted) return;
      setState(() => _repoStatus = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _startNew() {
    setState(() {
      _error = null;
      _editingRepoKey = null;
      _repoStatus = null;
      _advancedOpen = false;
    });
    _nameCtrl.clear();
    _urlCtrl.clear();
    _refCtrl.clear();
    _firebaseProjectIdCtrl.clear();
    _tokenCtrl.clear();
    _packagesDirsCtrl.clear();
    _crashBackendCtrl.clear();
    _bqDatasetCtrl.clear();
    _bqAndroidTableCtrl.clear();
    _bqIosTableCtrl.clear();
    _jiraProjectKeyCtrl.clear();
    _gitlabProjectCtrl.clear();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _refCtrl.dispose();
    _firebaseProjectIdCtrl.dispose();
    _tokenCtrl.dispose();
    _packagesDirsCtrl.dispose();
    _crashBackendCtrl.dispose();
    _bqDatasetCtrl.dispose();
    _bqAndroidTableCtrl.dispose();
    _bqIosTableCtrl.dispose();
    _jiraProjectKeyCtrl.dispose();
    _gitlabProjectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final async = ref.watch(repoRegistryProvider);
    final repos = async.valueOrNull?.repos ?? const [];
    final activeKey = async.valueOrNull?.active?.repoKey;
    final statusByKey = async.valueOrNull?.statusByKey ?? const {};

    final validationError = _validate();
    final canSave = !_saving && validationError == null;
    final headSha = (_repoStatus?['head_sha'] ?? '').toString().trim();
    final indexedSha = ((_repoStatus?['index_status'] as Map?)?['indexed_sha'] ?? '').toString().trim();

    final isNarrow = MediaQuery.sizeOf(context).width < 900;
    final selectedKey = (_editingRepoKey ?? '').trim();

    Widget repoListPanel() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Repositories',
                  style: theme.labelLarge?.copyWith(color: palette.textSecondary),
                ),
              ),
              if (async.isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _startNew,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!async.isLoading && repos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No repos saved yet.',
                style: theme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            )
          else if (!async.isLoading)
            ...[
              for (final r in repos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _saving ? null : () => _prefillFromRepo(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: palette.surface1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: r.repoKey == selectedKey
                              ? palette.primary.withValues(alpha: 0.75)
                              : r.repoKey == activeKey
                                  ? palette.primary.withValues(alpha: 0.55)
                                  : palette.border.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.name,
                                        style: theme.bodyMedium?.copyWith(
                                          fontWeight:
                                              r.repoKey == activeKey ? FontWeight.w700 : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (r.repoKey == activeKey) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: palette.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
                                        ),
                                        child: Text(
                                          'Active',
                                          style: theme.labelSmall?.copyWith(color: palette.primary),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  r.repoUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.labelSmall?.copyWith(color: palette.textMuted),
                                ),
                                if ((statusByKey[r.repoKey]?.headSha ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        'Commit: ${statusByKey[r.repoKey]!.headSha!.substring(0, 12)}',
                                        style: theme.labelSmall?.copyWith(color: palette.textMuted),
                                      ),
                                      const SizedBox(width: 8),
                                      if (statusByKey[r.repoKey]?.isSynced == true)
                                        Row(
                                          children: [
                                            Icon(Icons.check_circle, size: 14, color: palette.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Indexed',
                                              style: theme.labelSmall?.copyWith(color: palette.primary),
                                            ),
                                          ],
                                        )
                                      else
                                        Row(
                                          children: [
                                            Icon(Icons.sync, size: 14, color: palette.textMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Not indexed',
                                              style: theme.labelSmall?.copyWith(color: palette.textMuted),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                                if ((r.repoRef ?? '').toString().trim().isNotEmpty ||
                                    (r.firebaseProjectId ?? '').toString().trim().isNotEmpty ||
                                    r.hasToken == true) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if ((r.repoRef ?? '').toString().trim().isNotEmpty)
                                        _Chip(
                                          label: 'Ref: ${(r.repoRef ?? '').toString().trim()}',
                                          palette: palette,
                                          theme: theme,
                                        ),
                                      if ((r.firebaseProjectId ?? '').toString().trim().isNotEmpty)
                                        _Chip(
                                          label: 'Firebase: ${(r.firebaseProjectId ?? '').toString().trim()}',
                                          palette: palette,
                                          theme: theme,
                                        ),
                                      if (r.hasToken == true)
                                        _Chip(
                                          label: 'Token saved',
                                          palette: palette,
                                          theme: theme,
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Refresh (fetch + reindex on commit change)',
                            onPressed: _saving
                                ? null
                                : () async {
                                    try {
                                      await ref.read(repoRegistryProvider.notifier).refreshRepo(r.repoKey);
                                    } catch (e) {
                                      if (!mounted) return;
                                      setState(() => _error = e.toString());
                                    }
                                  },
                            icon: Icon(Icons.refresh, color: palette.textSecondary),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: _saving ? null : () => widget.onDelete(r.repoKey, r.name),
                            icon: Icon(Icons.delete_outline, color: palette.danger),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
        ],
      );
    }

    Widget detailsPanel() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: theme.labelLarge?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            selectedKey.isEmpty ? 'Create a new repo entry, or select one from the list.' : 'Editing: $selectedKey',
            style: theme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Display name',
              hintText: 'e.g. Taminaty Mobile',
              prefixIcon: const Icon(Icons.badge_outlined),
              suffixIcon: _nameCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: _saving ? null : () => _nameCtrl.clear(),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtrl,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Remote repo URL',
              hintText: 'https://github.com/org/repo.git  or  git@github.com:org/repo.git',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: _urlCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: _saving ? null : () => _urlCtrl.clear(),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _firebaseProjectIdCtrl,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Firebase project ID',
              hintText: 'e.g. my-firebase-project',
              helperText: 'Used for Crashlytics/BigQuery queries for this repo.',
              prefixIcon: const Icon(Icons.cloud_outlined),
              suffixIcon: _firebaseProjectIdCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: _saving ? null : () => _firebaseProjectIdCtrl.clear(),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _advancedOpen,
              onExpansionChanged: (v) => setState(() => _advancedOpen = v),
              title: Text(
                'Advanced',
                style: theme.labelLarge?.copyWith(color: palette.textSecondary),
              ),
              subtitle: Text(
                'Git ref, token, indexing and integrations',
                style: theme.bodySmall?.copyWith(color: palette.textMuted),
              ),
              children: [
                const SizedBox(height: 6),
                TextField(
                  controller: _crashBackendCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Crashlytics backend (optional)',
                    hintText: 'bigquery  or  cloud_logging',
                    helperText: 'Per-repo override for CRASHLYTICS_FETCH_BACKEND.',
                    prefixIcon: const Icon(Icons.cloud_sync_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bqDatasetCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'BigQuery dataset (optional)',
                    hintText: 'firebase_crashlytics',
                    helperText: 'Per-repo override for BQ_DATASET.',
                    prefixIcon: const Icon(Icons.table_chart_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bqAndroidTableCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Crashlytics Android table (optional)',
                    hintText: 'my_android_table',
                    helperText: 'Per-repo override for BQ_CRASHLYTICS_ANDROID_TABLE.',
                    prefixIcon: const Icon(Icons.table_rows_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bqIosTableCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Crashlytics iOS table (optional)',
                    hintText: 'my_ios_table',
                    helperText: 'Per-repo override for BQ_CRASHLYTICS_IOS_TABLE.',
                    prefixIcon: const Icon(Icons.table_rows_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _jiraProjectKeyCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Jira project key (optional)',
                    hintText: 'PROJ',
                    helperText: 'Per-repo override for JIRA_PROJECT_KEY.',
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _gitlabProjectCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'GitLab project (optional)',
                    hintText: 'namespace/project',
                    helperText: 'Per-repo override for GITLAB_PROJECT.',
                    prefixIcon: const Icon(Icons.merge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _packagesDirsCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Packages dirs (optional)',
                    hintText: 'e.g. packages, modules',
                    helperText: 'Comma-separated repo-relative dirs. Each dir is scanned as <dir>/*/lib.',
                    prefixIcon: const Icon(Icons.folder_outlined),
                    suffixIcon: _packagesDirsCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: _saving ? null : () => _packagesDirsCtrl.clear(),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                if (selectedKey.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: palette.surface1,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Repo status',
                                style: theme.labelLarge?.copyWith(color: palette.textSecondary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                headSha.isEmpty
                                    ? 'Commit: —'
                                    : 'Commit: ${headSha.substring(0, headSha.length < 12 ? headSha.length : 12)}',
                                style: theme.bodySmall?.copyWith(color: palette.textMuted),
                              ),
                              Text(
                                indexedSha.isEmpty
                                    ? 'Indexed: —'
                                    : 'Indexed: ${indexedSha.substring(0, indexedSha.length < 12 ? indexedSha.length : 12)}',
                                style: theme.bodySmall?.copyWith(color: palette.textMuted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: (_saving || _refreshing) ? null : _refreshRepo,
                          icon: _refreshing
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                                )
                              : const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _refCtrl,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Git ref (optional)',
                    hintText: 'branch / tag / commit SHA',
                    prefixIcon: const Icon(Icons.alt_route),
                    suffixIcon: _refCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: _saving ? null : () => _refCtrl.clear(),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tokenCtrl,
                  enabled: !_saving,
                  obscureText: !_showToken,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Access token (optional)',
                    hintText: 'Only needed for private repos',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _showToken ? 'Hide' : 'Show',
                          onPressed: _saving ? null : () => setState(() => _showToken = !_showToken),
                          icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                        ),
                        if (_tokenCtrl.text.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Clear',
                            onPressed: _saving ? null : () => _tokenCtrl.clear(),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'On save, the backend clones the repo first. If cloning fails, nothing is stored.',
            style: theme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          if (validationError != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: palette.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    validationError,
                    style: theme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: theme.bodySmall?.copyWith(color: palette.danger)),
          ],
        ],
      );
    }

    return AlertDialog(
      backgroundColor: palette.surface2,
      title: Text('Manage repositories', style: theme.titleLarge),
      content: SizedBox(
        width: isNarrow ? 720 : 1040,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useTwoCols = constraints.maxWidth >= 920;
            final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

            if (!useTwoCols) {
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      repoListPanel(),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: palette.border.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      detailsPanel(),
                    ],
                  ),
                ),
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 8),
                        child: repoListPanel(),
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 32,
                    thickness: 1,
                    color: palette.border.withValues(alpha: 0.55),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(left: 4),
                        child: detailsPanel(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (widget.allowClose)
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        FilledButton(
          onPressed: !canSave
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
                          packagesDirs: _parsePackagesDirs(),
                          crashlyticsFetchBackend: _crashBackendCtrl.text.trim().isEmpty
                              ? null
                              : _crashBackendCtrl.text.trim(),
                          bqDataset: _bqDatasetCtrl.text.trim().isEmpty ? null : _bqDatasetCtrl.text.trim(),
                          bqCrashlyticsAndroidTable: _bqAndroidTableCtrl.text.trim().isEmpty
                              ? null
                              : _bqAndroidTableCtrl.text.trim(),
                          bqCrashlyticsIosTable: _bqIosTableCtrl.text.trim().isEmpty
                              ? null
                              : _bqIosTableCtrl.text.trim(),
                          jiraProjectKey: _jiraProjectKeyCtrl.text.trim().isEmpty
                              ? null
                              : _jiraProjectKeyCtrl.text.trim(),
                          gitlabProject: _gitlabProjectCtrl.text.trim().isEmpty
                              ? null
                              : _gitlabProjectCtrl.text.trim(),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
              ],
              Text(_saving ? 'Cloning…' : 'Save'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final dynamic palette;
  final TextTheme theme;
  const _Chip({required this.label, required this.palette, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: theme.labelSmall?.copyWith(color: palette.textSecondary),
      ),
    );
  }
}

