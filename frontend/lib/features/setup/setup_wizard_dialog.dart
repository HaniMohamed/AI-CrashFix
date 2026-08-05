import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/backend_settings_provider.dart';
import '../../core/providers/repo_registry_provider.dart';
import '../../core/providers/setup_status_provider.dart';

/// Opens full-screen onboarding (first-run or edit). Prefer this from Settings/Help.
Future<void> openSetupWizard(
  BuildContext context,
  WidgetRef ref, {
  bool revisiting = false,
}) async {
  final path = revisiting ? '/onboarding?revisiting=1' : '/onboarding';
  context.go(path);
  // Invalidate after navigation so the page loads fresh status.
  ref.invalidate(setupStatusProvider);
  ref.invalidate(backendSettingsProvider);
  ref.invalidate(repoRegistryProvider);
}
