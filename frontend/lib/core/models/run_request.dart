enum RunMode { batch, single }

class RunRequest {
  final RunMode mode;
  final int limit;
  final bool mock;
  final bool skipJiraCreation;
  final List<String>? crashIds;
  final Map<String, dynamic>? crash;

  const RunRequest({
    this.mode = RunMode.batch,
    this.limit = 10,
    this.mock = false,
    this.skipJiraCreation = false,
    this.crashIds,
    this.crash,
  });

  RunRequest copyWith({
    RunMode? mode,
    int? limit,
    bool? mock,
    bool? skipJiraCreation,
    List<String>? crashIds,
    Map<String, dynamic>? crash,
  }) =>
      RunRequest(
        mode: mode ?? this.mode,
        limit: limit ?? this.limit,
        mock: mock ?? this.mock,
        skipJiraCreation: skipJiraCreation ?? this.skipJiraCreation,
        crashIds: crashIds ?? this.crashIds,
        crash: crash ?? this.crash,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'limit': limit,
        'mock': mock,
        'skip_jira_creation': skipJiraCreation,
        if (crashIds != null && crashIds!.isNotEmpty) 'crash_ids': crashIds,
        if (mode == RunMode.single && crash != null) 'crash': crash,
      };
}
