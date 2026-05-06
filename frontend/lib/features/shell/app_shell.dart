import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/analytics_provider.dart';
import '../../core/providers/crashes_provider.dart';
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
