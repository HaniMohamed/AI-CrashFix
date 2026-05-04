/// Mirrors the redacted snapshot returned by `GET /api/config`.
class ConfigView {
  final Map<String, dynamic> raw;
  const ConfigView(this.raw);

  factory ConfigView.fromJson(Map<String, dynamic> j) => ConfigView(j);

  Map<String, dynamic> section(String name) =>
      (raw[name] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Ordered list used to render config sections.
  List<({String key, String title, IconDataKey icon})> sections = const [
    (key: 'llm', title: 'LLM Provider', icon: IconDataKey.brain),
    (key: 'repo', title: 'Repository', icon: IconDataKey.repo),
    (key: 'crashlytics', title: 'Crashlytics', icon: IconDataKey.cloud),
    (key: 'jira', title: 'Jira', icon: IconDataKey.ticket),
    (key: 'gitlab', title: 'GitLab', icon: IconDataKey.git),
    (key: 'logging', title: 'Logging', icon: IconDataKey.log),
  ];
}

/// Indirection so models stay framework-free; widgets map to real Icons.
enum IconDataKey { brain, repo, cloud, ticket, git, log }
