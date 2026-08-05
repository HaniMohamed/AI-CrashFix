import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/auth_provider.dart';
import '../../shared/widgets/app_version_label.dart';
import '../../shared/widgets/fixora_mark.dart';

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
    label: 'Generated MRs',
    icon: Icons.merge_outlined,
    activeIcon: Icons.merge,
    path: '/mrs',
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
    label: 'Logs',
    icon: Icons.article_outlined,
    activeIcon: Icons.article,
    path: '/logs',
  ),
  SidebarItem(
    label: 'Settings',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune,
    path: '/settings',
  ),
  SidebarItem(
    label: 'Help',
    icon: Icons.help_outline,
    activeIcon: Icons.help,
    path: '/help',
  ),
];

const adminSidebarItem = SidebarItem(
  label: 'Administration',
  icon: Icons.admin_panel_settings_outlined,
  activeIcon: Icons.admin_panel_settings,
  path: '/admin',
);

List<SidebarItem> sidebarItemsForUser({required bool isAdmin}) {
  if (!isAdmin) return sidebarItems;
  return [...sidebarItems, adminSidebarItem];
}

class AppSidebar extends ConsumerWidget {
  final String currentPath;
  final bool collapsed;
  const AppSidebar({super.key, required this.currentPath, this.collapsed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    final items = sidebarItemsForUser(isAdmin: isAdmin);
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
          ...items.map((it) => _SidebarTile(
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
                        const FixoraMark(size: 18, radius: 5, elevated: false),
                        const SizedBox(width: 6),
                        Text(
                          'Fixora',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),                    const SizedBox(height: 4),
                    Text(
                      'Crashes \u2192 fix \u2192 PR\non autopilot.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          if (!collapsed)
            const Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.md,
              ),
              child: AppVersionLabel(),
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
    const mark = FixoraMark(size: 36);

    if (collapsed) {
      return const Padding(padding: EdgeInsets.all(8.0), child: mark);
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
                  'Fixora',
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
