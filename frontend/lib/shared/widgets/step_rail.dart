import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

class StepRailItem {
  final String label;
  final String? shortLabel;
  const StepRailItem({required this.label, this.shortLabel});
}

/// Horizontal / vertical step indicator for onboarding.
class StepRail extends StatelessWidget {
  final List<StepRailItem> steps;
  final int currentIndex;
  final bool vertical;

  const StepRail({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    Widget buildMarker(int i) {
      final done = i < currentIndex;
      final active = i == currentIndex;
      final color = done || active ? palette.primary : palette.textMuted;
      final bg = done
          ? palette.primary
          : active
              ? palette.primary.withValues(alpha: 0.18)
              : palette.surface2;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? palette.primary
                    : (done ? palette.primary : palette.border),
                width: active ? 1.5 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: done
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: Theme.of(context).colorScheme.onPrimary,
                  )
                : Text(
                    '${i + 1}',
                    style: theme.labelSmall?.copyWith(
                      color: active ? palette.primary : palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            steps[i].shortLabel ?? steps[i].label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.labelMedium?.copyWith(
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      );
    }

    Widget buildConnector(int afterIndex) {
      final filled = afterIndex < currentIndex;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 2,
            decoration: BoxDecoration(
              color: filled
                  ? palette.primary.withValues(alpha: 0.55)
                  : palette.border,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      );
    }

    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            buildMarker(i),
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 13, top: 4, bottom: 4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 2,
                  height: 18,
                  decoration: BoxDecoration(
                    color: i < currentIndex
                        ? palette.primary.withValues(alpha: 0.5)
                        : palette.border,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          buildMarker(i),
          if (i < steps.length - 1) buildConnector(i),
        ],
      ],
    );
  }
}
