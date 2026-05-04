import 'package:flutter/material.dart';

import 'sidebar.dart';
import 'topbar.dart';

/// Layout chrome shared by all top-level routes. Sidebar collapses on small
/// screens; topbar carries health pill, theme toggle, and base URL popover.
class AppShell extends StatefulWidget {
  final Widget child;
  final String currentPath;
  const AppShell({super.key, required this.child, required this.currentPath});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _userCollapsed = false;

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
        Navigator.of(context).maybePop();
        Navigator.of(context).pushReplacementNamed(sidebarItems[i].path);
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
