import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_gate.dart';
import '../features/auth/change_password_page.dart';
import '../features/auth/database_setup_page.dart';
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
import '../features/setup/onboarding_page.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/repos_page.dart';
import 'theme/motion.dart';

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
          path: '/setup/database',
          pageBuilder: (_, _) =>
              AuroraPage(child: DatabaseSetupPage()),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (_, _) =>
              AuroraPage(child: LoginPage()),
        ),
        GoRoute(
          path: '/change-password',
          pageBuilder: (_, _) =>
              AuroraPage(child: ChangePasswordPage()),
        ),
        GoRoute(
          path: '/onboarding',
          pageBuilder: (ctx, state) => AuroraPage(
            child: AuthGate(
              child: OnboardingPage(
                revisiting: state.uri.queryParameters['revisiting'] == '1',
              ),
            ),
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => AuthGate(
            child: AppShell(currentPath: state.uri.path, child: child),
          ),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, _) =>
                  AuroraPage(child: DashboardPage()),
            ),
            GoRoute(
              path: '/crashes',
              pageBuilder: (_, _) =>
                  AuroraPage(child: CrashesListPage()),
            ),
            GoRoute(
              path: '/crashes/:id',
              pageBuilder: (ctx, state) => AuroraPage(
                child: CrashDetailPage(crashId: state.pathParameters['id']!),
              ),
            ),
            GoRoute(
              path: '/runs/new',
              pageBuilder: (ctx, state) => AuroraPage(
                child: NewRunPage(
                    prefillCrashId: state.uri.queryParameters['prefill']),
              ),
            ),
            GoRoute(
              path: '/runs/live',
              pageBuilder: (_, _) =>
                  AuroraPage(child: RunLivePage()),
            ),
            GoRoute(
              path: '/mrs',
              pageBuilder: (_, _) =>
                  AuroraPage(child: GeneratedMrsPage()),
            ),
            GoRoute(
              path: '/logs',
              pageBuilder: (_, _) =>
                  AuroraPage(child: LogsPage()),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (_, _) =>
                  AuroraPage(child: SettingsPage()),
            ),
            GoRoute(
              path: '/repos',
              pageBuilder: (ctx, state) => AuroraPage(
                child: ReposPage(
                  returnTo: state.uri.queryParameters['returnTo'],
                ),
              ),
            ),
            GoRoute(
              path: '/help',
              pageBuilder: (_, _) =>
                  AuroraPage(child: HelpPage()),
            ),
            GoRoute(
              path: '/admin',
              pageBuilder: (_, _) =>
                  AuroraPage(child: AdminPage()),
            ),
          ],
        ),
      ],
    );
