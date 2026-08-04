import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import 'api_provider.dart';
import 'backend_process_provider.dart';

class GosiBrainLaunchState {
  final bool required;
  final bool ok;
  final String? envFilePath;
  final bool envFilePresent;
  final bool envFileNonempty;
  final bool authorizationPresent;
  final bool authorizationExpired;
  final String? reason;

  const GosiBrainLaunchState({
    this.required = false,
    this.ok = true,
    this.envFilePath,
    this.envFilePresent = false,
    this.envFileNonempty = false,
    this.authorizationPresent = false,
    this.authorizationExpired = false,
    this.reason,
  });

  factory GosiBrainLaunchState.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return const GosiBrainLaunchState();
    final rawPath = json['env_file_path'];
    return GosiBrainLaunchState(
      required: json['required'] == true,
      ok: json['ok'] != false,
      envFilePath: rawPath == null ? null : '$rawPath'.trim(),
      envFilePresent: json['env_file_present'] == true,
      envFileNonempty: json['env_file_nonempty'] == true,
      authorizationPresent: json['authorization_present'] == true,
      authorizationExpired: json['authorization_expired'] == true,
      reason: json['reason']?.toString(),
    );
  }

  bool get blocked => required && !ok;

  String get userFacingTitle {
    if (!blocked) return '';
    return switch (reason) {
      'authorization_expired' => 'GOSI Brain token expired',
      'authorization_missing' => 'GOSI Brain authorization required',
      _ => 'GOSI Brain configuration required',
    };
  }

  String get userFacingDetail {
    if (!blocked) return '';
    final path = envFilePath ?? '~/crash_fix_gosi_brain_conf.env';
    return switch (reason) {
      'env_file_missing' =>
        'Expected a non-empty configuration file at $path.',
      'authorization_missing' =>
        'GOSI_BRAIN_AUTHORIZATION is missing from $path.',
      'authorization_expired' =>
        'GOSI_BRAIN_AUTHORIZATION in $path has expired.',
      _ =>
        'GOSI Brain is configured but launch credentials are not ready.',
    };
  }
}

class HealthState {
  final bool? ok;
  final String? error;
  final String? crashStoreBackend;
  final bool? crashStoreOk;
  final String? crashStoreError;
  final String? crashStoreFallbackFrom;
  final String? userId;
  final bool repoDataReadonly;
  final GosiBrainLaunchState gosiBrainLaunch;
  final DateTime checkedAt;
  const HealthState({
    this.ok,
    this.error,
    this.crashStoreBackend,
    this.crashStoreOk,
    this.crashStoreError,
    this.crashStoreFallbackFrom,
    this.userId,
    this.repoDataReadonly = false,
    this.gosiBrainLaunch = const GosiBrainLaunchState(),
    required this.checkedAt,
  });

  bool get loading => ok == null && error == null;

  bool get crashStoreUnhealthy =>
      crashStoreBackend == 'postgres' && crashStoreOk == false;

  bool get usingLocalStoreFallback =>
      crashStoreFallbackFrom == 'postgres' && crashStoreBackend == 'sqlite';

  bool get gosiBrainLaunchBlocked => gosiBrainLaunch.blocked;

  String? get userFacingError {
    if (crashStoreUnhealthy) {
      return crashStoreError ??
          'The shared Postgres crash store is unavailable. '
              'Fixora can switch to a local SQLite store for this session.';
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
      String? crashStoreFallbackFrom;
      if (crashStore is Map) {
        crashStoreBackend = crashStore['backend']?.toString();
        crashStoreOk = crashStore['ok'] == true;
        final rawError = crashStore['error'] ?? crashStore['fallback_reason'];
        if (rawError != null && '$rawError'.trim().isNotEmpty) {
          crashStoreError = '$rawError';
        }
        final fb = crashStore['fallback_from'];
        if (fb != null && '$fb'.trim().isNotEmpty) {
          crashStoreFallbackFrom = '$fb'.trim();
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
      final gosiLaunch = res['gosi_brain_launch'] is Map
          ? GosiBrainLaunchState.fromJson(
              res['gosi_brain_launch'] as Map<dynamic, dynamic>,
            )
          : const GosiBrainLaunchState();
      final next = HealthState(
        ok: ok,
        crashStoreBackend: crashStoreBackend,
        crashStoreOk: crashStoreOk,
        crashStoreError: crashStoreError,
        crashStoreFallbackFrom: crashStoreFallbackFrom,
        userId: userId,
        repoDataReadonly: res['repo_data_readonly'] == true,
        gosiBrainLaunch: gosiLaunch,
        checkedAt: DateTime.now(),
      );
      if (ok && !next.crashStoreUnhealthy && !next.gosiBrainLaunchBlocked) {
        _consecutiveFailures = 0;
        _lastGood = next;
        return next;
      }
      // API up but DB down: report immediately (user needs to start Postgres).
      if (ok && next.crashStoreUnhealthy) {
        _consecutiveFailures = 0;
        return next;
      }
      if (ok && next.gosiBrainLaunchBlocked) {
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
        crashStoreFallbackFrom: _lastGood!.crashStoreFallbackFrom,
        userId: _lastGood!.userId,
        repoDataReadonly: _lastGood!.repoDataReadonly,
        gosiBrainLaunch: _lastGood!.gosiBrainLaunch,
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
