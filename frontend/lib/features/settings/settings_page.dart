import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/app_version_provider.dart';
import '../../core/providers/backend_settings_provider.dart';
import '../../core/providers/repo_effective_config_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/providers/setup_status_provider.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/fixora_mark.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../setup/setup_wizard_dialog.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final backendSettings = ref.watch(backendSettingsProvider);
    final settings = ref.watch(appSettingsProvider).requireValue;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: theme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Configure Fixora here. Values are saved in the app settings store (SQLite or Postgres) and '
                'override bootstrap .env on the next request — no restart needed for most keys. '
                'Per-repo Crashlytics / Jira / GitLab fields in Manage repos override these globals. '
                'Theme is stored locally on this device.',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ConnectionCard(settings: settings),
              const SizedBox(height: AppSpacing.lg),
              const _SetupWizardCard(),
              const SizedBox(height: AppSpacing.lg),
              _MachineUserCard(async: backendSettings),
              const SizedBox(height: AppSpacing.lg),
              _LlmSection(async: backendSettings),
              const SizedBox(height: AppSpacing.lg),
              _GlobalIntegrationsSection(async: backendSettings),
              const SizedBox(height: AppSpacing.lg),
              const _RepoIntegrationPanel(),
              const SizedBox(height: AppSpacing.lg),
              const _AboutCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupWizardCard extends ConsumerWidget {
  const _SetupWizardCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final setup = ref.watch(setupStatusProvider);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Setup wizard', style: theme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              setup.valueOrNull?.setupComplete == true
                  ? 'Re-open the guided setup to change LLM, Crashlytics, Jira/GitLab, or repos.'
                  : 'Finish onboarding, or jump into the wizard to edit any step.',
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            GradientButton(
              label: setup.valueOrNull?.setupComplete == true
                  ? 'Edit setup'
                  : 'Open setup wizard',
              icon: Icons.rocket_launch_outlined,
              onPressed: () => openSetupWizard(
                context,
                ref,
                revisiting: setup.valueOrNull?.setupComplete == true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LlmSection extends ConsumerStatefulWidget {
  final AsyncValue<BackendSettingsState> async;
  const _LlmSection({required this.async});

  @override
  ConsumerState<_LlmSection> createState() =>
      _LlmSectionState();
}

class _LlmSectionState extends ConsumerState<_LlmSection> {
  late final TextEditingController _geminiModelCtrl;
  late final TextEditingController _googleKeyCtrl;
  late final TextEditingController _openaiUrlCtrl;
  late final TextEditingController _openaiModelCtrl;
  late final TextEditingController _openaiKeyCtrl;
  late final TextEditingController _gosiUrlCtrl;
  late final TextEditingController _gosiModelCtrl;
  late final TextEditingController _gosiOauthDomainCtrl;
  late final TextEditingController _gosiUserIdCtrl;
  late final TextEditingController _gosiApiKeyCtrl;
  late final TextEditingController _gosiAuthCtrl;
  String _provider = 'gemini';
  double _gosiTemperature = 0.7;
  String _gosiStreaming = 'auto';
  bool _didSync = false;
  bool _saving = false;
  String? _saveMsg;

  @override
  void initState() {
    super.initState();
    _geminiModelCtrl = TextEditingController();
    _googleKeyCtrl = TextEditingController();
    _openaiUrlCtrl = TextEditingController();
    _openaiModelCtrl = TextEditingController();
    _openaiKeyCtrl = TextEditingController();
    _gosiUrlCtrl = TextEditingController();
    _gosiModelCtrl = TextEditingController();
    _gosiOauthDomainCtrl = TextEditingController();
    _gosiUserIdCtrl = TextEditingController();
    _gosiApiKeyCtrl = TextEditingController();
    _gosiAuthCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _geminiModelCtrl.dispose();
    _googleKeyCtrl.dispose();
    _openaiUrlCtrl.dispose();
    _openaiModelCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _gosiUrlCtrl.dispose();
    _gosiModelCtrl.dispose();
    _gosiOauthDomainCtrl.dispose();
    _gosiUserIdCtrl.dispose();
    _gosiApiKeyCtrl.dispose();
    _gosiAuthCtrl.dispose();
    super.dispose();
  }


  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveMsg = null;
    });
    try {
      final llm = <String, dynamic>{
        'provider': _provider,
        'gemini_model': _geminiModelCtrl.text.trim(),
        'openai_url': _openaiUrlCtrl.text.trim(),
        'openai_model': _openaiModelCtrl.text.trim(),
        'gosi_brain_url': _gosiUrlCtrl.text.trim(),
        'gosi_brain_model': _gosiModelCtrl.text.trim(),
        'gosi_brain_oauth_identity_domain_name': _gosiOauthDomainCtrl.text.trim(),
        'gosi_brain_user_id': _gosiUserIdCtrl.text.trim(),
        'gosi_brain_temperature': _gosiTemperature,
        'gosi_brain_streaming': _gosiStreaming,
      };
      if (_googleKeyCtrl.text.trim().isNotEmpty) {
        llm['google_api_key'] = _googleKeyCtrl.text.trim();
      }
      if (_openaiKeyCtrl.text.trim().isNotEmpty) {
        llm['openai_api_key'] = _openaiKeyCtrl.text.trim();
      }
      if (_gosiApiKeyCtrl.text.trim().isNotEmpty) {
        llm['gosi_brain_api_key'] = _gosiApiKeyCtrl.text.trim();
      }
      if (_gosiAuthCtrl.text.trim().isNotEmpty) {
        llm['gosi_brain_authorization'] = _gosiAuthCtrl.text.trim();
      }
      await ref.read(backendSettingsProvider.notifier).save({'llm': llm});
      _googleKeyCtrl.clear();
      _openaiKeyCtrl.clear();
      _gosiApiKeyCtrl.clear();
      _gosiAuthCtrl.clear();
      setState(() => _saveMsg = 'Saved.');
    } catch (e) {
      setState(() => _saveMsg = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return GlassCard(
      child: widget.async.when(
        loading: () => const ShimmerCard(height: 320),
        error: (e, _) => ErrorBanner(
          message: 'Failed to load LLM settings: $e',
          onRetry: () => ref.read(backendSettingsProvider.notifier).refresh(),
        ),
        data: (s) {
          final llm = s.section('llm');
          final hasGoogle = llm['has_google_api_key'] == true;
          final hasOpenai = llm['has_openai_api_key'] == true;
          final hasGosiApi = llm['has_gosi_brain_api_key'] == true;
          final hasGosiAuth = llm['has_gosi_brain_authorization'] == true;
          if (!_didSync) {
            _didSync = true;
            final p = (llm['provider'] ?? 'gemini')
                .toString()
                .trim()
                .toLowerCase();
            if (p == 'openai') {
              _provider = 'openai';
            } else if (p == 'gosi-brain') {
              _provider = 'gosi-brain';
            } else {
              _provider = 'gemini';
            }
            _geminiModelCtrl.text = (llm['gemini_model'] ?? '').toString();
            _openaiUrlCtrl.text = (llm['openai_url'] ?? '').toString();
            _openaiModelCtrl.text = (llm['openai_model'] ?? '').toString();
            _gosiUrlCtrl.text = (llm['gosi_brain_url'] ?? '').toString();
            _gosiModelCtrl.text = (llm['gosi_brain_model'] ?? '').toString();
            _gosiOauthDomainCtrl.text =
                (llm['gosi_brain_oauth_identity_domain_name'] ?? 'MobileDomain')
                    .toString();
            _gosiUserIdCtrl.text = (llm['gosi_brain_user_id'] ?? '').toString();
            final streaming = (llm['gosi_brain_streaming'] ?? 'auto')
                .toString()
                .trim()
                .toLowerCase();
            _gosiStreaming = (streaming == 'on' || streaming == 'off')
                ? streaming
                : 'auto';
            final temp = llm['gosi_brain_temperature'];
            _gosiTemperature = temp is num
                ? temp.toDouble().clamp(0.0, 1.0)
                : 0.7;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: palette.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('LLM provider', style: theme.headlineSmall),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        ref.read(backendSettingsProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Choose a provider and save. Secrets are write-only (never returned by the API).',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gemini', label: Text('Gemini')),
                  ButtonSegment(value: 'openai', label: Text('OpenAI')),
                  ButtonSegment(
                    value: 'gosi-brain',
                    label: Text('Advanced'),
                  ),
                ],
                selected: {_provider},
                onSelectionChanged: (s) => setState(() => _provider = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_provider == 'gemini') ...[
                TextField(
                  controller: _geminiModelCtrl,
                                    decoration: const InputDecoration(
                    labelText: 'Gemini model',
                    hintText: 'gemini-2.5-flash',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _googleKeyCtrl,
                                    decoration: InputDecoration(
                    labelText: 'Google API key',
                    helperText: hasGoogle
                        ? 'Configured on server (value hidden)'
                        : 'Not set',
                  ),
                  obscureText: true,
                ),
              ] else if (_provider == 'openai') ...[
                TextField(
                  controller: _openaiUrlCtrl,
                                    decoration: const InputDecoration(
                    labelText: 'OpenAI base URL',
                    hintText: 'https://api.openai.com/v1',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _openaiModelCtrl,
                                    decoration: const InputDecoration(
                    labelText: 'Model name',
                    hintText: 'gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _openaiKeyCtrl,
                                    decoration: InputDecoration(
                    labelText: 'OpenAI API key',
                    helperText: hasOpenai
                        ? 'Configured on server (value hidden)'
                        : 'Not set',
                  ),
                  obscureText: true,
                ),
              ] else ...[
                TextField(
                  controller: _gosiUrlCtrl,
                                    decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'https://your-gateway.example/v1/chat/completions',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiModelCtrl,
                                    decoration: const InputDecoration(labelText: 'Model name'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiOauthDomainCtrl,
                                    decoration: const InputDecoration(
                    labelText: 'OAuth identity domain name',
                    hintText: 'MobileDomain',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiUserIdCtrl,
                                    decoration: const InputDecoration(
                    labelText: 'User ID (custom_session)',
                    hintText: 'PersonNumber from JWT',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Streaming: $_gosiStreaming',
                  style: theme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Temperature (creativity): ${_gosiTemperature.toStringAsFixed(2)}',
                  style: theme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                Slider(
                  value: _gosiTemperature,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: _gosiTemperature.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _gosiTemperature = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiAuthCtrl,
                                    decoration: InputDecoration(
                    labelText: 'Authorization header value',
                    helperText: hasGosiAuth
                        ? 'Configured on server (value hidden)'
                        : 'Not set',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiApiKeyCtrl,
                                    decoration: InputDecoration(
                    labelText: 'API key (x-apikey)',
                    helperText: hasGosiApi
                        ? 'Configured on server (value hidden)'
                        : 'Not set',
                  ),
                  obscureText: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (_saveMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    _saveMsg!,
                    style: theme.bodySmall?.copyWith(
                      color: _saveMsg!.startsWith('Save failed')
                          ? palette.danger
                          : palette.success,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving || s.repoDataReadonly ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save LLM settings'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlobalIntegrationsSection extends ConsumerStatefulWidget {
  final AsyncValue<BackendSettingsState> async;
  const _GlobalIntegrationsSection({required this.async});

  @override
  ConsumerState<_GlobalIntegrationsSection> createState() =>
      _GlobalIntegrationsSectionState();
}

class _GlobalIntegrationsSectionState
    extends ConsumerState<_GlobalIntegrationsSection> {
  final _bqProjectCtrl = TextEditingController();
  final _jiraUrlCtrl = TextEditingController();
  final _jiraEmailCtrl = TextEditingController();
  final _jiraTokenCtrl = TextEditingController();
  final _jiraAuthCtrl = TextEditingController(text: 'auto');
  final _gitlabUrlCtrl = TextEditingController();
  final _gitlabTokenCtrl = TextEditingController();
  bool _didSync = false;
  bool _saving = false;
  String? _msg;

  @override
  void dispose() {
    _bqProjectCtrl.dispose();
    _jiraUrlCtrl.dispose();
    _jiraEmailCtrl.dispose();
    _jiraTokenCtrl.dispose();
    _jiraAuthCtrl.dispose();
    _gitlabUrlCtrl.dispose();
    _gitlabTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      await ref.read(backendSettingsProvider.notifier).save({
        'crashlytics': {
          'bq_project_id': _bqProjectCtrl.text.trim(),
        },
        'jira': {
          'server_url': _jiraUrlCtrl.text.trim(),
          'email': _jiraEmailCtrl.text.trim(),
          'auth': _jiraAuthCtrl.text.trim(),
          if (_jiraTokenCtrl.text.trim().isNotEmpty)
            'token': _jiraTokenCtrl.text.trim(),
        },
        'gitlab': {
          'server_url': _gitlabUrlCtrl.text.trim(),
          if (_gitlabTokenCtrl.text.trim().isNotEmpty)
            'token': _gitlabTokenCtrl.text.trim(),
        },
      });
      _jiraTokenCtrl.clear();
      _gitlabTokenCtrl.clear();
      setState(() => _msg = 'Saved global defaults.');
    } catch (e) {
      setState(() => _msg = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return GlassCard(
      child: widget.async.when(
        loading: () => const ShimmerCard(height: 240),
        error: (e, _) => ErrorBanner(
          message: 'Failed to load settings: $e',
          onRetry: () => ref.read(backendSettingsProvider.notifier).refresh(),
        ),
        data: (s) {
          final crash = s.section('crashlytics');
          final jira = s.section('jira');
          final gl = s.section('gitlab');
          if (!_didSync) {
            _didSync = true;
            _bqProjectCtrl.text = (crash['bq_project_id'] ?? '').toString();
            _jiraUrlCtrl.text = (jira['server_url'] ?? '').toString();
            _jiraEmailCtrl.text = (jira['email'] ?? '').toString();
            _jiraAuthCtrl.text = (jira['auth'] ?? 'auto').toString();
            _gitlabUrlCtrl.text = (gl['server_url'] ?? '').toString();
          }
          final readonly = s.repoDataReadonly;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune, color: palette.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Global integrations', style: theme.headlineSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Defaults used when a repo does not override them. '
                  'Upload GCP credentials via Manage repos or the setup wizard. '
                  'Tokens are write-only.',
                  style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _bqProjectCtrl,
                  enabled: !readonly,
                  decoration: const InputDecoration(
                    labelText: 'BQ / Firebase project ID',
                    helperText: 'Global default; repo Firebase project ID can override',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Jira', style: theme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _jiraUrlCtrl,
                  enabled: !readonly,
                  decoration: const InputDecoration(labelText: 'Jira server URL'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _jiraEmailCtrl,
                  enabled: !readonly,
                  decoration: const InputDecoration(
                    labelText: 'Jira email (Cloud)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _jiraAuthCtrl,
                  enabled: !readonly,
                  decoration: const InputDecoration(
                    labelText: 'Jira auth',
                    helperText: 'auto | basic | bearer',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _jiraTokenCtrl,
                  enabled: !readonly,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Jira token',
                    helperText: jira['has_token'] == true
                        ? 'Token saved (enter new value to replace)'
                        : 'Not set',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('GitLab', style: theme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _gitlabUrlCtrl,
                  enabled: !readonly,
                  decoration:
                      const InputDecoration(labelText: 'GitLab server URL'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gitlabTokenCtrl,
                  enabled: !readonly,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'GitLab token',
                    helperText: gl['has_token'] == true
                        ? 'Token saved (enter new value to replace)'
                        : 'Not set',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_msg != null)
                  Text(
                    _msg!,
                    style: theme.bodySmall?.copyWith(
                      color: _msg!.startsWith('Save failed')
                          ? palette.danger
                          : palette.success,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving || readonly ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save globals'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RepoIntegrationPanel extends ConsumerWidget {
  const _RepoIntegrationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final reg = ref.watch(repoRegistryProvider);

    return reg.when(
      loading: () => const GlassCard(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerCard(height: 200),
        ),
      ),
      error: (e, _) => ErrorBanner(
        message: 'Failed to load repos: $e',
        onRetry: () => ref.read(repoRegistryProvider.notifier).refresh(),
      ),
      data: (s) {
        final active = s.active;
        if (active == null || s.repos.isEmpty) {
          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Add a repo and select it in the top bar (or Manage repos) to see '
                'Crashlytics, Jira, and GitLab settings for that repo. Edit those values in Manage repos.',
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ),
          );
        }

        final cfgAsync = ref.watch(repoEffectiveConfigProvider(active.repoKey));

        return cfgAsync.when(
          loading: () => const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: ShimmerCard(height: 320),
            ),
          ),
          error: (e, _) => GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ErrorBanner(
                message: 'Failed to load repo integration config: $e',
                onRetry: () =>
                    ref.invalidate(repoEffectiveConfigProvider(active.repoKey)),
              ),
            ),
          ),
          data: (payload) {
            final repoMap = _asStringKeyMap(payload['repo']);
            final crashMap = _asStringKeyMap(payload['crashlytics']);
            final jiraMap = _asStringKeyMap(payload['jira']);
            final gitlabMap = _asStringKeyMap(payload['gitlab']);

            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hub_outlined, color: palette.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Repo integrations (read-only)',
                            style: theme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            ref.invalidate(
                              repoEffectiveConfigProvider(active.repoKey),
                            );
                            ref.read(repoRegistryProvider.notifier).refresh();
                          },
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Effective values for “${active.name}”. Tokens are never shown—only whether they are set. '
                      'Change these in Manage repos (and Crashlytics/GCP defaults via server .env or uploaded service account JSON).',
                      style: theme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ReadonlyKvGroup(
                      title: 'Repository',
                      icon: Icons.folder_outlined,
                      rows: repoMap,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ReadonlyKvGroup(
                      title: 'Crashlytics',
                      icon: Icons.cloud_outlined,
                      rows: crashMap,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ReadonlyKvGroup(
                      title: 'Jira',
                      icon: Icons.confirmation_number_outlined,
                      rows: jiraMap,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ReadonlyKvGroup(
                      title: 'GitLab',
                      icon: Icons.merge_outlined,
                      rows: gitlabMap,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Map<String, dynamic> _asStringKeyMap(Object? raw) {
  if (raw is! Map) return {};
  return raw.map((k, v) => MapEntry(k.toString(), v));
}

class _ReadonlyKvGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, dynamic> rows;

  const _ReadonlyKvGroup({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final keys = rows.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: palette.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: theme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...keys.map((k) => _ReadonlyIntegrationRow(k: k, value: rows[k])),
      ],
    );
  }
}

class _ReadonlyIntegrationRow extends StatelessWidget {
  final String k;
  final Object? value;

  const _ReadonlyIntegrationRow({required this.k, this.value});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final label = k.replaceAll('_', ' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              label,
              style: theme.labelMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          Expanded(child: _valueWidget(context, value)),
        ],
      ),
    );
  }

  Widget _valueWidget(BuildContext context, Object? v) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    if (v == null) {
      return Text(
        '—',
        style: theme.bodyMedium?.copyWith(color: palette.textMuted),
      );
    }
    if (v is bool) {
      final b = v;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (b ? palette.success : palette.danger).withValues(alpha: 0.13),
          border: Border.all(
            color: (b ? palette.success : palette.danger).withValues(
              alpha: 0.4,
            ),
          ),
          borderRadius: AppRadii.all(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              b ? Icons.check : Icons.close,
              size: 12,
              color: b ? palette.success : palette.danger,
            ),
            const SizedBox(width: 4),
            Text(
              b ? 'yes' : 'no',
              style: theme.labelSmall?.copyWith(
                color: b ? palette.success : palette.danger,
              ),
            ),
          ],
        ),
      );
    }
    if (v is List) {
      final str = v
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .join(', ');
      return Text(
        str.isEmpty ? '—' : str,
        style: theme.bodyMedium?.copyWith(color: palette.text),
      );
    }
    final s = v.toString().trim();
    return Text(
      s.isEmpty ? '—' : s,
      style: theme.bodyMedium?.copyWith(color: palette.text),
    );
  }
}

class _MachineUserCard extends StatelessWidget {
  final AsyncValue<BackendSettingsState> async;
  const _MachineUserCard({required this.async});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return async.when(
      loading: () => const LoadingShimmer(height: 88),
      error: (e, _) => ErrorBanner(message: 'Failed to load user id: $e'),
      data: (state) {
        final id = state.userId;
        return GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge_outlined, color: palette.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Machine user ID', style: theme.headlineSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Scopes repos/settings on the shared Postgres store and is sent as '
                  'GOSI Brain custom_session.user_id. Matching is case-insensitive. '
                  'When AI_CRASH_FIX_USER_ID is set, GOSI_BRAIN_USER_ID is ignored. '
                  'Set via AI_CRASH_FIX_USER_ID in the env file'
                  '${state.userIdEditable ? ' or local Settings when using SQLite' : ''}.',
                  style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                SelectableText(
                  (id == null || id.isEmpty) ? '— not set —' : id,
                  style: theme.bodyLarge?.copyWith(
                    color: palette.text,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionCard extends ConsumerStatefulWidget {
  final AppSettings settings;
  const _ConnectionCard({required this.settings});

  @override
  ConsumerState<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends ConsumerState<_ConnectionCard> {
  bool _testing = false;
  String? _testResult;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Connection', style: theme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'API base URL is fixed by the app (e.g. dart-define or same-origin in release). '
            'Use Test connection to verify the backend is reachable.',
            style: theme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'API base URL',
            style: theme.labelLarge?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            widget.settings.apiBaseUrl,
            style: theme.bodyLarge?.copyWith(
              color: palette.text,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            icon: const Icon(Icons.bolt, size: 16),
            label: Text(_testing ? 'Testing…' : 'Test connection'),
            onPressed: _testing ? null : _runTest,
          ),
          if (_testResult != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _testResult!,
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Text('Theme', style: theme.titleMedium),
              const SizedBox(width: AppSpacing.lg),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ],
                selected: {widget.settings.themeMode},
                onSelectionChanged: (s) {
                  ref.read(appSettingsProvider.notifier).setThemeMode(s.first);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/api/health');
      final ok = res is Map && res['ok'] == true;
      setState(
        () => _testResult = ok
            ? 'Healthy ✓'
            : 'Reached, but unexpected response.',
      );
    } catch (e) {
      setState(() => _testResult = 'Failed: $e');
    } finally {
      setState(() => _testing = false);
    }
  }
}

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final async = ref.watch(appVersionProvider);
    return async.when(
      loading: () => const LoadingShimmer(height: 88),
      error: (_, _) => const SizedBox.shrink(),
      data: (v) => GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FixoraMark(size: 28, elevated: false),
                  const SizedBox(width: AppSpacing.sm),
                  Text('About', style: theme.headlineSmall),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fixora macOS / web UI version from package metadata.',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              _AboutRow(label: 'App', value: v.appName),
              const SizedBox(height: AppSpacing.sm),
              _AboutRow(label: 'Version', value: v.detailLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: theme.labelLarge?.copyWith(color: palette.textSecondary),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: theme.bodyLarge?.copyWith(
              color: palette.text,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
