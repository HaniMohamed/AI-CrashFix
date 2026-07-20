import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import 'api_provider.dart';
import 'backend_process_provider.dart';

class HealthState {
  final bool? ok;
  final String? error;
  final String? crashStoreBackend;
  final bool? crashStoreOk;
  final String? crashStoreError;
  final String? userId;
  final bool repoDataReadonly;
  final DateTime checkedAt;
  const HealthState({
    this.ok,
    this.error,
    this.crashStoreBackend,
    this.crashStoreOk,
    this.crashStoreError,
    this.userId,
    this.repoDataReadonly = false,
    required this.checkedAt,
  });

  bool get loading => ok == null && error == null;

  bool get crashStoreUnhealthy =>
      crashStoreBackend == 'postgres' && crashStoreOk == false;

  String? get userFacingError {
    if (crashStoreUnhealthy) {
      return crashStoreError ??
          'The shared Postgres crash store is unavailable. '
              'Check that the database is running and AI_CRASH_FIX_CRASH_DB_URL is correct.';
    }
    if (ok == false) {
      return error ?? 'The API is unavailable.';
    }
    return error;
  }
}

class HealthNotifier extends AsyncNotifier<HealthState> {
  Timer? _timer;
  int _consecutiveFailures = 0;
  HealthState? _lastGood;

  @override
  Future<HealthState> build() async {
    ref.onDispose(() => _timer?.cancel());
    // When embedded backend restarts on a new port, re-check immediately.
    ref.listen(backendProcessProvider, (prev, next) {
      if (prev?.valueOrNull?.baseUrl != next.valueOrNull?.baseUrl) {
        unawaited(refresh());
      }
    });
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
      final res = await api
          .getJson(Endpoints.health)
          .timeout(const Duration(seconds: 5));
      if (res is! Map) {
        return _failure(
          HealthState(
            ok: false,
            error: 'Unexpected health response',
            checkedAt: DateTime.now(),
          ),
        );
      }
      final crashStore = res['crash_store'];
      String? crashStoreBackend;
      bool? crashStoreOk;
      String? crashStoreError;
      if (crashStore is Map) {
        crashStoreBackend = crashStore['backend']?.toString();
        crashStoreOk = crashStore['ok'] == true;
        final rawError = crashStore['error'];
        if (rawError != null && '$rawError'.trim().isNotEmpty) {
          crashStoreError = '$rawError';
        }
      }
      final ok = res['ok'] == true;
      final rawUserId = res['user_id'];
      final userId = rawUserId == null
          ? null
          : () {
              final s = '$rawUserId'.trim();
              return s.isEmpty ? null : s;
            }();
      final next = HealthState(
        ok: ok,
        crashStoreBackend: crashStoreBackend,
        crashStoreOk: crashStoreOk,
        crashStoreError: crashStoreError,
        userId: userId,
        repoDataReadonly: res['repo_data_readonly'] == true,
        checkedAt: DateTime.now(),
      );
      if (ok && !next.crashStoreUnhealthy) {
        _consecutiveFailures = 0;
        _lastGood = next;
        return next;
      }
      // API up but DB down: report immediately (user needs to start Postgres).
      if (ok && next.crashStoreUnhealthy) {
        _consecutiveFailures = 0;
        return next;
      }
      return _failure(next);
    } catch (e) {
      return _failure(
        HealthState(error: e.toString(), checkedAt: DateTime.now()),
      );
    }
  }

  /// Ignore a single transient failure; keep last good state so the UI does
  /// not flash full-screen offline on a blip.
  HealthState _failure(HealthState failed) {
    _consecutiveFailures += 1;
    if (_consecutiveFailures < 2 && _lastGood != null) {
      return HealthState(
        ok: _lastGood!.ok,
        crashStoreBackend: _lastGood!.crashStoreBackend,
        crashStoreOk: _lastGood!.crashStoreOk,
        crashStoreError: _lastGood!.crashStoreError,
        userId: _lastGood!.userId,
        repoDataReadonly: _lastGood!.repoDataReadonly,
        checkedAt: DateTime.now(),
      );
    }
    return failed;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _check());
  }
}

final healthProvider =
    AsyncNotifierProvider<HealthNotifier, HealthState>(HealthNotifier.new);
