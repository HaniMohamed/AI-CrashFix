/// Mirrors the row returned by `GET /api/crashes` and `GET /api/crashes/{id}`.
class Crash {
  final String crashId;
  final String? jiraIssueId;
  final String? prUrl;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  /// Audit: machine user who first ingested / ran this crash (shared inventory).
  final String? createdByUserId;
  final bool analysisDone;
  final bool jiraCreated;
  final bool fixGenerated;
  final bool fixValidated;
  final bool diffApplied;
  final bool branchCreated;
  final bool mrCreated;
  final bool pipelineComplete;
  final int feedbackIterationCount;
  final bool feedbackLocked;

  /// MR lifecycle tracking populated once a merge request has been created.
  final String? mrStatus;
  final String? mrStatusCheckedAt;
  final String? mrCreatedAt;
  final String? fixedInVersionAndroid;
  final String? fixedInVersionIos;
  final String? fixedMarkedAt;
  final String? fixedMarkedByUserId;
  final bool reopened;
  final String? reopenedAt;
  final int reopenCount;
  final String? reopenedFromCrashId;

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
    this.createdByUserId,
    this.analysisDone = false,
    this.jiraCreated = false,
    this.fixGenerated = false,
    this.fixValidated = false,
    this.diffApplied = false,
    this.branchCreated = false,
    this.mrCreated = false,
    this.pipelineComplete = false,
    this.feedbackIterationCount = 0,
    this.feedbackLocked = false,
    this.mrStatus,
    this.mrStatusCheckedAt,
    this.mrCreatedAt,
    this.fixedInVersionAndroid,
    this.fixedInVersionIos,
    this.fixedMarkedAt,
    this.fixedMarkedByUserId,
    this.reopened = false,
    this.reopenedAt,
    this.reopenCount = 0,
    this.reopenedFromCrashId,
    this.result,
  });

  factory Crash.fromJson(Map<String, dynamic> j) => Crash(
        crashId: (j['crash_id'] ?? '').toString(),
        status: (j['status'] ?? 'in_progress').toString(),
        jiraIssueId: j['jira_issue_id'] as String?,
        prUrl: j['pr_url'] as String?,
        createdAt: j['created_at'] as String?,
        updatedAt: j['updated_at'] as String?,
        createdByUserId: () {
          final v = j['created_by_user_id'];
          if (v == null) return null;
          final s = v.toString().trim();
          return s.isEmpty ? null : s;
        }(),
        analysisDone: j['analysis_done'] == true,
        jiraCreated: j['jira_created'] == true,
        fixGenerated: j['fix_generated'] == true,
        fixValidated: j['fix_validated'] == true,
        diffApplied: j['diff_applied'] == true,
        branchCreated: j['branch_created'] == true,
        mrCreated: j['mr_created'] == true,
        pipelineComplete: j['pipeline_complete'] == true,
        feedbackIterationCount:
            (j['feedback_iteration_count'] as num?)?.toInt() ?? 0,
        feedbackLocked: j['feedback_locked'] == true,
        mrStatus: j['mr_status'] as String?,
        mrStatusCheckedAt: j['mr_status_checked_at'] as String?,
        mrCreatedAt: j['mr_created_at'] as String?,
        fixedInVersionAndroid: j['fixed_in_version_android'] as String?,
        fixedInVersionIos: j['fixed_in_version_ios'] as String?,
        fixedMarkedAt: j['fixed_marked_at'] as String?,
        fixedMarkedByUserId: j['fixed_marked_by_user_id'] as String?,
        reopened: j['reopened'] == true,
        reopenedAt: j['reopened_at'] as String?,
        reopenCount: (j['reopen_count'] as num?)?.toInt() ?? 0,
        reopenedFromCrashId: j['reopened_from_crash_id'] as String?,
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

  /// Prefer the previous run's skip flag so re-runs do not force-skip Jira.
  bool get skipJiraCreation => result?['skip_jira_creation'] == true;

  /// PR/MR fields from persisted `result` (CrashState).
  String? get prTitle {
    final v = result?['pr_title'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? get prBody {
    final v = result?['pr_body'];
    if (v == null) return null;
    final s = v.toString();
    return s.trim().isEmpty ? null : s;
  }

  String? get prBranch {
    final v = result?['pr_branch'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? get prUrlFromResult {
    final v = result?['pr_url'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? get effectivePrUrl => prUrl ?? prUrlFromResult;

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
