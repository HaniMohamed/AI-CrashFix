import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../models/repo_entry.dart';
import 'api_provider.dart';

class RepoRegistryState {
  final List<RepoEntry> repos;
  final RepoEntry? active;
  const RepoRegistryState({this.repos = const [], this.active});

  RepoRegistryState copyWith({List<RepoEntry>? repos, RepoEntry? active}) =>
      RepoRegistryState(
        repos: repos ?? this.repos,
        active: active ?? this.active,
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

    return RepoRegistryState(repos: items, active: active);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await build());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> upsertRepo({
    required String name,
    required String repoUrl,
    String? repoRef,
    String? firebaseProjectId,
    String? accessToken,
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

