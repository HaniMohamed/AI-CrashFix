import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/backend_settings_provider.dart';
import '../../core/providers/repo_effective_config_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/loading_shimmer.dart';

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
                'Theme is stored in the browser; the API base URL follows build/runtime defaults (not editable here). '
                'LLM keys are saved on the server (SQLite) with .env fallback. '
                'Crashlytics, Jira, and GitLab are configured per repo (read-only summary below for the selected repo).',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ConnectionCard(settings: settings),
              const SizedBox(height: AppSpacing.lg),
              _EditableLlmSection(async: backendSettings),
              const SizedBox(height: AppSpacing.lg),
              const _RepoIntegrationPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableLlmSection extends ConsumerStatefulWidget {
  final AsyncValue<BackendSettingsState> async;
  const _EditableLlmSection({required this.async});

  @override
  ConsumerState<_EditableLlmSection> createState() => _EditableLlmSectionState();
}

class _EditableLlmSectionState extends ConsumerState<_EditableLlmSection> {
  late final TextEditingController _geminiModelCtrl;
  late final TextEditingController _googleKeyCtrl;
  late final TextEditingController _openaiUrlCtrl;
  late final TextEditingController _openaiModelCtrl;
  late final TextEditingController _openaiKeyCtrl;
  late final TextEditingController _gosiUrlCtrl;
  late final TextEditingController _gosiModelCtrl;
  late final TextEditingController _gosiOauthDomainCtrl;
  late final TextEditingController _gosiApiKeyCtrl;
  late final TextEditingController _gosiAuthCtrl;
  String _provider = 'gemini';
  double _gosiTemperature = 0.7;
  bool _didSync = false;
  bool _saving = false;
  String? _result;

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
    _gosiApiKeyCtrl.dispose();
    _gosiAuthCtrl.dispose();
    super.dispose();
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
            final p = (llm['provider'] ?? 'gemini').toString().trim().toLowerCase();
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
            _gosiOauthDomainCtrl.text = (llm['gosi_brain_oauth_identity_domain_name'] ?? 'MobileDomain').toString();
            final temp = llm['gosi_brain_temperature'];
            _gosiTemperature = temp is num ? temp.toDouble().clamp(0.0, 1.0) : 0.7;
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
                    onPressed: () => ref.read(backendSettingsProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Choose Gemini, OpenAI, or GOSI Brain. Keys are not shown after save; enter a new value only to replace.',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gemini', label: Text('Gemini')),
                  ButtonSegment(value: 'openai', label: Text('OpenAI')),
                  ButtonSegment(value: 'gosi-brain', label: Text('GOSI Brain')),
                ],
                selected: {_provider},
                onSelectionChanged: (next) {
                  setState(() => _provider = next.first);
                },
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
                    helperText: hasGoogle ? 'Key saved — leave blank to keep' : 'Not set',
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
                    helperText: hasOpenai ? 'Key saved — leave blank to keep' : 'Not set',
                  ),
                  obscureText: true,
                ),
              ] else ...[
                TextField(
                  controller: _gosiUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'https://intsol.gosi.gov.sa/v1/iwaiapiproxy/chat/completions',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiModelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Model name',
                  ),
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
                Text(
                  'Temperature (creativity): ${_gosiTemperature.toStringAsFixed(2)}',
                  style: theme.bodySmall?.copyWith(color: palette.textSecondary),
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
                    helperText: hasGosiAuth ? 'Saved — leave blank to keep' : 'Not set',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gosiApiKeyCtrl,
                  decoration: InputDecoration(
                    labelText: 'API key (x-apikey)',
                    helperText: hasGosiApi ? 'Key saved — leave blank to keep' : 'Not set',
                  ),
                  obscureText: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() {
                              _saving = true;
                              _result = null;
                            });
                            try {
                              await ref.read(backendSettingsProvider.notifier).save({
                                'llm': {
                                  'provider': _provider,
                                  'gemini_model': _geminiModelCtrl.text.trim(),
                                  'openai_url': _openaiUrlCtrl.text.trim(),
                                  'openai_model': _openaiModelCtrl.text.trim(),
                                  'gosi_brain_url': _gosiUrlCtrl.text.trim(),
                                  'gosi_brain_model': _gosiModelCtrl.text.trim(),
                                  'gosi_brain_oauth_identity_domain_name': _gosiOauthDomainCtrl.text.trim(),
                                  'gosi_brain_temperature': _gosiTemperature,
                                  if (_googleKeyCtrl.text.trim().isNotEmpty)
                                    'google_api_key': _googleKeyCtrl.text.trim(),
                                  if (_openaiKeyCtrl.text.trim().isNotEmpty)
                                    'openai_api_key': _openaiKeyCtrl.text.trim(),
                                  if (_gosiApiKeyCtrl.text.trim().isNotEmpty)
                                    'gosi_brain_api_key': _gosiApiKeyCtrl.text.trim(),
                                  if (_gosiAuthCtrl.text.trim().isNotEmpty)
                                    'gosi_brain_authorization': _gosiAuthCtrl.text.trim(),
                                },
                              });
                              if (!mounted) return;
                              setState(() => _result = 'Saved.');
                              _googleKeyCtrl.clear();
                              _openaiKeyCtrl.clear();
                              _gosiApiKeyCtrl.clear();
                              _gosiAuthCtrl.clear();
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => _result = e.toString());
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                  if (_result != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _result!,
                        style: theme.bodySmall?.copyWith(color: palette.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
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
                      style: theme.bodySmall?.copyWith(color: palette.textSecondary),
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
      return Text('—', style: theme.bodyMedium?.copyWith(color: palette.textMuted));
    }
    if (v is bool) {
      final b = v;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (b ? palette.success : palette.danger).withValues(alpha: 0.13),
          border: Border.all(
            color: (b ? palette.success : palette.danger).withValues(alpha: 0.4),
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
      final str = v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).join(', ');
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
