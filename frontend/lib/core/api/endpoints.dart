class Endpoints {
  Endpoints._();

  static const String health = '/api/health';
  static const String setupStatus = '/api/setup/status';
  static const String setupProgress = '/api/setup/progress';
  static const String setupUseLocalStore = '/api/setup/use-local-store';
  static const String setupStore = '/api/setup/store';
  static const String setupTestStore = '/api/setup/test/store';
  static const String settings = '/api/settings';
  static const String settingsTestLlm = '/api/settings/test/llm';
  static const String settingsTestJira = '/api/settings/test/jira';
  static const String settingsTestGitlab = '/api/settings/test/gitlab';
  static const String runs = '/api/runs';
  static const String crashes = '/api/crashes';
  static const String analytics = '/api/analytics';
  static const String config = '/api/config';
  static const String googleCredentials = '/api/settings/google_credentials';
  static String repoGoogleCredentials(String repoKey) =>
      '${repoByKey(repoKey)}/google_credentials';
  static const String repos = '/api/repos';
  static const String activeRepo = '/api/repos/active';
  static const String selectRepo = '/api/repos/select';
  static String repoByKey(String repoKey) => '$repos/$repoKey';
  static String repoStatus(String repoKey) => '${repoByKey(repoKey)}/status';
  static String repoRefresh(String repoKey) => '${repoByKey(repoKey)}/refresh';
  static String repoEffectiveConfig(String repoKey) =>
      '${repoByKey(repoKey)}/effective-config';

  static const String logsMeta = '/api/logs/meta';
  static String logTail(String source) => '/api/logs/$source';

  static const String authBootstrapStatus = '/api/auth/bootstrap-status';
  static const String authBootstrapAdmin = '/api/auth/bootstrap-admin';
  static const String authLogin = '/api/auth/login';
  static const String authLogout = '/api/auth/logout';
  static const String authMe = '/api/auth/me';
  static const String authChangePassword = '/api/auth/change-password';
  static const String authUsers = '/api/auth/users';
  static String authUser(String id) => '$authUsers/$id';
  static String authUserResetPassword(String id) =>
      '$authUsers/$id/reset-password';
  static const String authAudit = '/api/auth/audit';
  static const String authSecuritySettings = '/api/auth/security-settings';
  static const String authRepoReadonly =
      '/api/auth/security-settings/repo-readonly';

  static String crashById(String id) => '$crashes/$id';
  static String crashDiff(String id) => '${crashById(id)}/diff';
  static String crashFeedback(String id) => '${crashById(id)}/feedback';
}
