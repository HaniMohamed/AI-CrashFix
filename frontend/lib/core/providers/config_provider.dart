import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../models/config_view.dart';
import 'api_provider.dart';
import 'repo_registry_provider.dart';

class ConfigNotifier extends AsyncNotifier<ConfigView> {
  @override
  Future<ConfigView> build() async {
    final active = ref.watch(repoRegistryProvider).valueOrNull?.active;
    final activeKey = active?.repoKey.trim();
    return _fetch(activeKey);
  }

  Future<ConfigView> _fetch(String? activeKey) async {
    final api = ref.read(apiClientProvider);
    final path = (activeKey != null && activeKey.isNotEmpty)
        ? Endpoints.configForRepo(activeKey)
        : Endpoints.config;
    final res = await api.getJson(path);
    return ConfigView.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final active = ref.read(repoRegistryProvider).valueOrNull?.active;
      final activeKey = active?.repoKey.trim();
      state = AsyncData(await _fetch(activeKey));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final configProvider =
    AsyncNotifierProvider<ConfigNotifier, ConfigView>(ConfigNotifier.new);
