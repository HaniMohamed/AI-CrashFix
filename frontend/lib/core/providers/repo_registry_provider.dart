import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../models/repo_entry.dart';
import 'api_provider.dart';

class RepoGitStatus {
  final String? headSha;
  final String? indexedSha;
  final String? lastIndexedAt;
  final String? lastError;

  const RepoGitStatus({
    this.headSha,
    this.indexedSha,
    this.lastIndexedAt,
    this.lastError,
  });

  bool get isSynced => headSha != null && indexedSha != null && headSha == indexedSha;

  static RepoGitStatus fromStatusJson(Map<String, dynamic> j) {
    final head = (j['head_sha'] ?? '').toString().trim();
    final idx = (j['index_status'] is Map ? (j['index_status'] as Map) : const {});
    final indexed = (idx['indexed_sha'] ?? '').toString().trim();
    final lastIndexedAt = (idx['last_indexed_at'] ?? '').toString().trim();
    final lastError = (idx['last_error'] ?? '').toString().trim();
    return RepoGitStatus(
      headSha: head.isEmpty ? null : head,
      indexedSha: indexed.isEmpty ? null : indexed,
      lastIndexedAt: lastIndexedAt.isEmpty ? null : lastIndexedAt,
      lastError: lastError.isEmpty ? null : lastError,
    );
  }
}

class RepoRegistryState {
  final List<RepoEntry> repos;
  final RepoEntry? active;
  final Map<String, RepoGitStatus> statusByKey;
  const RepoRegistryState({
    this.repos = const [],
    this.active,
    this.statusByKey = const {},
  });

  RepoRegistryState copyWith({
    List<RepoEntry>? repos,
    RepoEntry? active,
    Map<String, RepoGitStatus>? statusByKey,
  }) =>
      RepoRegistryState(
        repos: repos ?? this.repos,
        active: active ?? this.active,
        statusByKey: statusByKey ?? this.statusByKey,
      );
}

class RepoRegistryNotifier extends AsyncNotifier<RepoRegistryState> {
  @override
  Future<RepoRegistryState> build() async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson(Endpoints.repos);
    final items = ((res as Map)['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => RepoEntry.fromJson(e.cast<String, dynamic>()))
        .toList();

    final activeRes = await api.getJson(Endpoints.activeRepo);
    final activeJson = (activeRes as Map)['active'];
    RepoEntry? active;
    if (activeJson is Map) {
      active = RepoEntry.fromJson(activeJson.cast<String, dynamic>());
    }

    // If the backend has repos but no active selection (e.g. fresh DB,
    // or active repo deleted), auto-select the most recently updated repo.
    if (active == null && items.isNotEmpty) {
      try {
        final selected = await api.postJson(
          Endpoints.selectRepo,
          body: {'repo_key': items.first.repoKey},
        );
        final selJson = (selected as Map)['active'];
        if (selJson is Map) {
          active = RepoEntry.fromJson(selJson.cast<String, dynamic>());
        }
      } catch (_) {
        // If selection fails, fall back to showing the repo list without an active repo.
      }
    }

    final statuses = <String, RepoGitStatus>{};
    // Best-effort: fetch status for each repo so the UI can show commit + sync state.
    await Future.wait(
      items.map((r) async {
        try {
          final s = await api.getJson(Endpoints.repoStatus(r.repoKey));
          if (s is Map) {
            statuses[r.repoKey] = RepoGitStatus.fromStatusJson(s.cast<String, dynamic>());
          }
        } catch (_) {
          // ignore
        }
      }),
    );

    return RepoRegistryState(repos: items, active: active, statusByKey: statuses);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await build());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<Map<String, dynamic>> fetchRepoStatus(String repoKey) async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson(Endpoints.repoStatus(repoKey));
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> refreshRepo(String repoKey) async {
    final api = ref.read(apiClientProvider);
    final res = await api.postJson(Endpoints.repoRefresh(repoKey), body: const {});
    // The backend may have updated repo metadata (packages dirs, token state, etc).
    await refresh();
    return (res as Map).cast<String, dynamic>();
  }

  Future<void> upsertRepo({
    required String name,
    required String repoUrl,
    String? repoRef,
    String? firebaseProjectId,
    String? accessToken,
    List<String>? packagesDirs,
    String? crashlyticsFetchBackend,
    String? bqDataset,
    String? bqCrashlyticsAndroidTable,
    String? bqCrashlyticsIosTable,
    String? jiraProjectKey,
    String? gitlabProject,
  }) async {
    final api = ref.read(apiClientProvider);
    final res = await api.postJson(Endpoints.repos, body: {
      'name': name,
      'repo_url': repoUrl,
      if (repoRef != null && repoRef.trim().isNotEmpty) 'repo_ref': repoRef.trim(),
      if (firebaseProjectId != null && firebaseProjectId.trim().isNotEmpty)
        'firebase_project_id': firebaseProjectId.trim(),
      if (accessToken != null && accessToken.trim().isNotEmpty)
        'access_token': accessToken.trim(),
      if (packagesDirs != null && packagesDirs.where((e) => e.trim().isNotEmpty).isNotEmpty)
        'packages_dirs': packagesDirs.where((e) => e.trim().isNotEmpty).toList(),
      if (crashlyticsFetchBackend != null && crashlyticsFetchBackend.trim().isNotEmpty)
        'crashlytics_fetch_backend': crashlyticsFetchBackend.trim(),
      if (bqDataset != null && bqDataset.trim().isNotEmpty) 'bq_dataset': bqDataset.trim(),
      if (bqCrashlyticsAndroidTable != null && bqCrashlyticsAndroidTable.trim().isNotEmpty)
        'bq_crashlytics_android_table': bqCrashlyticsAndroidTable.trim(),
      if (bqCrashlyticsIosTable != null && bqCrashlyticsIosTable.trim().isNotEmpty)
        'bq_crashlytics_ios_table': bqCrashlyticsIosTable.trim(),
      if (jiraProjectKey != null && jiraProjectKey.trim().isNotEmpty)
        'jira_project_key': jiraProjectKey.trim(),
      if (gitlabProject != null && gitlabProject.trim().isNotEmpty) 'gitlab_project': gitlabProject.trim(),
    });
    final repoKey = (res is Map ? res['repo_key'] : null)?.toString().trim();
    await refresh();
    // Always auto-select the repo that was just added/updated.
    if (repoKey != null && repoKey.isNotEmpty) {
      await selectRepo(repoKey);
    }
  }

  Future<void> selectRepo(String repoKey) async {
    final api = ref.read(apiClientProvider);
    final res = await api.postJson(Endpoints.selectRepo, body: {
      'repo_key': repoKey,
    });
    final activeJson = (res as Map)['active'];
    final current = state.valueOrNull;
    if (activeJson is Map && current != null) {
      state = AsyncData(
        current.copyWith(
          active: RepoEntry.fromJson(activeJson.cast<String, dynamic>()),
        ),
      );
    } else {
      await refresh();
    }
  }

  Future<void> deleteRepo({
    required String repoKey,
    required String confirmName,
  }) async {
    final api = ref.read(apiClientProvider);
    await api.deleteJson(
      Endpoints.repoByKey(repoKey),
      body: {'confirm_name': confirmName},
    );
    await refresh();
  }
}

final repoRegistryProvider =
    AsyncNotifierProvider<RepoRegistryNotifier, RepoRegistryState>(
  RepoRegistryNotifier.new,
);

