import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../core/models/analytics.dart';
import '../../../shared/widgets/glass_card.dart';

class TopKeysCard extends StatefulWidget {
  final List<TopKey> platforms;
  final List<TopKey> versions;
  final List<TopKey> devices;
  const TopKeysCard({
    super.key,
    required this.platforms,
    required this.versions,
    required this.devices,
  });

  @override
  State<TopKeysCard> createState() => _TopKeysCardState();
}

class _TopKeysCardState extends State<TopKeysCard> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.palette;
    final tabs = const ['Platforms', 'Versions', 'Devices'];
    final list = [widget.platforms, widget.versions, widget.devices][_idx];
    final maxV = list.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top breakdown', style: theme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.surface1,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _idx = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _idx == i ? palette.surface2 : Colors.transparent,
                          borderRadius: AppRadii.all(AppRadii.pill),
                          border: Border.all(
                            color: _idx == i ? palette.border : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            tabs[i],
                            style: theme.labelMedium?.copyWith(
                              color: _idx == i ? palette.text : palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'No data yet',
                      style: theme.bodyMedium?.copyWith(color: palette.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final item = list[i];
                      final ratio = maxV == 0 ? 0.0 : item.count / maxV;
                      return Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              item.key,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: AppRadii.all(AppRadii.pill),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 8,
                                backgroundColor: palette.surface1,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color.lerp(palette.primary, palette.secondary, i / 6) ??
                                      palette.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(item.count.toString(), style: theme.titleMedium),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
