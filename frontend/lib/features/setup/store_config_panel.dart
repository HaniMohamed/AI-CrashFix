import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../shared/widgets/glass_card.dart';

/// Shared database / store backend form (first-run page + setup wizard).
class StoreConfigPanel extends StatelessWidget {
  final String storeBackend;
  final ValueChanged<String> onBackendChanged;
  final TextEditingController dbUrlCtrl;
  final TextEditingController dbUserCtrl;
  final TextEditingController dbPasswordCtrl;
  final TextEditingController machineUserIdCtrl;
  final bool showDbPassword;
  final VoidCallback onToggleDbPassword;
  final String? dbUrlMasked;
  final bool busy;

  const StoreConfigPanel({
    super.key,
    required this.storeBackend,
    required this.onBackendChanged,
    required this.dbUrlCtrl,
    required this.dbUserCtrl,
    required this.dbPasswordCtrl,
    required this.machineUserIdCtrl,
    required this.showDbPassword,
    required this.onToggleDbPassword,
    this.dbUrlMasked,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose where Fixora stores crashes, repos, settings, and accounts on this machine.',
          style: theme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Local SQLite is best for a single workstation. Remote Postgres is for shared team data.',
          style: theme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'sqlite',
              label: Text('Local SQLite'),
              icon: Icon(Icons.storage_outlined),
            ),
            ButtonSegment(
              value: 'postgres',
              label: Text('Remote Postgres'),
              icon: Icon(Icons.cloud_outlined),
            ),
          ],
          selected: {storeBackend},
          onSelectionChanged:
              busy ? null : (s) => onBackendChanged(s.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (storeBackend == 'sqlite') ...[
          GlassCard(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: palette.success),
              title: const Text('Local file database'),
              subtitle: const Text(
                'Data stays on this Mac under Application Support / AI_CRASH_FIX_DATA_DIR. '
                'No remote URL required.',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: machineUserIdCtrl,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Machine user ID (optional)',
              hintText: 'e.g. jane.doe',
              helperText: 'Useful if you later switch to shared Postgres.',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ] else ...[
          TextField(
            controller: dbUrlCtrl,
            enabled: !busy,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Postgres URL',
              hintText: 'postgresql://host:5432/fixora',
              helperText: dbUrlMasked == null || dbUrlMasked!.isEmpty
                  ? 'Include host and database. Username/password can go here or below.'
                  : 'Saved: $dbUrlMasked — enter a new URL to replace.',
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: dbUserCtrl,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'DB username (optional)',
              hintText: 'Merged into the URL when set',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: dbPasswordCtrl,
            enabled: !busy,
            obscureText: !showDbPassword,
            decoration: InputDecoration(
              labelText: 'DB password (optional)',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: showDbPassword ? 'Hide' : 'Show',
                onPressed: busy ? null : onToggleDbPassword,
                icon: Icon(
                  showDbPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: machineUserIdCtrl,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Machine user ID',
              hintText: 'Scopes shared Postgres rows for this workstation',
              helperText: 'Required for remote Postgres — e.g. your team username.',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ],
      ],
    );
  }
}
