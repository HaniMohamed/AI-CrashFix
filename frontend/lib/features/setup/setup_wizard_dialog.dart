import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/backend_settings_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/providers/run_session_provider.dart';
import '../../core/providers/setup_status_provider.dart';
import '../../core/models/run_request.dart';
import '../../shared/widgets/fixora_mark.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../shell/repo_manage_dialog.dart';

/// Multi-step Fixora onboarding. Shown as a modal when setup is incomplete,
/// and reopenable later from Settings / Help to edit the same data.
class SetupWizardDialog extends ConsumerStatefulWidget {
  final bool allowClose;
  /// When true, copy existing settings into the form and allow closing anytime.
  final bool revisiting;

  const SetupWizardDialog({
    super.key,
    this.allowClose = false,
    this.revisiting = false,
  });

  @override
  ConsumerState<SetupWizardDialog> createState() => _SetupWizardDialogState();
}

/// Opens the setup wizard (first-run or edit). Prefer this helper from Settings/Help.
Future<void> openSetupWizard(
  BuildContext context,
  WidgetRef ref, {
  bool revisiting = false,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: revisiting,
    builder: (_) => SetupWizardDialog(
      allowClose: true,
      revisiting: revisiting,
    ),
  );
  ref.invalidate(setupStatusProvider);
  ref.invalidate(backendSettingsProvider);
  ref.invalidate(repoRegistryProvider);
}

class _SetupWizardDialogState extends ConsumerState<SetupWizardDialog> {
  int _step = 0;
  bool _busy = false;
  bool _bootstrapped = false;
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

  // Integrations
  final _jiraUrlCtrl = TextEditingController();
  final _jiraEmailCtrl = TextEditingController();
  final _jiraTokenCtrl = TextEditingController();
  final _gitlabUrlCtrl = TextEditingController();
  final _gitlabTokenCtrl = TextEditingController();

  // App store / database
  String _storeBackend = 'sqlite';
  final _dbUrlCtrl = TextEditingController();
  final _dbUserCtrl = TextEditingController();
  final _dbPasswordCtrl = TextEditingController();
  final _machineUserIdCtrl = TextEditingController();
  bool _showDbPassword = false;
  String? _dbUrlMasked;

  static const _titles = [
    'Welcome',
    'Database',
    'LLM provider',
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
    _jiraUrlCtrl.dispose();
    _jiraEmailCtrl.dispose();
    _jiraTokenCtrl.dispose();
    _gitlabUrlCtrl.dispose();
    _gitlabTokenCtrl.dispose();
    _dbUrlCtrl.dispose();
    _dbUserCtrl.dispose();
    _dbPasswordCtrl.dispose();
    _machineUserIdCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    try {
      await ref.read(backendSettingsProvider.notifier).refresh();
      await _syncFromSettings();
      await _syncStoreConfig();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _continueExistingSetup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backendSettingsProvider.notifier).refresh();
      await _syncFromSettings();
      await _syncStoreConfig();
      setState(() => _step = 1);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncStoreConfig() async {
    try {
      final cfg =
          await ref.read(setupStatusProvider.notifier).fetchStoreConfig();
      final backend = (cfg['backend'] ?? 'sqlite').toString().toLowerCase();
      _storeBackend = backend == 'postgres' ? 'postgres' : 'sqlite';
      _dbUrlMasked = cfg['db_url_masked']?.toString();
      final uid = cfg['user_id']?.toString() ?? '';
      if (uid.isNotEmpty) _machineUserIdCtrl.text = uid;
      // Never put masked secrets back into the editable URL field.
      if (_dbUrlCtrl.text.trim().isEmpty &&
          _dbUrlMasked != null &&
          !_dbUrlMasked!.contains('***')) {
        _dbUrlCtrl.text = _dbUrlMasked!;
      }
    } catch (_) {}
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
      setState(() => _step = 3);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
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

  Future<void> _saveStore() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_storeBackend == 'postgres') {
        final url = _dbUrlCtrl.text.trim();
        if (url.isEmpty && (_dbUrlMasked == null || _dbUrlMasked!.isEmpty)) {
          throw Exception('Postgres URL is required');
        }
        if (_machineUserIdCtrl.text.trim().isEmpty) {
          throw Exception('Machine user ID is required for remote Postgres');
        }
      }
      await ref.read(setupStatusProvider.notifier).saveStoreConfig(
            backend: _storeBackend,
            dbUrl: _dbUrlCtrl.text.trim().isEmpty
                ? null
                : _dbUrlCtrl.text.trim(),
            username: _dbUserCtrl.text.trim().isEmpty
                ? null
                : _dbUserCtrl.text.trim(),
            password: _dbPasswordCtrl.text.isEmpty
                ? null
                : _dbPasswordCtrl.text,
            userId: _machineUserIdCtrl.text.trim().isEmpty
                ? null
                : _machineUserIdCtrl.text.trim(),
            testConnection: _storeBackend == 'postgres',
          );
      await _syncStoreConfig();
      await ref.read(setupStatusProvider.notifier).refresh();
      await ref.read(backendSettingsProvider.notifier).refresh();
      _dbPasswordCtrl.clear();
      if (mounted) {
        setState(() {
          _info = _storeBackend == 'sqlite'
              ? 'Local SQLite store selected.'
              : 'Remote Postgres store connected and saved.';
          _step = 2;
        });
      }
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
      await _syncStoreConfig();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref
          .read(setupStatusProvider.notifier)
          .saveProgress(markComplete: true);
      if (!status.setupComplete) {
        final missing = status.missing.isEmpty
            ? 'LLM provider and at least one repository'
            : status.missing.join(', ');
        if (mounted) {
          setState(() {
            _error =
                'Setup is still incomplete ($missing). Finish the earlier steps, then try again.';
          });
        }
        return;
      }
      await ref.read(repoRegistryProvider.notifier).refresh();
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
    final canClose = widget.allowClose || widget.revisiting;

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
                      widget.revisiting
                          ? 'Edit $kProductName setup'
                          : 'Set up $kProductName',
                      style: theme.headlineSmall,
                    ),
                  ),
                  if (canClose)
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
              widget.revisiting
                  ? 'Update LLM, integrations, or your Flutter repo '
                      '(including per-repo GCP Crashlytics credentials). '
                      'Existing secrets stay until you replace them.'
                  : '$kProductName turns Crashlytics crashes into reviewed code fixes, '
                      'optional Jira issues, and draft GitLab merge requests for Flutter apps.\n\n'
                      'Sign in is required. On first launch, create an administrator on the sign-in screen.',
              style: theme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (widget.revisiting && (setup?.setupPath ?? '').isNotEmpty) ...[
              GlassCard(
                child: ListTile(
                  leading: Icon(Icons.edit_outlined, color: palette.primary),
                  title: Text(
                    'Continue editing (${setup!.setupPath}) setup',
                  ),
                  subtitle: const Text(
                    'Jump back into LLM / integrations with current values.',
                  ),
                  onTap: _busy ? null : _continueExistingSetup,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Or restart from a path:',
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
            ] else
              Text(
                'Choose how you want to start. You can change settings later from Settings.',
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            if (!widget.revisiting || (setup?.setupPath ?? '').isEmpty)
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
                  'LLM + Flutter repo with GCP project ID and service account. '
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
              'Choose where Fixora stores crashes, repos, and settings on this machine.',
              style: theme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Local SQLite is best for a single workstation. Remote Postgres is for shared team data.',
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'sqlite',
                  label: Text('Local SQLite'),
                  icon: Icon(Icons.storage_outlined),
                ),
                ButtonSegment(
                  value: 'postgres',
                  label: Text('Remote Postgres'),
                  icon: Icon(Icons.cloud_outlined),
                ),
              ],
              selected: {_storeBackend},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _storeBackend = s.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_storeBackend == 'sqlite') ...[
              GlassCard(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline, color: palette.success),
                  title: const Text('Local file database'),
                  subtitle: const Text(
                    'Data stays on this Mac under Application Support / AI_CRASH_FIX_DATA_DIR. '
                    'No remote URL required.',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _machineUserIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Machine user ID (optional)',
                  hintText: 'e.g. jane.doe',
                  helperText: 'Useful if you later switch to shared Postgres.',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ] else ...[
              TextField(
                controller: _dbUrlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Postgres URL',
                  hintText: 'postgresql://host:5432/fixora',
                  helperText: _dbUrlMasked == null || _dbUrlMasked!.isEmpty
                      ? 'Include host and database. Username/password can go here or below.'
                      : 'Saved: $_dbUrlMasked — enter a new URL to replace.',
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _dbUserCtrl,
                decoration: const InputDecoration(
                  labelText: 'DB username (optional)',
                  hintText: 'Merged into the URL when set',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _dbPasswordCtrl,
                obscureText: !_showDbPassword,
                decoration: InputDecoration(
                  labelText: 'DB password (optional)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _showDbPassword ? 'Hide' : 'Show',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showDbPassword = !_showDbPassword),
                    icon: Icon(
                      _showDbPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _machineUserIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Machine user ID',
                  hintText: 'e.g. jane.doe',
                  helperText: 'Required — scopes your rows in the shared database.',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
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
                  label: _busy
                      ? 'Saving…'
                      : (_storeBackend == 'postgres' ? 'Test & continue' : 'Continue'),
                  onPressed: _busy ? null : _saveStore,
                ),
              ],
            ),
          ],
        );

      case 2:
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
                  onPressed: _busy ? null : () => setState(() => _step = 1),
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
              isMock
                  ? 'Add any Flutter git repo (token required for private remotes). '
                      'Mock runs do not need GCP credentials.'
                  : 'Add the Flutter app repository Fixora should analyze. '
                      'On that repo, set Firebase / GCP project ID, upload the '
                      'service account JSON, and Crashlytics dataset/tables '
                      '(plus package/bundle IDs).',
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
            if (!isMock) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Production Crashlytics readiness requires project ID + service '
                'account on the active repo (Manage repositories → Crashlytics).',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
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
