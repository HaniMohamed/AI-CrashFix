import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_version_provider.dart';

/// Muted version label for sidebar/footer surfaces.
class AppVersionLabel extends ConsumerWidget {
  final TextAlign align;
  const AppVersionLabel({super.key, this.align = TextAlign.center});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final async = ref.watch(appVersionProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (v) => Text(
        v.shortLabel,
        textAlign: align,
        style: theme.labelSmall?.copyWith(
          color: palette.textMuted,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
