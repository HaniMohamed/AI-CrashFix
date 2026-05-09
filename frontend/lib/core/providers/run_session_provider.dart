import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../api/ndjson_client.dart';
import '../models/run_event.dart';
import '../models/run_request.dart';
import 'api_provider.dart';
import 'repo_registry_provider.dart';

enum RunStatus { idle, starting, running, completed, failed }

class CrashRunState {
  final String crashId;
  final List<RunEvent> events;
  final Map<String, dynamic>? initialState;
  final Map<String, dynamic>? latestState;
  final Map<String, dynamic>? finalState;
  final String? failure;
  final bool completed;

  const CrashRunState({
    required this.crashId,
    this.events = const [],
    this.initialState,
    this.latestState,
    this.finalState,
    this.failure,
    this.completed = false,
  });

  CrashRunState copyWith({
    List<RunEvent>? events,
    Map<String, dynamic>? initialState,
    Map<String, dynamic>? latestState,
    Map<String, dynamic>? finalState,
    String? failure,
    bool? completed,
  }) =>
      CrashRunState(
        crashId: crashId,
        events: events ?? this.events,
        initialState: initialState ?? this.initialState,
        latestState: latestState ?? this.latestState,
        finalState: finalState ?? this.finalState,
        failure: failure ?? this.failure,
        completed: completed ?? this.completed,
      );
}

class RunSession {
  final RunStatus status;
  final String? runId;
  final RunRequest? request;
  final List<RunEvent> globalEvents;
  final Map<String, CrashRunState> perCrash;
  final List<String> crashOrder;
  final RunSummaryEvent? summary;
  final String? error;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const RunSession({
    this.status = RunStatus.idle,
    this.runId,
    this.request,
    this.globalEvents = const [],
    this.perCrash = const {},
    this.crashOrder = const [],
    this.summary,
    this.error,
    this.startedAt,
    this.endedAt,
  });

  bool get isActive =>
      status == RunStatus.starting || status == RunStatus.running;

  RunSession copyWith({
    RunStatus? status,
    String? runId,
    RunRequest? request,
    List<RunEvent>? globalEvents,
    Map<String, CrashRunState>? perCrash,
    List<String>? crashOrder,
    RunSummaryEvent? summary,
    String? error,
    DateTime? startedAt,
    DateTime? endedAt,
  }) =>
      RunSession(
        status: status ?? this.status,
        runId: runId ?? this.runId,
        request: request ?? this.request,
        globalEvents: globalEvents ?? this.globalEvents,
        perCrash: perCrash ?? this.perCrash,
        crashOrder: crashOrder ?? this.crashOrder,
        summary: summary ?? this.summary,
        error: error ?? this.error,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
      );
}

class RunSessionNotifier extends Notifier<RunSession> {
  StreamSubscription? _sub;
  ApiClient? _client;

  @override
  RunSession build() {
    ref.onDispose(() => _sub?.cancel());
    return const RunSession();
  }

  Future<void> start(RunRequest req) async {
    await _sub?.cancel();
    _client = ref.read(apiClientProvider);
    state = RunSession(
      status: RunStatus.starting,
      request: req,
      startedAt: DateTime.now(),
      globalEvents: const [],
      perCrash: const {},
      crashOrder: const [],
    );

    try {
      final active = ref.read(repoRegistryProvider).valueOrNull?.active;
      final body = req.copyWith(
        repoKey: active?.repoKey,
        // Keep url/ref as optional back-compat; backend prefers repo_key when present.
        repoUrl: active?.repoUrl,
        repoRef: active?.repoRef,
      );
      final stream = streamNdjsonPost(_client!, Endpoints.runs, body: body.toJson());
      _sub = stream.listen(
        _handleRaw,
        onError: (Object e, StackTrace _) {
          state = state.copyWith(
            status: RunStatus.failed,
            error: e.toString(),
            endedAt: DateTime.now(),
          );
        },
        onDone: () {
          if (state.status == RunStatus.running ||
              state.status == RunStatus.starting) {
            state = state.copyWith(
              status: state.summary == null
                  ? RunStatus.failed
                  : RunStatus.completed,
              endedAt: DateTime.now(),
            );
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: RunStatus.failed,
        error: e.toString(),
        endedAt: DateTime.now(),
      );
    }
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
    if (state.isActive) {
      state = state.copyWith(
        status: RunStatus.failed,
        error: 'Cancelled',
        endedAt: DateTime.now(),
      );
    }
  }

  void reset() {
    _sub?.cancel();
    _sub = null;
    state = const RunSession();
  }

  void _handleRaw(Map<String, dynamic> raw) {
    final ev = RunEvent.fromJson(raw);
    final globals = [...state.globalEvents, ev];
    var s = state.copyWith(globalEvents: globals);

    if (s.status == RunStatus.starting) {
      s = s.copyWith(status: RunStatus.running);
    }
    if (ev.runId != null && s.runId == null) {
      s = s.copyWith(runId: ev.runId);
    }

    final crashId = ev.crashId;
    if (crashId != null && crashId.isNotEmpty) {
      final perCrash = Map<String, CrashRunState>.from(s.perCrash);
      var existing = perCrash[crashId] ?? CrashRunState(crashId: crashId);
      existing = existing.copyWith(events: [...existing.events, ev]);

      switch (ev) {
        case CrashStartedEvent(:final initialState):
          existing = existing.copyWith(
            initialState: initialState,
            latestState: initialState,
          );
          if (!s.crashOrder.contains(crashId)) {
            // Newest crash cards at the top (batch processes multiple in parallel).
            s = s.copyWith(crashOrder: [crashId, ...s.crashOrder]);
          }
        case StateSnapshotEvent(:final state):
          existing = existing.copyWith(latestState: state);
        case CrashSkippedEvent(:final reason):
          final finalState = <String, dynamic>{
            'pipeline_status': 'skipped',
            if (reason != null && reason.trim().isNotEmpty)
              'pipeline_note': reason.trim(),
          };
          existing = existing.copyWith(
            finalState: finalState,
            latestState: finalState,
            completed: true,
          );
        case CrashCompletedEvent(:final finalState):
          existing = existing.copyWith(
            finalState: finalState,
            latestState: finalState,
            completed: true,
          );
        case CrashFailedEvent(:final error):
          existing = existing.copyWith(
            failure: (error['message'] ?? '').toString(),
            completed: true,
          );
        default:
          break;
      }

      perCrash[crashId] = existing;
      s = s.copyWith(perCrash: perCrash);
    }

    if (ev is RunSummaryEvent) {
      s = s.copyWith(
        summary: ev,
        status: RunStatus.completed,
        endedAt: DateTime.now(),
      );
    } else if (ev is ErrorEvent) {
      s = s.copyWith(
        status: RunStatus.failed,
        error: ev.message,
        endedAt: DateTime.now(),
      );
    }

    state = s;
  }
}

final runSessionProvider =
    NotifierProvider<RunSessionNotifier, RunSession>(RunSessionNotifier.new);
