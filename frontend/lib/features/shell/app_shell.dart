import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/spacing.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/providers/backend_process_provider.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/providers/setup_status_provider.dart';
import '../dashboard/widgets/hero_header.dart';
import '../setup/setup_wizard_dialog.dart';
import 'sidebar.dart';
import 'topbar.dart';

/// Layout chrome shared by all top-level routes. Sidebar collapses on small
/// screens; topbar carries health pill, theme toggle, and base URL popover.
///
/// When the user switches to `/` or `/crashes`, the corresponding data
/// providers are invalidated so lists and KPIs refetch without a manual retry.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentPath;
  const AppShell({super.key, required this.child, required this.currentPath});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _userCollapsed = false;
  bool _forcedDialogOpen = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath == widget.currentPath) return;
    final path = widget.currentPath;
    // Must not mutate providers during build; didUpdateWidget runs in that phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.currentPath != path) return;
      if (path == '/') {
        ref.read(analyticsProvider.notifier).refresh();
      } else if (path == '/crashes') {
        ref.invalidate(crashesProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod requirement: `ref.listen` must be registered during build.
    ref.listen<String?>(
      repoRegistryProvider.select((s) => s.valueOrNull?.active?.repoKey),
      (prev, next) {
        if (prev == next) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(analyticsProvider.notifier).refresh();
          ref.invalidate(crashesProvider);
        });
      },
    );

    final repoAsync = ref.watch(repoRegistryProvider);
    final healthAsync = ref.watch(healthProvider);
    final setupAsync = ref.watch(setupStatusProvider);
    final hasRepos = repoAsync.valueOrNull?.repos.isNotEmpty == true;
    final setupIncomplete = setupAsync.valueOrNull?.needsWizard == true ||
        (setupAsync.hasValue && !hasRepos && setupAsync.valueOrNull?.setupComplete != true);

    Widget shellWithTopbar({
      required Widget body,
      required bool absorbSidebar,
    }) {
      final wide = MediaQuery.sizeOf(context).width >= 720;
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                absorbSidebar
                    ? AbsorbPointer(child: AppSidebar(currentPath: '/', collapsed: false))
                    : AppSidebar(currentPath: '/', collapsed: false),
              Expanded(
                child: Column(
                  children: [
                    AppTopbar(onToggleSidebar: () {}),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (healthAsync.isLoading) {
      return shellWithTopbar(
        absorbSidebar: true,
        body: AbsorbPointer(
          absorbing: true,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Checking API and crash store…',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final health = healthAsync.valueOrNull;
    if (healthAsync.hasError ||
        health?.ok != true ||
        health?.crashStoreUnhealthy == true) {
      final title = health?.crashStoreUnhealthy == true
          ? 'Shared crash database unavailable'
          : 'Could not reach the API';
      final detail = health?.userFacingError ?? '${healthAsync.error}';
      return shellWithTopbar(
        absorbSidebar: false,
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    health?.crashStoreUnhealthy == true
                        ? 'Team Postgres is unreachable. Start it (see infra/postgres), or '
                            'use a local SQLite launch env (AI_CRASH_FIX_CRASH_STORE_BACKEND=sqlite). '
                            'Then retry.'
                        : 'The embedded backend may have stopped. Retry restarts it. '
                            'If this keeps happening, check backend logs under '
                            '~/Library/Application Support/Fixora/',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () {
                      // Restart embedded backend if it died (e.g. after a bad
                      // lifecycle kill or crash); then re-check health.
                      ref.invalidate(backendProcessProvider);
                      ref.invalidate(healthProvider);
                      ref.invalidate(repoRegistryProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (health?.gosiBrainLaunchBlocked == true) {
      final gosi = health!.gosiBrainLaunch;
      return shellWithTopbar(
        absorbSidebar: false,
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    gosi.userFacingTitle.isNotEmpty
                        ? gosi.userFacingTitle
                        : 'Launch from CodeFaster',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    gosi.userFacingDetail,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Launch Fixora from the CodeFaster app so it can write '
                    'a fresh ~/crash_fix_gosi_brain_conf.env with your GOSI Brain '
                    'credentials. Quit this app, launch from CodeFaster, then open '
                    'Fixora again.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(backendProcessProvider);
                      ref.invalidate(healthProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // While repo registry is loading, do not mount dashboard (avoids analytics JSON errors).
    if (repoAsync.isLoading) {
      return shellWithTopbar(
        absorbSidebar: true,
        body: AbsorbPointer(
          absorbing: true,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Loading repositories…',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Wrong API URL / offline: show retry instead of a broken dashboard (hasValue is false).
    if (repoAsync.hasError) {
      return shellWithTopbar(
        absorbSidebar: false,
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Could not load repositories',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '${repoAsync.error}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Check the API base URL in the top bar (must point at the Python '
                    'backend, e.g. http://localhost:8000), then retry. '
                    'After the API responds, you can add your first repo in the dialog.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(backendProcessProvider);
                      ref.invalidate(repoRegistryProvider);
                      ref.invalidate(healthProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Hard gate: incomplete Fixora setup (wizard) blocks navigation.
    if (repoAsync.hasValue && setupAsync.hasValue && setupIncomplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (widget.currentPath != '/') {
          context.go('/');
        }
        if (_forcedDialogOpen) return;
        _forcedDialogOpen = true;
        final repoDataReadonly =
            ref.read(healthProvider).valueOrNull?.repoDataReadonly == true;
        try {
          await showDialog<void>(
            context: context,
            barrierDismissible: repoDataReadonly,
            builder: (ctx) => SetupWizardDialog(allowClose: repoDataReadonly),
          );
          if (mounted) {
            ref.invalidate(setupStatusProvider);
            ref.invalidate(repoRegistryProvider);
          }
        } finally {
          if (mounted) _forcedDialogOpen = false;
        }
      });

      return shellWithTopbar(
        absorbSidebar: true,
        body: AbsorbPointer(
          absorbing: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xxxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HeroHeader(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Complete the Fixora setup wizard to continue. '
                  'You can re-open Help anytime after setup for tips and checklists.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final autoCollapse = width < 1100;
    final hideSidebar = width < 720;
    final collapsed = _userCollapsed || autoCollapse;

    return Scaffold(
      body: Row(
        children: [
          if (!hideSidebar)
            AppSidebar(currentPath: widget.currentPath, collapsed: collapsed),
          Expanded(
            child: Column(
              children: [
                AppTopbar(
                  onToggleSidebar: () {
                    setState(() => _userCollapsed = !_userCollapsed);
                  },
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: hideSidebar
          ? _BottomNav(currentPath: widget.currentPath)
          : null,
    );
  }
}

class _BottomNav extends StatelessWidget {
  final String currentPath;
  const _BottomNav({required this.currentPath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int idx = 0;
    for (var i = 0; i < sidebarItems.length; i++) {
      final p = sidebarItems[i].path;
      if (p == '/' && currentPath == '/') idx = i;
      if (p != '/' && currentPath.startsWith(p)) idx = i;
    }
    return NavigationBar(
      selectedIndex: idx,
      onDestinationSelected: (i) {
        // Use GoRouter navigation (Navigator.pushReplacementNamed doesn't apply
        // when using MaterialApp.router).
        context.go(sidebarItems[i].path);
      },
      backgroundColor: theme.scaffoldBackgroundColor,
      destinations: [
        for (final it in sidebarItems)
          NavigationDestination(
            icon: Icon(it.icon),
            selectedIcon: Icon(it.activeIcon ?? it.icon),
            label: it.label,
          ),
      ],
    );
  }
}
