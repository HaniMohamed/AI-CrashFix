import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../widgets/glass_card.dart';

/// Highlights a one-time secret (temp password) with copy affordance.
class OneTimeSecretCard extends StatefulWidget {
  final String secret;
  final String title;
  final String? message;
  final bool obscureByDefault;

  const OneTimeSecretCard({
    super.key,
    required this.secret,
    this.title = 'Temporary password',
    this.message,
    this.obscureByDefault = false,
  });

  @override
  State<OneTimeSecretCard> createState() => _OneTimeSecretCardState();
}

class _OneTimeSecretCardState extends State<OneTimeSecretCard> {
  bool _obscure = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.secret));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: const Text('Temporary password copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureByDefault;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final display = _obscure ? '•' * widget.secret.length : widget.secret;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.key_outlined, size: 18, color: palette.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.titleSmall?.copyWith(color: palette.warning),
                ),
              ),
            ],
          ),
          if (widget.message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.message!,
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: palette.surface1.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    display,
                    style: AppTypography.mono(
                      color: palette.primary,
                      size: 15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _obscure ? 'Show' : 'Hide',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 20,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _copy,
            icon: Icon(
              _copied ? Icons.check_rounded : Icons.content_copy_rounded,
              size: 18,
            ),
            label: Text(_copied ? 'Copied' : 'Copy password'),
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary.withValues(alpha: 0.15),
              foregroundColor: palette.primary,
            ),
          ),
        ],
      ),
    );
  }
}
