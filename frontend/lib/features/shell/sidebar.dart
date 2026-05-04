import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

class SidebarItem {
  final String label;
  final IconData icon;
  final String path;
  final IconData? activeIcon;
  const SidebarItem({
    required this.label,
    required this.icon,
    required this.path,
    this.activeIcon,
  });
}

const sidebarItems = <SidebarItem>[
  SidebarItem(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    path: '/',
  ),
  SidebarItem(
    label: 'Crashes',
    icon: Icons.bug_report_outlined,
    activeIcon: Icons.bug_report,
    path: '/crashes',
  ),
  SidebarItem(
    label: 'New Run',
    icon: Icons.play_circle_outline,
    activeIcon: Icons.play_circle,
    path: '/runs/new',
  ),
  SidebarItem(
    label: 'Live Run',
    icon: Icons.bolt_outlined,
    activeIcon: Icons.bolt,
    path: '/runs/live',
  ),
  SidebarItem(
    label: 'Settings',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune,
    path: '/settings',
  ),
];

class AppSidebar extends StatelessWidget {
  final String currentPath;
  final bool collapsed;
  const AppSidebar({super.key, required this.currentPath, this.collapsed = false});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final width = collapsed ? 76.0 : 232.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      width: width,
      decoration: BoxDecoration(
        color: palette.surface1,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          _Brand(collapsed: collapsed),
          const SizedBox(height: AppSpacing.xl),
          ...sidebarItems.map((it) => _SidebarTile(
                item: it,
                collapsed: collapsed,
                active: _isActive(it.path),
                onTap: () => context.go(it.path),
              )),
          const Spacer(),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: palette.brandGradient,
                  borderRadius: AppRadii.all(AppRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          'AI Crash Fix',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Crashes \u2192 fix \u2192 PR, on autopilot.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isActive(String path) {
    if (path == '/') return currentPath == '/';
    return currentPath.startsWith(path);
  }
}

class _Brand extends StatelessWidget {
  final bool collapsed;
  const _Brand({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mark = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: palette.brandGradient,
        borderRadius: AppRadii.all(AppRadii.md),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
    );

    if (collapsed) {
      return Padding(padding: const EdgeInsets.all(8.0), child: mark);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          mark,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Crash Fix',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'console',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.textSecondary,
                        letterSpacing: 1.2,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final SidebarItem item;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final color = active ? palette.text : palette.textSecondary;
    final bg = active ? palette.primary.withValues(alpha: 0.12) : Colors.transparent;
    final iconData = active ? (item.activeIcon ?? item.icon) : item.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.all(AppRadii.md),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 10 : AppSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AppRadii.all(AppRadii.md),
              border: Border.all(
                color: active ? palette.primary.withValues(alpha: 0.35) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(iconData, size: 18, color: color),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      item.label,
                      style: theme.labelLarge?.copyWith(color: color),
                    ),
                  ),
                  if (active)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
