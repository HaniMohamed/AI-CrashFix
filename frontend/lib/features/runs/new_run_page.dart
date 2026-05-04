import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/models/run_request.dart';
import '../../core/providers/config_provider.dart';
import '../../core/providers/run_session_provider.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';

class NewRunPage extends ConsumerStatefulWidget {
  final String? prefillCrashId;
  const NewRunPage({super.key, this.prefillCrashId});

  @override
  ConsumerState<NewRunPage> createState() => _NewRunPageState();
}

class _NewRunPageState extends ConsumerState<NewRunPage> {
  RunMode _mode = RunMode.batch;
  int _limit = 10;
  bool _mock = false;
  bool _skipJira = true;
  final _crashIdsCtrl = TextEditingController();
  final _singleCrashIdCtrl = TextEditingController();
  String? _singleRunError;

  @override
  void initState() {
    super.initState();
    if (widget.prefillCrashId != null) {
      _mode = RunMode.single;
      _singleCrashIdCtrl.text = widget.prefillCrashId!;
    }
  }

  @override
  void dispose() {
    _crashIdsCtrl.dispose();
    _singleCrashIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final config = ref.watch(configProvider);

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
              Text('Trigger a new run', style: theme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Configure every flag the API accepts and stream live events on the next page.',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              config.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (cfg) {
                  final llm = cfg.section('llm');
                  final cl = cfg.section('crashlytics');
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: palette.surface2,
                      border: Border.all(color: palette.border),
                      borderRadius: AppRadii.all(AppRadii.md),
                    ),
                    child: Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _ChipFact(label: 'LLM', value: '${llm['provider']}'),
                        _ChipFact(label: 'Backend', value: '${cl['backend']}'),
                        _ChipFact(label: 'Project', value: '${cl['project_id'] ?? '-'}'),
                        _ChipFact(
                          label: 'Mock fetch',
                          value: _mock ? 'on' : 'off',
                        ),
                      ],
                    ),
                  );
                },
              ),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mode', style: theme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<RunMode>(
                      segments: const [
                        ButtonSegment(
                          value: RunMode.batch,
                          icon: Icon(Icons.layers_outlined),
                          label: Text('Batch'),
                        ),
                        ButtonSegment(
                          value: RunMode.single,
                          icon: Icon(Icons.flag_outlined),
                          label: Text('Single crash'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_mode == RunMode.batch) ..._buildBatchFields(palette, theme),
                    if (_mode == RunMode.single) ..._buildSingleFields(palette, theme),
                    const SizedBox(height: AppSpacing.xl),
                    _SwitchRow(
                      label: 'Mock crashes (no BigQuery / Cloud Logging)',
                      value: _mock,
                      onChanged: (v) => setState(() => _mock = v),
                    ),
                    _SwitchRow(
                      label: 'Skip Jira creation',
                      value: _skipJira,
                      onChanged: (v) => setState(() => _skipJira = v),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_singleRunError != null) ...[
                      ErrorBanner(message: _singleRunError!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Row(
                      children: [
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: () {
                            ref.read(runSessionProvider.notifier).reset();
                            setState(() {
                              _crashIdsCtrl.clear();
                              _singleCrashIdCtrl.clear();
                              _mock = false;
                              _skipJira = true;
                              _limit = 10;
                              _mode = RunMode.batch;
                              _singleRunError = null;
                            });
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Reset'),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        GradientButton(
                          label: 'Start run',
                          icon: Icons.bolt,
                          onPressed: _start,
                        ),
                      ],
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

  List<Widget> _buildBatchFields(AppPalette palette, TextTheme theme) {
    return [
      Text('Limit ($_limit)', style: theme.titleMedium),
      Slider(
        value: _limit.toDouble(),
        min: 1,
        max: 200,
        divisions: 199,
        label: _limit.toString(),
        onChanged: (v) => setState(() => _limit = v.round()),
      ),
      const SizedBox(height: AppSpacing.md),
      Text('Crash IDs whitelist (optional)', style: theme.titleMedium),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Comma- or newline-separated. Only crashes whose id appears here are processed (batch only).',
        style: theme.bodySmall?.copyWith(color: palette.textSecondary),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _crashIdsCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'abc123, def456 …',
        ),
      ),
    ];
  }

  List<Widget> _buildSingleFields(AppPalette palette, TextTheme theme) {
    return [
      Text('Crashlytics issue id', style: theme.titleMedium),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'The server loads this issue from Crashlytics (BigQuery or Cloud Logging), '
        'or reuses the last saved pipeline state from the local store if the issue is not in export.',
        style: theme.bodySmall?.copyWith(color: palette.textSecondary),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _singleCrashIdCtrl,
        style: AppTypography.mono(color: palette.text, size: 14),
        decoration: const InputDecoration(
          hintText: 'e.g. issue_mock_0001 or your Crashlytics issue id',
        ),
      ),
    ];
  }

  void _start() {
    setState(() => _singleRunError = null);
    String? singleCrashId;
    List<String>? crashIds;

    if (_mode == RunMode.single) {
      singleCrashId = _singleCrashIdCtrl.text.trim();
      if (singleCrashId.isEmpty) {
        setState(() => _singleRunError = 'Enter a non-empty crash id.');
        return;
      }
    } else {
      final raw = _crashIdsCtrl.text;
      if (raw.trim().isNotEmpty) {
        crashIds = raw
            .split(RegExp(r'[\s,]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }

    final req = RunRequest(
      mode: _mode,
      limit: _limit,
      mock: _mock,
      skipJiraCreation: _skipJira,
      crashIds: crashIds,
      crashId: singleCrashId,
    );

    ref.read(runSessionProvider.notifier).start(req);
    context.go('/runs/live');
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.bodyLarge)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ChipFact extends StatelessWidget {
  final String label;
  final String value;
  const _ChipFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.labelSmall?.copyWith(color: palette.textMuted, letterSpacing: 1),
        ),
        const SizedBox(width: 6),
        Text(value, style: theme.labelLarge?.copyWith(color: palette.text)),
      ],
    );
  }
}
