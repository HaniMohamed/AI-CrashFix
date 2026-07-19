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
  final String? jiraServerUrl;
  final String? jiraEmail;
  final bool hasJiraToken;
  final String? jiraIssueType;
  final String? jiraProjectKey;
  final String? jiraCreateFields;
  final String? jiraCreateMode;
  final String? jiraParentIssueKey;
  final String? gitlabProject;
  final String? crashlyticsAndroidPackage;
  final String? crashlyticsIosBundleId;

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
    this.jiraServerUrl,
    this.jiraEmail,
    this.hasJiraToken = false,
    this.jiraIssueType,
    this.jiraProjectKey,
    this.jiraCreateFields,
    this.jiraCreateMode,
    this.jiraParentIssueKey,
    this.gitlabProject,
    this.crashlyticsAndroidPackage,
    this.crashlyticsIosBundleId,
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
        jiraServerUrl: (j['jira_server_url'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['jira_server_url'] as String?)?.trim(),
        jiraEmail: (j['jira_email'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['jira_email'] as String?)?.trim(),
        hasJiraToken: j['has_jira_token'] == true,
        jiraIssueType: (j['jira_issue_type'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['jira_issue_type'] as String?)?.trim(),
        jiraProjectKey: (j['jira_project_key'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['jira_project_key'] as String?)?.trim(),
        jiraCreateFields:
            (j['jira_create_fields'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['jira_create_fields'] as String?)?.trim(),
        jiraCreateMode: _normalizeJiraCreateMode(j['jira_create_mode']),
        jiraParentIssueKey:
            (j['jira_parent_issue_key'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['jira_parent_issue_key'] as String?)?.trim(),
        gitlabProject: (j['gitlab_project'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['gitlab_project'] as String?)?.trim(),
        crashlyticsAndroidPackage:
            (j['crashlytics_android_package'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['crashlytics_android_package'] as String?)?.trim(),
        crashlyticsIosBundleId:
            (j['crashlytics_ios_bundle_id'] as String?)?.trim().isEmpty ?? true
                ? null
                : (j['crashlytics_ios_bundle_id'] as String?)?.trim(),
      );

  static String _normalizeJiraCreateMode(dynamic raw) {
    final mode = (raw ?? '').toString().trim().toLowerCase();
    if (mode == 'under_parent' ||
        mode == 'sub_issue' ||
        mode == 'subtask' ||
        mode == 'sub-bug' ||
        mode == 'child') {
      return 'under_parent';
    }
    return 'standalone';
  }
}
