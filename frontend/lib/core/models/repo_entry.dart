class RepoEntry {
  final String repoKey;
  final String name;
  final String repoUrl;
  final String? repoRef;
  final String? firebaseProjectId;
  final bool hasToken;
  final List<String> packagesDirs;
  final String? crashlyticsFetchBackend;
  final String? bqDataset;
  final String? bqCrashlyticsAndroidTable;
  final String? bqCrashlyticsIosTable;
  final String? jiraProjectKey;
  final String? gitlabProject;

  const RepoEntry({
    required this.repoKey,
    required this.name,
    required this.repoUrl,
    this.repoRef,
    this.firebaseProjectId,
    this.hasToken = false,
    this.packagesDirs = const [],
    this.crashlyticsFetchBackend,
    this.bqDataset,
    this.bqCrashlyticsAndroidTable,
    this.bqCrashlyticsIosTable,
    this.jiraProjectKey,
    this.gitlabProject,
  });

  factory RepoEntry.fromJson(Map<String, dynamic> j) => RepoEntry(
        repoKey: (j['repo_key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        repoUrl: (j['repo_url'] ?? '').toString(),
        repoRef: (j['repo_ref'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['repo_ref'] as String?),
        firebaseProjectId:
            (j['firebase_project_id'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['firebase_project_id'] as String?),
        hasToken: j['has_token'] == true,
        packagesDirs: ((j['packages_dirs'] as List?) ?? const [])
            .whereType<dynamic>()
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(growable: false),
        crashlyticsFetchBackend:
            (j['crashlytics_fetch_backend'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['crashlytics_fetch_backend'] as String?)?.trim(),
        bqDataset: (j['bq_dataset'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['bq_dataset'] as String?)?.trim(),
        bqCrashlyticsAndroidTable:
            (j['bq_android_table'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['bq_android_table'] as String?)?.trim(),
        bqCrashlyticsIosTable: (j['bq_ios_table'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['bq_ios_table'] as String?)?.trim(),
        jiraProjectKey: (j['jira_project_key'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['jira_project_key'] as String?)?.trim(),
        gitlabProject: (j['gitlab_project'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['gitlab_project'] as String?)?.trim(),
      );
}

