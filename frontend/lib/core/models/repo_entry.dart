class RepoEntry {
  final String repoKey;
  final String name;
  final String repoUrl;
  final String? repoRef;
  final String? firebaseProjectId;
  final bool hasToken;
  final List<String> packagesDirs;

  const RepoEntry({
    required this.repoKey,
    required this.name,
    required this.repoUrl,
    this.repoRef,
    this.firebaseProjectId,
    this.hasToken = false,
    this.packagesDirs = const [],
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
      );
}

