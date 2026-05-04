import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../api/api_client.dart';

/// Single source of truth for the active [ApiClient]; rebuilds when the user
/// edits the API base URL in settings.
final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final client = ApiClient(baseUrl: settings.apiBaseUrl);
  ref.onDispose(client.close);
  return client;
});
