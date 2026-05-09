class RepoEntry {
  final String repoKey;
  final String name;
  final String repoUrl;
  final String? repoRef;
  final bool hasToken;

  const RepoEntry({
    required this.repoKey,
    required this.name,
    required this.repoUrl,
    this.repoRef,
    this.hasToken = false,
  });

  factory RepoEntry.fromJson(Map<String, dynamic> j) => RepoEntry(
        repoKey: (j['repo_key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        repoUrl: (j['repo_url'] ?? '').toString(),
        repoRef: (j['repo_ref'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['repo_ref'] as String?),
        hasToken: j['has_token'] == true,
      );
}

