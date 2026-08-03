import 'package:flutter/material.dart';

/// Transparent Fixora product mark (PNG with alpha).
const String kFixoraMarkAsset = 'assets/brand/fixora_mark.png';

/// Product mark used in the sidebar and other brand chrome.
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

    if (!elevated) {
      return SizedBox(width: size, height: size, child: mark);
    }

    // Soft rounded glow only — avoid clipping onto an opaque squircle fill.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: mark,
    );
  }
}
