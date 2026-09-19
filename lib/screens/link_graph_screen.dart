import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/graph_models.dart';
import '../services/cache_service.dart';
import '../services/graph_physics_engine.dart';
import '../widgets/app_motion.dart';
import '../widgets/instagram_badge.dart';
import '../widgets/link_graph_painter.dart';
import '../widgets/social_badge.dart';
import '../widgets/utopia_loader.dart';
import 'user_profile_screen.dart';

/// Route builder with silky smooth crossfade transition for Graph View toggle
Route<T> buildGraphCrossfadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: child,
      );
    },
  );
}

class LinkGraphScreen extends StatefulWidget {
  const LinkGraphScreen({super.key});

  @override
  State<LinkGraphScreen> createState() => _LinkGraphScreenState();
}

class _LinkGraphScreenState extends State<LinkGraphScreen>
    with TickerProviderStateMixin {
  final GraphPhysicsEngine _physicsEngine = GraphPhysicsEngine();
  final TransformationController _transformController =
      TransformationController();

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _currentScale = 1.0;
  AnimationController? _cameraAnimController;

  bool _isLoading = true;
  String? _selectedNodeId;
  Set<String> _selectedNeighbors = const {};

  // Touch and physical node dragging state (Obsidian style)
  String? _draggedNodeId;
  Offset? _pointerDownLocal;
  bool _hasDraggedPointer = false;
  bool _isPanEnabled = true;
  int _activePointers = 0;

  StreamSubscription? _usersSubscription;
  StreamSubscription? _followsSubscription;

  // Cached raw user documents for instant lookup
  final Map<String, Map<String, dynamic>> _userDocs = {};

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
    _initGraphData();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.04) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  /// Start the physics simulation ticker if not running
  void _wakePhysics({double impulse = 0.0}) {
    _physicsEngine.wake(impulse: impulse);
    if (_ticker == null || !_ticker!.isActive) {
      _ticker?.dispose();
      _lastTick = Duration.zero;
      _ticker = createTicker(_onPhysicsTick)..start();
    }
  }

  void _onPhysicsTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }

    final double dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    // Advance physics step
    final isStillMoving = _physicsEngine.step(dt.clamp(0.008, 0.033));

    // If settled and no node is actively being dragged, stop ticker to save battery
    if (!isStillMoving && _draggedNodeId == null) {
      _ticker?.stop();
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Initial load: fetch all users and all accepted mutual links at once
  Future<void> _initGraphData() async {
    try {
      final db = FirebaseFirestore.instance;

      // 1. Fetch all users
      final usersSnap = await db.collection('users').get();
      final List<GraphNode> initialNodes = [];

      for (final doc in usersSnap.docs) {
        final data = doc.data();
        _userDocs[doc.id] = data;

        final rawName = (data['displayName'] ?? 'Student').toString();
        final name = UtopiaApp.sanitizeDisplayName(rawName);
        final photo = (data['photoUrl'] ?? data['photoURL'])?.toString();
        final branch = data['branch']?.toString();

        initialNodes.add(
          GraphNode(
            id: doc.id,
            name: name,
            avatarUrl: photo,
            branch: branch,
            isCurrentUser: doc.id == _currentUid,
          ),
        );
      }

      // Initialize physics layout with spacious sunflower spiral
      _physicsEngine.setInitialNodes(initialNodes);

      // 2. Fetch all accepted mutual links
      final followsSnap = await db
          .collection('follows')
          .where('status', isEqualTo: 'accepted')
          .get();

      for (final doc in followsSnap.docs) {
        final data = doc.data();
        final followerId = (data['followerId'] ?? '').toString();
        final followingId = (data['followingId'] ?? '').toString();

        if (followerId.isNotEmpty && followingId.isNotEmpty) {
          _physicsEngine.addEdge(followerId, followingId, wakeEngine: false);
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Center camera view after layout initialization
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerCameraOnGraph();
          _wakePhysics(impulse: 1.5);
        });
      }

      // 3. Listen to real-time additions and removals of mutual links
      _listenToRealtimeLinks();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Real-time live updates: listen to backend events for newly accepted links
  void _listenToRealtimeLinks() {
    final db = FirebaseFirestore.instance;

    _followsSubscription = db
        .collection('follows')
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) async {
      bool hasNewEdges = false;

      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;

        final followerId = (data['followerId'] ?? '').toString();
        final followingId = (data['followingId'] ?? '').toString();

        if (followerId.isEmpty || followingId.isEmpty) continue;

        if (change.type == DocumentChangeType.added) {
          // If either user was not in graph, load and spawn near its linked partner with spacious offset
          await _ensureUserInGraph(followerId, linkedToId: followingId);
          await _ensureUserInGraph(followingId, linkedToId: followerId);

          final added = _physicsEngine.addEdge(followerId, followingId);
          if (added) hasNewEdges = true;
        } else if (change.type == DocumentChangeType.removed) {
          final edgeId = GraphEdge.canonicalId(followerId, followingId);
          _physicsEngine.removeEdge(edgeId);
          hasNewEdges = true;
        }
      }

      if (hasNewEdges) {
        // Wake up physics engine briefly so the layout re-settles around the change
        _wakePhysics(impulse: 1.2);
      }
    });

    // Also listen to users collection to keep metadata updated
    _usersSubscription = db.collection('users').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;
        _userDocs[change.doc.id] = data;
      }
    });
  }

  /// Ensure a user is present in the graph.
  /// If newly added, spawns near [linkedToId] with spacious breathing room.
  Future<void> _ensureUserInGraph(String uid, {String? linkedToId}) async {
    if (_physicsEngine.nodes.containsKey(uid)) return;

    Map<String, dynamic>? data = _userDocs[uid];
    if (data == null) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          data = doc.data();
          _userDocs[uid] = data!;
        }
      } catch (_) {}
    }

    final rawName = ((data?['displayName'] ?? 'Student')).toString();
    final name = UtopiaApp.sanitizeDisplayName(rawName);
    final photo = (data?['photoUrl'] ?? data?['photoURL'])?.toString();
    final branch = data?['branch']?.toString();

    final newNode = GraphNode(
      id: uid,
      name: name,
      avatarUrl: photo,
      branch: branch,
      isCurrentUser: uid == _currentUid,
    );

    // Add node: spawns near linked node
    _physicsEngine.addNode(newNode, linkedToId: linkedToId, wakeEngine: true);
  }

  /// Center and fit camera on the entire graph layout with smooth animation
  void _centerCameraOnGraph() {
    _cameraAnimController?.stop();
    _cameraAnimController?.dispose();

    final bounds = _physicsEngine.getBounds(padding: 240.0);
    final size = MediaQuery.of(context).size;

    final scaleX = size.width / max(bounds.width, 100.0);
    final scaleY = size.height / max(bounds.height, 100.0);
    final fitScale = min(scaleX, scaleY).clamp(0.28, 1.10);

    final targetTx = size.width / 2 - bounds.center.dx * fitScale;
    final targetTy = size.height / 2 - bounds.center.dy * fitScale;

    final currentMatrix = _transformController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final tx0 = currentMatrix.storage[12];
    final ty0 = currentMatrix.storage[13];

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _cameraAnimController = controller;

    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    controller.addListener(() {
      final t = curved.value;
      final s = currentScale + (fitScale - currentScale) * t;
      final tx = tx0 + (targetTx - tx0) * t;
      final ty = ty0 + (targetTy - ty0) * t;

      final m = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setTranslationRaw(tx, ty, 0.0);
      _transformController.value = m;
    });

    controller.forward().then((_) {
      if (_cameraAnimController == controller) {
        _cameraAnimController = null;
        controller.dispose();
      }
    });
  }

  /// Smoothly animate camera to center on a specific node
  void _focusOnNode(GraphNode node) {
    _cameraAnimController?.stop();
    _cameraAnimController?.dispose();

    final size = MediaQuery.of(context).size;
    const targetScale = 1.65;
    final currentMatrix = _transformController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final tx0 = currentMatrix.storage[12];
    final ty0 = currentMatrix.storage[13];

    final targetTx = size.width / 2 - node.position.dx * targetScale;
    final targetTy = size.height / 2 - node.position.dy * targetScale;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _cameraAnimController = controller;

    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    controller.addListener(() {
      final t = curved.value;
      final s = currentScale + (targetScale - currentScale) * t;
      final tx = tx0 + (targetTx - tx0) * t;
      final ty = ty0 + (targetTy - ty0) * t;

      final m = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setTranslationRaw(tx, ty, 0.0);
      _transformController.value = m;
    });

    controller.forward().then((_) {
      if (_cameraAnimController == controller) {
        _cameraAnimController = null;
        controller.dispose();
      }
    });

    setState(() {
      _selectedNodeId = node.id;
      _selectedNeighbors = _physicsEngine.getNeighbors(node.id);
    });
  }

  // ─── Direct Touch & Obsidian Dot Dragging ──────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    _pointerDownLocal = event.localPosition;
    _hasDraggedPointer = false;

    if (_activePointers == 1) {
      final scenePoint = _transformController.toScene(event.localPosition);

      // Hit-test with generous touch radius (30px)
      final hitNode = _physicsEngine.hitTest(scenePoint, hitPadding: 26.0);

      if (hitNode != null) {
        HapticFeedback.lightImpact();
        _draggedNodeId = hitNode.id;
        _physicsEngine.dragNode(hitNode.id, scenePoint);
        _wakePhysics();

        // Disable InteractiveViewer pan so user drags the dot itself!
        setState(() {
          _isPanEnabled = false;
        });
      } else {
        _draggedNodeId = null;
        if (!_isPanEnabled) {
          setState(() {
            _isPanEnabled = true;
          });
        }
      }
    } else {
      // Multi-touch (pinch-to-zoom): cancel dot dragging
      if (_draggedNodeId != null) {
        _physicsEngine.releaseNode(_draggedNodeId!);
        _draggedNodeId = null;
      }
      if (!_isPanEnabled) {
        setState(() {
          _isPanEnabled = true;
        });
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownLocal != null) {
      final moveDist = (event.localPosition - _pointerDownLocal!).distance;
      if (moveDist > 6.0) {
        _hasDraggedPointer = true;
      }
    }

    if (_draggedNodeId != null && _activePointers == 1) {
      final scenePoint = _transformController.toScene(event.localPosition);

      // Move dragged dot in physics engine: pulls connected springs in real-time!
      _physicsEngine.dragNode(_draggedNodeId!, scenePoint);
      _wakePhysics();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = max(0, _activePointers - 1);

    if (_draggedNodeId != null) {
      final releasedId = _draggedNodeId!;
      if (!_hasDraggedPointer) {
        // Tap on node: select & show card
        HapticFeedback.selectionClick();
        setState(() {
          _selectedNodeId = releasedId;
          _selectedNeighbors = _physicsEngine.getNeighbors(releasedId);
          _draggedNodeId = null;
          _isPanEnabled = true;
        });
        _wakePhysics(impulse: 0.3);
      } else {
        // Drag completed: release dot with organic spring settling
        _physicsEngine.releaseNode(releasedId, Offset.zero);
        setState(() {
          _draggedNodeId = null;
          _isPanEnabled = true;
        });
        _wakePhysics(impulse: 0.6);
      }
    } else {
      // Tapped empty background: dismiss selection
      if (!_hasDraggedPointer && _selectedNodeId != null) {
        setState(() {
          _selectedNodeId = null;
          _selectedNeighbors = const {};
        });
      }
      if (!_isPanEnabled) {
        setState(() {
          _isPanEnabled = true;
        });
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = max(0, _activePointers - 1);
    if (_draggedNodeId != null) {
      _physicsEngine.releaseNode(_draggedNodeId!);
      _draggedNodeId = null;
    }
    if (!_isPanEnabled) {
      setState(() {
        _isPanEnabled = true;
      });
    }
  }

  void _openSearchSheet(AppTheme theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _GraphSearchSheet(
        nodes: _physicsEngine.nodes.values.toList(),
        theme: theme,
        onSelectNode: (node) {
          Navigator.of(ctx).pop();
          _focusOnNode(node);
        },
      ),
    );
  }

  void _openThemePicker(BuildContext context, AppTheme currentTheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ThemePickerSheet(
        currentTheme: currentTheme,
        onSelectTheme: (newTheme) async {
          HapticFeedback.selectionClick();
          U.applyTheme(newTheme.key);
          await CacheService().saveAppSetting('theme_accent', newTheme.key);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  void dispose() {
    _cameraAnimController?.dispose();
    _ticker?.dispose();
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _usersSubscription?.cancel();
    _followsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: appThemeNotifier,
      builder: (context, theme, _) {
        final selectedNode = _selectedNodeId != null
            ? _physicsEngine.nodes[_selectedNodeId]
            : null;

        final canvasBg = theme.isDark
            ? (theme.bg == Colors.black ? const Color(0xFF080B12) : theme.bg)
            : theme.bg;

        return Scaffold(
          backgroundColor: canvasBg,
          body: Stack(
            children: [
              // ── 1. Full-screen Interactive Graph Canvas ────────────────────
              if (_isLoading)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const UtopiaLoader(),
                      const SizedBox(height: 18),
                      Text(
                        'Generating campus link graph...',
                        style: GoogleFonts.outfit(
                          color: theme.sub,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 0.12,
                    maxScale: 4.8,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    panEnabled: _isPanEnabled,
                    scaleEnabled: true,
                    child: SizedBox(
                      width: 5000,
                      height: 5000,
                      child: CustomPaint(
                        painter: LinkGraphPainter(
                          nodes: _physicsEngine.nodes,
                          edges: _physicsEngine.edges,
                          theme: theme,
                          selectedNodeId: _selectedNodeId,
                          draggedNodeId: _draggedNodeId,
                          selectedNeighbors: _selectedNeighbors,
                          currentScale: _currentScale,
                        ),
                      ),
                    ),
                  ),
                ),

              // ── 2. Floating Top Navigation Bar (Clean & Borderless) ─────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: (theme.isDark ? theme.surface : Colors.white)
                                .withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: theme.isDark ? 0.20 : 0.04),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Back / Return Button (crossfades back)
                              _M3IconButton(
                                icon: Icons.arrow_back_rounded,
                                tooltip: 'Back to People',
                                theme: theme,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).pop();
                                },
                              ),
                              const SizedBox(width: 12),

                              // Title & Physics Indicator (No glow)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Link Graph',
                                          style: GoogleFonts.outfit(
                                            color: theme.text,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: theme.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: theme.primary.withValues(alpha: 0.3),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            'BETA',
                                            style: GoogleFonts.robotoFlex(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w700,
                                              color: theme.primary,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          width: 6.5,
                                          height: 6.5,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _physicsEngine.isSleeping
                                                ? theme.dim.withValues(alpha: 0.4)
                                                : theme.teal,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_physicsEngine.nodeCount} students · ${_physicsEngine.edgeCount} mutual links',
                                      style: GoogleFonts.outfit(
                                        color: theme.sub,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Theme Switcher Button
                              _M3IconButton(
                                icon: Icons.palette_outlined,
                                tooltip: 'Theme Settings',
                                theme: theme,
                                onTap: () => _openThemePicker(context, theme),
                              ),
                              const SizedBox(width: 8),

                              // Search Student Button
                              _M3IconButton(
                                icon: Icons.search_rounded,
                                tooltip: 'Search Student',
                                theme: theme,
                                onTap: () => _openSearchSheet(theme),
                              ),
                              const SizedBox(width: 8),

                              // Exit Toggle Button
                              _M3IconButton(
                                icon: Icons.hub_rounded,
                                tooltip: 'Exit Graph Mode',
                                isActive: true,
                                theme: theme,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 3. Floating Action Toolbar (Clean & Borderless) ─────────────
              Positioned(
                right: 16,
                bottom: selectedNode != null ? 220 : 32,
                child: SafeArea(
                  top: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 7),
                        decoration: BoxDecoration(
                          color: (theme.isDark ? theme.surface : Colors.white)
                              .withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                  alpha: theme.isDark ? 0.20 : 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Center / Fit Graph Button
                            _ActionToolbarItem(
                              icon: Icons.filter_center_focus_rounded,
                              tooltip: 'Center View',
                              theme: theme,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _centerCameraOnGraph();
                              },
                            ),
                            const SizedBox(height: 4),

                            // Re-simulate / Shake Layout Button
                            _ActionToolbarItem(
                              icon: Icons.auto_awesome_rounded,
                              tooltip: 'Re-simulate Physics',
                              theme: theme,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                _wakePhysics(impulse: 2.2);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 4. Selected User Preview Card (Bottom Floating Pill) ──────
              if (selectedNode != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: SafeArea(
                    top: false,
                    child: _SelectedUserCard(
                      node: selectedNode,
                      userData: _userDocs[selectedNode.id] ?? {},
                      currentUid: _currentUid,
                      theme: theme,
                      onClose: () {
                        setState(() {
                          _selectedNodeId = null;
                          _selectedNeighbors = const {};
                        });
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Material 3 HUD icon button with full theme support
class _M3IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;
  final AppTheme theme;

  const _M3IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.theme,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: M3Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isActive
                ? theme.primary.withValues(alpha: 0.16)
                : (theme.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? theme.primary : theme.text,
          ),
        ),
      ),
    );
  }
}

/// Compact vertical action toolbar button
class _ActionToolbarItem extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppTheme theme;

  const _ActionToolbarItem({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: M3Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 19,
            color: theme.sub,
          ),
        ),
      ),
    );
  }
}

/// Spacious, clean glassmorphic preview card for a selected node (Zero strokes, Zero glows)
class _SelectedUserCard extends StatelessWidget {
  final GraphNode node;
  final Map<String, dynamic> userData;
  final String currentUid;
  final AppTheme theme;
  final VoidCallback onClose;

  const _SelectedUserCard({
    required this.node,
    required this.userData,
    required this.currentUid,
    required this.theme,
    required this.onClose,
  });

  void _openProfile(BuildContext context, String email, String? photoUrl) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      buildForwardRoute(
        UserProfileScreen(
          uid: node.id,
          displayName: node.name,
          email: email,
          photoUrl: photoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = node.avatarUrl;
    final isMe = node.id == currentUid;
    final branch = (userData['branch'] ?? node.branch ?? '').toString().trim();
    final email = (userData['email'] ?? '').toString().trim();

    // Social links
    final instagramId = (userData['instagramId'] ?? '').toString().trim();
    final githubId = (userData['githubId'] ?? userData['githubUsername'] ?? '')
        .toString()
        .trim();
    final discordId =
        (userData['discordId'] ?? userData['discordUsername'] ?? '')
            .toString()
            .trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (theme.isDark ? theme.surface : Colors.white)
                .withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: theme.isDark ? 0.25 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Tappable Avatar
                  M3Pressable(
                    onTap: () => _openProfile(context, email, photoUrl),
                    borderRadius: BorderRadius.circular(25),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: node.color.withValues(alpha: 0.2),
                      ),
                      child: ClipOval(
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => _buildFallbackInitial(),
                              )
                            : _buildFallbackInitial(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Tappable Name & Subtitles (Opens User Profile)
                  Expanded(
                    child: M3Pressable(
                      onTap: () => _openProfile(context, email, photoUrl),
                      borderRadius: BorderRadius.circular(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  node.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: theme.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: theme.sub.withValues(alpha: 0.6),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.teal.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'You',
                                    style: GoogleFonts.outfit(
                                      color: theme.teal,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            branch.isNotEmpty
                                ? branch
                                : (email.isNotEmpty ? email : 'Campus Member'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: theme.sub,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (instagramId.isNotEmpty ||
                              githubId.isNotEmpty ||
                              discordId.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (instagramId.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: InstagramBadge(
                                        handle: instagramId,
                                        iconSize: 12,
                                        compact: true),
                                  ),
                                if (githubId.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: GithubBadge(
                                        handle: githubId,
                                        iconSize: 12,
                                        compact: true),
                                  ),
                                if (discordId.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: DiscordBadge(
                                        handle: discordId,
                                        iconSize: 12,
                                        compact: true),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Dismiss Button
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: theme.sub, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Bottom Actions Row (Clean, minimal connection count pill)
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hub_outlined,
                            color: theme.primary, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${node.degree} ${node.degree == 1 ? 'connection' : 'connections'}',
                          style: GoogleFonts.outfit(
                            color: theme.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackInitial() {
    final initial =
        node.name.isNotEmpty ? node.name.trim()[0].toUpperCase() : 'U';
    return Container(
      color: node.color.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Search Modal Sheet to search and smoothly fly-to node
class _GraphSearchSheet extends StatefulWidget {
  final List<GraphNode> nodes;
  final AppTheme theme;
  final ValueChanged<GraphNode> onSelectNode;

  const _GraphSearchSheet({
    required this.nodes,
    required this.theme,
    required this.onSelectNode,
  });

  @override
  State<_GraphSearchSheet> createState() => _GraphSearchSheetState();
}

class _GraphSearchSheetState extends State<_GraphSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<GraphNode> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.nodes;
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      setState(() {
        if (q.isEmpty) {
          _filtered = widget.nodes;
        } else {
          _filtered = widget.nodes.where((n) {
            final name = n.name.toLowerCase();
            final branch = (n.branch ?? '').toLowerCase();
            return name.contains(q) || branch.contains(q);
          }).toList();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: theme.isDark ? theme.surface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.sub.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Search Input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: theme.isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: GoogleFonts.outfit(color: theme.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search campus member...',
                      hintStyle: GoogleFonts.outfit(
                          color: theme.dim, fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: theme.sub, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

              // Result List
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final node = _filtered[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 19,
                        backgroundColor: node.color.withValues(alpha: 0.35),
                        backgroundImage: node.avatarUrl != null &&
                                node.avatarUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(node.avatarUrl!)
                            : null,
                        child: node.avatarUrl == null ||
                                node.avatarUrl!.isEmpty
                            ? Text(
                                node.name.isNotEmpty
                                    ? node.name[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(
                        node.name,
                        style: GoogleFonts.outfit(
                          color: theme.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        node.branch ?? 'Campus Member',
                        style: GoogleFonts.outfit(
                          color: theme.sub,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${node.degree} links',
                          style: GoogleFonts.outfit(
                            color: theme.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      onTap: () => widget.onSelectNode(node),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Material 3 Theme Picker Modal Sheet to switch theme on the fly
class _ThemePickerSheet extends StatelessWidget {
  final AppTheme currentTheme;
  final ValueChanged<AppTheme> onSelectTheme;

  const _ThemePickerSheet({
    required this.currentTheme,
    required this.onSelectTheme,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.60,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: currentTheme.isDark ? currentTheme.surface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: currentTheme.sub.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.palette_rounded, color: currentTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'GRAPH THEME',
                      style: GoogleFonts.outfit(
                        color: currentTheme.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: appThemes.length,
                  itemBuilder: (ctx, i) {
                    final t = appThemes[i];
                    final isSelected = t.key == currentTheme.key;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: M3Pressable(
                        onTap: () => onSelectTheme(t),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? t.primary.withValues(alpha: 0.16)
                                : (currentTheme.isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.03)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              // Theme Mini-Card Swatch
                              Container(
                                width: 32,
                                height: 32,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: t.bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: t.border,
                                    width: 1.2,
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: t.card,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: t.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.label,
                                      style: GoogleFonts.outfit(
                                        color: currentTheme.text,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      t.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: currentTheme.sub,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (isSelected)
                                Icon(Icons.check_circle_rounded, color: t.primary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
