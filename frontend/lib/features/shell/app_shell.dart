import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/spacing.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../dashboard/widgets/hero_header.dart';
import 'sidebar.dart';
import 'topbar.dart';
import 'repo_manage_dialog.dart';

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
    final hasRepos = repoAsync.valueOrNull?.repos.isNotEmpty == true;

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

    // Hard gate: if no repos configured, keep the user in onboarding and block navigation,
    // even if they opened the app via a deep link.
    if (repoAsync.hasValue && !hasRepos) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Force dashboard behind the dialog; deep links must not be usable before onboarding.
        if (widget.currentPath != '/') {
          context.go('/');
        }
        if (_forcedDialogOpen) return;
        _forcedDialogOpen = true;
        try {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => ManageReposDialog(
              allowClose: false,
              onDelete: (repoKey, repoName) async {
                // Deletion is allowed, but there shouldn't be any repos here anyway.
                // Keep signature compatible with the dialog.
              },
            ),
          );
        } finally {
          if (mounted) _forcedDialogOpen = false;
        }
      });

      // Do not mount DashboardPage here: it watches analytics and would show JSON/HTML errors
      // while the API is misconfigured. Hero + copy only; repo dialog carries the real work.
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
                  'Add your first repository using the dialog above. '
                  'If the API URL is wrong, use the field at the top of that dialog.',
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
