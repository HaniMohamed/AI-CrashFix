import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../models/config_view.dart';
import 'api_provider.dart';

class ConfigNotifier extends AsyncNotifier<ConfigView> {
  @override
  Future<ConfigView> build() async => _fetch();

  Future<ConfigView> _fetch() async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson(Endpoints.config);
    return ConfigView.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final configProvider =
    AsyncNotifierProvider<ConfigNotifier, ConfigView>(ConfigNotifier.new);
