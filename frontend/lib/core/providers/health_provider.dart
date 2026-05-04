import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import 'api_provider.dart';

class HealthState {
  final bool? ok;
  final String? error;
  final DateTime checkedAt;
  const HealthState({this.ok, this.error, required this.checkedAt});

  bool get loading => ok == null && error == null;
}

class HealthNotifier extends AsyncNotifier<HealthState> {
  Timer? _timer;

  @override
  Future<HealthState> build() async {
    ref.onDispose(() => _timer?.cancel());
    _scheduleNext();
    return _check();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 15), () async {
      state = AsyncData(await _check());
      _scheduleNext();
    });
  }

  Future<HealthState> _check() async {
    final api = ref.read(apiClientProvider);
    try {
      final res = await api.getJson(Endpoints.health);
      final ok = (res is Map && res['ok'] == true);
      return HealthState(ok: ok, checkedAt: DateTime.now());
    } catch (e) {
      return HealthState(error: e.toString(), checkedAt: DateTime.now());
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _check());
  }
}

final healthProvider =
    AsyncNotifierProvider<HealthNotifier, HealthState>(HealthNotifier.new);
