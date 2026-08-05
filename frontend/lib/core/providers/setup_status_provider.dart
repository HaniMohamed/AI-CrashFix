import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import 'api_provider.dart';

class SetupCheck {
  final String id;
  final String label;
  final bool required;
  final bool ok;
  final String? detail;
  final Map<String, dynamic> raw;

  const SetupCheck({
    required this.id,
    required this.label,
    required this.required,
    required this.ok,
    this.detail,
    this.raw = const {},
  });

  factory SetupCheck.fromJson(Map<String, dynamic> json) {
    return SetupCheck(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? ''}',
      required: json['required'] == true,
      ok: json['ok'] == true,
      detail: json['detail']?.toString(),
      raw: json,
    );
  }
}

class SetupStatus {
  final String nextStep;
  final bool setupComplete;
  final String? setupPath;
  final String? setupCompletedAt;
  final List<String> missing;
  final List<SetupCheck> checks;
  final String? provider;
  final int repoCount;
  final Map<String, dynamic> raw;

  const SetupStatus({
    required this.nextStep,
    required this.setupComplete,
    this.setupPath,
    this.setupCompletedAt,
    this.missing = const [],
    this.checks = const [],
    this.provider,
    this.repoCount = 0,
    this.raw = const {},
  });

  factory SetupStatus.fromJson(Map<String, dynamic> json) {
    final checksRaw = json['checks'];
    final checks = <SetupCheck>[];
    if (checksRaw is List) {
      for (final c in checksRaw) {
        if (c is Map) {
          checks.add(SetupCheck.fromJson(c.cast<String, dynamic>()));
        }
      }
    }
    final missingRaw = json['missing'];
    final missing = <String>[];
    if (missingRaw is List) {
      for (final m in missingRaw) {
        missing.add('$m');
      }
    }
    return SetupStatus(
      nextStep: '${json['next_step'] ?? 'welcome'}',
      setupComplete: json['setup_complete'] == true,
      setupPath: json['setup_path']?.toString(),
      setupCompletedAt: json['setup_completed_at']?.toString(),
      missing: missing,
      checks: checks,
      provider: json['provider']?.toString(),
      repoCount: (json['repo_count'] is num)
          ? (json['repo_count'] as num).toInt()
          : 0,
      raw: json,
    );
  }

  SetupCheck? check(String id) {
    for (final c in checks) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool get needsWizard => !setupComplete;
}

class SetupStatusNotifier extends AsyncNotifier<SetupStatus> {
  @override
  Future<SetupStatus> build() async => _fetch();

  Future<SetupStatus> _fetch() async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson(Endpoints.setupStatus);
    return SetupStatus.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<SetupStatus> saveProgress({
    String? setupPath,
    bool? markComplete,
    bool? clearComplete,
  }) async {
    final api = ref.read(apiClientProvider);
    final body = <String, dynamic>{};
    if (setupPath != null) body['setup_path'] = setupPath;
    if (markComplete != null) body['mark_complete'] = markComplete;
    if (clearComplete != null) body['clear_complete'] = clearComplete;
    final res = await api.postJson(Endpoints.setupProgress, body: body);
    final status = SetupStatus.fromJson((res as Map).cast<String, dynamic>());
    state = AsyncData(status);
    return status;
  }

  Future<Map<String, dynamic>> fetchStoreConfig() async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson(Endpoints.setupStore);
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> saveStoreConfig({
    required String backend,
    String? dbUrl,
    String? username,
    String? password,
    String? userId,
    bool testConnection = true,
  }) async {
    final api = ref.read(apiClientProvider);
    final body = <String, dynamic>{
      'backend': backend,
      'test_connection': testConnection,
      if (dbUrl != null) 'db_url': dbUrl,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (userId != null) 'user_id': userId,
    };
    final res = await api.postJson(Endpoints.setupStore, body: body);
    // Store switch can change health / readiness.
    ref.invalidateSelf();
    return (res as Map).cast<String, dynamic>();
  }
}

final setupStatusProvider =
    AsyncNotifierProvider<SetupStatusNotifier, SetupStatus>(
  SetupStatusNotifier.new,
);
