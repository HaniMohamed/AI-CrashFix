import 'crash.dart';

class AnalyticsTotals {
  final int all;
  final int completed;
  final int inProgress;
  final int skipped;
  final int failed;
  final int withJira;
  final int withPr;
  final int pipelineComplete;

  const AnalyticsTotals({
    required this.all,
    required this.completed,
    required this.inProgress,
    required this.skipped,
    required this.failed,
    required this.withJira,
    required this.withPr,
    required this.pipelineComplete,
  });

  factory AnalyticsTotals.fromJson(Map<String, dynamic> j) => AnalyticsTotals(
        all: (j['all'] ?? 0) as int,
        completed: (j['completed'] ?? 0) as int,
        inProgress: (j['in_progress'] ?? 0) as int,
        skipped: (j['skipped'] ?? 0) as int,
        failed: (j['failed'] ?? 0) as int,
        withJira: (j['with_jira'] ?? 0) as int,
        withPr: (j['with_pr'] ?? 0) as int,
        pipelineComplete: (j['pipeline_complete'] ?? 0) as int,
      );
}

class TimeseriesPoint {
  final String date;
  final int created;
  final int completed;
  final int failed;

  const TimeseriesPoint({
    required this.date,
    required this.created,
    required this.completed,
    required this.failed,
  });

  factory TimeseriesPoint.fromJson(Map<String, dynamic> j) => TimeseriesPoint(
        date: (j['date'] ?? '').toString(),
        created: (j['created'] ?? 0) as int,
        completed: (j['completed'] ?? 0) as int,
        failed: (j['failed'] ?? 0) as int,
      );
}

class TopKey {
  final String key;
  final int count;
  const TopKey({required this.key, required this.count});

  factory TopKey.fromJson(Map<String, dynamic> j) => TopKey(
        key: (j['key'] ?? '').toString(),
        count: (j['count'] ?? 0) as int,
      );
}

class Analytics {
  final AnalyticsTotals totals;
  final Map<String, int> pipelineFunnel;
  final Map<String, double> stepSuccessRate;
  final double completionRate;
  final double avgPipelineDurationSeconds;
  final List<TimeseriesPoint> timeseriesDaily;
  final List<TopKey> topPlatforms;
  final List<TopKey> topAppVersions;
  final List<TopKey> topDevices;
  final List<Crash> recent;
  final String? generatedAt;

  const Analytics({
    required this.totals,
    required this.pipelineFunnel,
    required this.stepSuccessRate,
    required this.completionRate,
    required this.avgPipelineDurationSeconds,
    required this.timeseriesDaily,
    required this.topPlatforms,
    required this.topAppVersions,
    required this.topDevices,
    required this.recent,
    this.generatedAt,
  });

  factory Analytics.fromJson(Map<String, dynamic> j) {
    Map<String, int> intMap(dynamic raw) {
      if (raw is! Map) return const {};
      return {for (final e in raw.entries) e.key.toString(): (e.value ?? 0) as int};
    }

    Map<String, double> doubleMap(dynamic raw) {
      if (raw is! Map) return const {};
      return {
        for (final e in raw.entries)
          e.key.toString(): (e.value as num?)?.toDouble() ?? 0.0,
      };
    }

    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
        (raw is List)
            ? raw.whereType<Map<String, dynamic>>().map(f).toList()
            : <T>[];

    return Analytics(
      totals: AnalyticsTotals.fromJson(
        (j['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      pipelineFunnel: intMap(j['pipeline_funnel']),
      stepSuccessRate: doubleMap(j['step_success_rate']),
      completionRate: (j['completion_rate'] as num?)?.toDouble() ?? 0.0,
      avgPipelineDurationSeconds:
          (j['avg_pipeline_duration_seconds'] as num?)?.toDouble() ?? 0.0,
      timeseriesDaily: list(j['timeseries_daily'], TimeseriesPoint.fromJson),
      topPlatforms: list(j['top_platforms'], TopKey.fromJson),
      topAppVersions: list(j['top_app_versions'], TopKey.fromJson),
      topDevices: list(j['top_devices'], TopKey.fromJson),
      recent: list(j['recent'], Crash.fromJson),
      generatedAt: j['generated_at']?.toString(),
    );
  }
}
