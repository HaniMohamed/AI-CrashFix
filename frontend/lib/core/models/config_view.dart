/// Mirrors the redacted snapshot returned by `GET /api/config`.
class ConfigView {
  final Map<String, dynamic> raw;
  const ConfigView(this.raw);

  factory ConfigView.fromJson(Map<String, dynamic> j) => ConfigView(j);

  Map<String, dynamic> section(String name) =>
      (raw[name] as Map?)?.cast<String, dynamic>() ?? const {};
}
