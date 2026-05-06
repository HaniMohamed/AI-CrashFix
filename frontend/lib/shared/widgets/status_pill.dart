import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';

class StatusPill extends StatelessWidget {
  final String status;
  final bool dense;
  const StatusPill({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.forStatus(status);
    final label = _label(status);
    final scheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        border: Border.all(color: c.withValues(alpha: 0.45)),
        borderRadius: AppRadii.all(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: scheme.labelSmall?.copyWith(
              color: c,
              letterSpacing: 0.4,
              fontSize: dense ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }

  static String _label(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'COMPLETED';
      case 'in_progress':
        return 'RUNNING';
      case 'skipped':
        return 'SKIPPED';
      case 'failed':
        return 'FAILED';
      default:
        return 'RUNNING';
    }
  }
}
