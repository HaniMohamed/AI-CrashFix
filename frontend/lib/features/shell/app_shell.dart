import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/analytics_provider.dart';
import '../../core/providers/crashes_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../dashboard/dashboard_page.dart';
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

      // Keep the app UI (dashboard) as the background so the dialog doesn't sit on a blank/black page.
      // Block ALL background interaction until a repo is added.
      return PopScope(
        canPop: false,
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: true,
              child: Scaffold(
                body: Row(
                  children: [
                    // Show the normal chrome, but disable it via AbsorbPointer.
                    if (MediaQuery.sizeOf(context).width >= 720)
                      AppSidebar(currentPath: '/', collapsed: false),
                    Expanded(
                      child: Column(
                        children: [
                          AppTopbar(onToggleSidebar: () {}),
                          const Expanded(child: DashboardPage()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const ModalBarrier(dismissible: false, color: Colors.transparent),
          ],
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
