enum RunMode { batch, single }

class RunRequest {
  final RunMode mode;
  final int limit;
  final bool mock;
  final bool skipJiraCreation;
  final List<String>? crashIds;
  /// Single mode: Crashlytics issue id; the API fetches the crash then runs the graph.
  final String? crashId;
  /// Optional: stable repo key (preferred). If set, backend resolves URL/ref/token/project id from registry.
  final String? repoKey;
  /// Optional: remote git repository URL to clone for this run.
  final String? repoUrl;
  /// Optional: git ref to checkout (branch/tag/commit).
  final String? repoRef;

  const RunRequest({
    this.mode = RunMode.batch,
    this.limit = 10,
    this.mock = false,
    this.skipJiraCreation = false,
    this.crashIds,
    this.crashId,
    this.repoKey,
    this.repoUrl,
    this.repoRef,
  });

  RunRequest copyWith({
    RunMode? mode,
    int? limit,
    bool? mock,
    bool? skipJiraCreation,
    List<String>? crashIds,
    String? crashId,
    String? repoKey,
    String? repoUrl,
    String? repoRef,
  }) =>
      RunRequest(
        mode: mode ?? this.mode,
        limit: limit ?? this.limit,
        mock: mock ?? this.mock,
        skipJiraCreation: skipJiraCreation ?? this.skipJiraCreation,
        crashIds: crashIds ?? this.crashIds,
        crashId: crashId ?? this.crashId,
        repoKey: repoKey ?? this.repoKey,
        repoUrl: repoUrl ?? this.repoUrl,
        repoRef: repoRef ?? this.repoRef,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'limit': limit,
        'mock': mock,
        'skip_jira_creation': skipJiraCreation,
        if (crashIds != null && crashIds!.isNotEmpty) 'crash_ids': crashIds,
        if (mode == RunMode.single && (crashId != null && crashId!.trim().isNotEmpty))
          'crash_id': crashId!.trim(),
        if (repoKey != null && repoKey!.trim().isNotEmpty) 'repo_key': repoKey!.trim(),
        if (repoUrl != null && repoUrl!.trim().isNotEmpty) 'repo_url': repoUrl!.trim(),
        if (repoRef != null && repoRef!.trim().isNotEmpty) 'repo_ref': repoRef!.trim(),
      };
}
