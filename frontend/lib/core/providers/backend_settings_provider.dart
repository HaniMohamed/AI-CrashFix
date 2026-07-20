import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_provider.dart';

class BackendSettingsState {
  final Map<String, dynamic> raw;
  const BackendSettingsState(this.raw);

  Map<String, dynamic> section(String name) =>
      (raw[name] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Machine identity for shared Postgres scoping (case-insensitive elsewhere).
  String? get userId {
    final v = raw['user_id'];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  bool get userIdEditable => raw['user_id_editable'] == true;

  bool get repoDataReadonly => raw['repo_data_readonly'] == true;
}

class BackendSettingsNotifier extends AsyncNotifier<BackendSettingsState> {
  @override
  Future<BackendSettingsState> build() async => _fetch();

  Future<BackendSettingsState> _fetch() async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson('/api/settings');
    return BackendSettingsState((res as Map).cast<String, dynamic>());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> save(Map<String, dynamic> payload) async {
    final api = ref.read(apiClientProvider);
    await api.postJson('/api/settings', body: payload);
    await refresh();
  }
}

final backendSettingsProvider = AsyncNotifierProvider<BackendSettingsNotifier, BackendSettingsState>(
  BackendSettingsNotifier.new,
);

