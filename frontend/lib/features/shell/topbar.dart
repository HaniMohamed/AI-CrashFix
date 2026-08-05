import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_settings.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../shared/widgets/gradient_button.dart';

class AppTopbar extends ConsumerWidget {
  final VoidCallback onToggleSidebar;
  const AppTopbar({super.key, required this.onToggleSidebar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(appSettingsProvider).requireValue;
    final reposAsync = ref.watch(repoRegistryProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.bg.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: palette.border.withValues(alpha: 0.85))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onToggleSidebar,
            icon: const Icon(Icons.menu),
            tooltip: 'Toggle sidebar',
          ),
          const SizedBox(width: AppSpacing.sm),
          const Flexible(child: _SearchOrTitle()),
          const Spacer(),
          _RepoPicker(async: reposAsync),
          if (wide) ...[
            const SizedBox(width: AppSpacing.md),
            const _HealthPill(),
          ],
          const SizedBox(width: AppSpacing.sm),
          const _ThemeToggle(),
          IconButton(
            onPressed: () => ref.read(authProvider.notifier).logout().then((_) {
              if (context.mounted) context.go('/login');
            }),
            tooltip: 'Sign out',
            icon: Icon(Icons.logout, color: palette.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          GradientButton(
            dense: true,
            label: 'New run',
            icon: Icons.play_arrow_rounded,
            onPressed: () => context.go('/runs/new'),
          ),
          // Keep settings URL accessible but quieter.
          if (wide) ...[
            const SizedBox(width: AppSpacing.sm),
            _BaseUrlPopover(currentUrl: settings.apiBaseUrl),
          ],
        ],
      ),
    );
  }
}

class _RepoPicker extends ConsumerStatefulWidget {
  final AsyncValue<RepoRegistryState> async;
  const _RepoPicker({required this.async});

  @override
  ConsumerState<_RepoPicker> createState() => _RepoPickerState();
}

class _RepoPickerState extends ConsumerState<_RepoPicker> {
  void _openManagePage() {
    context.go('/repos');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return widget.async.when(
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface2,
          border: Border.all(color: palette.border),
          borderRadius: AppRadii.all(AppRadii.pill),
        ),
        child: Text(
          'Repo…',
          style: theme.labelMedium?.copyWith(color: palette.textMuted),
        ),
      ),
      error: (_, _) => OutlinedButton.icon(
        icon: const Icon(Icons.source_outlined, size: 16),
        label: const Text('Repo'),
        onPressed: _openManagePage,
      ),
      data: (data) {
        // NOTE: First-run onboarding is enforced globally by `AppShell` (non-dismissible),
        // so the topbar must not auto-open a second, dismissible dialog.

        final active = data.active;
        final label = (active?.name.trim().isNotEmpty ?? false)
            ? active!.name
            : 'Select repo';
        return PopupMenuButton<String>(
          tooltip: 'Repository',
          position: PopupMenuPosition.under,
          color: palette.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.md),
          ),
          onSelected: (v) async {
            if (v == '__manage__') {
              _openManagePage();
              return;
            }
            await ref.read(repoRegistryProvider.notifier).selectRepo(v);
            // Repo-scoped providers are refreshed by AppShell's listener.
          },
          itemBuilder: (ctx) => [
            if (data.repos.isEmpty)
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'No repos saved yet.',
                  style: theme.labelMedium?.copyWith(color: palette.textMuted),
                ),
              ),
            for (final r in data.repos)
              PopupMenuItem<String>(
                value: r.repoKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.name, style: theme.bodyMedium)),
                        const SizedBox(width: 8),
                        if (data.statusByKey[r.repoKey]?.isSynced == true)
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: palette.primary,
                          )
                        else if ((data.statusByKey[r.repoKey]?.headSha ?? '')
                            .isNotEmpty)
                          Icon(Icons.sync, size: 14, color: palette.textMuted),
                      ],
                    ),
                    Text(
                      r.repoUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    if ((data.statusByKey[r.repoKey]?.headSha ?? '').isNotEmpty)
                      Text(
                        'Commit: ${(data.statusByKey[r.repoKey]!.headSha!).substring(0, 12)}',
                        style: theme.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: '__manage__',
              child: Row(
                children: [
                  Icon(Icons.add, size: 16),
                  SizedBox(width: 8),
                  Text('Manage repos…'),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.surface2,
              border: Border.all(color: palette.border),
              borderRadius: AppRadii.all(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.source_outlined,
                  size: 14,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.labelMedium?.copyWith(color: palette.text),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: palette.textMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchOrTitle extends StatelessWidget {
  const _SearchOrTitle();

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context);
    final theme = Theme.of(context).textTheme;
    final loc = route.uri.path;
    final title = switch (loc) {
      '/' => 'Dashboard',
      _ when loc.startsWith('/crashes/') => 'Crash detail',
      '/crashes' => 'Crashes',
      '/runs/new' => 'New run',
      '/runs/live' => 'Live run',
      '/mrs' => 'Generated MRs',
      '/logs' => 'Logs',
      '/repos' => 'Repositories',
      '/settings' => 'Settings',
      '/help' => 'Help',
      '/admin' => 'Administration',
      _ => '',
    };
    return Text(
      title,
      overflow: TextOverflow.ellipsis,
      style: theme.headlineSmall,
    );
  }
}

class _HealthPill extends ConsumerWidget {
  const _HealthPill();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final health = ref.watch(healthProvider);
    Color dot;
    String label;
    if (health.isLoading) {
      dot = palette.warning;
      label = 'Checking…';
    } else if (health.hasError) {
      dot = palette.danger;
      label = 'API offline';
    } else {
      final ok = health.value?.ok == true;
      final crashStoreUnhealthy = health.value?.crashStoreUnhealthy == true;
      final localFallback = health.value?.usingLocalStoreFallback == true;
      if (crashStoreUnhealthy) {
        dot = palette.danger;
        label = 'DB offline';
      } else if (localFallback) {
        dot = palette.warning;
        label = 'Local SQLite';
      } else {
        dot = ok ? palette.success : palette.danger;
        label = ok ? 'API healthy' : 'API offline';
      }
    }
    final tooltipDetail = health.value?.crashStoreUnhealthy == true
        ? health.value?.crashStoreError
        : null;
    return Tooltip(
      message: [
        'Last check: ${health.value?.checkedAt.toLocal().toString().split('.').first ?? "—"}',
        if (tooltipDetail != null && tooltipDetail.isNotEmpty) tooltipDetail,
      ].join('\n'),
      child: InkWell(
        borderRadius: AppRadii.all(AppRadii.pill),
        onTap: () => ref.read(healthProvider.notifier).refresh(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.surface2,
            border: Border.all(color: palette.border),
            borderRadius: AppRadii.all(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: dot.withValues(alpha: 0.6), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.labelMedium?.copyWith(color: palette.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BaseUrlPopover extends ConsumerStatefulWidget {
  final String currentUrl;
  const _BaseUrlPopover({required this.currentUrl});

  @override
  ConsumerState<_BaseUrlPopover> createState() => _BaseUrlPopoverState();
}

class _BaseUrlPopoverState extends ConsumerState<_BaseUrlPopover> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentUrl);
  }

  @override
  void didUpdateWidget(covariant _BaseUrlPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUrl != widget.currentUrl) {
      _ctrl.text = widget.currentUrl;
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
    return PopupMenuButton<void>(
      enabled: false,
      tooltip: 'API base URL',
      position: PopupMenuPosition.under,
      color: palette.surface2,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.md)),
      itemBuilder: (ctx) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'API base URL',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'http://localhost:8000',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setBaseUrl(_ctrl.text.trim());
                          Navigator.of(ctx).pop();
                          ref.invalidate(healthProvider);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface2,
          border: Border.all(color: palette.border),
          borderRadius: AppRadii.all(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns, size: 14, color: palette.textSecondary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                widget.currentUrl,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: palette.text),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appSettingsProvider).requireValue.themeMode;
    final isDark = mode == ThemeMode.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light' : 'Switch to dark',
      icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
      },
    );
  }
}
