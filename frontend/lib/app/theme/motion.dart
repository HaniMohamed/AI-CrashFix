import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_settings.dart';

/// Shared motion tokens and presets for Aurora Obsidian.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration aurora = Duration(seconds: 18);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutCubic;

  static bool reduceMotion(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return true;
    if (MediaQuery.maybeOf(context)?.accessibleNavigation == true) return true;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      return container.read(appSettingsProvider).valueOrNull?.reduceMotion == true;
    } catch (_) {
      return false;
    }
  }
}

extension AppMotionWidgetsX on Widget {
  Widget fadeSlideUp({
    Duration delay = Duration.zero,
    Duration duration = AppMotion.normal,
    double offset = 16,
    bool enabled = true,
  }) {
    if (!enabled) return this;
    return animate(delay: delay)
        .fadeIn(duration: duration, curve: AppMotion.easeOut)
        .slideY(begin: offset / 100, end: 0, duration: duration, curve: AppMotion.easeOut);
  }

  Widget scaleIn({
    Duration delay = Duration.zero,
    Duration duration = AppMotion.normal,
    bool enabled = true,
  }) {
    if (!enabled) return this;
    return animate(delay: delay)
        .fadeIn(duration: duration, curve: AppMotion.easeOut)
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          duration: duration,
          curve: AppMotion.easeOut,
        );
  }
}

/// Light fade/slide page transition for feature routes.
class AuroraPage<T> extends CustomTransitionPage<T> {
  AuroraPage({
    required super.child,
    super.name,
    super.arguments,
    super.key,
    super.fullscreenDialog,
  }) : super(
          transitionDuration: AppMotion.normal,
          reverseTransitionDuration: AppMotion.fast,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: AppMotion.easeOut);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.018),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
