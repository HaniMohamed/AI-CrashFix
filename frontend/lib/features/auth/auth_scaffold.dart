import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../../app/theme/spacing.dart';
import '../../shared/widgets/aurora_background.dart';
import '../../shared/widgets/page_hero.dart';
import '../../shared/widgets/soft_panel.dart';

/// Shared cinematic layout for auth / bootstrap pages.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget form;
  final double maxWidth;
  final bool showBrand;

  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.form,
    this.maxWidth = 440,
    this.showBrand = true,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduceMotion(context);
    return Scaffold(
      body: AuroraBackground(
        intensity: AuroraIntensity.immersive,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth + 80),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    final hero = PageHero(
                      title: title,
                      subtitle: subtitle,
                      showBrand: showBrand,
                      compact: !wide,
                    ).fadeSlideUp(enabled: !reduce);

                    final panel = SoftPanel(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: form,
                    ).fadeSlideUp(delay: const Duration(milliseconds: 80), enabled: !reduce);

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: hero),
                          const SizedBox(width: AppSpacing.xxl),
                          SizedBox(width: maxWidth, child: panel),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        hero,
                        const SizedBox(height: AppSpacing.xxl),
                        panel,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
