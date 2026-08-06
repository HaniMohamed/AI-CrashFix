import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/spacing.dart';
import '../../core/api/endpoints.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/providers/api_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/backend_process_provider.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/providers/setup_status_provider.dart';
import '../../shared/widgets/aurora_background.dart';
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
    // Only hard-block when the API itself is unreachable. A dead team Postgres
    // used to freeze the whole UI; backend now falls back to SQLite, and any
    // remaining store issue is shown as a soft banner (below).
    if (healthAsync.hasError || health?.ok != true) {
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
                    'Could not reach the API',
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
                    'The embedded backend may have stopped. Retry restarts it. '
                    'If this keeps happening, check backend logs under '
                    '~/Library/Application Support/Fixora/',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(backendProcessProvider);
                      ref.invalidate(healthProvider);
                      ref.invalidate(repoRegistryProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  if (health?.crashStoreUnhealthy == true) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final api = ref.read(apiClientProvider);
                          await api.postJson(Endpoints.setupUseLocalStore);
                        } catch (_) {}
                        ref.invalidate(healthProvider);
                        ref.invalidate(repoRegistryProvider);
                        ref.invalidate(setupStatusProvider);
                      },
                      icon: const Icon(Icons.storage_outlined),
                      label: const Text('Use local SQLite instead'),
                    ),
                  ],
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

    // Hard gate: incomplete Fixora setup redirects to full-screen onboarding.
    // Allow /repos during setup so onboarding can open the dedicated repos page.
    if (repoAsync.hasValue && setupAsync.hasValue && setupIncomplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final path = GoRouterState.of(context).uri.path;
        if (path == '/onboarding' || path == '/repos') return;
        context.go('/onboarding');
      });

      final path = widget.currentPath;
      if (path == '/repos') {
        // Fall through to normal shell so ReposPage can render.
      } else {
        return shellWithTopbar(
          absorbSidebar: true,
          body: const AbsorbPointer(
            absorbing: true,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
    }

    final width = MediaQuery.sizeOf(context).width;
    final autoCollapse = width < 1100;
    final hideSidebar = width < 720;
    final collapsed = _userCollapsed || autoCollapse;

    return Scaffold(
      body: AuroraBackground(
        intensity: AuroraIntensity.ambient,
        child: Row(
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
                  if (health?.crashStoreUnhealthy == true ||
                      health?.usingLocalStoreFallback == true)
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                health?.crashStoreUnhealthy == true
                                    ? 'Team Postgres is unreachable. Switch to local SQLite to continue.'
                                    : 'Using local SQLite because team Postgres is offline.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (health?.crashStoreUnhealthy == true)
                              TextButton(
                                onPressed: () async {
                                  try {
                                    final api = ref.read(apiClientProvider);
                                    await api.postJson(
                                      Endpoints.setupUseLocalStore,
                                    );
                                  } catch (_) {}
                                  ref.invalidate(healthProvider);
                                  ref.invalidate(repoRegistryProvider);
                                },
                                child: const Text('Use local SQLite'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: hideSidebar
          ? _BottomNav(currentPath: widget.currentPath)
          : null,
    );
  }
}

class _BottomNav extends ConsumerWidget {
  final String currentPath;
  const _BottomNav({required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    final more = moreItemsForUser(isAdmin: isAdmin);

    int idx = 0;
    final onMore = more.any((it) {
      if (it.path == '/') return currentPath == '/';
      return currentPath.startsWith(it.path);
    });
    if (currentPath == '/' || currentPath.startsWith('/crashes')) {
      idx = currentPath == '/' ? 0 : 1;
    } else if (currentPath.startsWith('/runs')) {
      idx = 2;
    } else if (onMore) {
      idx = 3;
    }

    return NavigationBar(
      selectedIndex: idx,
      onDestinationSelected: (i) async {
        if (i < 3) {
          context.go(mobilePrimaryItems[i].path);
          return;
        }
        final chosen = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final it in more)
                    ListTile(
                      leading: Icon(it.icon),
                      title: Text(it.label),
                      selected: currentPath.startsWith(it.path) ||
                          (it.path == '/' && currentPath == '/'),
                      onTap: () => Navigator.pop(ctx, it.path),
                    ),
                ],
              ),
            );
          },
        );
        if (chosen != null && context.mounted) context.go(chosen);
      },
      backgroundColor: theme.scaffoldBackgroundColor,
      destinations: [
        for (final it in mobilePrimaryItems)
          NavigationDestination(
            icon: Icon(it.icon),
            selectedIcon: Icon(it.activeIcon ?? it.icon),
            label: it.label,
          ),
        const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more_horiz),
          label: 'More',
        ),
      ],
    );
  }
}
