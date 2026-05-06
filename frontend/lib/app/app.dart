import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_settings.dart';
import '../core/providers/backend_process_provider.dart';
import 'theme/app_theme.dart';

class AiCrashFixApp extends ConsumerWidget {
  final GoRouter router;
  const AiCrashFixApp({super.key, required this.router});
  const AiCrashFixApp.withRouter({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appSettingsProvider);
    final backend = ref.watch(backendProcessProvider);
    return async.when(
      loading: () => MaterialApp(
        title: 'AI Crash Fix',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (e, _) => MaterialApp(
        title: 'AI Crash Fix',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load settings: $e'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(appSettingsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      data: (settings) {
        // Kept for backward compatibility: on web, this provider should never
        // block initial paint.
        if (backend.isLoading) {
          return MaterialApp(
            title: 'AI Crash Fix',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (backend.hasError) {
          return MaterialApp(
            title: 'AI Crash Fix',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Backend bootstrap error: ${backend.error}'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(backendProcessProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return MaterialApp.router(
          title: 'AI Crash Fix',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          routerConfig: router,
        );
      },
    );
  }
}
