import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/backend_settings_provider.dart';
import '../../core/providers/config_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/loading_shimmer.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final config = ref.watch(configProvider);
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
                'Backend config is read from .env at server startup. Edit the file and restart uvicorn to apply changes.',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ConnectionCard(settings: settings),
              const SizedBox(height: AppSpacing.lg),
              _EditableBackendSettingsCard(async: backendSettings),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text('Backend configuration', style: theme.headlineMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        ref.read(configProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              config.when(
                loading: () => Column(
                  children: List.generate(
                    3,
                    (_) => const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.lg),
                      child: ShimmerCard(height: 140),
                    ),
                  ),
                ),
                error: (e, _) => ErrorBanner(
                  message: 'Failed to load /api/config: $e',
                  onRetry: () => ref.read(configProvider.notifier).refresh(),
                ),
                data: (cfg) => Column(
                  children: [
                    _ConfigSection(
                      title: 'LLM Provider',
                      icon: Icons.auto_awesome,
                      data: cfg.section('llm'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ConfigSection(
                      title: 'Crashlytics',
                      icon: Icons.cloud_outlined,
                      data: cfg.section('crashlytics'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ConfigSection(
                      title: 'Jira',
                      icon: Icons.confirmation_number_outlined,
                      data: cfg.section('jira'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ConfigSection(
                      title: 'GitLab',
                      icon: Icons.merge_outlined,
                      data: cfg.section('gitlab'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableBackendSettingsCard extends ConsumerStatefulWidget {
  final AsyncValue<BackendSettingsState> async;
  const _EditableBackendSettingsCard({required this.async});

  @override
  ConsumerState<_EditableBackendSettingsCard> createState() =>
      _EditableBackendSettingsCardState();
}

class _EditableBackendSettingsCardState
    extends ConsumerState<_EditableBackendSettingsCard> {
  late final TextEditingController _jiraUrl;
  late final TextEditingController _jiraToken;
  late final TextEditingController _gitlabUrl;
  late final TextEditingController _gitlabToken;
  late final TextEditingController _openaiKey;
  late final TextEditingController _googleKey;
  String? _result;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _jiraUrl = TextEditingController();
    _jiraToken = TextEditingController();
    _gitlabUrl = TextEditingController();
    _gitlabToken = TextEditingController();
    _openaiKey = TextEditingController();
    _googleKey = TextEditingController();
  }

  @override
  void dispose() {
    _jiraUrl.dispose();
    _jiraToken.dispose();
    _gitlabUrl.dispose();
    _gitlabToken.dispose();
    _openaiKey.dispose();
    _googleKey.dispose();
    super.dispose();
  }

  void _syncFrom(BackendSettingsState s) {
    _jiraUrl.text = (s.section('jira')['server_url'] ?? '').toString();
    _gitlabUrl.text = (s.section('gitlab')['server_url'] ?? '').toString();
    // Tokens/keys are not returned; keep empty.
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return GlassCard(
      child: widget.async.when(
        loading: () => const ShimmerCard(height: 220),
        error: (e, _) => ErrorBanner(
          message: 'Failed to load editable settings: $e',
          onRetry: () => ref.read(backendSettingsProvider.notifier).refresh(),
        ),
        data: (s) {
          _syncFrom(s);
          final hasJira = s.section('jira')['has_token'] == true;
          final hasGitlab = s.section('gitlab')['has_token'] == true;
          final hasOpenai = s.section('llm')['has_openai_api_key'] == true;
          final hasGoogle = s.section('llm')['has_google_api_key'] == true;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: palette.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Editable backend settings', style: theme.headlineSmall),
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
                'Saved server-side (SQLite) with .env fallback. Secrets are not shown after saving.',
                style: theme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _jiraUrl,
                      decoration: const InputDecoration(
                        labelText: 'Jira server URL',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _jiraToken,
                      decoration: InputDecoration(
                        labelText: 'Jira token',
                        helperText: hasJira ? 'Token saved' : 'Not set',
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _gitlabUrl,
                      decoration: const InputDecoration(
                        labelText: 'GitLab server URL',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _gitlabToken,
                      decoration: InputDecoration(
                        labelText: 'GitLab token',
                        helperText: hasGitlab ? 'Token saved' : 'Not set',
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _openaiKey,
                      decoration: InputDecoration(
                        labelText: 'OpenAI API key',
                        helperText: hasOpenai ? 'Key saved' : 'Not set',
                      ),
                      obscureText: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _googleKey,
                      decoration: InputDecoration(
                        labelText: 'Google API key (Gemini)',
                        helperText: hasGoogle ? 'Key saved' : 'Not set',
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
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
                              await ref
                                  .read(backendSettingsProvider.notifier)
                                  .save({
                                    'jira': {
                                      'server_url': _jiraUrl.text.trim(),
                                      if (_jiraToken.text.trim().isNotEmpty)
                                        'token': _jiraToken.text.trim(),
                                    },
                                    'gitlab': {
                                      'server_url': _gitlabUrl.text.trim(),
                                      if (_gitlabToken.text.trim().isNotEmpty)
                                        'token': _gitlabToken.text.trim(),
                                    },
                                    'llm': {
                                      if (_openaiKey.text.trim().isNotEmpty)
                                        'openai_api_key': _openaiKey.text
                                            .trim(),
                                      if (_googleKey.text.trim().isNotEmpty)
                                        'google_api_key': _googleKey.text
                                            .trim(),
                                    },
                                  });
                              if (!mounted) return;
                              setState(() => _result = 'Saved.');
                              _jiraToken.clear();
                              _gitlabToken.clear();
                              _openaiKey.clear();
                              _googleKey.clear();
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => _result = e.toString());
                            } finally {
                              if (mounted) {
                                setState(() => _saving = false);
                              }
                            }
                          },
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                  if (_result != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _result!,
                        style: theme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
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

class _ConnectionCard extends ConsumerStatefulWidget {
  final AppSettings settings;
  const _ConnectionCard({required this.settings});

  @override
  ConsumerState<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends ConsumerState<_ConnectionCard> {
  late TextEditingController _ctrl;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.settings.apiBaseUrl);
  }

  @override
  void didUpdateWidget(covariant _ConnectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.apiBaseUrl != widget.settings.apiBaseUrl) {
      _ctrl.text = widget.settings.apiBaseUrl;
    }
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
            'Where to reach the AI Crash Fix backend (saved locally in your browser).',
            style: theme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    labelText: 'API base URL',
                    hintText: 'http://localhost:8000',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                onPressed: () {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setBaseUrl(_ctrl.text.trim());
                  ref.invalidate(healthProvider);
                  setState(() => _testResult = 'Saved.');
                },
                child: const Text('Save'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                icon: const Icon(Icons.bolt, size: 16),
                label: Text(_testing ? 'Testing…' : 'Test connection'),
                onPressed: _testing ? null : _runTest,
              ),
            ],
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

class _ConfigSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, dynamic> data;
  const _ConfigSection({
    required this.title,
    required this.icon,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: theme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (data.isEmpty)
            Text(
              'No values configured.',
              style: theme.bodyMedium?.copyWith(color: palette.textMuted),
            )
          else
            ...data.entries.map((e) => _Row(k: e.key, v: e.value)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String k;
  final Object? v;
  const _Row({required this.k, this.v});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    Widget value;
    if (v is bool) {
      final b = v as bool;
      value = Container(
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
              b ? 'set' : 'not set',
              style: theme.labelSmall?.copyWith(
                color: b ? palette.success : palette.danger,
              ),
            ),
          ],
        ),
      );
    } else {
      final str = v == null || v.toString().isEmpty ? '—' : v.toString();
      value = Text(str, style: theme.bodyMedium?.copyWith(color: palette.text));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(
              k.replaceAll('_', ' '),
              style: theme.labelMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}
