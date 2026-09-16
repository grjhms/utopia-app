import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../models/graph_models.dart';

/// Clean, modern, minimalist vector painter for the Link Graph.
/// Strictly eliminates glows, fuzzy blur masks, and noisy outer strokes
/// in favor of crisp, modern digital aesthetics.
class LinkGraphPainter extends CustomPainter {
  final Map<String, GraphNode> nodes;
  final Map<String, GraphEdge> edges;
  final String? selectedNodeId;
  final String? draggedNodeId;
  final Set<String> selectedNeighbors;
  final double currentScale;
  final bool showLabelsOverride;
  final AppTheme theme;

  static const double zoomLabelThreshold = 1.35;

  // Reusable sharp paints for 60-120fps performance
  final Paint _edgePaint = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final Paint _nodePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  final Paint _labelBgPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  LinkGraphPainter({
    required this.nodes,
    required this.edges,
    required this.theme,
    this.selectedNodeId,
    this.draggedNodeId,
    this.selectedNeighbors = const {},
    required this.currentScale,
    this.showLabelsOverride = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasSelection = selectedNodeId != null || draggedNodeId != null;
    final activeFocusId = draggedNodeId ?? selectedNodeId;
    final isDark = theme.isDark;

    // 1. Subtle, Minimalist Clean Grid Points
    _drawCleanGrid(canvas, isDark);

    // 2. Crisp Vector Edges (No blur / No glow passes)
    for (final edge in edges.values) {
      final nodeA = nodes[edge.sourceId];
      final nodeB = nodes[edge.targetId];
      if (nodeA == null || nodeB == null) continue;

      final isConnectedToFocus = hasSelection &&
          (edge.sourceId == activeFocusId || edge.targetId == activeFocusId);

      if (isConnectedToFocus) {
        // Crisp active link line
        _edgePaint
          ..color = theme.primary
          ..strokeWidth = 1.8;
        canvas.drawLine(nodeA.position, nodeB.position, _edgePaint);
      } else {
        // Clean, subtle resting link line
        final alpha = hasSelection ? 0.025 : (isDark ? 0.14 : 0.40);
        _edgePaint
          ..color = (isDark ? theme.sub : theme.border).withValues(alpha: alpha)
          ..strokeWidth = 0.9;
        canvas.drawLine(nodeA.position, nodeB.position, _edgePaint);
      }
    }

    // 3. Crisp Flat Geometric Nodes (Pure dots, no outer blur)
    for (final node in nodes.values) {
      final isSelected = node.id == selectedNodeId;
      final isDragged = node.id == draggedNodeId;
      final isNeighbor = selectedNeighbors.contains(node.id);
      final isDimmed = hasSelection && !isSelected && !isDragged && !isNeighbor;

      final baseRadius = node.radius;
      final radius = isDragged
          ? baseRadius * 1.25
          : (isSelected ? baseRadius * 1.18 : baseRadius);
      final pos = node.position;

      final nodeColor = isDimmed
          ? node.color.withValues(alpha: 0.18)
          : node.color;

      // Clean, solid flat dot (No rings, no strokes, no glows)
      _nodePaint.color = nodeColor;
      canvas.drawCircle(pos, radius, _nodePaint);

      // Current user subtle inner indicator or selected dot indicator
      if ((isDragged || isSelected) && radius >= 6.0) {
        // Crisp inner dot contrast for focus
        _nodePaint.color = isDark ? Colors.white : Colors.black.withValues(alpha: 0.85);
        canvas.drawCircle(pos, 2.5, _nodePaint);
      }

      // Initial inside dot when zoomed in
      if ((currentScale >= 1.85 || isSelected || isDragged) &&
          radius >= 9.0 &&
          !isDimmed) {
        final initial = node.name.trim().isNotEmpty
            ? node.name.trim()[0].toUpperCase()
            : 'U';
        _drawNodeInitial(canvas, pos, initial, radius);
      }
    }

    // 4. Clean Minimalist Labels
    final shouldDrawAllLabels =
        showLabelsOverride || currentScale >= zoomLabelThreshold;

    for (final node in nodes.values) {
      final isSelected = node.id == selectedNodeId;
      final isDragged = node.id == draggedNodeId;
      final isNeighbor = selectedNeighbors.contains(node.id);

      if (shouldDrawAllLabels || isSelected || isDragged || isNeighbor) {
        _drawNodeLabel(
          canvas,
          node,
          isSelected: isSelected || isDragged,
          isNeighbor: isNeighbor,
          isDimmed: hasSelection && !isSelected && !isDragged && !isNeighbor,
          isDark: isDark,
        );
      }
    }
  }

  void _drawCleanGrid(Canvas canvas, bool isDark) {
    final gridDotPaint = Paint()
      ..color = (isDark ? theme.sub : theme.border).withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    const spacing = 180.0;
    const dotRadius = 0.9;

    for (double x = -3200; x <= 3200; x += spacing) {
      for (double y = -3200; y <= 3200; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, gridDotPaint);
      }
    }
  }

  void _drawNodeInitial(
      Canvas canvas, Offset center, String initial, double radius) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: initial,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: (radius * 0.9).clamp(8.0, 13.0),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  void _drawNodeLabel(
    Canvas canvas,
    GraphNode node, {
    required bool isSelected,
    required bool isNeighbor,
    required bool isDimmed,
    required bool isDark,
  }) {
    final displayName = node.name.isEmpty ? 'Student' : node.name;
    final cleanName = displayName.length > 16
        ? '${displayName.substring(0, 15)}…'
        : displayName;

    final fontSize = isSelected ? 12.0 : 10.5;
    final textColor = isSelected
        ? (isDark ? Colors.white : theme.primary)
        : (isNeighbor
            ? theme.primary
            : (isDimmed
                ? theme.dim.withValues(alpha: 0.25)
                : (isDark ? const Color(0xFFE2E8F0) : theme.text)));

    final textPainter = TextPainter(
      text: TextSpan(
        text: cleanName,
        style: GoogleFonts.outfit(
          color: textColor,
          fontSize: fontSize,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: -0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelPos = Offset(
      node.position.dx - (textPainter.width / 2),
      node.position.dy + node.radius + (isSelected ? 6.0 : 4.0),
    );

    // Clean, subtle label pill without heavy borders
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelPos.dx - 4,
        labelPos.dy - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      ),
      const Radius.circular(5),
    );

    _labelBgPaint.color = isDark
        ? (isSelected ? const Color(0xFF0F172A) : Colors.black).withValues(alpha: 0.78)
        : (isSelected ? const Color(0xFFF1F5F9) : Colors.white).withValues(alpha: 0.90);
    canvas.drawRRect(bgRect, _labelBgPaint);

    textPainter.paint(canvas, labelPos);
  }

  @override
  bool shouldRepaint(covariant LinkGraphPainter oldDelegate) {
    return true;
  }
}
