import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../models/analytics.dart';
import 'api_provider.dart';

class AnalyticsNotifier extends AsyncNotifier<Analytics> {
  @override
  Future<Analytics> build() async => _fetch();

  Future<Analytics> _fetch({bool noCache = false}) async {
    final api = ref.read(apiClientProvider);
    final res = await api.getJson(Endpoints.analytics, query: {
      if (noCache) 'no_cache': '1',
    });
    return Analytics.fromJson(res as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch(noCache: true));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final analyticsProvider =
    AsyncNotifierProvider<AnalyticsNotifier, Analytics>(AnalyticsNotifier.new);
