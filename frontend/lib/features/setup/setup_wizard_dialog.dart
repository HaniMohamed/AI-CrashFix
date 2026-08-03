import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/api/endpoints.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/backend_settings_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/providers/run_session_provider.dart';
import '../../core/providers/setup_status_provider.dart';
import '../../core/models/run_request.dart';
import '../../shared/widgets/fixora_mark.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../util/service_account_json_pick.dart';
import '../shell/repo_manage_dialog.dart';

/// Multi-step Fixora onboarding. Shown as a modal when setup is incomplete.
class SetupWizardDialog extends ConsumerStatefulWidget {
  final bool allowClose;
  const SetupWizardDialog({super.key, this.allowClose = false});

  @override
  ConsumerState<SetupWizardDialog> createState() => _SetupWizardDialogState();
}

class _SetupWizardDialogState extends ConsumerState<SetupWizardDialog> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _info;

  // LLM
  String _provider = 'gemini';
  final _geminiModelCtrl = TextEditingController(text: 'gemini-2.5-flash');
  final _googleKeyCtrl = TextEditingController();
  final _openaiUrlCtrl =
      TextEditingController(text: 'https://api.openai.com/v1');
  final _openaiModelCtrl = TextEditingController(text: 'gpt-4o-mini');
  final _openaiKeyCtrl = TextEditingController();
  final _gosiUrlCtrl = TextEditingController();
  final _gosiModelCtrl = TextEditingController();
  final _gosiAuthCtrl = TextEditingController();
  final _gosiApiKeyCtrl = TextEditingController();

  // Crashlytics
  final _bqProjectCtrl = TextEditingController();
  bool _credsUploading = false;
  bool _hasCreds = false;

  // Integrations
  final _jiraUrlCtrl = TextEditingController();
  final _jiraEmailCtrl = TextEditingController();
  final _jiraTokenCtrl = TextEditingController();
  final _gitlabUrlCtrl = TextEditingController();
  final _gitlabTokenCtrl = TextEditingController();

  static const _titles = [
    'Welcome',
    'LLM provider',
    'Crashlytics / GCP',
    'Jira & GitLab',
    'Flutter repository',
    'First run',
  ];

  @override
  void dispose() {
    _geminiModelCtrl.dispose();
    _googleKeyCtrl.dispose();
    _openaiUrlCtrl.dispose();
    _openaiModelCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _gosiUrlCtrl.dispose();
    _gosiModelCtrl.dispose();
    _gosiAuthCtrl.dispose();
    _gosiApiKeyCtrl.dispose();
    _bqProjectCtrl.dispose();
    _jiraUrlCtrl.dispose();
    _jiraEmailCtrl.dispose();
    _jiraTokenCtrl.dispose();
    _gitlabUrlCtrl.dispose();
    _gitlabTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _syncFromSettings() async {
    final s = ref.read(backendSettingsProvider).valueOrNull;
    if (s == null) return;
    final llm = s.section('llm');
    final p = (llm['provider'] ?? 'gemini').toString().toLowerCase();
    _provider = (p == 'openai' || p == 'gosi-brain') ? p : 'gemini';
    _geminiModelCtrl.text = (llm['gemini_model'] ?? 'gemini-2.5-flash').toString();
    _openaiUrlCtrl.text =
        (llm['openai_url'] ?? 'https://api.openai.com/v1').toString();
    _openaiModelCtrl.text = (llm['openai_model'] ?? 'gpt-4o-mini').toString();
    _gosiUrlCtrl.text = (llm['gosi_brain_url'] ?? '').toString();
    _gosiModelCtrl.text = (llm['gosi_brain_model'] ?? '').toString();
    final crash = s.section('crashlytics');
    _bqProjectCtrl.text = (crash['bq_project_id'] ?? '').toString();
    _hasCreds =
        (crash['google_application_credentials'] ?? '').toString().trim().isNotEmpty;
    final jira = s.section('jira');
    _jiraUrlCtrl.text = (jira['server_url'] ?? '').toString();
    _jiraEmailCtrl.text = (jira['email'] ?? '').toString();
    final gl = s.section('gitlab');
    _gitlabUrlCtrl.text = (gl['server_url'] ?? '').toString();
  }

  Future<void> _saveLlm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final llm = <String, dynamic>{'provider': _provider};
      if (_provider == 'gemini') {
        llm['gemini_model'] = _geminiModelCtrl.text.trim();
        if (_googleKeyCtrl.text.trim().isNotEmpty) {
          llm['google_api_key'] = _googleKeyCtrl.text.trim();
        }
      } else if (_provider == 'openai') {
        llm['openai_url'] = _openaiUrlCtrl.text.trim();
        llm['openai_model'] = _openaiModelCtrl.text.trim();
        if (_openaiKeyCtrl.text.trim().isNotEmpty) {
          llm['openai_api_key'] = _openaiKeyCtrl.text.trim();
        }
      } else {
        llm['gosi_brain_url'] = _gosiUrlCtrl.text.trim();
        llm['gosi_brain_model'] = _gosiModelCtrl.text.trim();
        if (_gosiAuthCtrl.text.trim().isNotEmpty) {
          llm['gosi_brain_authorization'] = _gosiAuthCtrl.text.trim();
        }
        if (_gosiApiKeyCtrl.text.trim().isNotEmpty) {
          llm['gosi_brain_api_key'] = _gosiApiKeyCtrl.text.trim();
        }
      }
      await ref.read(backendSettingsProvider.notifier).save({'llm': llm});
      await ref.read(setupStatusProvider.notifier).refresh();
      setState(() => _step = 2);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCrashlytics({required bool skip}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!skip) {
        await ref.read(backendSettingsProvider.notifier).save({
          'crashlytics': {
            'bq_project_id': _bqProjectCtrl.text.trim(),
          },
        });
      }
      await ref.read(setupStatusProvider.notifier).refresh();
      setState(() => _step = 3);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadCreds() async {
    setState(() {
      _credsUploading = true;
      _error = null;
    });
    try {
      final picked = await pickServiceAccountJsonFile();
      if (picked == null) return;
      final api = ref.read(apiClientProvider);
      await api.postMultipartFile(
        Endpoints.googleCredentials,
        bytes: picked.bytes,
        filename: picked.name,
      );
      setState(() {
        _hasCreds = true;
        _info = 'Service account uploaded.';
      });
      await ref.read(backendSettingsProvider.notifier).refresh();
      await ref.read(setupStatusProvider.notifier).refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _credsUploading = false);
    }
  }

  Future<void> _saveIntegrations({required bool skip}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!skip) {
        final payload = <String, dynamic>{
          'jira': {
            'server_url': _jiraUrlCtrl.text.trim(),
            'email': _jiraEmailCtrl.text.trim(),
            if (_jiraTokenCtrl.text.trim().isNotEmpty)
              'token': _jiraTokenCtrl.text.trim(),
          },
          'gitlab': {
            'server_url': _gitlabUrlCtrl.text.trim(),
            if (_gitlabTokenCtrl.text.trim().isNotEmpty)
              'token': _gitlabTokenCtrl.text.trim(),
          },
        };
        await ref.read(backendSettingsProvider.notifier).save(payload);
      }
      await ref.read(setupStatusProvider.notifier).refresh();
      setState(() => _step = 4);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePath(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backendSettingsProvider.notifier).refresh();
      await _syncFromSettings();
      await ref
          .read(setupStatusProvider.notifier)
          .saveProgress(setupPath: path, clearComplete: true);
      setState(() => _step = 1);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRepoDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManageReposDialog(
        allowClose: true,
        onDelete: (_, _) async {},
      ),
    );
    await ref.read(repoRegistryProvider.notifier).refresh();
    await ref.read(setupStatusProvider.notifier).refresh();
    final status = ref.read(setupStatusProvider).valueOrNull;
    if (status != null && status.repoCount > 0 && mounted) {
      setState(() => _step = 5);
    }
  }

  Future<void> _runMockDemo() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = 'Starting mock run…';
    });
    try {
      final req = RunRequest(
        mode: RunMode.batch,
        limit: 1,
        mock: true,
        skipJiraCreation: true,
      );
      await ref.read(runSessionProvider.notifier).start(req);
      if (mounted) context.go('/runs/live');
      await ref
          .read(setupStatusProvider.notifier)
          .saveProgress(markComplete: true);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishWithoutRun() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(setupStatusProvider.notifier)
          .saveProgress(markComplete: true);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final setup = ref.watch(setupStatusProvider).valueOrNull;
    final isMock = setup?.setupPath == 'mock';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const FixoraMark(size: 28, elevated: false),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Set up $kProductName',
                      style: theme.headlineSmall,
                    ),
                  ),
                  if (widget.allowClose)
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),              const SizedBox(height: AppSpacing.sm),
              Text(
                'Step ${_step + 1} of ${_titles.length}: ${_titles[_step]}',
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              LinearProgressIndicator(
                value: (_step + 1) / _titles.length,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                Text(_error!,
                    style: theme.bodySmall?.copyWith(color: palette.danger)),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_info != null) ...[
                Text(_info!,
                    style: theme.bodySmall?.copyWith(color: palette.success)),
                const SizedBox(height: AppSpacing.sm),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: _buildStep(context, isMock: isMock, setup: setup),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required bool isMock,
    required SetupStatus? setup,
  }) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;

    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$kProductName turns Crashlytics crashes into reviewed code fixes, '
              'optional Jira issues, and draft GitLab merge requests for Flutter apps.',
              style: theme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Choose how you want to start. You can change settings later.',
              style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            GlassCard(
              child: ListTile(
                leading: Icon(Icons.science_outlined, color: palette.secondary),
                title: const Text('Quick demo (mock)'),
                subtitle: const Text(
                  'Configure an LLM key, add a sample repo, run a mock crash. '
                  'No GCP / Jira / GitLab required.',
                ),
                onTap: _busy ? null : () => _choosePath('mock'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            GlassCard(
              child: ListTile(
                leading: Icon(Icons.business_center_outlined,
                    color: palette.primary),
                title: const Text('Production setup'),
                subtitle: const Text(
                  'LLM + GCP Crashlytics credentials + Flutter repo. '
                  'Jira and GitLab are optional.',
                ),
                onTap: _busy ? null : () => _choosePath('production'),
              ),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Secrets are saved in Fixora settings (not required in a .env file for day-to-day use).',
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gemini', label: Text('Gemini')),
                ButtonSegment(value: 'openai', label: Text('OpenAI')),
                ButtonSegment(value: 'gosi-brain', label: Text('Advanced')),
              ],
              selected: {_provider},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _provider = s.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_provider == 'gemini') ...[
              TextField(
                controller: _geminiModelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Gemini model',
                  helperText: 'Default: gemini-2.5-flash',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _googleKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Google API key',
                  helperText: setup?.check('llm')?.ok == true
                      ? 'Already configured (enter a new key to replace)'
                      : 'Required — from Google AI Studio / Cloud',
                ),
              ),
            ] else if (_provider == 'openai') ...[
              TextField(
                controller: _openaiUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'OpenAI base URL',
                  helperText: 'Use an OpenAI-compatible gateway if needed',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _openaiModelCtrl,
                decoration: const InputDecoration(labelText: 'Model'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _openaiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
            ] else ...[
              Text(
                'Advanced OpenAI-compatible endpoint (e.g. enterprise gateway). '
                'Requires URL, Authorization header, and API key.',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _gosiUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Chat completions URL',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _gosiModelCtrl,
                decoration: const InputDecoration(labelText: 'Model'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _gosiAuthCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Authorization header value',
                  helperText: 'Full value, e.g. Bearer eyJ…',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _gosiApiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key header'),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _step = 0),
                  child: const Text('Back'),
                ),
                const Spacer(),
                GradientButton(
                  label: _busy ? 'Saving…' : 'Continue',
                  onPressed: _busy ? null : _saveLlm,
                ),
              ],
            ),
          ],
        );
      case 2:
        if (isMock) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mock path skips live Crashlytics. You can add GCP credentials later in Settings.',
                style: theme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _step = 1),
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  GradientButton(
                    label: 'Continue',
                    onPressed: _busy ? null : () => _saveCrashlytics(skip: true),
                  ),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload a GCP service account JSON with BigQuery (or Cloud Logging) access '
              'to your Firebase Crashlytics export.',
              style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _bqProjectCtrl,
              decoration: const InputDecoration(
                labelText: 'GCP / BigQuery project ID',
                helperText: 'Usually the same as your Firebase project ID',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: (_busy || _credsUploading) ? null : _uploadCreds,
              icon: _credsUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_hasCreds
                  ? 'Replace service account JSON'
                  : 'Upload service account JSON'),
            ),
            if (_hasCreds) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Credentials on file.',
                  style: theme.bodySmall?.copyWith(color: palette.success)),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _step = 1),
                  child: const Text('Back'),
                ),
                const Spacer(),
                GradientButton(
                  label: _busy ? 'Saving…' : 'Continue',
                  onPressed: _busy ? null : () => _saveCrashlytics(skip: false),
                ),
              ],
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional. Skip if you only want analysis without Jira issues or MRs. '
              'Per-repo project keys are set when you add a Flutter repository.',
              style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Jira', style: theme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _jiraUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Jira server URL',
                hintText: 'https://your-domain.atlassian.net',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _jiraEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'Jira email (Cloud Basic auth)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _jiraTokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Jira API token / PAT',
                helperText: 'Server/DC PATs often need bearer auth (Settings)',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('GitLab', style: theme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _gitlabUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'GitLab server URL',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _gitlabTokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'GitLab token'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _step = 2),
                  child: const Text('Back'),
                ),
                TextButton(
                  onPressed:
                      _busy ? null : () => _saveIntegrations(skip: true),
                  child: const Text('Skip'),
                ),
                const Spacer(),
                GradientButton(
                  label: _busy ? 'Saving…' : 'Continue',
                  onPressed:
                      _busy ? null : () => _saveIntegrations(skip: false),
                ),
              ],
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add the Flutter app repository Fixora should analyze. '
              'Set Crashlytics table names and Jira/GitLab project on that repo.',
              style: theme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              setup != null && setup.repoCount > 0
                  ? '${setup.repoCount} repo(s) configured.'
                  : 'No repositories yet.',
              style: theme.bodyMedium?.copyWith(
                color: setup != null && setup.repoCount > 0
                    ? palette.success
                    : palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: 'Open Manage repositories',
              icon: Icons.folder_open,
              onPressed: _busy ? null : _openRepoDialog,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _step = 3),
                  child: const Text('Back'),
                ),
                const Spacer(),
                GradientButton(
                  label: 'Continue',
                  onPressed: (setup != null && setup.repoCount > 0 && !_busy)
                      ? () => setState(() => _step = 5)
                      : null,
                ),
              ],
            ),
          ],
        );
      case 5:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You’re ready. Run a mock batch to verify the pipeline, '
              'or finish and explore the dashboard.',
              style: theme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: _busy ? 'Starting…' : 'Run mock demo',
              icon: Icons.play_arrow_rounded,
              onPressed: _busy ? null : _runMockDemo,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: _busy ? null : _finishWithoutRun,
              child: const Text('Finish without running'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _step = 4),
              child: const Text('Back'),
            ),
          ],
        );
    }
  }
}
