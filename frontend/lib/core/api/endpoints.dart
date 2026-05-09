class Endpoints {
  Endpoints._();

  static const String health = '/api/health';
  static const String runs = '/api/runs';
  static const String crashes = '/api/crashes';
  static const String analytics = '/api/analytics';
  static const String config = '/api/config';
  static const String repos = '/api/repos';
  static const String activeRepo = '/api/repos/active';
  static const String selectRepo = '/api/repos/select';

  static String crashById(String id) => '$crashes/$id';
}
