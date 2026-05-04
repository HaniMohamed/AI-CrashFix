class Endpoints {
  Endpoints._();

  static const String health = '/api/health';
  static const String runs = '/api/runs';
  static const String crashes = '/api/crashes';
  static const String analytics = '/api/analytics';
  static const String config = '/api/config';

  static String crashById(String id) => '$crashes/$id';
}
