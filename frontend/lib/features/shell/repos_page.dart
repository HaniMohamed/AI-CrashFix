import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../shared/widgets/soft_panel.dart';
import 'repo_delete_dialog.dart';
import 'repo_manage_dialog.dart';

/// Full-page repository management (Aurora Obsidian).
class ReposPage extends ConsumerWidget {
  /// Optional path to return to (e.g. `/onboarding` during setup).
  final String? returnTo;

  const ReposPage({super.key, this.returnTo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (returnTo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(returnTo!);
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to onboarding'),
              ),
            ),
          Expanded(
            child: SoftPanel(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ManageReposDialog(
                presentation: ManageReposPresentation.page,
                allowClose: returnTo != null,
                onDelete: (repoKey, repoName) async {
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => DeleteRepoDialog(
                      repoKey: repoKey,
                      repoName: repoName,
                    ),
                  );
                },
                onSaved: () {
                  if (!context.mounted) return;
                  if (returnTo != null) {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(returnTo!);
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Repository saved'),
                        backgroundColor: palette.surface2,
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
