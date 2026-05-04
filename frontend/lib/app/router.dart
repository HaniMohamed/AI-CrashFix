import 'package:go_router/go_router.dart';

import '../features/crashes/crash_detail_page.dart';
import '../features/crashes/crashes_list_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/runs/new_run_page.dart';
import '../features/runs/run_live_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shell/app_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(currentPath: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (_, _) => const NoTransitionPage(child: DashboardPage()),
        ),
        GoRoute(
          path: '/crashes',
          pageBuilder: (_, _) =>
              const NoTransitionPage(child: CrashesListPage()),
        ),
        GoRoute(
          path: '/crashes/:id',
          pageBuilder: (ctx, state) => NoTransitionPage(
            child: CrashDetailPage(crashId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/runs/new',
          pageBuilder: (ctx, state) => NoTransitionPage(
            child: NewRunPage(prefillCrashId: state.uri.queryParameters['prefill']),
          ),
        ),
        GoRoute(
          path: '/runs/live',
          pageBuilder: (_, _) => const NoTransitionPage(child: RunLivePage()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (_, _) => const NoTransitionPage(child: SettingsPage()),
        ),
      ],
    ),
  ],
);
