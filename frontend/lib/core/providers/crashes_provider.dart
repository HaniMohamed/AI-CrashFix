import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../models/crash.dart';
import 'api_provider.dart';
import 'repo_registry_provider.dart';

class CrashListQuery {
  final String? status;
  final int limit;
  final int offset;
  final bool includeResult;
  const CrashListQuery({
    this.status,
    this.limit = 50,
    this.offset = 0,
    this.includeResult = false,
  });

  CrashListQuery copyWith({String? status, int? limit, int? offset, bool? includeResult}) =>
      CrashListQuery(
        status: status ?? this.status,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
        includeResult: includeResult ?? this.includeResult,
      );
}

class CrashListPage {
  final List<Crash> items;
  final int limit;
  final int offset;
  final int count;
  const CrashListPage({
    required this.items,
    required this.limit,
    required this.offset,
    required this.count,
  });
}

final crashesQueryProvider = StateProvider<CrashListQuery>((ref) {
  return const CrashListQuery();
});

final crashesProvider = FutureProvider<CrashListPage>((ref) async {
  final api = ref.watch(apiClientProvider);
  final q = ref.watch(crashesQueryProvider);
  final repo = ref.watch(repoRegistryProvider).valueOrNull?.active;
  final res = await api.getJson(Endpoints.crashes, query: {
    if (q.status != null) 'status': q.status,
    'limit': q.limit,
    'offset': q.offset,
    if (q.includeResult) 'include_result': 1,
    if (repo != null) 'repo_key': repo.repoKey,
  });
  final j = (res as Map).cast<String, dynamic>();
  final items = (j['items'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Crash.fromJson(e.cast<String, dynamic>()))
      .toList();
  return CrashListPage(
    items: items,
    limit: (j['limit'] as num?)?.toInt() ?? q.limit,
    offset: (j['offset'] as num?)?.toInt() ?? q.offset,
    count: (j['count'] as num?)?.toInt() ?? items.length,
  );
});

final crashDetailProvider =
    FutureProvider.autoDispose.family<Crash, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final repo = ref.watch(repoRegistryProvider).valueOrNull?.active;
  final res = await api.getJson(
    Endpoints.crashById(id),
    query: {if (repo != null) 'repo_key': repo.repoKey},
  );
  return Crash.fromJson((res as Map).cast<String, dynamic>());
});
