import 'dart:math';
import 'package:flutter/material.dart';

/// Represents a single user node in the link graph.
class GraphNode {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? branch;
  final bool isCurrentUser;

  Offset position;
  Offset velocity;
  bool isPinned;
  int degree;
  Color color;

  GraphNode({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.branch,
    this.isCurrentUser = false,
    Offset? position,
    Offset? velocity,
    this.isPinned = false,
    this.degree = 0,
    Color? color,
  })  : position = position ?? Offset.zero,
        velocity = velocity ?? Offset.zero,
        color = color ?? _generateColor(id, branch, isCurrentUser);

  /// Radius scaled smoothly by degree (connections count) like Obsidian.
  double get radius {
    if (isCurrentUser) {
      return (9.5 + min(13.0, degree * 1.5)).clamp(10.0, 22.0);
    }
    return (6.5 + min(11.0, degree * 1.3)).clamp(6.5, 18.5);
  }

  /// Mass for physics integration (higher degree nodes are heavier and more stable).
  double get mass => 1.0 + (degree * 0.25).clamp(0.0, 5.0);

  static Color _generateColor(String id, String? branch, bool isCurrentUser) {
    if (isCurrentUser) {
      return const Color(0xFF10B981); // Radiant emerald for the current user
    }

    // Branch based coloring or deterministic pastel palette
    final b = (branch ?? '').toLowerCase();
    if (b.contains('cse') || b.contains('ai') || b.contains('data')) {
      return const Color(0xFF6366F1); // Indigo
    } else if (b.contains('ece') || b.contains('eee')) {
      return const Color(0xFF0EA5E9); // Sky blue
    } else if (b.contains('mech') || b.contains('civil') || b.contains('mining')) {
      return const Color(0xFFF59E0B); // Amber
    } else if (b.contains('petroleum') || b.contains('agri')) {
      return const Color(0xFF14B8A6); // Teal
    }

    // Deterministic palette based on UID hash
    final hash = id.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    const palette = [
      Color(0xFF818CF8), // Violet
      Color(0xFF38BDF8), // Cyan
      Color(0xFF34D399), // Mint
      Color(0xFFF472B6), // Pink
      Color(0xFFFBBF24), // Gold
      Color(0xFFA78BFA), // Lavender
      Color(0xFF2DD4BF), // Aqua
    ];
    return palette[hash % palette.length];
  }
}

/// Represents an undirected mutual connection edge between two users.
class GraphEdge {
  final String id;
  final String sourceId;
  final String targetId;

  GraphEdge({
    required this.sourceId,
    required this.targetId,
  }) : id = canonicalId(sourceId, targetId);

  /// Canonical edge ID ensures undirected uniqueness
  static String canonicalId(String a, String b) {
    return a.compareTo(b) < 0 ? '$a--$b' : '$b--$a';
  }

  /// Check if an edge connects to a specific user
  bool connects(String uid) => sourceId == uid || targetId == uid;

  /// Get the other end of the edge
  String other(String uid) => sourceId == uid ? targetId : sourceId;
}
