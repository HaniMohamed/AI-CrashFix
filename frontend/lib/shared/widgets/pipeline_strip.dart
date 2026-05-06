import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/crash.dart';

/// 7 mini steps showing the pipeline progression for a crash. Filled when done,
/// outlined while pending. Hover/tooltip for label.
class PipelineStrip extends StatelessWidget {
  final Crash crash;
  final double size;
  const PipelineStrip({super.key, required this.crash, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final failed = crash.status.toLowerCase() == 'failed';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final step in crash.pipelineSteps) ...[
          Tooltip(
            message: '${step.label} - ${step.done ? "done" : "pending"}',
            child: Container(
              width: size + 2,
              height: size + 2,
              decoration: BoxDecoration(
                color: step.done ? palette.primary : Colors.transparent,
                border: Border.all(
                  color: step.done
                      ? palette.primary
                      : (failed ? palette.danger : palette.border),
                  width: 1.4,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }
}
