/// Sealed type modelling each NDJSON event emitted by `POST /api/runs`.
///
/// Keep [type] strings synced with `app/api/events.py`.
sealed class RunEvent {
  const RunEvent({required this.type, required this.runId, this.crashId});

  final String type;
  final String? runId;
  final String? crashId;

  factory RunEvent.fromJson(Map<String, dynamic> j) {
    final t = (j['type'] ?? '').toString();
    final runId = j['run_id']?.toString();
    final crashId = j['crash_id']?.toString();
    switch (t) {
      case 'run_started':
        return RunStartedEvent(
          runId: runId,
          mode: (j['mode'] ?? 'batch').toString(),
          limit: (j['limit'] as num?)?.toInt() ?? 0,
          mock: j['mock'] == true,
          skipJiraCreation: j['skip_jira_creation'] == true,
          backend: j['crashlytics_backend']?.toString(),
        );
      case 'crash_fetched':
        return CrashFetchedEvent(
          runId: runId,
          count: (j['count'] as num?)?.toInt() ?? 0,
          crashIds: (j['crash_ids'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
        );
      case 'crash_skipped':
        return CrashSkippedEvent(
          runId: runId,
          crashId: crashId,
          reason: j['reason']?.toString(),
        );
      case 'crash_started':
        return CrashStartedEvent(
          runId: runId,
          crashId: crashId,
          initialState: (j['initial_state'] as Map?)?.cast<String, dynamic>() ??
              const {},
        );
      case 'node_started':
        return NodeStartedEvent(
          runId: runId,
          crashId: crashId,
          node: (j['node'] ?? '').toString(),
          extra: j['extra'],
        );
      case 'node_completed':
        return NodeCompletedEvent(
          runId: runId,
          crashId: crashId,
          node: (j['node'] ?? '').toString(),
          durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
          delta: (j['delta'] as Map?)?.cast<String, dynamic>() ?? const {},
          extra: j['extra'],
        );
      case 'node_error':
        return NodeErrorEvent(
          runId: runId,
          crashId: crashId,
          node: (j['node'] ?? '').toString(),
          durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
          delta: (j['delta'] as Map?)?.cast<String, dynamic>() ?? const {},
          error: (j['error'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'router':
        return RouterEvent(
          runId: runId,
          crashId: crashId,
          router: (j['router'] ?? '').toString(),
          route: (j['route'] ?? '').toString(),
          durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        );
      case 'state_snapshot':
        return StateSnapshotEvent(
          runId: runId,
          crashId: crashId,
          afterNode: j['after_node']?.toString(),
          state: (j['state'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'crash_completed':
        return CrashCompletedEvent(
          runId: runId,
          crashId: crashId,
          finalState: (j['final_state'] as Map?)?.cast<String, dynamic>() ??
              const {},
        );
      case 'crash_failed':
        return CrashFailedEvent(
          runId: runId,
          crashId: crashId,
          error: (j['error'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'run_summary':
        return RunSummaryEvent(
          runId: runId,
          fetched: (j['fetched'] as num?)?.toInt() ?? 0,
          processed: (j['processed'] as num?)?.toInt() ?? 0,
          skipped: (j['skipped'] as num?)?.toInt() ?? 0,
          deduped: (j['deduped'] as num?)?.toInt() ?? 0,
          failed: (j['failed'] as num?)?.toInt() ?? 0,
        );
      case 'error':
        return ErrorEvent(
          runId: runId,
          error: (j['error'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      default:
        return UnknownEvent(type: t, runId: runId, raw: j);
    }
  }
}

class RunStartedEvent extends RunEvent {
  final String mode;
  final int limit;
  final bool mock;
  final bool skipJiraCreation;
  final String? backend;
  const RunStartedEvent({
    required super.runId,
    required this.mode,
    required this.limit,
    required this.mock,
    required this.skipJiraCreation,
    this.backend,
  }) : super(type: 'run_started');
}

class CrashFetchedEvent extends RunEvent {
  final int count;
  final List<String> crashIds;
  const CrashFetchedEvent({
    required super.runId,
    required this.count,
    required this.crashIds,
  }) : super(type: 'crash_fetched');
}

class CrashSkippedEvent extends RunEvent {
  final String? reason;
  const CrashSkippedEvent({
    required super.runId,
    required super.crashId,
    this.reason,
  }) : super(type: 'crash_skipped');
}

class CrashStartedEvent extends RunEvent {
  final Map<String, dynamic> initialState;
  const CrashStartedEvent({
    required super.runId,
    required super.crashId,
    required this.initialState,
  }) : super(type: 'crash_started');
}

class NodeStartedEvent extends RunEvent {
  final String node;
  final Object? extra;
  const NodeStartedEvent({
    required super.runId,
    required super.crashId,
    required this.node,
    this.extra,
  }) : super(type: 'node_started');
}

class NodeCompletedEvent extends RunEvent {
  final String node;
  final int durationMs;
  final Map<String, dynamic> delta;
  final Object? extra;
  const NodeCompletedEvent({
    required super.runId,
    required super.crashId,
    required this.node,
    required this.durationMs,
    required this.delta,
    this.extra,
  }) : super(type: 'node_completed');

  int get added => (delta['added'] as List?)?.length ?? 0;
  int get changed => (delta['changed'] as List?)?.length ?? 0;
  int get removed => (delta['removed'] as List?)?.length ?? 0;
}

class NodeErrorEvent extends RunEvent {
  final String node;
  final int durationMs;
  final Map<String, dynamic> delta;
  final Map<String, dynamic> error;
  const NodeErrorEvent({
    required super.runId,
    required super.crashId,
    required this.node,
    required this.durationMs,
    required this.delta,
    required this.error,
  }) : super(type: 'node_error');
}

class RouterEvent extends RunEvent {
  final String router;
  final String route;
  final int durationMs;
  const RouterEvent({
    required super.runId,
    required super.crashId,
    required this.router,
    required this.route,
    required this.durationMs,
  }) : super(type: 'router');
}

class StateSnapshotEvent extends RunEvent {
  final String? afterNode;
  final Map<String, dynamic> state;
  const StateSnapshotEvent({
    required super.runId,
    required super.crashId,
    required this.afterNode,
    required this.state,
  }) : super(type: 'state_snapshot');
}

class CrashCompletedEvent extends RunEvent {
  final Map<String, dynamic> finalState;
  const CrashCompletedEvent({
    required super.runId,
    required super.crashId,
    required this.finalState,
  }) : super(type: 'crash_completed');
}

class CrashFailedEvent extends RunEvent {
  final Map<String, dynamic> error;
  const CrashFailedEvent({
    required super.runId,
    required super.crashId,
    required this.error,
  }) : super(type: 'crash_failed');
}

class RunSummaryEvent extends RunEvent {
  final int fetched;
  final int processed;
  final int skipped;
  final int deduped;
  final int failed;
  const RunSummaryEvent({
    required super.runId,
    required this.fetched,
    required this.processed,
    required this.skipped,
    required this.deduped,
    required this.failed,
  }) : super(type: 'run_summary');
}

class ErrorEvent extends RunEvent {
  final Map<String, dynamic> error;
  const ErrorEvent({required super.runId, required this.error})
      : super(type: 'error');

  String get message => (error['message'] ?? '').toString();
  String get errorType => (error['type'] ?? '').toString();
}

class UnknownEvent extends RunEvent {
  final Map<String, dynamic> raw;
  UnknownEvent({required super.type, required super.runId, required this.raw});
}
