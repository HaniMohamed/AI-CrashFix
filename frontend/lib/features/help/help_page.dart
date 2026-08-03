import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/setup_status_provider.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../setup/setup_wizard_dialog.dart';

class HelpPage extends ConsumerWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final setup = ref.watch(setupStatusProvider);

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
              Text('Help', style: theme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Guides for running $kProductName without editing .env day-to-day. '
                'Configuration precedence: repo → Settings store → bootstrap env.',
                style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              setup.when(
                loading: () => const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: LinearProgressIndicator(),
                  ),
                ),
                error: (e, _) => GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('Could not load setup status: $e'),
                  ),
                ),
                data: (s) => GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Readiness', style: theme.headlineSmall),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          s.setupComplete
                              ? 'Setup looks complete.'
                              : 'Next step: ${s.nextStep}',
                          style: theme.bodyMedium
                              ?.copyWith(color: palette.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ...s.checks.map(
                          (c) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              c.ok ? Icons.check_circle : Icons.error_outline,
                              color: c.ok
                                  ? palette.success
                                  : (c.required ? palette.danger : palette.warning),
                            ),
                            title: Text(c.label),
                            subtitle: c.detail != null ? Text(c.detail!) : null,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        GradientButton(
                          label: 'Open setup wizard',
                          icon: Icons.rocket_launch_outlined,
                          onPressed: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  const SetupWizardDialog(allowClose: true),
                            );
                            ref.invalidate(setupStatusProvider);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _HelpTopic(
                title: 'Getting started',
                body:
                    '1) Open Fixora (DMG or local). 2) Complete the setup wizard: '
                    'pick mock or production, save an LLM key, optionally add GCP / Jira / GitLab, '
                    'then add your Flutter repo. 3) Run a mock batch to verify the pipeline. '
                    'Day-to-day secrets live in Settings — bootstrap .env is only for store backend / team mode.',
              ),
              const _HelpTopic(
                title: 'Crashlytics tables',
                body:
                    'Firebase exports Crashlytics events to BigQuery tables named like '
                    '<package>_ANDROID and <package>_IOS. Set dataset + table names on each '
                    'repo in Manage repositories. Cloud Logging backend is an alternative if you '
                    'route Crashlytics logs instead of BigQuery export.',
              ),
              const _HelpTopic(
                title: 'Jira auth',
                body:
                    'Jira Cloud: Basic auth with email + API token (auth=auto or basic). '
                    'Jira Server/Data Center personal access tokens usually need auth=bearer. '
                    'Required custom fields go in Jira create fields JSON (per repo or global).',
              ),
              const _HelpTopic(
                title: 'GitLab merge requests',
                body:
                    'PR creation needs a successful fix diff and a Jira issue id. '
                    'Set GitLab server + token globally, and namespace/project per repo '
                    '(often auto-derived from the git remote URL).',
              ),
              const _HelpTopic(
                title: 'Team Postgres mode',
                body:
                    'Set AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres and AI_CRASH_FIX_CRASH_DB_URL '
                    'in bootstrap env (or launch env file). Each machine needs AI_CRASH_FIX_USER_ID. '
                    'See infra/postgres for Docker Compose.',
              ),
              const _HelpTopic(
                title: 'Troubleshooting',
                body:
                    'API offline: check base URL (top bar) and that uvicorn / embedded backend is running. '
                    'Stack mapping weak: install ripgrep (rg). '
                    'Diff apply fails: repo ref may not match the crash build. '
                    'macOS Gatekeeper: xattr -cr /Applications/Fixora.app',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpTopic extends StatelessWidget {
  final String title;
  final String body;
  const _HelpTopic({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
