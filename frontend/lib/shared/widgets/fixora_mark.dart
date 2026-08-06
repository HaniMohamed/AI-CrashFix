import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';

/// Transparent Fixora product mark (PNG with alpha).
const String kFixoraMarkAsset = 'assets/brand/fixora_mark.png';

/// Product mark used in the sidebar and other brand chrome.
///
/// Always draws a soft brand glow so the mark reads clearly on dark aurora
/// surfaces. [elevated] adds a slightly stronger halo + depth shadow.
class FixoraMark extends StatelessWidget {
  final double size;
  final double radius;
  final bool elevated;

  const FixoraMark({
    super.key,
    this.size = 36,
    this.radius = 12,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>();
    final glow = palette?.glow ?? AppColors.glow;
    final primary = palette?.primary ?? AppColors.teal;

    final mark = Image.asset(
      kFixoraMarkAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.shield_moon_outlined, size: size * 0.55),
      ),
    );

    final innerAlpha = elevated ? 0.32 : 0.22;
    final outerAlpha = elevated ? 0.14 : 0.10;
    final innerBlur = size * (elevated ? 0.42 : 0.34);
    final outerBlur = size * (elevated ? 0.72 : 0.58);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft circular halo behind the mark (not a hard card shadow).
          IgnorePointer(
            child: Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: innerAlpha),
                    blurRadius: innerBlur,
                    spreadRadius: size * 0.02,
                  ),
                  BoxShadow(
                    color: glow.withValues(alpha: outerAlpha),
                    blurRadius: outerBlur,
                    spreadRadius: size * 0.01,
                  ),
                  if (elevated)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: size * 0.28,
                      offset: Offset(0, size * 0.08),
                    ),
                ],
              ),
            ),
          ),
          mark,
        ],
      ),
    );
  }
}
