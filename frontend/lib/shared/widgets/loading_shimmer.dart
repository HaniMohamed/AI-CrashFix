import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

class LoadingShimmer extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? radius;
  const LoadingShimmer({super.key, this.height = 14, this.width, this.radius});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Shimmer.fromColors(
      baseColor: palette.surface2,
      highlightColor: palette.surface1,
      period: const Duration(milliseconds: 1300),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: radius ?? AppRadii.all(AppRadii.sm),
        ),
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  final double height;
  const ShimmerCard({super.key, this.height = 140});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Shimmer.fromColors(
      baseColor: palette.surface2,
      highlightColor: palette.surface1,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
      ),
    );
  }
}
