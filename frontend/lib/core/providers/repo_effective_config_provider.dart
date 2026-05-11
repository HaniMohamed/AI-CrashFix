import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import 'api_provider.dart';

/// Merged Crashlytics / Jira / GitLab view for one repo (`GET /api/repos/.../effective-config`).
final repoEffectiveConfigProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, repoKey) async {
  final api = ref.read(apiClientProvider);
  final res = await api.getJson(Endpoints.repoEffectiveConfig(repoKey));
  return (res as Map).cast<String, dynamic>();
});
