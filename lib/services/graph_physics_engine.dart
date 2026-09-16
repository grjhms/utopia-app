import 'dart:math';
import 'package:flutter/material.dart';
import '../models/graph_models.dart';

/// Force-directed physics layout engine.
/// Simulates Coulomb repulsion, Hooke spring attraction, centering gravity,
/// velocity damping, and kinetic energy sleep detection.
class GraphPhysicsEngine {
  final Map<String, GraphNode> nodes = {};
  final Map<String, GraphEdge> edges = {};
  final Map<String, Set<String>> adjacency = {};

  // Physics tuning parameters — tuned for fluid, organic, springy Obsidian layout
  double repulsionStrength = 16000.0;
  double springStrength = 0.052;
  double springLength = 135.0;
  double centeringStrength = 0.0025;
  double damping = 0.940;
  double maxVelocity = 48.0;
  double energySleepThreshold = 0.06;
  int consecutiveRestFramesRequired = 25;

  bool _isSleeping = false;
  int _restFrames = 0;
  final Random _rng = Random();

  bool get isSleeping => _isSleeping;
  int get nodeCount => nodes.length;
  int get edgeCount => edges.length;

  /// Wake up the simulation
  void wake({double impulse = 1.0}) {
    _isSleeping = false;
    _restFrames = 0;
    if (impulse > 0) {
      for (final node in nodes.values) {
        if (!node.isPinned) {
          final angle = _rng.nextDouble() * 2 * pi;
          node.velocity += Offset(cos(angle), sin(angle)) * (impulse * 3.0);
        }
      }
    }
  }

  /// Interactive dragging of a node with running momentum
  void dragNode(String nodeId, Offset newPosition) {
    final node = nodes[nodeId];
    if (node == null) return;
    node.isPinned = true;
    final delta = newPosition - node.position;
    node.velocity = delta * 0.45;
    node.position = newPosition;
    _isSleeping = false;
    _restFrames = 0;
  }

  /// Release a dragged node with natural inertia
  void releaseNode(String nodeId, [Offset? throwVelocity]) {
    final node = nodes[nodeId];
    if (node == null) return;
    node.isPinned = false;
    if (throwVelocity != null && throwVelocity != Offset.zero) {
      node.velocity = throwVelocity;
    }
    wake(impulse: 0.6);
  }

  /// Add or update a node.
  /// If [linkedToId] is provided, the node spawns near that linked node with spacious breathing room.
  void addNode(
    GraphNode node, {
    String? linkedToId,
    bool wakeEngine = true,
  }) {
    final existing = nodes[node.id];
    if (existing != null) {
      // Keep existing position and physics state, update metadata
      existing.color = node.color;
      return;
    }

    // Determine initial spawn position
    if (linkedToId != null && nodes.containsKey(linkedToId)) {
      // Spawn near linked node with spacious offset
      final parentPos = nodes[linkedToId]!.position;
      final angle = _rng.nextDouble() * 2 * pi;
      final dist = 80.0 + _rng.nextDouble() * 60.0;
      node.position = parentPos + Offset(cos(angle), sin(angle)) * dist;
      node.velocity = Offset(cos(angle), sin(angle)) * 4.0;
    } else if (node.position == Offset.zero) {
      // Spacious golden ratio spiral placement
      final index = nodes.length;
      final theta = index * 2.3999632; // Golden angle in radians
      final r = 55.0 * sqrt(index + 1);
      node.position = Offset(r * cos(theta), r * sin(theta));
      node.velocity = Offset((_rng.nextDouble() - 0.5) * 4, (_rng.nextDouble() - 0.5) * 4);
    }

    nodes[node.id] = node;
    adjacency.putIfAbsent(node.id, () => <String>{});

    if (wakeEngine) {
      wake();
    }
  }

  /// Bulk initialize nodes with spacious sunflower spiral layout
  void setInitialNodes(List<GraphNode> newNodes) {
    nodes.clear();
    adjacency.clear();

    for (int i = 0; i < newNodes.length; i++) {
      final node = newNodes[i];
      final theta = i * 2.3999632;
      final r = 55.0 * sqrt(i + 1);
      node.position = Offset(r * cos(theta), r * sin(theta));
      node.velocity = Offset((_rng.nextDouble() - 0.5) * 6, (_rng.nextDouble() - 0.5) * 6);
      node.degree = 0;
      nodes[node.id] = node;
      adjacency[node.id] = <String>{};
    }
    wake(impulse: 1.2);
  }

  /// Add an undirected edge between two users
  bool addEdge(String sourceId, String targetId, {bool wakeEngine = true}) {
    if (sourceId == targetId) return false;
    final edge = GraphEdge(sourceId: sourceId, targetId: targetId);
    if (edges.containsKey(edge.id)) return false;

    edges[edge.id] = edge;

    // Update adjacency and degrees
    adjacency.putIfAbsent(sourceId, () => <String>{}).add(targetId);
    adjacency.putIfAbsent(targetId, () => <String>{}).add(sourceId);

    if (nodes.containsKey(sourceId)) {
      nodes[sourceId]!.degree++;
    }
    if (nodes.containsKey(targetId)) {
      nodes[targetId]!.degree++;
    }

    if (wakeEngine) {
      wake();
    }
    return true;
  }

  /// Remove an edge
  void removeEdge(String edgeId, {bool wakeEngine = true}) {
    final edge = edges.remove(edgeId);
    if (edge == null) return;

    adjacency[edge.sourceId]?.remove(edge.targetId);
    adjacency[edge.targetId]?.remove(edge.sourceId);

    if (nodes.containsKey(edge.sourceId)) {
      nodes[edge.sourceId]!.degree = max(0, nodes[edge.sourceId]!.degree - 1);
    }
    if (nodes.containsKey(edge.targetId)) {
      nodes[edge.targetId]!.degree = max(0, nodes[edge.targetId]!.degree - 1);
    }

    if (wakeEngine) {
      wake();
    }
  }

  /// Advance physics simulation by [dt] seconds (typically clamped ~0.016s).
  /// Returns true if the layout is still moving, false if it has settled to sleep.
  bool step(double dt) {
    if (_isSleeping || nodes.isEmpty) return false;

    final nodeList = nodes.values.toList();
    final n = nodeList.length;
    final forces = <String, Offset>{};

    // 1. Initialize forces with Centering Force
    for (int i = 0; i < n; i++) {
      final node = nodeList[i];
      // Pull toward origin (0, 0)
      forces[node.id] = -node.position * centeringStrength;
    }

    // 2. All-pairs Repulsion (Coulomb's Law with soft-core clamp)
    const maxRepulsionDistance = 1400.0;
    const maxRepulsionDistSq = maxRepulsionDistance * maxRepulsionDistance;

    for (int i = 0; i < n; i++) {
      final nodeA = nodeList[i];
      final posA = nodeA.position;

      for (int j = i + 1; j < n; j++) {
        final nodeB = nodeList[j];
        final posB = nodeB.position;

        double dx = posA.dx - posB.dx;
        double dy = posA.dy - posB.dy;
        double distSq = dx * dx + dy * dy;

        if (distSq > maxRepulsionDistSq) continue;

        if (distSq < 0.001) {
          // Break dead-center singularity
          dx = (_rng.nextDouble() - 0.5) * 2.0;
          dy = (_rng.nextDouble() - 0.5) * 2.0;
          distSq = dx * dx + dy * dy;
        }

        final dist = sqrt(distSq);
        final effectiveDist = max(dist, 20.0);
        final forceMag = repulsionStrength / (effectiveDist * effectiveDist);

        final fx = (dx / dist) * forceMag;
        final fy = (dy / dist) * forceMag;
        final f = Offset(fx, fy);

        forces[nodeA.id] = forces[nodeA.id]! + f;
        forces[nodeB.id] = forces[nodeB.id]! - f;
      }
    }

    // 3. Edge Attraction (Hooke's Spring Law)
    for (final edge in edges.values) {
      final nodeA = nodes[edge.sourceId];
      final nodeB = nodes[edge.targetId];
      if (nodeA == null || nodeB == null) continue;

      double dx = nodeB.position.dx - nodeA.position.dx;
      double dy = nodeB.position.dy - nodeA.position.dy;
      double dist = sqrt(dx * dx + dy * dy);

      if (dist < 0.001) {
        dx = 0.01;
        dist = 0.01;
      }

      final displacement = dist - springLength;
      final springForceMag = displacement * springStrength;

      final fx = (dx / dist) * springForceMag;
      final fy = (dy / dist) * springForceMag;
      final f = Offset(fx, fy);

      forces[nodeA.id] = forces[nodeA.id]! + f;
      forces[nodeB.id] = forces[nodeB.id]! - f;
    }

    // 4. Numerical Integration & Damping
    double totalKineticEnergy = 0.0;
    final timeStep = dt.clamp(0.008, 0.033);

    for (int i = 0; i < n; i++) {
      final node = nodeList[i];
      if (node.isPinned) {
        node.velocity = Offset.zero;
        continue;
      }

      final force = forces[node.id] ?? Offset.zero;
      final acceleration = force / node.mass;

      // Update velocity with damping
      var nextVelocity = (node.velocity + acceleration * timeStep) * damping;

      // Clamp speed
      final speed = nextVelocity.distance;
      if (speed > maxVelocity) {
        nextVelocity = (nextVelocity / speed) * maxVelocity;
      }

      node.velocity = nextVelocity;
      node.position += node.velocity * (timeStep * 60.0); // normalize step rate

      totalKineticEnergy += nextVelocity.dx * nextVelocity.dx + nextVelocity.dy * nextVelocity.dy;
    }

    // 5. Kinetic Energy Threshold to Sleep
    if (totalKineticEnergy < energySleepThreshold) {
      _restFrames++;
      if (_restFrames >= consecutiveRestFramesRequired) {
        _isSleeping = true;
        // Zero all velocities when settled
        for (final node in nodeList) {
          node.velocity = Offset.zero;
        }
        return false;
      }
    } else {
      _restFrames = 0;
      _isSleeping = false;
    }

    return true;
  }

  /// Get bounding rectangle of the entire graph layout
  Rect getBounds({double padding = 80.0}) {
    if (nodes.isEmpty) {
      return Rect.fromCenter(center: Offset.zero, width: 600, height: 600);
    }

    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final node in nodes.values) {
      minX = min(minX, node.position.dx);
      maxX = max(maxX, node.position.dx);
      minY = min(minY, node.position.dy);
      maxY = max(maxY, node.position.dy);
    }

    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// Find node at touch/click coordinates in graph space within hit radius
  GraphNode? hitTest(Offset point, {double hitPadding = 18.0}) {
    GraphNode? bestNode;
    double closestDist = double.infinity;

    for (final node in nodes.values) {
      final dist = (node.position - point).distance;
      final targetRadius = max(node.radius + hitPadding, 26.0);
      if (dist <= targetRadius && dist < closestDist) {
        closestDist = dist;
        bestNode = node;
      }
    }

    return bestNode;
  }

  /// Get 1st degree neighbor node IDs for a given node
  Set<String> getNeighbors(String nodeId) {
    return adjacency[nodeId] ?? <String>{};
  }
}
