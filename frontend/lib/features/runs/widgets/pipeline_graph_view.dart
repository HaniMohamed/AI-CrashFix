import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/run_event.dart';
import '../../../shared/widgets/json_tree_viewer.dart';

enum _EdgeKind { normal, conditional }

// Shared layout constants (used for both sizing + painting).
const double _pad = 18;
const double _nodeW = 190;
const double _nodeH = 52;
const double _colGap = 140;
const double _rowGap = 34;

class _GraphNode {
  final String id;
  final String label;
  final bool isRouter;
  const _GraphNode({required this.id, required this.label, required this.isRouter});
}

class _GraphEdge {
  final String from;
  final String to;
  final _EdgeKind kind;
  final String? label;
  final String? routerId;
  const _GraphEdge({
    required this.from,
    required this.to,
    required this.kind,
    this.label,
    this.routerId,
  });
}

class _GraphModel {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final String? currentNodeId;
  final _GraphEdge? activeEdge;
  final bool hasInFlight;
  final Set<String> started;
  final Set<String> completed;
  final Set<String> errored;
  const _GraphModel({
    required this.nodes,
    required this.edges,
    required this.currentNodeId,
    required this.activeEdge,
    required this.hasInFlight,
    required this.started,
    required this.completed,
    required this.errored,
  });
}

/// Visual graph view of the streaming LangGraph pipeline.
///
/// This is intentionally "best effort": it renders the graph implied by the
/// streamed events. Routers become dashed conditional edges.
class PipelineGraphView extends StatefulWidget {
  final List<RunEvent> events;
  final bool completed;
  final bool failed;

  const PipelineGraphView({
    super.key,
    required this.events,
    required this.completed,
    required this.failed,
  });

  @override
  State<PipelineGraphView> createState() => _PipelineGraphViewState();
}

class _PipelineGraphViewState extends State<PipelineGraphView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flowCtrl;
  final TransformationController _xform = TransformationController();
  Size? _lastViewport;
  bool _didInitTransform = false;
  double _minScale = 0.5;
  Matrix4? _fitMatrix;
  bool _clamping = false;

  @override
  void initState() {
    super.initState();
    _flowCtrl = AnimationController(
      vsync: this,
      duration: 1400.ms,
    )..repeat();
    _xform.addListener(_clampToFitMinScale);
  }

  @override
  void didUpdateWidget(covariant PipelineGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final animate = !(widget.completed || widget.failed);
    if (animate) {
      if (!_flowCtrl.isAnimating) _flowCtrl.repeat();
    } else {
      if (_flowCtrl.isAnimating) _flowCtrl.stop();
    }
  }

  @override
  void dispose() {
    _flowCtrl.dispose();
    _xform.removeListener(_clampToFitMinScale);
    _xform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final model = _buildModel(widget.events);
    final animateFlow = !(widget.completed || widget.failed) && model.hasInFlight;

    if (model.nodes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surface2,
          border: Border.all(color: palette.border),
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        child: Text(
          'Waiting for first node…',
          style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
      );
    }

    final statusColor = widget.failed
        ? palette.danger
        : (widget.completed ? palette.success : palette.primary);

    final latestSnapshot = _latestStateSnapshot(widget.events);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface2,
        border: Border.all(color: palette.border),
        borderRadius: AppRadii.all(AppRadii.md),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.md),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final layout = _fixedLayoutForIds(model.nodes.map((e) => e.id).toSet());
                  final fallback = [
                    model.nodes.map((e) => e.id).toList()..sort(),
                  ];
                  final bands = layout?.bands ?? [fallback];

                  double bandWidth(List<List<String>> cols) {
                    final maxLevel = cols.length - 1;
                    return _pad * 2 +
                        cols.length * _nodeW +
                        math.max(0, maxLevel) * _colGap;
                  }

                  double bandHeight(List<List<String>> cols) {
                    final maxRows = cols.fold<int>(0, (m, b) => math.max(m, b.length));
                    return _pad * 2 +
                        maxRows * _nodeH +
                        math.max(0, maxRows - 1) * _rowGap;
                  }

                  final widths = bands.map((b) => bandWidth(b)).toList();
                  final heights = bands.map((b) => bandHeight(b)).toList();
                  final neededW = widths.fold<double>(0, (m, v) => math.max(m, v));
                  const bandGap = 120.0;
                  final neededH =
                      heights.fold<double>(0, (s, v) => s + v) +
                          bandGap * math.max(0, bands.length - 1) +
                          56; // room for the status pill overlay

                  // Canvas is the full graph; viewport is the card.
                  final canvasW = neededW;
                  final canvasH = neededH;

                  // Auto-fit the full graph into the current viewport once.
                  final viewport = Size(c.maxWidth, c.maxHeight);
                  if (!_didInitTransform || _lastViewport != viewport) {
                    _lastViewport = viewport;
                    final sx = viewport.width / canvasW;
                    final sy = viewport.height / canvasH;
                    final s = math.min(1.0, math.max(0.35, math.min(sx, sy)));
                    _minScale = s;
                    final dx = (viewport.width - canvasW * s) / 2;
                    final dy = (viewport.height - canvasH * s) / 2;
                    _fitMatrix = Matrix4.identity()
                      ..translateByDouble(dx, dy, 0, 1)
                      ..scaleByDouble(s, s, 1, 1);
                    _xform.value = _fitMatrix!.clone();
                    _didInitTransform = true;
                  }

                  return InteractiveViewer(
                    transformationController: _xform,
                    minScale: _minScale,
                    maxScale: 3.2,
                    boundaryMargin: const EdgeInsets.all(480),
                    constrained: true,
                    panEnabled: false,
                    scaleEnabled: false,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _flowCtrl,
                          builder: (ctx, _) => SizedBox(
                            width: canvasW,
                            height: canvasH,
                            child: CustomPaint(
                              painter: _PipelineGraphPainter(
                                palette: palette,
                                theme: theme,
                                model: model,
                                t: _flowCtrl.value,
                                statusColor: statusColor,
                                animateFlow: animateFlow,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              top: AppSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.surface2.withValues(alpha: 0.9),
                  border: Border.all(color: palette.border),
                  borderRadius: AppRadii.all(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.55),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.failed
                          ? 'pipeline failed'
                          : (widget.completed ? 'pipeline completed' : 'pipeline running'),
                      style: theme.labelMedium?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (latestSnapshot != null && latestSnapshot.isNotEmpty)
              Positioned(
                right: AppSpacing.md,
                top: AppSpacing.md,
                child: Tooltip(
                  message: 'Inspect latest state snapshot',
                  child: IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showState(context, latestSnapshot),
                    icon: Icon(Icons.layers_outlined, color: palette.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _latestStateSnapshot(List<RunEvent> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      final ev = events[i];
      if (ev is StateSnapshotEvent && ev.state.isNotEmpty) {
        return ev.state;
      }
    }
    return null;
  }

  void _clampToFitMinScale() {
    if (_clamping) return;
    final fit = _fitMatrix;
    if (fit == null) return;
    final currentScale = _xform.value.getMaxScaleOnAxis();
    if (currentScale + 1e-6 < _minScale) {
      _clamping = true;
      _xform.value = fit.clone();
      _clamping = false;
    }
  }

  void _showState(BuildContext context, Map<String, dynamic> state) {
    final palette = context.palette;
    final pretty = const JsonEncoder.withIndent('  ').convert(state);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: palette.surface2,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.lg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 650),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'CrashState snapshot',
                      style: Theme.of(ctx).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy JSON',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: pretty)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: JsonTreeView(value: state, expandToDepth: 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _normNodeId(String raw) {
    // Backend uses indented names for subgraph logs (e.g. "-------generate_fix").
    final t = raw.trim();
    return t.replaceFirst(RegExp(r'^-+\s*'), '');
  }

  static String _normRouterId(String raw) => _normNodeId(raw);

  static const List<_GraphNode> _specNodes = [
    // Main graph
    _GraphNode(id: 'map_stacktrace', label: 'Map stacktrace', isRouter: false),
    _GraphNode(id: 'route_after_map_stacktrace', label: 'Route', isRouter: true),
    _GraphNode(id: 'repo_context', label: 'Repo context', isRouter: false),
    _GraphNode(id: 'git_regression', label: 'Git regression', isRouter: false),
    _GraphNode(id: 'llm_analysis', label: 'LLM analysis', isRouter: false),
    _GraphNode(id: 'route_after_llm_analysis', label: 'Route', isRouter: true),
    _GraphNode(id: 'jira_create', label: 'Create Jira', isRouter: false),
    _GraphNode(id: 'mark_skipped_no_mapped_frames', label: 'Skipped (no frames)', isRouter: false),
    // Note: we intentionally do NOT render the parent "fix_generation" wrapper
    // node; the subgraph nodes below are the actual pipeline steps.

    // Fix subgraph (render as part of the full pipeline)
    _GraphNode(id: 'generate_fix', label: 'Generate fix', isRouter: false),
    _GraphNode(id: 'review_fix', label: 'Review fix', isRouter: false),
    _GraphNode(id: 'validate_fix', label: 'Validate fix', isRouter: false),
    _GraphNode(id: 'route_after_validate_fix', label: 'Route', isRouter: true),
    _GraphNode(id: 'generate_pr', label: 'Generate PR', isRouter: false),
    _GraphNode(id: 'fallback', label: 'Fallback', isRouter: false),
  ];

  static const List<_GraphEdge> _specEdges = [
    // Main flow
    _GraphEdge(from: 'map_stacktrace', to: 'route_after_map_stacktrace', kind: _EdgeKind.normal),
    _GraphEdge(
      from: 'route_after_map_stacktrace',
      to: 'repo_context',
      kind: _EdgeKind.conditional,
      label: 'mapped',
      routerId: 'route_after_map_stacktrace',
    ),
    _GraphEdge(
      from: 'route_after_map_stacktrace',
      to: 'mark_skipped_no_mapped_frames',
      kind: _EdgeKind.conditional,
      label: 'no frames',
      routerId: 'route_after_map_stacktrace',
    ),
    _GraphEdge(from: 'repo_context', to: 'git_regression', kind: _EdgeKind.normal),
    _GraphEdge(from: 'git_regression', to: 'llm_analysis', kind: _EdgeKind.normal),
    _GraphEdge(from: 'llm_analysis', to: 'route_after_llm_analysis', kind: _EdgeKind.normal),
    _GraphEdge(
      from: 'route_after_llm_analysis',
      to: 'generate_fix',
      kind: _EdgeKind.conditional,
      label: 'skip Jira',
      routerId: 'route_after_llm_analysis',
    ),
    _GraphEdge(
      from: 'route_after_llm_analysis',
      to: 'jira_create',
      kind: _EdgeKind.conditional,
      label: 'create Jira',
      routerId: 'route_after_llm_analysis',
    ),
    // Jira path enters directly into the fix subgraph.
    _GraphEdge(from: 'jira_create', to: 'generate_fix', kind: _EdgeKind.normal),
    _GraphEdge(from: 'generate_fix', to: 'review_fix', kind: _EdgeKind.normal),
    _GraphEdge(from: 'review_fix', to: 'validate_fix', kind: _EdgeKind.normal),
    _GraphEdge(from: 'validate_fix', to: 'route_after_validate_fix', kind: _EdgeKind.normal),
    _GraphEdge(
      from: 'route_after_validate_fix',
      to: 'generate_pr',
      kind: _EdgeKind.conditional,
      label: 'valid',
      routerId: 'route_after_validate_fix',
    ),
    _GraphEdge(
      from: 'route_after_validate_fix',
      to: 'generate_fix',
      kind: _EdgeKind.conditional,
      label: 'retry',
      routerId: 'route_after_validate_fix',
    ),
    _GraphEdge(
      from: 'route_after_validate_fix',
      to: 'fallback',
      kind: _EdgeKind.conditional,
      label: 'fail',
      routerId: 'route_after_validate_fix',
    ),
  ];

  _GraphModel _buildModel(List<RunEvent> events) {
    // Always start from the canonical spec so we can draw "future" nodes dimmed.
    final nodesById = {for (final n in _specNodes) n.id: n};
    final edges = List<_GraphEdge>.from(_specEdges);

    // Track runtime state.
    final startedAt = <String, int>{}; // nodeId -> start index
    final completedAt = <String, int>{}; // nodeId -> completion index
    final erroredAt = <String, int>{}; // nodeId -> error index

    String? lastRouter;
    String? lastRouteLabel;

    for (var i = 0; i < events.length; i++) {
      final ev = events[i];
      switch (ev) {
        case NodeStartedEvent(:final node):
          var id = _normNodeId(node);
          if (id == 'fix_generation') id = 'generate_fix';
          startedAt[id] = i;
        case NodeCompletedEvent(:final node):
          var id = _normNodeId(node);
          if (id == 'fix_generation') id = 'generate_fix';
          completedAt[id] = i;
        case NodeErrorEvent(:final node):
          var id = _normNodeId(node);
          if (id == 'fix_generation') id = 'generate_fix';
          erroredAt[id] = i;
        case RouterEvent(:final router, :final route):
          lastRouter = _normRouterId(router);
          // Note: `route` is either the destination node id (main routers) OR a
          // label like "valid/retry/fail" (validate_fix router). We use it to
          // activate the matching conditional edge from the spec.
          lastRouteLabel = route.trim().isEmpty ? null : route.trim();
        default:
          break;
      }
    }

    String? current;
    // Current node is the most recently started node that isn't finished.
    for (final e in startedAt.entries) {
      final id = e.key;
      final done = completedAt.containsKey(id) || erroredAt.containsKey(id);
      if (!done) {
        if (current == null || e.value > (startedAt[current] ?? -1)) {
          current = id;
        }
      }
    }
    final hasInFlight = current != null;

    // If nothing running, consider the last completed node as "current".
    if (current == null && (completedAt.isNotEmpty || erroredAt.isNotEmpty)) {
      String? best;
      int bestIdx = -1;
      for (final e in completedAt.entries) {
        if (e.value > bestIdx) {
          bestIdx = e.value;
          best = e.key;
        }
      }
      for (final e in erroredAt.entries) {
        if (e.value > bestIdx) {
          bestIdx = e.value;
          best = e.key;
        }
      }
      current = best;
    }

    _GraphEdge? activeEdge;
    // Prefer activating the selected conditional edge from the last router.
    if (hasInFlight && lastRouter != null && lastRouteLabel != null) {
      activeEdge = edges.cast<_GraphEdge?>().firstWhere(
        (e) =>
            e != null &&
            e.kind == _EdgeKind.conditional &&
            (e.routerId ?? e.from) == lastRouter &&
            // main routers: label == destination; validate router: label == "valid/retry/fail"
            ((e.label ?? '') == lastRouteLabel || e.to == _normNodeId(lastRouteLabel!)),
        orElse: () => null,
      );
    }
    if (hasInFlight && activeEdge == null && current != null) {
      // Pick an incoming edge to the current node if any, otherwise an outgoing.
      activeEdge = edges.cast<_GraphEdge?>().firstWhere(
            (e) => e != null && e.to == current,
            orElse: () => null,
          ) ??
          edges.cast<_GraphEdge?>().firstWhere(
                (e) => e != null && e.from == current,
                orElse: () => null,
              );
    }

    final nodes = nodesById.values.toList();

    return _GraphModel(
      nodes: nodes,
      edges: edges,
      currentNodeId: current,
      activeEdge: activeEdge,
      hasInFlight: hasInFlight,
      started: startedAt.keys.toSet(),
      completed: completedAt.keys.toSet(),
      errored: erroredAt.keys.toSet(),
    );
  }
}

class _PipelineGraphPainter extends CustomPainter {
  final AppPalette palette;
  final TextTheme theme;
  final _GraphModel model;
  final double t;
  final Color statusColor;
  final bool animateFlow;

  _PipelineGraphPainter({
    required this.palette,
    required this.theme,
    required this.model,
    required this.t,
    required this.statusColor,
    required this.animateFlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = model.nodes;
    final edges = model.edges;
    if (nodes.isEmpty) return;

    // Layout: prefer a fixed layout matching the canonical backend graph.
    // We render it as 3 ROWS:
    // - Row 1: main pipeline up to llm_analysis
    // - Row 2: route_after_llm_analysis + jira_create
    // - Row 3: fix generation subgraph nodes
    final fixed = _fixedLayoutForIds(nodes.map((e) => e.id).toSet());

    final nodeRects = <String, RRect>{};

    // Paint subtle grid background.
    _paintGrid(canvas, size);

    if (fixed == null) {
      final buckets = [
        // Fallback: bucket everything by id (single column).
        nodes.map((e) => e.id).toList()..sort(),
      ];
      _layoutBucketsSingleBand(size, buckets, nodeRects);
    } else {
      _layoutBucketsMultiBands(size, fixed.bands, nodeRects);
    }

    // Edges behind nodes.
    for (final e in edges) {
      final a = nodeRects[e.from];
      final b = nodeRects[e.to];
      if (a == null || b == null) continue;
      _paintEdge(canvas, a, b, e, isActive: model.activeEdge == e);
    }

    // Nodes.
    for (final n in nodes) {
      final rr = nodeRects[n.id];
      if (rr == null) continue;
      final isCurrent = n.id == model.currentNodeId;
      final isCompleted = model.completed.contains(n.id);
      final isErrored = model.errored.contains(n.id);
      final isStarted = model.started.contains(n.id);
      _paintNode(
        canvas,
        rr,
        n,
        isCurrent: isCurrent,
        isCompleted: isCompleted,
        isErrored: isErrored,
        isStarted: isStarted,
      );
    }

    // Flow dot on active edge.
    final ae = animateFlow ? model.activeEdge : null;
    if (ae != null) {
      final a = nodeRects[ae.from];
      final b = nodeRects[ae.to];
      if (a != null && b != null) {
        _paintFlowDot(canvas, a, b, ae);
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = palette.border.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    const step = 64.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintNode(Canvas canvas, RRect rr, _GraphNode node,
      {required bool isCurrent,
      required bool isCompleted,
      required bool isErrored,
      required bool isStarted}) {
    final baseFill = node.isRouter ? palette.surface2 : palette.surface1;
    final border = node.isRouter ? palette.secondary : palette.border;
    final glow = isCurrent ? statusColor : null;

    // Future nodes (not started yet) should be dimmed.
    final future = !(isStarted || isCompleted || isErrored || isCurrent);
    final dim = future ? 0.45 : 1.0;

    if (glow != null) {
      final pulse = 0.6 + 0.4 * math.sin(t * math.pi * 2);
      final glowPaint = Paint()
        ..color = glow.withValues(alpha: 0.15 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawRRect(rr.inflate(4 + 3 * pulse), glowPaint);
    }

    final fillPaint = Paint()..color = baseFill.withValues(alpha: dim);
    canvas.drawRRect(rr, fillPaint);

    final Color stateBorderColor = isErrored
        ? palette.danger
        : (isCompleted ? palette.success : (isCurrent ? statusColor : border));
    final borderPaint = Paint()
      ..color = stateBorderColor.withValues(alpha: dim == 1.0 ? 1.0 : 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCurrent ? 2.2 : 1.2;
    canvas.drawRRect(rr, borderPaint);

    // If current, we render a badge on the right side; reserve width so it
    // never overlaps the node label.
    TextPainter? badge;
    double reservedRight = 0;
    if (isCurrent) {
      badge = TextPainter(
        text: TextSpan(
          text: 'CURRENT',
          style: theme.labelSmall?.copyWith(
            color: statusColor,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 8.0;
      reservedRight = badge.width + padX * 2 + 12; // badge + padding + gap
    }

    // Title text.
    final textPainter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: AppTypography.mono(
          color: palette.text.withValues(alpha: dim),
          size: 13,
        ),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(20, rr.width - 42 - reservedRight));

    final iconPaint = Paint()
      ..color = (isErrored
              ? palette.danger
              : (isCompleted ? palette.success : (node.isRouter ? palette.secondary : palette.primary)))
          .withValues(alpha: dim);
    final iconCenter = Offset(rr.left + 14, rr.top + rr.height / 2);
    final iconSize = 10.0;
    // Simple circle/icon marker (avoid IconPainter overhead in CustomPainter).
    canvas.drawCircle(iconCenter, iconSize / 2.2, iconPaint);
    if (node.isRouter) {
      final p = Paint()
        ..color = palette.surface2.withValues(alpha: dim)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(iconCenter.dx - 4, iconCenter.dy + 4),
        Offset(iconCenter.dx + 4, iconCenter.dy - 4),
        p,
      );
    }

    final tx = rr.left + 28;
    final ty = rr.top + (rr.height - textPainter.height) / 2;
    textPainter.paint(canvas, Offset(tx, ty));

    if (isCurrent) {
      final padX = 8.0;
      final padY = 4.0;
      final bW = (badge?.width ?? 0) + padX * 2;
      final bH = (badge?.height ?? 0) + padY * 2;
      final bRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rr.right - bW - 10,
          rr.top + (rr.height - bH) / 2,
          bW,
          bH,
        ),
        const Radius.circular(999),
      );
      canvas.drawRRect(
        bRect,
        Paint()..color = statusColor.withValues(alpha: 0.10),
      );
      canvas.drawRRect(
        bRect,
        Paint()
          ..color = statusColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      badge?.paint(canvas, Offset(bRect.left + padX, bRect.top + padY));
    }
  }

  void _paintEdge(Canvas canvas, RRect from, RRect to, _GraphEdge e,
      {required bool isActive}) {
    final _EdgeGeom geom = _edgePath(from, to, e);
    final path = geom.path;
    final tanAnchor = geom.tangentAnchor;

    final baseColor = e.kind == _EdgeKind.conditional
        ? palette.secondary
        : palette.border;
    final color = isActive
        ? statusColor.withValues(alpha: 0.95)
        : baseColor.withValues(alpha: 0.9);

    final isCrossBand = geom.kind == _EdgeRouteKind.crossBand;
    final thickness = isActive
        ? 2.2
        : (isCrossBand ? 2.0 : 1.4);

    // Slight glow on the important cross-band connectors (Jira → Fix gen → Generate fix).
    if (isCrossBand) {
      final glowPaint = Paint()
        ..color = (isActive ? statusColor : palette.primary).withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness + 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(path, glowPaint);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    if (e.kind == _EdgeKind.conditional) {
      _drawDashedPath(canvas, path, paint, dash: 8, gap: 6);
    } else {
      canvas.drawPath(path, paint);
    }

    // Tiny arrow head.
    final end = geom.end;
    final tan = _tangentAtEnd(tanAnchor, end);
    final arrowP = end;
    final a1 = arrowP - Offset(tan.dx, tan.dy) * 10 + Offset(-tan.dy, tan.dx) * 4;
    final a2 = arrowP - Offset(tan.dx, tan.dy) * 10 + Offset(tan.dy, -tan.dx) * 4;
    final arrow = Path()
      ..moveTo(arrowP.dx, arrowP.dy)
      ..lineTo(a1.dx, a1.dy)
      ..lineTo(a2.dx, a2.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);

    if (e.kind == _EdgeKind.conditional && e.label != null) {
      // Place label near the middle of the rendered path (works for loops too).
      Offset mid = Offset(
        (from.center.dx + to.center.dx) / 2,
        (from.center.dy + to.center.dy) / 2,
      );
      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final m = metrics.first;
        final pos = m.getTangentForOffset(m.length * 0.52);
        if (pos != null) mid = pos.position;
      }
      final tp = TextPainter(
        text: TextSpan(
          text: e.label,
          style: theme.labelSmall?.copyWith(
            color: palette.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 140);
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(mid.dx - tp.width / 2 - 6, mid.dy - tp.height / 2 - 4,
            tp.width + 12, tp.height + 8),
        const Radius.circular(999),
      );
      canvas.drawRRect(bg, Paint()..color = palette.surface2.withValues(alpha: 0.86));
      canvas.drawRRect(
        bg,
        Paint()
          ..color = palette.border.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
    }
  }

  void _paintFlowDot(Canvas canvas, RRect from, RRect to, _GraphEdge e) {
    final geom = _edgePath(from, to, e);
    final metrics = geom.path.computeMetrics().toList();
    Offset dotPos = Offset((from.left + to.left) / 2, (from.top + to.top) / 2);
    if (metrics.isNotEmpty) {
      final m = metrics.first;
      final pos = m.getTangentForOffset(m.length * t);
      if (pos != null) dotPos = pos.position;
    }
    final alpha = 0.35 + 0.65 * math.sin((t * math.pi * 2));
    canvas.drawCircle(
      dotPos,
      4.2,
      Paint()
        ..color = statusColor.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(dotPos, 2.6, Paint()..color = statusColor);
  }

  Offset _tangentAtEnd(Offset p2, Offset p3) {
    final v = (p3 - p2);
    final len = v.distance;
    if (len == 0) return const Offset(1, 0);
    return v / len;
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final a = dist;
        final b = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(a, b), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineGraphPainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.t != t ||
        oldDelegate.statusColor != statusColor ||
        oldDelegate.palette != palette;
  }

  void _layoutBucketsSingleBand(
    Size size,
    List<List<String>> buckets,
    Map<String, RRect> out,
  ) {
    final maxLevel = buckets.length - 1;
    final totalW = _pad * 2 + buckets.length * _nodeW + maxLevel * _colGap;
    final x0 = math.max(_pad, (size.width - totalW) / 2);
    for (var col = 0; col < buckets.length; col++) {
      final ids = buckets[col];
      final colH = ids.length * _nodeH + math.max(0, ids.length - 1) * _rowGap;
      final y0 = math.max(_pad + 26, (size.height - colH) / 2);
      for (var row = 0; row < ids.length; row++) {
        final id = ids[row];
        final x = x0 + col * (_nodeW + _colGap);
        final y = y0 + row * (_nodeH + _rowGap);
        out[id] = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _nodeW, _nodeH),
          const Radius.circular(14),
        );
      }
    }
  }

  void _layoutBucketsMultiBands(
    Size size,
    List<List<List<String>>> bands,
    Map<String, RRect> out,
  ) {
    const bandGap = 120.0;

    double bandWidth(List<List<String>> b) {
      final maxLevel = b.length - 1;
      return _pad * 2 + b.length * _nodeW + math.max(0, maxLevel) * _colGap;
    }

    double bandHeight(List<List<String>> b) {
      final maxRows = b.fold<int>(0, (m, c) => math.max(m, c.length));
      return _pad * 2 +
          maxRows * _nodeH +
          math.max(0, maxRows - 1) * _rowGap;
    }

    final widths = bands.map(bandWidth).toList();
    final heights = bands.map(bandHeight).toList();
    final maxW = widths.fold<double>(0, (m, v) => math.max(m, v));
    final x0 = math.max(_pad, (size.width - maxW) / 2);

    final totalH = heights.fold<double>(0, (s, v) => s + v) +
        bandGap * math.max(0, bands.length - 1);
    final yStart = math.max(_pad + 26, (size.height - totalH) / 2);

    var y = yStart;
    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      _placeBand(band: b, x0: x0, y0: y, out: out);
      y += bandHeight(b) + (i == bands.length - 1 ? 0 : bandGap);
    }
  }

  void _placeBand({
    required List<List<String>> band,
    required double x0,
    required double y0,
    required Map<String, RRect> out,
  }) {
    for (var col = 0; col < band.length; col++) {
      final ids = band[col];
      final colH = ids.length * _nodeH + math.max(0, ids.length - 1) * _rowGap;
      final colY0 = y0 + math.max(0, (_bandMaxHeight(band) - colH) / 2);
      for (var row = 0; row < ids.length; row++) {
        final id = ids[row];
        final x = x0 + col * (_nodeW + _colGap);
        final y = colY0 + row * (_nodeH + _rowGap);
        out[id] = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _nodeW, _nodeH),
          const Radius.circular(14),
        );
      }
    }
  }

  double _bandMaxHeight(List<List<String>> band) {
    final maxRows = band.fold<int>(0, (m, c) => math.max(m, c.length));
    return maxRows * _nodeH + math.max(0, maxRows - 1) * _rowGap;
  }

  _EdgeGeom _edgePath(RRect from, RRect to, _GraphEdge e) {
    // If target is significantly below source, route as a vertical "drop" edge
    // (reads much cleaner in the 2-row layout).
    final dy = (to.top - from.bottom);
    final crossBand = dy > 36;
    if (crossBand) {
      final start = Offset(from.center.dx, from.bottom);
      final end = Offset(to.center.dx, to.top);
      final p1 = Offset(start.dx, start.dy + 60);
      final p2 = Offset(end.dx, end.dy - 60);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, end.dx, end.dy);
      return _EdgeGeom(
        kind: _EdgeRouteKind.crossBand,
        path: path,
        end: end,
        tangentAnchor: p2,
      );
    }

    final p0 = Offset(from.right, from.top + from.height / 2);
    final p3 = Offset(to.left, to.top + to.height / 2);

    // Back-edges (cycles) are drawn as a loop that routes around the nodes.
    final isBackEdge = p3.dx <= p0.dx + 8;
    if (!isBackEdge) {
      final dx = math.max(24.0, (p3.dx - p0.dx) * 0.55);
      final p1 = Offset(p0.dx + dx, p0.dy);
      final p2 = Offset(p3.dx - dx, p3.dy);
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
      return _EdgeGeom(
        kind: _EdgeRouteKind.forward,
        path: path,
        end: p3,
        tangentAnchor: p2,
      );
    }

    // Loop: go right, bend up/down, then come back left into the target.
    final rightX = math.max(p0.dx + 32, from.right + 32);
    final midY = (p0.dy + p3.dy) / 2;
    final lift = 48 + (p0.dy - p3.dy).abs() * 0.2;
    final arcY = (p0.dy < p3.dy) ? (midY - lift) : (midY + lift);

    final p1 = Offset(rightX, p0.dy);
    final p2 = Offset(rightX + 24, arcY);
    final p4 = Offset(p3.dx - 28, arcY);
    final p5 = Offset(p3.dx - 28, p3.dy);

    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, rightX + 48, arcY)
      ..lineTo(p4.dx, p4.dy)
      ..cubicTo(p4.dx, p4.dy, p5.dx, p5.dy, p3.dx, p3.dy);
    return _EdgeGeom(
      kind: _EdgeRouteKind.backEdge,
      path: path,
      end: p3,
      tangentAnchor: p5,
    );
  }
}

enum _EdgeRouteKind { forward, backEdge, crossBand }

class _EdgeGeom {
  final _EdgeRouteKind kind;
  final Path path;
  final Offset end;
  final Offset tangentAnchor;
  const _EdgeGeom({
    required this.kind,
    required this.path,
    required this.end,
    required this.tangentAnchor,
  });
}

/// Canonical, stable layout buckets. Returns null if the expected nodes aren't
/// present (e.g. future graph versions).
class _FixedLayout {
  final List<List<List<String>>> bands;
  const _FixedLayout({required this.bands});
}

_FixedLayout? _fixedLayoutForIds(Set<String> ids) {
  // 3-row layout: top row, middle row, bottom row.
  const topCols = [
    ['map_stacktrace'],
    ['route_after_map_stacktrace'],
    ['repo_context', 'mark_skipped_no_mapped_frames'],
    ['git_regression'],
    ['llm_analysis'],
  ];
  const midCols = [
    ['route_after_llm_analysis'],
    ['jira_create'],
  ];
  const botCols = [
    ['generate_fix'],
    ['review_fix'],
    ['validate_fix'],
    ['route_after_validate_fix'],
    ['generate_pr', 'fallback'],
  ];

  for (final required in const [
    'map_stacktrace',
    'llm_analysis',
    'generate_fix',
    'validate_fix',
  ]) {
    if (!ids.contains(required)) return null;
  }

  List<List<String>> filterCols(List<List<String>> cols) {
    final out = <List<String>>[];
    for (final col in cols) {
      final present = col.where(ids.contains).toList();
      if (present.isNotEmpty) out.add(present);
    }
    return out;
  }

  final top = filterCols(topCols);
  final mid = filterCols(midCols);
  final bot = filterCols(botCols);
  if (top.isEmpty || bot.isEmpty) return null;
  final bands = <List<List<String>>>[
    top,
    if (mid.isNotEmpty) mid,
    bot,
  ];
  return _FixedLayout(bands: bands);
}

