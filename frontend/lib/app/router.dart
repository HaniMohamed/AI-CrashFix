import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/crashes/crash_detail_page.dart';
import '../features/crashes/crashes_list_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/runs/new_run_page.dart';
import '../features/runs/run_live_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shell/app_shell.dart';

String _initialLocationFromUrl() {
  // Support hash-style deep links like:
  //   http://localhost:1234/#/runs/live
  // by reading the fragment on web. This keeps local dev links working even if
  // the app is otherwise using path routing.
  if (kIsWeb) {
    final frag = Uri.base.fragment.trim();
    if (frag.startsWith('/')) return frag;
    if (frag.startsWith('#/')) return frag.substring(1);
  }
  return '/';
}

GoRouter createAppRouter() => GoRouter(
      // Must be computed at runtime (after web URL strategy is set in `main`),
      // otherwise deep links like `/#/runs/live` can get lost and the router
      // will rewrite the URL back to `/`.
      initialLocation: _initialLocationFromUrl(),
      debugLogDiagnostics: kIsWeb,
      redirect: (() {
        // Only redirect once on web to support opening the app via a hash deep
        // link (/#/foo) when the platform router reports "/". If we keep doing
        // this on every navigation, clicking "Dashboard" ("/") can bounce back
        // to the previous fragment before the URL updates.
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
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(currentPath: state.uri.path, child: child),
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
              path: '/settings',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: SettingsPage()),
            ),
          ],
        ),
      ],
    );
