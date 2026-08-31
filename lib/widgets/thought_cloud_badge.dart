import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../services/people_interaction_service.dart';

/// A fluidly animated, interactive Thought Cloud badge for active user statuses.
///
/// In mini mode: Sits in the top-right area (~30% occupancy) of an avatar,
/// displaying the vibe emoji with a whimsical thought-cloud trail.
///
/// When tapped: Spawns a fluidly animated, screen-bounded Overlay Thought Cloud
/// displaying full text, optional GIF/media, and location. It adaptively clamps
/// within the screen viewport (left/right/top/bottom) so nothing ever overflows
/// or clips off-screen.
///
/// When tapped outside: Minimizes back smoothly to the mini cloud state.
/// Tapping the underlying profile still opens the profile as usual.
class ThoughtCloudBadge extends StatefulWidget {
  const ThoughtCloudBadge({
    super.key,
    required this.vibe,
    this.avatarRadius = 34,
    this.compact = false,
    this.onExpandChanged,
  });

  final CampusVibe? vibe;
  final double avatarRadius;
  final bool compact;
  final ValueChanged<bool>? onExpandChanged;

  @override
  State<ThoughtCloudBadge> createState() => _ThoughtCloudBadgeState();
}

class _ThoughtCloudBadgeState extends State<ThoughtCloudBadge> {
  OverlayEntry? _overlayEntry;
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant ThoughtCloudBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vibe == null && _isExpanded) {
      _closeOverlay();
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isExpanded = false;
  }

  void _closeOverlay() {
    if (!_isExpanded || _overlayEntry == null) return;
    _isExpanded = false;
    widget.onExpandChanged?.call(false);
    if (mounted) setState(() {});
  }

  void _toggleExpand() {
    HapticFeedback.selectionClick();
    if (_isExpanded) {
      _closeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final vibe = widget.vibe;
    if (vibe == null || vibe.isExpired) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final badgeOffset = renderBox.localToGlobal(Offset.zero);
    final badgeSize = renderBox.size;

    _removeOverlay();
    _isExpanded = true;
    widget.onExpandChanged?.call(true);
    if (mounted) setState(() {});

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _ThoughtCloudOverlayWidget(
        vibe: vibe,
        badgeOffset: badgeOffset,
        badgeSize: badgeSize,
        onDismiss: () {
          _closeOverlay();
          _removeOverlay();
        },
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final vibe = widget.vibe;
    if (vibe == null || vibe.isExpired || vibe.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final isCompact = widget.compact || widget.avatarRadius < 28;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleExpand,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topRight,
        children: [
          // ── Thought Bubble Trail (Two trailing circles pointing to avatar) ──
          Positioned(
            bottom: -3.5,
            left: isCompact ? -1 : 2,
            child: Container(
              width: isCompact ? 5.5 : 7.0,
              height: isCompact ? 5.5 : 7.0,
              decoration: BoxDecoration(
                color: U.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: U.primary.withValues(alpha: 0.5),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -7.5,
            left: isCompact ? -5 : -3,
            child: Container(
              width: isCompact ? 3.5 : 4.5,
              height: isCompact ? 3.5 : 4.5,
              decoration: BoxDecoration(
                color: U.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: U.primary.withValues(alpha: 0.4),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // ── Mini Cloud Badge (Top-Right ~30% occupancy) ──
          Material(
            color: Colors.transparent,
            elevation: 2.5,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: BoxConstraints(
                minWidth: isCompact ? 28 : 34,
                maxWidth: isCompact ? 38 : 44,
                minHeight: isCompact ? 22 : 26,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 4.5 : 6,
                vertical: isCompact ? 3 : 4,
              ),
              decoration: BoxDecoration(
                color: U.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isExpanded
                      ? U.primary
                      : U.primary.withValues(alpha: 0.45),
                  width: _isExpanded ? 1.5 : 1.1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    vibe.emoji.isNotEmpty ? vibe.emoji : '💭',
                    style: TextStyle(
                      fontSize: isCompact ? 11.5 : 13.5,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// EXPANDED THOUGHT CLOUD OVERLAY (Full-Screen Edge-Bounded)
// ────────────────────────────────────────────────────────────────────────────
class _ThoughtCloudOverlayWidget extends StatefulWidget {
  const _ThoughtCloudOverlayWidget({
    required this.vibe,
    required this.badgeOffset,
    required this.badgeSize,
    required this.onDismiss,
  });

  final CampusVibe vibe;
  final Offset badgeOffset;
  final Size badgeSize;
  final VoidCallback onDismiss;

  @override
  State<_ThoughtCloudOverlayWidget> createState() =>
      _ThoughtCloudOverlayWidgetState();
}

class _ThoughtCloudOverlayWidgetState extends State<_ThoughtCloudOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInOutCubic,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    HapticFeedback.lightImpact();
    _animController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;

    // Cloud width is constrained to stay comfortably inside the screen
    final cloudWidth = (screenWidth * 0.70).clamp(200.0, 260.0);

    // Target badge center
    final badgeCenterX = widget.badgeOffset.dx + widget.badgeSize.width / 2;

    // Calculate safe X position (never touch or overflow left/right screen edges)
    double cloudLeft;
    Alignment scaleAlignment;

    if (badgeCenterX < screenWidth * 0.45) {
      // Badge is on the left side: align left edge near badge, expand rightwards
      cloudLeft = widget.badgeOffset.dx - 12;
      scaleAlignment = Alignment.topLeft;
    } else {
      // Badge is on the right side: align right edge near badge, expand leftwards
      cloudLeft = widget.badgeOffset.dx + widget.badgeSize.width - cloudWidth + 12;
      scaleAlignment = Alignment.topRight;
    }

    // Clamp strictly within 14px margins of the screen width
    cloudLeft = cloudLeft.clamp(14.0, screenWidth - cloudWidth - 14.0);

    // Calculate safe Y position (place above badge if space permits, else below)
    final hasSpaceAbove = widget.badgeOffset.dy - topPadding > 150;
    double cloudTop;

    if (hasSpaceAbove) {
      cloudTop = widget.badgeOffset.dy - 12; // anchor near top of badge
      scaleAlignment = badgeCenterX < screenWidth * 0.45
          ? Alignment.bottomLeft
          : Alignment.bottomRight;
    } else {
      cloudTop = widget.badgeOffset.dy + widget.badgeSize.height + 6;
      scaleAlignment = badgeCenterX < screenWidth * 0.45
          ? Alignment.topLeft
          : Alignment.topRight;
    }

    // Clamp Y to remain completely within screen safe areas
    cloudTop = cloudTop.clamp(
      topPadding + 10.0,
      screenHeight - bottomPadding - 280.0,
    );

    final hasMedia = widget.vibe.mediaUrl != null &&
        widget.vibe.mediaUrl!.isNotEmpty;

    return Stack(
      children: [
        // ── Full-Screen Transparent Barrier (Click outside to dismiss) ──
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleDismiss,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),

        // ── Animated Screen-Bounded Thought Cloud ──
        Positioned(
          left: cloudLeft,
          top: cloudTop,
          width: cloudWidth,
          child: ScaleTransition(
            scale: _scaleAnimation,
            alignment: scaleAlignment,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                onTap: _handleDismiss, // Tapping cloud itself closes it
                child: Material(
                  color: Colors.transparent,
                  elevation: 10,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: U.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: U.primary.withValues(alpha: 0.55),
                        width: 1.3,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row
                        Row(
                          children: [
                            Text(
                              widget.vibe.emoji.isNotEmpty
                                  ? widget.vibe.emoji
                                  : '💭',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Thoughts',
                                style: GoogleFonts.outfit(
                                  color: U.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: U.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: U.border,
                                  width: 0.6,
                                ),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: U.sub,
                              ),
                            ),
                          ],
                        ),

                        // Thought text
                        if (widget.vibe.text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.vibe.text,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: GoogleFonts.outfit(
                              color: U.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],

                        // GIF / Image Media Preview (if present)
                        if (hasMedia) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(
                                maxHeight: 110,
                              ),
                              width: double.infinity,
                              color: U.surface,
                              child: CachedNetworkImage(
                                imageUrl: widget.vibe.mediaUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  height: 80,
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        U.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 60,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.broken_image_rounded,
                                    size: 20,
                                    color: U.sub,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],

                        // Location
                        if (widget.vibe.location != null &&
                            widget.vibe.location!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 11,
                                color: U.sub,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  widget.vibe.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: U.sub,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
