import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../api/api_client.dart';
import 'backend_process_provider.dart';

/// Single source of truth for the active [ApiClient]; rebuilds when the user
/// edits the API base URL in settings.
final apiClientProvider = Provider<ApiClient>((ref) {
  // Only build after prefs are loaded so we never create a client that is
  // immediately disposed when AsyncNotifier finishes (that caused offline /
  // failed dashboard on first paint).
  final settings = ref.watch(appSettingsProvider).requireValue;
  final backend = ref.watch(backendProcessProvider).valueOrNull;
  final client = ApiClient(baseUrl: backend?.baseUrl ?? settings.apiBaseUrl);
  ref.onDispose(client.close);
  return client;
});
