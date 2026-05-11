import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/endpoints.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/config_provider.dart';
import '../../core/models/repo_entry.dart';
import '../../core/providers/repo_registry_provider.dart';

/// `namespace/project` path for the GitLab API, derived from a normal git remote URL.
String? deriveGitlabProjectPathFromRepoUrl(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return null;
  if (u.startsWith('git@')) {
    final at = u.indexOf('@');
    final colon = u.indexOf(':');
    if (colon <= at || colon >= u.length - 1) return null;
    var path = u.substring(colon + 1).trim();
    if (path.toLowerCase().endsWith('.git')) {
      path = path.substring(0, path.length - 4);
    }
    path = path.replaceAll(RegExp(r'^/+|/+$'), '');
    return path.isEmpty ? null : path;
  }
  final uri = Uri.tryParse(u);
  if (uri == null || uri.host.isEmpty) return null;
  var path = uri.path;
  if (path.toLowerCase().endsWith('.git')) {
    path = path.substring(0, path.length - 4);
  }
  path = path.replaceAll(RegExp(r'^/+|/+$'), '');
  if (path.isEmpty) return null;
  return path;
}

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
  late final TextEditingController _jiraServerUrlCtrl;
  late final TextEditingController _jiraEmailCtrl;
  late final TextEditingController _jiraTokenCtrl;
  late final TextEditingController _jiraIssueTypeCtrl;
  late final TextEditingController _jiraProjectKeyCtrl;

  bool _saving = false;
  bool _refreshing = false;
  /// Accordion: at most one panel expanded; `0` = repository (default), `1` = Crashlytics, `2` = integrations.
  int? _expandedPanelIndex = 0;
  bool _showToken = false;
  bool _showJiraToken = false;
  String? _error;
  String? _editingRepoKey;
  Map<String, dynamic>? _repoStatus;
  bool _gcpCredsUploading = false;
  String? _gcpCredsLastMessage;
  bool _gcpCredsLastError = false;

  static const _crashBackendOptions = <String>['cloud_logging', 'bigquery'];
  static const bool _debug = kDebugMode;

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
    _jiraServerUrlCtrl = TextEditingController();
    _jiraEmailCtrl = TextEditingController();
    _jiraTokenCtrl = TextEditingController();
    _jiraIssueTypeCtrl = TextEditingController(text: 'Bug');
    _jiraProjectKeyCtrl = TextEditingController();

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
    _jiraServerUrlCtrl.addListener(onEdit);
    _jiraEmailCtrl.addListener(onEdit);
    _jiraTokenCtrl.addListener(onEdit);
    _jiraIssueTypeCtrl.addListener(onEdit);
    _jiraProjectKeyCtrl.addListener(onEdit);
  }

  String? _validate() {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final fpid = _firebaseProjectIdCtrl.text.trim();
    final crashBackend = _crashBackendCtrl.text.trim();

    if (name.isEmpty) return 'Display name is required.';
    if (url.isEmpty) return 'Remote repo URL is required.';
    final looksLikeHttp =
        url.startsWith('http://') || url.startsWith('https://');
    final looksLikeSsh = url.startsWith('git@');
    if (!looksLikeHttp && !looksLikeSsh) {
      return 'Repo URL should start with https://, http://, or git@';
    }
    if (fpid.isEmpty) return 'Firebase project ID is required.';
    // Firebase/GCP project ids are lowercase letters/digits/hyphen, typically 6–30+ chars.
    final ok = RegExp(r'^[a-z0-9-]+$').hasMatch(fpid);
    if (!ok)
      return 'Firebase project ID should be lowercase letters, digits, and hyphens only.';

    if (crashBackend.isEmpty) return 'Crashlytics backend is required.';
    if (!_crashBackendOptions.contains(crashBackend)) {
      return 'Crashlytics backend must be cloud_logging or bigquery.';
    }
    if (crashBackend == 'bigquery') {
      if (_bqDatasetCtrl.text.trim().isEmpty)
        return 'BigQuery dataset is required when using BigQuery backend.';
      if (_bqAndroidTableCtrl.text.trim().isEmpty) {
        return 'Crashlytics Android table is required when using BigQuery backend.';
      }
      if (_bqIosTableCtrl.text.trim().isEmpty)
        return 'Crashlytics iOS table is required when using BigQuery backend.';
    }
    return null;
  }

  void _prefillFromRepo(RepoEntry r) {
    setState(() {
      _error = null;
      _editingRepoKey = r.repoKey;
      _nameCtrl.text = r.name;
      _urlCtrl.text = r.repoUrl;
      _refCtrl.text = (r.repoRef ?? '').toString();
      _firebaseProjectIdCtrl.text = (r.firebaseProjectId ?? '').toString();
      _tokenCtrl.text = '';
      final dirs = r.packagesDirs;
      _packagesDirsCtrl.text = dirs
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .join(', ');
      _crashBackendCtrl.text = (r.crashlyticsFetchBackend ?? '').toString();
      _bqDatasetCtrl.text = (r.bqDataset ?? '').toString();
      _bqAndroidTableCtrl.text = (r.bqCrashlyticsAndroidTable ?? '').toString();
      _bqIosTableCtrl.text = (r.bqCrashlyticsIosTable ?? '').toString();
      _jiraServerUrlCtrl.text = (r.jiraServerUrl ?? '').toString();
      _jiraEmailCtrl.text = (r.jiraEmail ?? '').toString();
      _jiraTokenCtrl.text = '';
      _jiraIssueTypeCtrl.text =
          (r.jiraIssueType ?? '').trim().isEmpty ? 'Bug' : r.jiraIssueType!.trim();
      _jiraProjectKeyCtrl.text = (r.jiraProjectKey ?? '').toString();
      _expandedPanelIndex = 0;
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
      final s = await ref
          .read(repoRegistryProvider.notifier)
          .fetchRepoStatus(key);
      if (!mounted) return;
      setState(() => _repoStatus = s);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _pickAndUploadGcpCredentials() async {
    setState(() {
      _gcpCredsLastMessage = null;
      _gcpCredsLastError = false;
    });
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (!mounted) return;
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.single;
    final bytes = file.bytes;
    final name = file.name.trim().isEmpty ? 'credentials.json' : file.name.trim();
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _gcpCredsLastMessage =
            'Could not read file (empty or unavailable on this platform).';
        _gcpCredsLastError = true;
      });
      return;
    }
    setState(() => _gcpCredsUploading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.postMultipartFile(
        Endpoints.googleCredentials,
        bytes: bytes,
        filename: name,
      );
      if (!mounted) return;
      setState(() {
        _gcpCredsUploading = false;
        _gcpCredsLastError = false;
        _gcpCredsLastMessage =
            'Saved on the server. The backend uses this key for Crashlytics '
            '(BigQuery or Cloud Logging, depending on the backend you chose).';
      });
      await ref.read(configProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gcpCredsUploading = false;
        _gcpCredsLastError = true;
        _gcpCredsLastMessage = e.toString();
      });
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
      _expandedPanelIndex = 0;
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
    _jiraServerUrlCtrl.clear();
    _jiraEmailCtrl.clear();
    _jiraTokenCtrl.clear();
    _jiraIssueTypeCtrl.text = 'Bug';
    _jiraProjectKeyCtrl.clear();
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
    _jiraServerUrlCtrl.dispose();
    _jiraEmailCtrl.dispose();
    _jiraTokenCtrl.dispose();
    _jiraIssueTypeCtrl.dispose();
    _jiraProjectKeyCtrl.dispose();
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
    final indexedSha =
        ((_repoStatus?['index_status'] as Map?)?['indexed_sha'] ?? '')
            .toString()
            .trim();

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
                  style: theme.labelLarge?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
              if (async.isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.primary,
                  ),
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
          else if (!async.isLoading) ...[
            for (final r in repos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _saving ? null : () => _prefillFromRepo(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                                        fontWeight: r.repoKey == activeKey
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (r.repoKey == activeKey) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: palette.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'Active',
                                        style: theme.labelSmall?.copyWith(
                                          color: palette.primary,
                                        ),
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
                                style: theme.labelSmall?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                              if ((statusByKey[r.repoKey]?.headSha ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Commit: ${statusByKey[r.repoKey]!.headSha!.substring(0, 12)}',
                                      style: theme.labelSmall?.copyWith(
                                        color: palette.textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (statusByKey[r.repoKey]?.isSynced ==
                                        true)
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            size: 14,
                                            color: palette.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Indexed',
                                            style: theme.labelSmall?.copyWith(
                                              color: palette.primary,
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.sync,
                                            size: 14,
                                            color: palette.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Not indexed',
                                            style: theme.labelSmall?.copyWith(
                                              color: palette.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                              if ((r.repoRef ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty ||
                                  (r.firebaseProjectId ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty ||
                                  r.hasToken == true ||
                                  r.hasJiraToken ||
                                  (r.jiraServerUrl ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if ((r.repoRef ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty)
                                      _Chip(
                                        label:
                                            'Ref: ${(r.repoRef ?? '').toString().trim()}',
                                        palette: palette,
                                        theme: theme,
                                      ),
                                    if ((r.firebaseProjectId ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty)
                                      _Chip(
                                        label:
                                            'Firebase: ${(r.firebaseProjectId ?? '').toString().trim()}',
                                        palette: palette,
                                        theme: theme,
                                      ),
                                    if (r.hasToken == true)
                                      _Chip(
                                        label: 'Token saved',
                                        palette: palette,
                                        theme: theme,
                                      ),
                                    if (r.hasJiraToken)
                                      _Chip(
                                        label: 'Jira token saved',
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
                                    await ref
                                        .read(repoRegistryProvider.notifier)
                                        .refreshRepo(r.repoKey);
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() => _error = e.toString());
                                  }
                                },
                          icon: Icon(
                            Icons.refresh,
                            color: palette.textSecondary,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: _saving
                              ? null
                              : () => widget.onDelete(r.repoKey, r.name),
                          icon: Icon(
                            Icons.delete_outline,
                            color: palette.danger,
                          ),
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
      final crashBackend = _crashBackendCtrl.text.trim();
      final crashBackendValue = _crashBackendOptions.contains(crashBackend)
          ? crashBackend
          : null;
      final usesBigQuery = crashBackendValue == 'bigquery';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: theme.labelLarge?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            selectedKey.isEmpty
                ? 'Create a new repo entry, or select one from the list.'
                : 'Editing: $selectedKey',
            style: theme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionPanelList(
              elevation: 0,
              expandedHeaderPadding: EdgeInsets.zero,
              expansionCallback: (int index, bool isExpanded) {
                setState(() {
                  if (isExpanded) {
                    _expandedPanelIndex = index;
                  } else if (_expandedPanelIndex == index) {
                    _expandedPanelIndex = null;
                  }
                });
              },
              children: [
                ExpansionPanel(
                  canTapOnHeader: true,
                  backgroundColor: palette.surface2,
                  isExpanded: _expandedPanelIndex == 0,
                  headerBuilder: (context, expanded) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Repository',
                        style: theme.labelLarge?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        'Display name, remote URL, Git, packages',
                        style: theme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    );
                  },
                  body: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                    onPressed:
                                        _saving ? null : () => _nameCtrl.clear(),
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
                            hintText:
                                'https://github.com/org/repo.git  or  git@github.com:org/repo.git',
                            prefixIcon: const Icon(Icons.link),
                            suffixIcon: _urlCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed:
                                        _saving ? null : () => _urlCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                    onPressed:
                                        _saving ? null : () => _refCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _tokenCtrl,
                          enabled: !_saving,
                          obscureText: !_showToken,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Access token (optional)',
                            hintText: 'Only needed for private repos',
                            prefixIcon: const Icon(Icons.key_outlined),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: _showToken ? 'Hide' : 'Show',
                                  onPressed: _saving
                                      ? null
                                      : () => setState(
                                            () => _showToken = !_showToken,
                                          ),
                                  icon: Icon(
                                    _showToken
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                ),
                                if (_tokenCtrl.text.trim().isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _tokenCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                              ],
                            ),
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
                            helperText:
                                'Comma-separated repo-relative dirs. Each dir is scanned as <dir>/*/lib.',
                            prefixIcon: const Icon(Icons.folder_outlined),
                            suffixIcon: _packagesDirsCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _packagesDirsCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ExpansionPanel(
                  canTapOnHeader: true,
                  backgroundColor: palette.surface2,
                  isExpanded: _expandedPanelIndex == 1,
                  headerBuilder: (context, expanded) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Crashlytics resources',
                        style: theme.labelLarge?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        'Required for fetching Crashlytics',
                        style: theme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    );
                  },
                  body: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _firebaseProjectIdCtrl,
                          enabled: !_saving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Firebase project ID',
                            hintText: 'e.g. my-firebase-project',
                            helperText:
                                'GCP / Firebase project id used for Crashlytics queries.',
                            prefixIcon: const Icon(Icons.cloud_outlined),
                            suffixIcon: _firebaseProjectIdCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _firebaseProjectIdCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _saving || _gcpCredsUploading
                                ? null
                                : _pickAndUploadGcpCredentials,
                            icon: _gcpCredsUploading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: palette.textSecondary,
                                    ),
                                  )
                                : const Icon(Icons.key_outlined),
                            label: Text(
                              _gcpCredsUploading
                                  ? 'Uploading credentials…'
                                  : 'Upload GCP service account JSON',
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This must be a GCP service account key JSON (field "type", '
                          'usually service_account), with access to your Crashlytics data. '
                          'It is not the Android google-services.json from the Firebase console.',
                          style: theme.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                        if (_gcpCredsLastMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _gcpCredsLastMessage!,
                            style: theme.bodySmall?.copyWith(
                              color: _gcpCredsLastError
                                  ? palette.danger
                                  : palette.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: crashBackendValue,
                          items: _crashBackendOptions
                              .map(
                                (v) => DropdownMenuItem<String>(
                                  value: v,
                                  child: Text(v),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _saving
                              ? null
                              : (v) {
                                  setState(() {
                                    _crashBackendCtrl.text = (v ?? '').trim();
                                    if (_crashBackendCtrl.text != 'bigquery') {
                                      _bqDatasetCtrl.clear();
                                      _bqAndroidTableCtrl.clear();
                                      _bqIosTableCtrl.clear();
                                    }
                                  });
                                },
                          decoration: InputDecoration(
                            labelText: 'Crashlytics backend',
                            helperText: _debug
                                ? 'Maps to CRASHLYTICS_FETCH_BACKEND.'
                                : 'Where Crashlytics data is queried from.',
                            prefixIcon: const Icon(Icons.cloud_sync_outlined),
                          ),
                        ),
                        if (usesBigQuery) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _bqDatasetCtrl,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'BigQuery dataset',
                              hintText: 'firebase_crashlytics',
                              helperText: _debug
                                  ? 'BQ_DATASET'
                                  : 'Dataset name that contains Crashlytics tables.',
                              prefixIcon:
                                  const Icon(Icons.table_chart_outlined),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _bqAndroidTableCtrl,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Crashlytics Android table',
                              hintText: 'my_android_table',
                              helperText: _debug
                                  ? 'BQ_CRASHLYTICS_ANDROID_TABLE'
                                  : 'Table name for Android crashes.',
                              prefixIcon: const Icon(Icons.table_rows_outlined),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _bqIosTableCtrl,
                            enabled: !_saving,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Crashlytics iOS table',
                              hintText: 'my_ios_table',
                              helperText: _debug
                                  ? 'BQ_CRASHLYTICS_IOS_TABLE'
                                  : 'Table name for iOS crashes.',
                              prefixIcon: const Icon(Icons.table_rows_outlined),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ExpansionPanel(
                  canTapOnHeader: true,
                  backgroundColor: palette.surface2,
                  isExpanded: _expandedPanelIndex == 2,
                  headerBuilder: (context, expanded) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Jira integration',
                        style: theme.labelLarge?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        'Jira connection, issue defaults, and repo index status',
                        style: theme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    );
                  },
                  body: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _jiraServerUrlCtrl,
                          enabled: !_saving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Jira server URL',
                            hintText: 'https://jira.example.com/',
                            helperText: _debug
                                ? 'JIRA_SERVER_URL'
                                : 'Base URL of your Jira instance.',
                            prefixIcon: const Icon(Icons.link_outlined),
                            suffixIcon: _jiraServerUrlCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _jiraServerUrlCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _jiraEmailCtrl,
                          enabled: !_saving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Jira email (optional)',
                            hintText: 'user@company.com',
                            helperText: _debug
                                ? 'JIRA_EMAIL'
                                : 'Use with API token (Basic auth). Leave empty for Bearer token only.',
                            prefixIcon: const Icon(Icons.email_outlined),
                            suffixIcon: _jiraEmailCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _jiraEmailCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _jiraTokenCtrl,
                          enabled: !_saving,
                          obscureText: !_showJiraToken,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Jira API token (optional)',
                            hintText: 'Not shown after save',
                            helperText: _debug
                                ? 'JIRA_TOKEN'
                                : 'Stored on the server only. Leave blank to keep an existing token.',
                            prefixIcon: const Icon(Icons.key_outlined),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: _showJiraToken ? 'Hide' : 'Show',
                                  onPressed: _saving
                                      ? null
                                      : () => setState(
                                            () =>
                                                _showJiraToken = !_showJiraToken,
                                          ),
                                  icon: Icon(
                                    _showJiraToken
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                ),
                                if (_jiraTokenCtrl.text.trim().isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _jiraTokenCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _jiraProjectKeyCtrl,
                          enabled: !_saving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Jira project key',
                            hintText: 'PROJ',
                            helperText: _debug
                                ? 'JIRA_PROJECT_KEY'
                                : 'Project where new issues are created.',
                            prefixIcon: const Icon(
                              Icons.confirmation_number_outlined,
                            ),
                            suffixIcon: _jiraProjectKeyCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _saving
                                        ? null
                                        : () => _jiraProjectKeyCtrl.clear(),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _jiraIssueTypeCtrl,
                          enabled: !_saving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Jira issue type',
                            hintText: 'Bug',
                            helperText: _debug
                                ? 'JIRA_ISSUE_TYPE'
                                : 'Must match an issue type name in your Jira project.',
                            prefixIcon: const Icon(Icons.category_outlined),
                            suffixIcon: _jiraIssueTypeCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Reset to Bug',
                                    onPressed: _saving
                                        ? null
                                        : () => setState(
                                              () => _jiraIssueTypeCtrl.text =
                                                  'Bug',
                                            ),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (selectedKey.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surface1,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: palette.border.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Repo status',
                                        style: theme.labelLarge?.copyWith(
                                          color: palette.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        headSha.isEmpty
                                            ? 'Commit: —'
                                            : 'Commit: ${headSha.substring(0, headSha.length < 12 ? headSha.length : 12)}',
                                        style: theme.bodySmall?.copyWith(
                                          color: palette.textMuted,
                                        ),
                                      ),
                                      Text(
                                        indexedSha.isEmpty
                                            ? 'Indexed: —'
                                            : 'Indexed: ${indexedSha.substring(0, indexedSha.length < 12 ? indexedSha.length : 12)}',
                                        style: theme.bodySmall?.copyWith(
                                          color: palette.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: (_saving || _refreshing)
                                      ? null
                                      : _refreshRepo,
                                  icon: _refreshing
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: palette.primary,
                                          ),
                                        )
                                      : const Icon(Icons.refresh, size: 16),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
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
            Text(
              _error!,
              style: theme.bodySmall?.copyWith(color: palette.danger),
            ),
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
                      Divider(
                        height: 1,
                        color: palette.border.withValues(alpha: 0.5),
                      ),
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
                    await ref
                        .read(repoRegistryProvider.notifier)
                        .upsertRepo(
                          name: _nameCtrl.text.trim(),
                          repoUrl: _urlCtrl.text.trim(),
                          repoRef: _refCtrl.text.trim().isEmpty
                              ? null
                              : _refCtrl.text.trim(),
                          firebaseProjectId:
                              _firebaseProjectIdCtrl.text.trim().isEmpty
                              ? null
                              : _firebaseProjectIdCtrl.text.trim(),
                          accessToken: _tokenCtrl.text.trim().isEmpty
                              ? null
                              : _tokenCtrl.text.trim(),
                          packagesDirs: _parsePackagesDirs(),
                          crashlyticsFetchBackend: _crashBackendCtrl.text
                              .trim(),
                          bqDataset: _bqDatasetCtrl.text.trim().isEmpty
                              ? null
                              : _bqDatasetCtrl.text.trim(),
                          bqCrashlyticsAndroidTable:
                              _bqAndroidTableCtrl.text.trim().isEmpty
                              ? null
                              : _bqAndroidTableCtrl.text.trim(),
                          bqCrashlyticsIosTable:
                              _bqIosTableCtrl.text.trim().isEmpty
                              ? null
                              : _bqIosTableCtrl.text.trim(),
                          jiraProjectKey:
                              _jiraProjectKeyCtrl.text.trim().isEmpty
                              ? null
                              : _jiraProjectKeyCtrl.text.trim(),
                          jiraServerUrl:
                              _jiraServerUrlCtrl.text.trim().isEmpty
                              ? null
                              : _jiraServerUrlCtrl.text.trim(),
                          jiraEmail: _jiraEmailCtrl.text.trim().isEmpty
                              ? null
                              : _jiraEmailCtrl.text.trim(),
                          jiraToken: _jiraTokenCtrl.text.trim().isEmpty
                              ? null
                              : _jiraTokenCtrl.text.trim(),
                          jiraIssueType:
                              _jiraIssueTypeCtrl.text.trim().isEmpty
                              ? null
                              : _jiraIssueTypeCtrl.text.trim(),
                          gitlabProject:
                              deriveGitlabProjectPathFromRepoUrl(
                                _urlCtrl.text.trim(),
                              ),
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
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
  const _Chip({
    required this.label,
    required this.palette,
    required this.theme,
  });

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
