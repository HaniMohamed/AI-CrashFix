import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/theme/app_theme.dart';

enum AuroraIntensity { immersive, ambient }

/// Animated neural aurora mesh background.
class AuroraBackground extends ConsumerStatefulWidget {
  final AuroraIntensity intensity;
  final Widget? child;
  final bool enabled;

  const AuroraBackground({
    super.key,
    this.intensity = AuroraIntensity.ambient,
    this.child,
    this.enabled = true,
  });

  @override
  ConsumerState<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends ConsumerState<AuroraBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      if (_paused) return;
      setState(() => _elapsed = elapsed);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  bool _settingsReduce = false;

  void _syncTicker({bool? reduce}) {
    if (!mounted) return;
    final r = reduce ??
        (_settingsReduce ||
            MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.maybeOf(context)?.accessibleNavigation == true);
    final shouldRun = widget.enabled && !_paused && !r;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = _elapsed.inMilliseconds / 1000.0;
    final opacity = widget.intensity == AuroraIntensity.immersive ? 1.0 : 0.42;
    _settingsReduce =
        ref.watch(appSettingsProvider).valueOrNull?.reduceMotion == true;
    final reduce = _settingsReduce ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true;
    _syncTicker(reduce: reduce);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: palette.bg),
        Opacity(
          opacity: opacity,
          child: CustomPaint(
            painter: _AuroraPainter(
              t: t,
              primary: palette.primary,
              secondary: palette.secondary,
              glow: palette.glow,
              intensity: widget.intensity,
              animate: widget.enabled && !reduce,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final Color primary;
  final Color secondary;
  final Color glow;
  final AuroraIntensity intensity;
  final bool animate;

  _AuroraPainter({
    required this.t,
    required this.primary,
    required this.secondary,
    required this.glow,
    required this.intensity,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final time = animate ? t : 0.0;
    final blobs = <_BlobSpec>[
      _BlobSpec(
        center: Offset(
          size.width * (0.18 + 0.06 * math.sin(time * 0.21)),
          size.height * (0.22 + 0.05 * math.cos(time * 0.17)),
        ),
        radius: size.shortestSide * (intensity == AuroraIntensity.immersive ? 0.42 : 0.34),
        color: primary.withValues(alpha: 0.22),
      ),
      _BlobSpec(
        center: Offset(
          size.width * (0.78 + 0.05 * math.cos(time * 0.15)),
          size.height * (0.28 + 0.07 * math.sin(time * 0.19)),
        ),
        radius: size.shortestSide * 0.36,
        color: glow.withValues(alpha: 0.16),
      ),
      _BlobSpec(
        center: Offset(
          size.width * (0.55 + 0.07 * math.sin(time * 0.13)),
          size.height * (0.78 + 0.04 * math.cos(time * 0.23)),
        ),
        radius: size.shortestSide * 0.40,
        color: secondary.withValues(alpha: 0.12),
      ),
    ];

    for (final blob in blobs) {
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          blob.center,
          blob.radius,
          [
            blob.color,
            blob.color.withValues(alpha: 0),
          ],
        );
      canvas.drawCircle(blob.center, blob.radius, paint);
    }

    // Neural nodes + faint connections
    final nodeCount = intensity == AuroraIntensity.immersive ? 14 : 9;
    final nodes = <Offset>[];
    for (var i = 0; i < nodeCount; i++) {
      final seed = i * 1.7;
      final x = size.width * (0.08 + 0.84 * _hash(seed));
      final y = size.height * (0.1 + 0.8 * _hash(seed + 3.1));
      final driftX = 8 * math.sin(time * 0.35 + seed);
      final driftY = 6 * math.cos(time * 0.28 + seed * 1.3);
      nodes.add(Offset(x + driftX, y + driftY));
    }

    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = primary.withValues(alpha: intensity == AuroraIntensity.immersive ? 0.14 : 0.08);

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final d = (nodes[i] - nodes[j]).distance;
        if (d < size.shortestSide * 0.28) {
          canvas.drawLine(nodes[i], nodes[j], linkPaint);
        }
      }
    }

    final nodePaint = Paint()..color = glow.withValues(alpha: 0.55);
    final corePaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final n in nodes) {
      canvas.drawCircle(n, 2.2, nodePaint);
      canvas.drawCircle(n, 1.0, corePaint);
    }
  }

  double _hash(double n) {
    final x = math.sin(n * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.glow != glow ||
        oldDelegate.intensity != intensity ||
        oldDelegate.animate != animate;
  }
}

class _BlobSpec {
  final Offset center;
  final double radius;
  final Color color;
  const _BlobSpec({required this.center, required this.radius, required this.color});
}
