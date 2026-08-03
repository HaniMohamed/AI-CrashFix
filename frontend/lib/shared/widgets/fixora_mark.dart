import 'package:flutter/material.dart';

/// Asset path for the Fixora product mark (light-background PNG).
const String kFixoraMarkAsset = 'assets/brand/fixora_mark.png';

/// Squircle product mark used in the sidebar and other brand chrome.
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
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        kFixoraMarkAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: const Color(0xFFF5F5F7),
          child: Icon(Icons.shield_moon_outlined, size: size * 0.55),
        ),
      ),
    );

    if (!elevated) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: mark,
    );
  }
}
