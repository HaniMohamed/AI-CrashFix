/// Mirrors the row returned by `GET /api/crashes` and `GET /api/crashes/{id}`.
class Crash {
  final String crashId;
  final String? jiraIssueId;
  final String? prUrl;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final bool analysisDone;
  final bool jiraCreated;
  final bool fixGenerated;
  final bool fixValidated;
  final bool diffApplied;
  final bool branchCreated;
  final bool mrCreated;
  final bool pipelineComplete;

  /// Parsed `result` JSON (final CrashState). May be null when not requested
  /// or when the run hasn't finished.
  final Map<String, dynamic>? result;

  const Crash({
    required this.crashId,
    required this.status,
    this.jiraIssueId,
    this.prUrl,
    this.createdAt,
    this.updatedAt,
    this.analysisDone = false,
    this.jiraCreated = false,
    this.fixGenerated = false,
    this.fixValidated = false,
    this.diffApplied = false,
    this.branchCreated = false,
    this.mrCreated = false,
    this.pipelineComplete = false,
    this.result,
  });

  factory Crash.fromJson(Map<String, dynamic> j) => Crash(
        crashId: (j['crash_id'] ?? '').toString(),
        status: (j['status'] ?? 'in_progress').toString(),
        jiraIssueId: j['jira_issue_id'] as String?,
        prUrl: j['pr_url'] as String?,
        createdAt: j['created_at'] as String?,
        updatedAt: j['updated_at'] as String?,
        analysisDone: j['analysis_done'] == true,
        jiraCreated: j['jira_created'] == true,
        fixGenerated: j['fix_generated'] == true,
        fixValidated: j['fix_validated'] == true,
        diffApplied: j['diff_applied'] == true,
        branchCreated: j['branch_created'] == true,
        mrCreated: j['mr_created'] == true,
        pipelineComplete: j['pipeline_complete'] == true,
        result: j['result'] is Map<String, dynamic>
            ? j['result'] as Map<String, dynamic>
            : null,
      );

  /// Convenience accessors over the parsed result JSON.
  String? get platform => result?['platform'] as String?;
  String? get appVersion => result?['app_version'] as String?;
  String? get exception => result?['exception'] as String?;
  String? get rootCause => result?['root_cause'] as String?;
  String? get fixSuggestion => result?['fix_suggestion'] as String?;
  Object? get device => result?['device'];

  /// Set when the LangGraph run errors; also reflected in row `status == failed`.
  String? get graphError {
    final v = result?['graph_error'];
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    return v.toString();
  }

  String? get graphRunStartTime {
    final v = result?['graph_run_start_time'];
    if (v == null) return null;
    return v.toString();
  }

  String? get graphRunEndTime {
    final v = result?['graph_run_end_time'];
    if (v == null) return null;
    return v.toString();
  }

  /// Package name (Android) or bundle id (iOS) from Crashlytics export.
  String? get appIdentifier {
    final v = result?['app_identifier'];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Firebase Console app segment, e.g. `android:com.example.app`.
  String? get crashlyticsConsoleAppId {
    final v = result?['crashlytics_console_app_id'];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Elapsed graph run when both timestamps parse; otherwise null.
  double? get graphRunDurationSeconds {
    final a = graphRunStartTime;
    final b = graphRunEndTime;
    if (a == null || b == null) return null;
    try {
      final start = DateTime.parse(a);
      final end = DateTime.parse(b);
      final sec = end.difference(start).inMilliseconds / 1000.0;
      return sec >= 0 ? sec : null;
    } catch (_) {
      return null;
    }
  }

  String get deviceLabel {
    final d = device;
    if (d == null) return '';
    if (d is String) return d;
    if (d is Map) {
      for (final k in const ['model', 'name', 'manufacturer', 'id']) {
        final v = d[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return d.toString();
  }

  /// 7 step flags, ordered in pipeline sequence.
  List<({String key, String label, bool done})> get pipelineSteps => [
        (key: 'analysis_done', label: 'Analysis', done: analysisDone),
        (key: 'fix_generated', label: 'Fix gen', done: fixGenerated),
        (key: 'fix_validated', label: 'Validated', done: fixValidated),
        (key: 'diff_applied', label: 'Diff', done: diffApplied),
        (key: 'branch_created', label: 'Branch', done: branchCreated),
        (key: 'mr_created', label: 'MR', done: mrCreated),
        (key: 'jira_created', label: 'Jira', done: jiraCreated),
      ];
}
