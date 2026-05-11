class Endpoints {
  Endpoints._();

  static const String health = '/api/health';
  static const String runs = '/api/runs';
  static const String crashes = '/api/crashes';
  static const String analytics = '/api/analytics';
  static const String config = '/api/config';
  static const String googleCredentials = '/api/settings/google_credentials';
  static const String repos = '/api/repos';
  static const String activeRepo = '/api/repos/active';
  static const String selectRepo = '/api/repos/select';
  static String repoByKey(String repoKey) => '$repos/$repoKey';
  static String repoStatus(String repoKey) => '${repoByKey(repoKey)}/status';
  static String repoRefresh(String repoKey) => '${repoByKey(repoKey)}/refresh';
  static String repoEffectiveConfig(String repoKey) =>
      '${repoByKey(repoKey)}/effective-config';

  static String crashById(String id) => '$crashes/$id';
}
