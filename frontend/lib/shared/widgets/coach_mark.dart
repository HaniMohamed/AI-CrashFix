import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

/// First-visit tip banners dismissed into SharedPreferences.
class CoachMark extends ConsumerStatefulWidget {
  final String id;
  final String title;
  final String body;
  final Widget? action;

  const CoachMark({
    super.key,
    required this.id,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  ConsumerState<CoachMark> createState() => _CoachMarkState();
}

class _CoachMarkState extends ConsumerState<CoachMark> {
  bool? _visible;

  String get _key => 'coach.dismissed.${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _visible = !(p.getBool(_key) ?? false));
  }

  Future<void> _dismiss() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_visible != true) return const SizedBox.shrink();
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: palette.secondary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(widget.title, style: theme.titleMedium)),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: _dismiss,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Text(
            widget.body,
            style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (widget.action != null) ...[
            const SizedBox(height: AppSpacing.md),
            widget.action!,
          ],
        ],
      ),
    );
  }
}
