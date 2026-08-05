import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/auth_provider.dart';

/// Redirects unauthenticated users to login and forces password change when required.
class AuthGate extends ConsumerStatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (!auth.initialized || auth.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (auth.needsStoreSetup) {
          context.go('/setup/database');
        } else {
          context.go('/login');
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    if (auth.user?.mustChangePassword == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/change-password');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return widget.child;
  }
}
