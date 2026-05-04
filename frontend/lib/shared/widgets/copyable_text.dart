import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/typography.dart';

class CopyableText extends StatelessWidget {
  final String text;
  final String? display;
  final double size;
  const CopyableText({
    super.key,
    required this.text,
    this.display,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Copied: $text'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Tooltip(
          message: 'Copy',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                display ?? text,
                style: AppTypography.mono(color: palette.text, size: size),
              ),
              const SizedBox(width: 4),
              Icon(Icons.copy, size: size, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
