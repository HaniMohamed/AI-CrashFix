import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/models/analytics.dart';
import '../../core/providers/analytics_provider.dart';
import '../../shared/widgets/error_banner.dart';
import 'widgets/hero_header.dart';
import 'widgets/kpi_strip.dart';
import 'widgets/pipeline_funnel.dart';
import 'widgets/recent_activity.dart';
import 'widgets/status_donut.dart';
import 'widgets/timeseries_chart.dart';
import 'widgets/top_keys_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsProvider);
    final palette = context.palette;

    return RefreshIndicator(
      color: palette.primary,
      backgroundColor: palette.surface2,
      onRefresh: () => ref.read(analyticsProvider.notifier).refresh(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HeroHeader(),
            const SizedBox(height: AppSpacing.xl),
            async.when(
              loading: () => const KpiStrip(loading: true),
              error: (e, _) => ErrorBanner(
                message: 'Failed to load analytics: $e',
                onRetry: () => ref.read(analyticsProvider.notifier).refresh(),
              ),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KpiStrip(analytics: data),
                  const SizedBox(height: AppSpacing.xl),
                  PipelineFunnel(analytics: data),
                  const SizedBox(height: AppSpacing.xl),
                  _ChartsRow(analytics: data),
                  const SizedBox(height: AppSpacing.xl),
                  RecentActivity(items: data.recent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartsRow extends StatelessWidget {
  final Analytics analytics;
  const _ChartsRow({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final stacked = w < 1100;

    final cards = <Widget>[
      Expanded(flex: 3, child: TimeseriesChart(points: analytics.timeseriesDaily)),
      const SizedBox(width: AppSpacing.lg, height: AppSpacing.lg),
      Expanded(flex: 2, child: StatusDonut(totals: analytics.totals)),
      const SizedBox(width: AppSpacing.lg, height: AppSpacing.lg),
      Expanded(
        flex: 2,
        child: TopKeysCard(
          platforms: analytics.topPlatforms,
          versions: analytics.topAppVersions,
          devices: analytics.topDevices,
        ),
      ),
    ];

    if (!stacked) {
      return SizedBox(height: 320, child: Row(children: cards));
    }
    return Column(
      children: [
        SizedBox(
          height: 280,
          child: TimeseriesChart(points: analytics.timeseriesDaily),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(height: 280, child: StatusDonut(totals: analytics.totals)),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 320,
          child: TopKeysCard(
            platforms: analytics.topPlatforms,
            versions: analytics.topAppVersions,
            devices: analytics.topDevices,
          ),
        ),
      ],
    );
  }
}
