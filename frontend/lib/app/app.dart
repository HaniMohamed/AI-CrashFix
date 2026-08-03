import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_settings.dart';
import '../core/providers/backend_process_provider.dart';
import 'theme/app_theme.dart';

class FixoraApp extends ConsumerStatefulWidget {
  final GoRouter router;
  const FixoraApp({super.key, required this.router});
  const FixoraApp.withRouter({super.key, required this.router});

  @override
  ConsumerState<FixoraApp> createState() => _FixoraAppState();
}

class _FixoraAppState extends ConsumerState<FixoraApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort: window/app teardown should already have stopped the backend.
    unawaited(EmbeddedBackendLifecycle.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only tear down the backend when the Flutter engine is going away.
    // Do NOT stop on `hidden` / `inactive` — on macOS those fire when the user
    // switches apps or minimizes, which previously left the UI pointing at a
    // dead port ("Could not reach the API" / Connection refused).
    if (state == AppLifecycleState.detached) {
      unawaited(EmbeddedBackendLifecycle.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appSettingsProvider);
    final backend = ref.watch(backendProcessProvider);
    return async.when(
      loading: () => MaterialApp(
        title: 'Fixora',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (e, _) => MaterialApp(
        title: 'Fixora',
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
                    onPressed: () => ref.invalidate(appSettingsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      data: (settings) {
        if (backend.isLoading) {
          return MaterialApp(
            title: 'Fixora',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (backend.hasError) {
          return MaterialApp(
            title: 'Fixora',
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
                        onPressed: () =>
                            ref.invalidate(backendProcessProvider),
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
          title: 'Fixora',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          routerConfig: widget.router,
        );
      },
    );
  }
}
