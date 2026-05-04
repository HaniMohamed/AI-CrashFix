import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../core/models/analytics.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/glass_card.dart';

class TimeseriesChart extends StatelessWidget {
  final List<TimeseriesPoint> points;
  const TimeseriesChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final maxV = _maxValue();

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Last 30 days', style: theme.headlineSmall),
              const Spacer(),
              _LegendDot(color: palette.primary, label: 'Created'),
              const SizedBox(width: 12),
              _LegendDot(color: palette.success, label: 'Completed'),
              const SizedBox(width: 12),
              _LegendDot(color: palette.danger, label: 'Failed'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxV == 0 ? 1 : null,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: palette.border.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: maxV == 0 ? 1 : (maxV / 4).ceilToDouble(),
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: theme.labelSmall?.copyWith(color: palette.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (points.length / 6).ceilToDouble().clamp(1, 10),
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            Fmt.shortDate(points[i].date),
                            style: theme.labelSmall?.copyWith(color: palette.textMuted),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => palette.surface2,
                    getTooltipItems: (spots) => spots.map((s) {
                      final point = points[s.x.toInt()];
                      final color = s.bar.color ?? palette.primary;
                      return LineTooltipItem(
                        '${point.date}\n${s.y.toInt()}',
                        TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  _buildLine(_pointsFor(_Series.created), palette.primary),
                  _buildLine(_pointsFor(_Series.completed), palette.success),
                  _buildLine(_pointsFor(_Series.failed), palette.danger),
                ],
                minY: 0,
                maxY: maxV == 0 ? 1 : maxV.toDouble() * 1.2,
              ),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  int _maxValue() {
    var m = 0;
    for (final p in points) {
      if (p.created > m) m = p.created;
      if (p.completed > m) m = p.completed;
      if (p.failed > m) m = p.failed;
    }
    return m;
  }

  List<FlSpot> _pointsFor(_Series s) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = switch (s) {
        _Series.created => points[i].created,
        _Series.completed => points[i].completed,
        _Series.failed => points[i].failed,
      };
      spots.add(FlSpot(i.toDouble(), v.toDouble()));
    }
    return spots;
  }

  LineChartBarData _buildLine(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.32,
      barWidth: 2.4,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

enum _Series { created, completed, failed }

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.textSecondary)),
      ],
    );
  }
}
