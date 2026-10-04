import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';
import '../../../core/models/run_event.dart';
import '../../../shared/widgets/json_tree_viewer.dart';

enum _EdgeKind { normal, conditional }

/// Viewport-driven spacing so the DAG fits cleanly across screen widths.
class _LayoutDensity {
  final double pad;
  final double nodeW;
  final double nodeH;
  final double colGap;
  final double rowGap;
  final double bandGap;
  final double nodeRadius;
  final double fontSize;

  const _LayoutDensity({
    required this.pad,
    required this.nodeW,
    required this.nodeH,
    required this.colGap,
    required this.rowGap,
    required this.bandGap,
    required this.nodeRadius,
    required this.fontSize,
  });

  static _LayoutDensity forWidth(double width) {
    if (width < 720) {
      return const _LayoutDensity(
        pad: 14,
        nodeW: 148,
        nodeH: 44,
        colGap: 72,
        rowGap: 22,
        bandGap: 72,
        nodeRadius: 12,
        fontSize: 11.5,
      );
    }
    if (width < 1100) {
      return const _LayoutDensity(
        pad: 16,
        nodeW: 168,
        nodeH: 48,
        colGap: 100,
        rowGap: 28,
        bandGap: 96,
        nodeRadius: 13,
        fontSize: 12,
      );
    }
    return const _LayoutDensity(
      pad: 18,
      nodeW: 190,
      nodeH: 52,
      colGap: 140,
      rowGap: 34,
      bandGap: 120,
      nodeRadius: 14,
      fontSize: 13,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LayoutDensity &&
          pad == other.pad &&
          nodeW == other.nodeW &&
          nodeH == other.nodeH &&
          colGap == other.colGap &&
          rowGap == other.rowGap &&
          bandGap == other.bandGap &&
          nodeRadius == other.nodeRadius &&
          fontSize == other.fontSize;

  @override
  int get hashCode => Object.hash(
        pad,
        nodeW,
        nodeH,
        colGap,
        rowGap,
        bandGap,
        nodeRadius,
        fontSize,
      );
}

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
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _flowCtrl = AnimationController(
      vsync: this,
      duration: 1400.ms,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant PipelineGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    final reduce = AppMotion.reduceMotion(context);
    _reduceMotion = reduce;
    final shouldAnimate =
        !reduce && !(widget.completed || widget.failed);
    if (shouldAnimate) {
      if (!_flowCtrl.isAnimating) _flowCtrl.repeat();
    } else {
      if (_flowCtrl.isAnimating) _flowCtrl.stop();
      if (reduce && _flowCtrl.value != 0) {
        _flowCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _flowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final model = _buildModel(widget.events);
    final animateFlow = !_reduceMotion &&
        !(widget.completed || widget.failed) &&
        model.hasInFlight;

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
    final isRunning = !(widget.completed || widget.failed);

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
            // Full-bleed atmosphere so the fitted graph never shows as a nested box.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _flowCtrl,
                builder: (ctx, _) => CustomPaint(
                  painter: _AtmospherePainter(
                    palette: palette,
                    t: _flowCtrl.value,
                    reduceMotion: _reduceMotion,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final density = _LayoutDensity.forWidth(c.maxWidth);
                  final layout =
                      _fixedLayoutForIds(model.nodes.map((e) => e.id).toSet());
                  final fallback = [
                    model.nodes.map((e) => e.id).toList()..sort(),
                  ];
                  final bands = layout?.bands ?? [fallback];

                  double bandWidth(List<List<String>> cols) {
                    final maxLevel = cols.length - 1;
                    return density.pad * 2 +
                        cols.length * density.nodeW +
                        math.max(0, maxLevel) * density.colGap;
                  }

                  double bandHeight(List<List<String>> cols) {
                    final maxRows =
                        cols.fold<int>(0, (m, b) => math.max(m, b.length));
                    return density.pad * 2 +
                        maxRows * density.nodeH +
                        math.max(0, maxRows - 1) * density.rowGap;
                  }

                  final widths = bands.map((b) => bandWidth(b)).toList();
                  final heights = bands.map((b) => bandHeight(b)).toList();
                  final canvasW =
                      widths.fold<double>(0, (m, v) => math.max(m, v));
                  final canvasH = heights.fold<double>(0, (s, v) => s + v) +
                      density.bandGap * math.max(0, bands.length - 1) +
                      56; // room for the status pill overlay

                  // Fit without InteractiveViewer — no scroll-wheel zoom / pan.
                  return FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
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
                              density: density,
                              t: _flowCtrl.value,
                              statusColor: statusColor,
                              animateFlow: animateFlow,
                              reduceMotion: _reduceMotion,
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
              child: AnimatedBuilder(
                animation: _flowCtrl,
                builder: (ctx, _) {
                  final pulse = isRunning && !_reduceMotion
                      ? 0.55 + 0.45 * math.sin(_flowCtrl.value * math.pi * 2)
                      : 1.0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surface2.withValues(alpha: 0.92),
                      border: Border.all(
                        color: isRunning
                            ? statusColor.withValues(alpha: 0.35 * pulse)
                            : palette.border,
                      ),
                      borderRadius: AppRadii.all(AppRadii.pill),
                      boxShadow: isRunning
                          ? [
                              BoxShadow(
                                color: statusColor.withValues(
                                  alpha: 0.12 * pulse,
                                ),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
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
                                color: statusColor.withValues(
                                  alpha: 0.55 * pulse,
                                ),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.failed
                              ? 'pipeline failed'
                              : (widget.completed
                                  ? 'pipeline completed'
                                  : 'pipeline running'),
                          style: theme.labelMedium?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: pretty)),
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
    _GraphNode(
      id: 'mark_skipped_no_mapped_frames',
      label: 'Skipped (no frames)',
      isRouter: false,
    ),
    // Note: we intentionally do NOT render the parent "fix_generation" wrapper
    // node; the subgraph nodes below are the actual pipeline steps.

    // Fix subgraph (render as part of the full pipeline)
    _GraphNode(id: 'generate_fix', label: 'Generate fix', isRouter: false),
    _GraphNode(id: 'review_fix', label: 'Review fix', isRouter: false),
    _GraphNode(id: 'validate_fix', label: 'Validate fix', isRouter: false),
    _GraphNode(id: 'route_after_validate_fix', label: 'Route', isRouter: true),
    _GraphNode(id: 'generate_pr', label: 'Generate PR', isRouter: false),
    _GraphNode(id: 'jira_update', label: 'Update Jira', isRouter: false),
    _GraphNode(id: 'fallback', label: 'Fallback', isRouter: false),
  ];

  static const List<_GraphEdge> _specEdges = [
    // Main flow
    _GraphEdge(
      from: 'map_stacktrace',
      to: 'route_after_map_stacktrace',
      kind: _EdgeKind.normal,
    ),
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
    _GraphEdge(
      from: 'repo_context',
      to: 'git_regression',
      kind: _EdgeKind.normal,
    ),
    _GraphEdge(
      from: 'git_regression',
      to: 'llm_analysis',
      kind: _EdgeKind.normal,
    ),
    _GraphEdge(
      from: 'llm_analysis',
      to: 'route_after_llm_analysis',
      kind: _EdgeKind.normal,
    ),
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
    _GraphEdge(
      from: 'validate_fix',
      to: 'route_after_validate_fix',
      kind: _EdgeKind.normal,
    ),
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
    _GraphEdge(from: 'generate_pr', to: 'jira_update', kind: _EdgeKind.normal),
  ];

  _GraphModel _buildModel(List<RunEvent> events) {
    // Always start from the canonical spec so we can draw "future" nodes dimmed.
    final nodesById = {for (final n in _specNodes) n.id: n};
    final edges = List<_GraphEdge>.from(_specEdges);

    // Track runtime state.
    final startedAt = <String, int>{}; // nodeId -> start index
    final completedAt = <String, int>{}; // nodeId -> completion index
    final erroredAt = <String, int>{}; // nodeId -> error index

    final entryEdgeForNode = <String, _GraphEdge>{};

    String? lastCompletedNode;
    int lastCompletedIdx = -1;

    String? lastRouter;
    String? lastRouteLabel;
    int lastRouterIdx = -1;

    for (var i = 0; i < events.length; i++) {
      final ev = events[i];
      switch (ev) {
        case NodeStartedEvent(:final node):
          var id = _normNodeId(node);
          if (id == 'fix_generation') id = 'generate_fix';
          startedAt[id] = i;

          // Record the edge that led into this node for accurate "active edge"
          // animation. Prefer the most recent router decision if it happened
          // after the last completion (i.e., it actually routed into this node).
          _GraphEdge? entry;
          if (lastRouter != null &&
              lastRouteLabel != null &&
              lastRouterIdx > lastCompletedIdx) {
            entry = edges.cast<_GraphEdge?>().firstWhere(
              (e) =>
                  e != null &&
                  e.kind == _EdgeKind.conditional &&
                  (e.routerId ?? e.from) == lastRouter &&
                  // main routers: label == destination; validate router: label == "valid/retry/fail"
                  ((e.label ?? '') == lastRouteLabel || e.to == id),
              orElse: () => null,
            );
          }
          if (entry == null && lastCompletedNode != null) {
            entry = edges.cast<_GraphEdge?>().firstWhere(
              (e) => e != null && e.from == lastCompletedNode && e.to == id,
              orElse: () => null,
            );
          }
          if (entry != null) {
            entryEdgeForNode[id] = entry;
          }
        case NodeCompletedEvent(:final node):
          var id = _normNodeId(node);
          if (id == 'fix_generation') id = 'generate_fix';
          completedAt[id] = i;
          lastCompletedNode = id;
          lastCompletedIdx = i;
        case NodeErrorEvent(:final node):
          var id = _normNodeId(node);
          if (id == 'fix_generation') id = 'generate_fix';
          erroredAt[id] = i;
          lastCompletedNode = id;
          lastCompletedIdx = i;
        case RouterEvent(:final router, :final route):
          lastRouter = _normRouterId(router);
          // Note: `route` is either the destination node id (main routers) OR a
          // label like "valid/retry/fail" (validate_fix router). We use it to
          // activate the matching conditional edge from the spec.
          lastRouteLabel = route.trim().isEmpty ? null : route.trim();
          lastRouterIdx = i;
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
    // Prefer the actual transition edge that led into the current in-flight node.
    if (hasInFlight && current != null) {
      activeEdge = entryEdgeForNode[current];
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

/// Full-bleed grid / vignette behind the fitted graph (avoids a nested canvas box).
class _AtmospherePainter extends CustomPainter {
  final AppPalette palette;
  final double t;
  final bool reduceMotion;

  _AtmospherePainter({
    required this.palette,
    required this.t,
    required this.reduceMotion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Soft vignette that covers the entire host, not the scaled graph canvas.
    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.12),
        radius: 1.2,
        colors: [
          palette.surface1.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.18),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);

    final breath = reduceMotion
        ? 1.0
        : (0.78 + 0.22 * math.sin(t * math.pi * 2));
    final paint = Paint()
      ..color = palette.border.withValues(alpha: 0.06 * breath)
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.palette != palette ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

class _PipelineGraphPainter extends CustomPainter {
  final AppPalette palette;
  final TextTheme theme;
  final _GraphModel model;
  final _LayoutDensity density;
  final double t;
  final Color statusColor;
  final bool animateFlow;
  final bool reduceMotion;

  _PipelineGraphPainter({
    required this.palette,
    required this.theme,
    required this.model,
    required this.density,
    required this.t,
    required this.statusColor,
    required this.animateFlow,
    required this.reduceMotion,
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
      final isCompletedPath = model.completed.contains(e.from) &&
          (model.completed.contains(e.to) ||
              model.started.contains(e.to) ||
              e.to == model.currentNodeId);
      _paintEdge(
        canvas,
        a,
        b,
        e,
        isActive: model.activeEdge == e,
        isCompletedPath: isCompletedPath,
      );
    }

    // Nodes.
    for (final n in nodes) {
      final rr = nodeRects[n.id];
      if (rr == null) continue;
      final isCurrent = n.id == model.currentNodeId && model.hasInFlight;
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

    // Comet trail on active edge.
    final ae = animateFlow ? model.activeEdge : null;
    if (ae != null) {
      final a = nodeRects[ae.from];
      final b = nodeRects[ae.to];
      if (a != null && b != null) {
        _paintCometTrail(canvas, a, b, ae);
      }
    }
  }

  void _paintNode(
    Canvas canvas,
    RRect rr,
    _GraphNode node, {
    required bool isCurrent,
    required bool isCompleted,
    required bool isErrored,
    required bool isStarted,
  }) {
    final baseFill = node.isRouter ? palette.surface2 : palette.surface1;
    final border = node.isRouter ? palette.secondary : palette.border;

    // Future nodes (not started yet) should be dimmed.
    final future = !(isStarted || isCompleted || isErrored || isCurrent);
    final dim = future ? 0.48 : 1.0;

    if (isCurrent) {
      final pulse = reduceMotion
          ? 0.85
          : (0.55 + 0.45 * math.sin(t * math.pi * 2));
      // Outer glow
      canvas.drawRRect(
        rr.inflate(8 + 4 * pulse),
        Paint()
          ..color = statusColor.withValues(alpha: 0.10 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
      // Inner halo
      canvas.drawRRect(
        rr.inflate(3 + 2 * pulse),
        Paint()
          ..color = (palette.glow).withValues(alpha: 0.18 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    } else if (isErrored && !reduceMotion) {
      final pulse = 0.7 + 0.3 * math.sin(t * math.pi * 2);
      canvas.drawRRect(
        rr.inflate(3),
        Paint()
          ..color = palette.danger.withValues(alpha: 0.08 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Soft glass fill.
    canvas.drawRRect(
      rr,
      Paint()..color = baseFill.withValues(alpha: dim * 0.96),
    );
    // Top sheen for non-future nodes.
    if (!future) {
      final sheen = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.04 * dim),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(rr.outerRect);
      canvas.drawRRect(rr, sheen);
    }

    final Color stateBorderColor = isErrored
        ? palette.danger
        : (isCompleted
            ? palette.success
            : (isCurrent
                ? statusColor
                : (future ? border.withValues(alpha: 0.7) : border)));
    final borderWidth = isCurrent ? 2.4 : (isCompleted || isErrored ? 1.6 : 1.15);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = stateBorderColor.withValues(alpha: dim == 1.0 ? 1.0 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Breathing progress ring for current node.
    if (isCurrent && !reduceMotion) {
      final ringPulse = 0.4 + 0.6 * math.sin(t * math.pi * 2);
      canvas.drawRRect(
        rr.inflate(1.5),
        Paint()
          ..color = statusColor.withValues(alpha: 0.22 * ringPulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Title text — full width (CURRENT badge floats above).
    final textPainter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: AppTypography.mono(
          color: palette.text.withValues(alpha: dim),
          size: density.fontSize,
        ),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(20, rr.width - 42));

    final iconPaint = Paint()
      ..color = (isErrored
              ? palette.danger
              : (isCompleted
                  ? palette.success
                  : (node.isRouter ? palette.secondary : palette.primary)))
          .withValues(alpha: dim);
    final iconCenter = Offset(rr.left + 14, rr.top + rr.height / 2);
    const iconSize = 10.0;
    canvas.drawCircle(iconCenter, iconSize / 2.2, iconPaint);

    if (isCompleted) {
      // Tiny checkmark in the status disc.
      final check = Paint()
        ..color = palette.surface2.withValues(alpha: dim)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(iconCenter.dx - 2.4, iconCenter.dy)
          ..lineTo(iconCenter.dx - 0.4, iconCenter.dy + 2.0)
          ..lineTo(iconCenter.dx + 2.8, iconCenter.dy - 2.2),
        check,
      );
    } else if (node.isRouter) {
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

    // Floating CURRENT badge above the node.
    if (isCurrent) {
      final badge = TextPainter(
        text: TextSpan(
          text: 'CURRENT',
          style: theme.labelSmall?.copyWith(
            color: statusColor,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 8.0;
      const padY = 3.5;
      final bW = badge.width + padX * 2;
      final bH = badge.height + padY * 2;
      final bRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rr.left + (rr.width - bW) / 2,
          rr.top - bH - 6,
          bW,
          bH,
        ),
        const Radius.circular(999),
      );
      canvas.drawRRect(
        bRect,
        Paint()..color = statusColor.withValues(alpha: 0.12),
      );
      canvas.drawRRect(
        bRect,
        Paint()
          ..color = statusColor.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      badge.paint(canvas, Offset(bRect.left + padX, bRect.top + padY));
    }
  }

  void _paintEdge(
    Canvas canvas,
    RRect from,
    RRect to,
    _GraphEdge e, {
    required bool isActive,
    required bool isCompletedPath,
  }) {
    final geom = _edgePath(from, to, e);
    final path = geom.path;
    final tanAnchor = geom.tangentAnchor;

    final baseColor = e.kind == _EdgeKind.conditional
        ? palette.secondary
        : palette.border;
    Color color;
    if (isActive) {
      color = statusColor.withValues(alpha: 0.95);
    } else if (isCompletedPath) {
      color = palette.success.withValues(alpha: 0.72);
    } else {
      color = baseColor.withValues(alpha: 0.85);
    }

    final isCrossBand = geom.kind == _EdgeRouteKind.crossBand;
    final thickness = isActive
        ? 2.6
        : (isCompletedPath ? 2.0 : (isCrossBand ? 2.0 : 1.35));

    // Soft outer glow for active / completed / cross-band edges.
    if (isActive || isCompletedPath || isCrossBand) {
      final glowColor = isActive
          ? statusColor
          : (isCompletedPath ? palette.success : palette.primary);
      canvas.drawPath(
        path,
        Paint()
          ..color = glowColor.withValues(alpha: isActive ? 0.22 : 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness + (isActive ? 8 : 5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
          ..strokeCap = StrokeCap.round,
      );
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    if (e.kind == _EdgeKind.conditional) {
      final phase = (reduceMotion || !animateFlow) ? 0.0 : t * 14;
      _drawDashedPath(canvas, path, paint, dash: 8, gap: 6, phase: phase);
    } else {
      canvas.drawPath(path, paint);
    }

    // Tiny arrow head.
    final end = geom.end;
    final tan = _tangentAtEnd(tanAnchor, end);
    final arrowP = end;
    final a1 =
        arrowP - Offset(tan.dx, tan.dy) * 10 + Offset(-tan.dy, tan.dx) * 4;
    final a2 =
        arrowP - Offset(tan.dx, tan.dy) * 10 + Offset(tan.dy, -tan.dx) * 4;
    final arrow = Path()
      ..moveTo(arrowP.dx, arrowP.dy)
      ..lineTo(a1.dx, a1.dy)
      ..lineTo(a2.dx, a2.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);

    if (e.kind == _EdgeKind.conditional && e.label != null) {
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
            fontSize: density.fontSize - 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 140);
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          mid.dx - tp.width / 2 - 6,
          mid.dy - tp.height / 2 - 4,
          tp.width + 12,
          tp.height + 8,
        ),
        const Radius.circular(999),
      );
      canvas.drawRRect(
        bg,
        Paint()..color = palette.surface2.withValues(alpha: 0.88),
      );
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

  void _paintCometTrail(Canvas canvas, RRect from, RRect to, _GraphEdge e) {
    final geom = _edgePath(from, to, e);
    final metrics = geom.path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    if (m.length <= 0) return;

    const trailCount = 6;
    const spacing = 0.035;

    for (var i = trailCount - 1; i >= 0; i--) {
      final frac = (t - i * spacing) % 1.0;
      final pos = m.getTangentForOffset(m.length * frac);
      if (pos == null) continue;
      final fade = 1.0 - (i / trailCount);
      final radius = 1.4 + 2.4 * fade;
      canvas.drawCircle(
        pos.position,
        radius + 2.5,
        Paint()
          ..color = statusColor.withValues(alpha: 0.18 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        pos.position,
        radius,
        Paint()..color = statusColor.withValues(alpha: 0.35 + 0.55 * fade),
      );
    }

    // Bright head.
    final head = m.getTangentForOffset(m.length * t);
    if (head != null) {
      final alpha = 0.45 + 0.55 * math.sin(t * math.pi * 2);
      canvas.drawCircle(
        head.position,
        5.5,
        Paint()
          ..color = palette.glow.withValues(alpha: 0.35 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        head.position,
        3.0,
        Paint()..color = statusColor.withValues(alpha: 0.95),
      );
      canvas.drawCircle(
        head.position,
        1.3,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
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
    double phase = 0,
  }) {
    for (final metric in path.computeMetrics()) {
      final period = dash + gap;
      var dist = phase % period;
      if (dist < 0) dist += period;
      // If phase lands in a gap, skip to next dash start.
      if (dist > dash) {
        dist = dist - period;
      }
      while (dist < metric.length) {
        final a = math.max(0.0, dist);
        final b = math.min(dist + dash, metric.length);
        if (b > a) {
          canvas.drawPath(metric.extractPath(a, b), paint);
        }
        dist += period;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineGraphPainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.t != t ||
        oldDelegate.statusColor != statusColor ||
        oldDelegate.palette != palette ||
        oldDelegate.animateFlow != animateFlow ||
        oldDelegate.reduceMotion != reduceMotion ||
        oldDelegate.density != density;
  }

  void _layoutBucketsSingleBand(
    Size size,
    List<List<String>> buckets,
    Map<String, RRect> out,
  ) {
    final maxLevel = buckets.length - 1;
    final totalW = density.pad * 2 +
        buckets.length * density.nodeW +
        maxLevel * density.colGap;
    final x0 = math.max(density.pad, (size.width - totalW) / 2);
    for (var col = 0; col < buckets.length; col++) {
      final ids = buckets[col];
      final colH = ids.length * density.nodeH +
          math.max(0, ids.length - 1) * density.rowGap;
      final y0 = math.max(density.pad + 26, (size.height - colH) / 2);
      for (var row = 0; row < ids.length; row++) {
        final id = ids[row];
        final x = x0 + col * (density.nodeW + density.colGap);
        final y = y0 + row * (density.nodeH + density.rowGap);
        out[id] = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, density.nodeW, density.nodeH),
          Radius.circular(density.nodeRadius),
        );
      }
    }
  }

  void _layoutBucketsMultiBands(
    Size size,
    List<List<List<String>>> bands,
    Map<String, RRect> out,
  ) {
    double bandWidth(List<List<String>> b) {
      final maxLevel = b.length - 1;
      return density.pad * 2 +
          b.length * density.nodeW +
          math.max(0, maxLevel) * density.colGap;
    }

    double bandHeight(List<List<String>> b) {
      final maxRows = b.fold<int>(0, (m, c) => math.max(m, c.length));
      return density.pad * 2 +
          maxRows * density.nodeH +
          math.max(0, maxRows - 1) * density.rowGap;
    }

    final widths = bands.map(bandWidth).toList();
    final heights = bands.map(bandHeight).toList();
    final maxW = widths.fold<double>(0, (m, v) => math.max(m, v));
    final x0 = math.max(density.pad, (size.width - maxW) / 2);

    final totalH = heights.fold<double>(0, (s, v) => s + v) +
        density.bandGap * math.max(0, bands.length - 1);
    final yStart = math.max(density.pad + 26, (size.height - totalH) / 2);

    var y = yStart;
    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      _placeBand(band: b, x0: x0, y0: y, out: out);
      y += bandHeight(b) + (i == bands.length - 1 ? 0 : density.bandGap);
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
      final colH = ids.length * density.nodeH +
          math.max(0, ids.length - 1) * density.rowGap;
      final colY0 = y0 + math.max(0, (_bandMaxHeight(band) - colH) / 2);
      for (var row = 0; row < ids.length; row++) {
        final id = ids[row];
        final x = x0 + col * (density.nodeW + density.colGap);
        final y = colY0 + row * (density.nodeH + density.rowGap);
        out[id] = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, density.nodeW, density.nodeH),
          Radius.circular(density.nodeRadius),
        );
      }
    }
  }

  double _bandMaxHeight(List<List<String>> band) {
    final maxRows = band.fold<int>(0, (m, c) => math.max(m, c.length));
    return maxRows * density.nodeH +
        math.max(0, maxRows - 1) * density.rowGap;
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
    ['jira_update'],
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
