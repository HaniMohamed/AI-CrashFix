import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../shared/widgets/diff_viewer.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/loading_shimmer.dart';

class CrashChangesPage extends ConsumerWidget {
  final String crashId;
  const CrashChangesPage({super.key, required this.crashId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final async = ref.watch(crashDiffProvider(crashId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => context.go('/crashes/$crashId'),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to crash'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text('Changes', style: theme.displaySmall),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(crashDiffProvider(crashId)),
                icon: Icon(Icons.refresh_rounded, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            crashId,
            style: theme.bodySmall?.copyWith(
              color: palette.textMuted,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          async.when(
            loading: () => const ShimmerCard(height: 220),
            error: (e, _) => ErrorBanner(
              message: 'Failed to load diff for $crashId: $e',
              onRetry: () => ref.invalidate(crashDiffProvider(crashId)),
            ),
            data: (diff) => DiffViewer(diff: diff),
          ),
        ],
      ),
    );
  }
}
