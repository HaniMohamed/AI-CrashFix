import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_gate.dart';
import '../features/auth/change_password_page.dart';
import '../features/auth/login_page.dart';
import '../features/admin/admin_page.dart';
import '../features/crashes/crash_detail_page.dart';
import '../features/crashes/crashes_list_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/mrs/generated_mrs_page.dart';
import '../features/runs/new_run_page.dart';
import '../features/runs/run_live_page.dart';
import '../features/logs/logs_page.dart';
import '../features/settings/settings_page.dart';
import '../features/help/help_page.dart';
import '../features/shell/app_shell.dart';

String _initialLocationFromUrl() {
  if (kIsWeb) {
    final frag = Uri.base.fragment.trim();
    if (frag.startsWith('/')) return frag;
    if (frag.startsWith('#/')) return frag.substring(1);
  }
  return '/';
}

GoRouter createAppRouter() => GoRouter(
      initialLocation: _initialLocationFromUrl(),
      debugLogDiagnostics: kIsWeb,
      redirect: (() {
        final initialFrag = kIsWeb ? Uri.base.fragment.trim() : '';
        var redirected = false;
        return (context, state) {
          if (!kIsWeb || redirected) return null;
          if (state.uri.path != '/') return null;
          if (initialFrag.startsWith('/')) {
            redirected = true;
            return initialFrag;
          }
          if (initialFrag.startsWith('#/')) {
            redirected = true;
            return initialFrag.substring(1);
          }
          return null;
        };
      })(),
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (_, _) =>
              const NoTransitionPage(child: LoginPage()),
        ),
        GoRoute(
          path: '/change-password',
          pageBuilder: (_, _) =>
              const NoTransitionPage(child: ChangePasswordPage()),
        ),
        ShellRoute(
          builder: (context, state, child) => AuthGate(
            child: AppShell(currentPath: state.uri.path, child: child),
          ),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: DashboardPage()),
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
                child: NewRunPage(
                    prefillCrashId: state.uri.queryParameters['prefill']),
              ),
            ),
            GoRoute(
              path: '/runs/live',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: RunLivePage()),
            ),
            GoRoute(
              path: '/mrs',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: GeneratedMrsPage()),
            ),
            GoRoute(
              path: '/logs',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: LogsPage()),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: SettingsPage()),
            ),
            GoRoute(
              path: '/help',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: HelpPage()),
            ),
            GoRoute(
              path: '/admin',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: AdminPage()),
            ),
          ],
        ),
      ],
    );
