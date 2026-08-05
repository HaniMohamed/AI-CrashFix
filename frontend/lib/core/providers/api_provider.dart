import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../../app/app_settings.dart';
import 'auth_provider.dart';
import 'backend_process_provider.dart';

/// Single source of truth for the active [ApiClient]; rebuilds when the user
/// edits the API base URL in settings or auth token changes.
final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(appSettingsProvider).requireValue;
  final backend = ref.watch(backendProcessProvider).valueOrNull;
  final token = ref.watch(authProvider.select((s) => s.token));
  final client = ApiClient(
    baseUrl: backend?.baseUrl ?? settings.apiBaseUrl,
    authToken: token,
    onUnauthorized: () => ref.read(authProvider.notifier).handleUnauthorized(),
  );
  ref.onDispose(client.close);
  return client;
});
