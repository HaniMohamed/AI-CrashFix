import 'dart:async';

import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/providers/run_session_provider.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/glass_card.dart';

class LiveSummaryStrip extends StatefulWidget {
  final RunSession session;
  const LiveSummaryStrip({super.key, required this.session});

  @override
  State<LiveSummaryStrip> createState() => _LiveSummaryStripState();
}

class _LiveSummaryStripState extends State<LiveSummaryStrip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final processed = s.summary?.processed ?? _countCompletedCrashes();
    final skipped = s.summary?.skipped ?? 0;
    final failed = s.summary?.failed ?? _countFailedCrashes();
    final fetched = s.summary?.fetched ?? s.crashOrder.length;

    final elapsed = (s.endedAt ?? DateTime.now())
        .difference(s.startedAt ?? DateTime.now())
        .inSeconds;

    final palette = context.palette;
    final cards = <_SummaryCardData>[
      _SummaryCardData('Fetched', fetched, palette.primary),
      _SummaryCardData('Processed', processed, palette.success),
      _SummaryCardData('Skipped', skipped, palette.textMuted),
      _SummaryCardData('Failed', failed, palette.danger),
    ];

    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: _SummaryCard(d: cards[i])),
            if (i != cards.length - 1)
              Container(
                width: 1,
                height: 56,
                color: palette.border,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
          ],
          Container(
            width: 1,
            height: 56,
            color: palette.border,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Elapsed',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  Fmt.duration(elapsed.toDouble()),
                  style: AppTypography.counter(color: palette.text, size: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _countCompletedCrashes() => widget.session.perCrash.values
      .where((c) => c.completed && c.failure == null)
      .length;

  int _countFailedCrashes() => widget.session.perCrash.values
      .where((c) => c.failure != null)
      .length;
}

class _SummaryCardData {
  final String label;
  final int value;
  final Color color;
  _SummaryCardData(this.label, this.value, this.color);
}

class _SummaryCard extends StatelessWidget {
  final _SummaryCardData d;
  const _SummaryCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: d.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              d.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: palette.textMuted,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedFlipCounter(
          value: d.value,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          textStyle: AppTypography.counter(color: palette.text, size: 32),
        ),
      ],
    );
  }
}
