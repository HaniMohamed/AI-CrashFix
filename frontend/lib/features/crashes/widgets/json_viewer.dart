import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/json_tree_viewer.dart';

/// JSON value with expandable maps/lists ([JsonTreeView]) and a raw JSON copy action.
class JsonViewer extends StatelessWidget {
  final Object? value;
  const JsonViewer({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    final pretty = const JsonEncoder.withIndent('  ').convert(value);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CrashState', style: theme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => Clipboard.setData(ClipboardData(text: pretty)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: palette.surface1,
              borderRadius: AppRadii.all(AppRadii.md),
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            constraints: const BoxConstraints(maxHeight: 600),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: JsonTreeView(value: value, expandToDepth: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
