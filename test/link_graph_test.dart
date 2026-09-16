import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utopia_app/models/graph_models.dart';
import 'package:utopia_app/services/graph_physics_engine.dart';

void main() {
  group('GraphModel tests', () {
    test('canonical edge ID is undirected and identical regardless of order', () {
      final edge1 = GraphEdge(sourceId: 'alice', targetId: 'bob');
      final edge2 = GraphEdge(sourceId: 'bob', targetId: 'alice');

      expect(edge1.id, equals(edge2.id));
      expect(edge1.id, equals('alice--bob'));
      expect(edge1.connects('alice'), isTrue);
      expect(edge1.connects('bob'), isTrue);
      expect(edge1.connects('charlie'), isFalse);
      expect(edge1.other('alice'), equals('bob'));
      expect(edge1.other('bob'), equals('alice'));
    });

    test('node radius scales smoothly with connection degree', () {
      final nodeIsolated = GraphNode(id: '1', name: 'Isolated', degree: 0);
      final nodeConnected = GraphNode(id: '2', name: 'Hub', degree: 10);

      expect(nodeIsolated.radius, lessThan(nodeConnected.radius));
      expect(nodeConnected.radius, lessThanOrEqualTo(20.0));
    });

    test('current user node is highlighted and has distinctive radius', () {
      final currentUser = GraphNode(
        id: 'me',
        name: 'Myself',
        isCurrentUser: true,
      );

      expect(currentUser.isCurrentUser, isTrue);
      expect(currentUser.color, equals(const Color(0xFF10B981)));
      expect(currentUser.radius, greaterThanOrEqualTo(8.0));
    });
  });

  group('GraphPhysicsEngine tests', () {
    late GraphPhysicsEngine engine;

    setUp(() {
      engine = GraphPhysicsEngine();
    });

    test('bulk initial nodes are distributed and degrees initialized', () {
      final nodes = List.generate(
        10,
        (i) => GraphNode(id: 'user_$i', name: 'User $i'),
      );
      engine.setInitialNodes(nodes);

      expect(engine.nodeCount, equals(10));
      expect(engine.edgeCount, equals(0));
      expect(engine.isSleeping, isFalse);

      // Verify no two nodes share the exact same starting position
      final positions = engine.nodes.values.map((n) => n.position).toSet();
      expect(positions.length, equals(10));
    });

    test('spring attraction pulls connected nodes closer', () {
      final nodeA = GraphNode(id: 'A', name: 'A', position: const Offset(-200, 0));
      final nodeB = GraphNode(id: 'B', name: 'B', position: const Offset(200, 0));

      engine.addNode(nodeA, wakeEngine: false);
      engine.addNode(nodeB, wakeEngine: false);
      engine.addEdge('A', 'B', wakeEngine: false);

      final initialDistance = (nodeB.position - nodeA.position).distance;
      expect(initialDistance, equals(400.0));

      // Run multiple physics steps
      for (int i = 0; i < 40; i++) {
        engine.step(0.016);
      }

      final afterDistance = (engine.nodes['B']!.position - engine.nodes['A']!.position).distance;
      expect(afterDistance, lessThan(initialDistance));
      expect(engine.nodes['A']!.degree, equals(1));
      expect(engine.nodes['B']!.degree, equals(1));
    });

    test('repulsion pushes overlapping nodes apart', () {
      final nodeA = GraphNode(id: 'A', name: 'A', position: const Offset(0, 0));
      final nodeB = GraphNode(id: 'B', name: 'B', position: const Offset(2, 2));

      engine.addNode(nodeA, wakeEngine: false);
      engine.addNode(nodeB, wakeEngine: false);

      final initialDistance = (nodeB.position - nodeA.position).distance;

      for (int i = 0; i < 30; i++) {
        engine.step(0.016);
      }

      final afterDistance = (engine.nodes['B']!.position - engine.nodes['A']!.position).distance;
      expect(afterDistance, greaterThan(initialDistance));
    });

    test('physics simulation settles and sleeps when kinetic energy drops below threshold', () {
      final nodeA = GraphNode(id: 'A', name: 'A', position: const Offset(-20, 0));
      final nodeB = GraphNode(id: 'B', name: 'B', position: const Offset(20, 0));

      engine.addNode(nodeA, wakeEngine: false);
      engine.addNode(nodeB, wakeEngine: false);
      engine.addEdge('A', 'B', wakeEngine: false);

      // Run steps until settled or max iterations
      bool stillMoving = true;
      int steps = 0;
      while (stillMoving && steps < 400) {
        stillMoving = engine.step(0.016);
        steps++;
      }

      expect(engine.isSleeping, isTrue);
      expect(stillMoving, isFalse);
    });

    test('newly added node linked to an existing node spawns near the linked node', () {
      final nodeA = GraphNode(id: 'A', name: 'A', position: const Offset(150, -80));
      engine.addNode(nodeA, wakeEngine: false);

      final nodeB = GraphNode(id: 'B', name: 'B');
      engine.addNode(nodeB, linkedToId: 'A', wakeEngine: false);

      final distance = (nodeB.position - nodeA.position).distance;
      // Spacious spawn near the node it's linked to (~80-150px)
      expect(distance, greaterThan(60.0));
      expect(distance, lessThan(160.0));
    });

    test('dragNode pins position and releaseNode unpins with organic settling', () {
      final node = GraphNode(id: 'drag_me', name: 'Draggable', position: const Offset(50, 50));
      engine.addNode(node, wakeEngine: false);

      expect(node.isPinned, isFalse);

      engine.dragNode('drag_me', const Offset(200, 200));
      expect(node.position, equals(const Offset(200, 200)));
      expect(node.isPinned, isTrue);

      engine.releaseNode('drag_me');
      expect(node.isPinned, isFalse);
    });

    test('hitTest detects node within touch radius', () {
      final nodeA = GraphNode(id: 'A', name: 'A', position: const Offset(100, 100));
      engine.addNode(nodeA, wakeEngine: false);

      final hitExact = engine.hitTest(const Offset(100, 100));
      expect(hitExact?.id, equals('A'));

      final hitNearby = engine.hitTest(const Offset(110, 105));
      expect(hitNearby?.id, equals('A'));

      final hitFar = engine.hitTest(const Offset(300, 300));
      expect(hitFar, isNull);
    });
  });
}
