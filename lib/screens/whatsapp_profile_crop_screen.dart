import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

/// Full-screen WhatsApp-style profile picture cropper.
///
/// Provides a circular crop aperture, darkened scrim, dynamic rule-of-thirds
/// alignment grid, multi-touch pan and pinch-to-zoom, 90-degree rotation,
/// horizontal flip, and high-resolution Skia canvas export.
class WhatsAppProfileCropScreen extends StatefulWidget {
  const WhatsAppProfileCropScreen({
    super.key,
    required this.imageFile,
  });

  final File imageFile;

  @override
  State<WhatsAppProfileCropScreen> createState() =>
      _WhatsAppProfileCropScreenState();
}

class _WhatsAppProfileCropScreenState extends State<WhatsAppProfileCropScreen>
    with SingleTickerProviderStateMixin {
  ui.Image? _uiImage;
  bool _isLoading = true;
  String? _errorMessage;

  // Viewport & crop geometry
  Size _viewportSize = Size.zero;
  double _cropRadius = 140.0;
  Offset _cropCenter = Offset.zero;

  // Transform states
  double _scale = 1.0;
  double _minScale = 1.0;
  Offset _offset = Offset.zero;
  int _quarterTurns = 0; // 0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°
  bool _isFlipped = false;

  // Gesture tracking
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocalPoint = Offset.zero;

  // Grid fade state
  bool _showGrid = false;
  Timer? _gridTimer;

  // Export state
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _gridTimer?.cancel();
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _uiImage = frame.image;
        _isLoading = false;
      });
      _initTransformIfReady();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load image: $e';
        _isLoading = false;
      });
    }
  }

  void _initTransformIfReady() {
    if (_uiImage == null || _viewportSize == Size.zero) return;

    final imgW = _uiImage!.width.toDouble();
    final imgH = _uiImage!.height.toDouble();

    // Responsive crop circle diameter
    final maxD = math.min(_viewportSize.width - 48, _viewportSize.height - 48);
    _cropRadius = (maxD / 2).clamp(90.0, 220.0);
    _cropCenter = Offset(_viewportSize.width / 2, _viewportSize.height / 2);

    final isTransposed = _quarterTurns % 2 == 1;
    final effW = isTransposed ? imgH : imgW;
    final effH = isTransposed ? imgW : imgH;

    // Minimum scale required so that the image completely fills the 2R x 2R crop circle
    final scaleW = (2 * _cropRadius) / effW;
    final scaleH = (2 * _cropRadius) / effH;
    _minScale = math.max(scaleW, scaleH);

    _scale = _minScale;
    _offset = Offset.zero;
  }

  void _clampOffset() {
    if (_uiImage == null) return;
    final imgW = _uiImage!.width.toDouble();
    final imgH = _uiImage!.height.toDouble();

    final isTransposed = _quarterTurns % 2 == 1;
    final effW = isTransposed ? imgH : imgW;
    final effH = isTransposed ? imgW : imgH;

    final maxOffsetX = math.max(0.0, (effW * _scale / 2) - _cropRadius);
    final maxOffsetY = math.max(0.0, (effH * _scale / 2) - _cropRadius);

    final clampedX = _offset.dx.clamp(-maxOffsetX, maxOffsetX);
    final clampedY = _offset.dy.clamp(-maxOffsetY, maxOffsetY);

    _offset = Offset(clampedX, clampedY);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocalPoint = details.localFocalPoint;

    _triggerGridVisibility();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_startScale * details.scale).clamp(_minScale, _minScale * 5.0);
      _offset = _startOffset + (details.localFocalPoint - _startFocalPoint);
      _clampOffset();
    });
    _triggerGridVisibility();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _scheduleGridHide();
  }

  void _triggerGridVisibility() {
    _gridTimer?.cancel();
    if (!_showGrid) {
      setState(() => _showGrid = true);
    }
  }

  void _scheduleGridHide() {
    _gridTimer?.cancel();
    _gridTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _showGrid) {
        setState(() => _showGrid = false);
      }
    });
  }

  void _rotateQuarterTurn() {
    HapticFeedback.lightImpact();
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;

      final imgW = _uiImage!.width.toDouble();
      final imgH = _uiImage!.height.toDouble();
      final isTransposed = _quarterTurns % 2 == 1;
      final effW = isTransposed ? imgH : imgW;
      final effH = isTransposed ? imgW : imgH;

      final scaleW = (2 * _cropRadius) / effW;
      final scaleH = (2 * _cropRadius) / effH;
      _minScale = math.max(scaleW, scaleH);

      if (_scale < _minScale) {
        _scale = _minScale;
      }
      _clampOffset();
    });
    _triggerGridVisibility();
    _scheduleGridHide();
  }

  void _flipHorizontal() {
    HapticFeedback.lightImpact();
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _quarterTurns = 0;
      _isFlipped = false;
      _initTransformIfReady();
    });
  }

  Future<void> _cropAndFinish() async {
    if (_uiImage == null || _isCropping) return;
    setState(() => _isCropping = true);
    HapticFeedback.mediumImpact();

    try {
      const int outputSize = 1024;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble()),
      );

      final cropRect = Rect.fromCircle(
        center: _cropCenter,
        radius: _cropRadius,
      );

      // Map on-screen cropRect [cropRect.left, cropRect.top, 2R, 2R]
      // to the output canvas [0, 0, outputSize, outputSize]
      final scaleFactor = outputSize / (2 * _cropRadius);
      canvas.scale(scaleFactor, scaleFactor);
      canvas.translate(-cropRect.left, -cropRect.top);

      // Apply the user's interactive transformations
      final imgW = _uiImage!.width.toDouble();
      final imgH = _uiImage!.height.toDouble();

      canvas.save();
      canvas.translate(_cropCenter.dx + _offset.dx, _cropCenter.dy + _offset.dy);
      canvas.rotate(_quarterTurns * math.pi / 2);
      if (_isFlipped) {
        canvas.scale(-1, 1);
      }
      canvas.scale(_scale, _scale);
      canvas.drawImage(
        _uiImage!,
        Offset(-imgW / 2, -imgH / 2),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(outputSize, outputSize);
      final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to encode cropped image to PNG.');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final outputFile = File(
        '${tempDir.path}/cropped_avatar_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await outputFile.writeAsBytes(pngBytes);

      if (mounted) {
        Navigator.of(context).pop(outputFile);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFE53935),
            content: Text(
              'Error cropping image: $e',
              style: GoogleFonts.robotoFlex(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1317), // WhatsApp dark background
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            _buildTopBar(),

            // Interactive Crop Viewport
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A884)),
                        strokeWidth: 2.5,
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.robotoFlex(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final newSize = Size(constraints.maxWidth, constraints.maxHeight);
                            if (_viewportSize != newSize) {
                              _viewportSize = newSize;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(_initTransformIfReady);
                                }
                              });
                            }

                            final cropRect = Rect.fromCircle(
                              center: _cropCenter,
                              radius: _cropRadius,
                            );

                            return GestureDetector(
                              onScaleStart: _onScaleStart,
                              onScaleUpdate: _onScaleUpdate,
                              onScaleEnd: _onScaleEnd,
                              onDoubleTap: () {
                                setState(() {
                                  if (_scale > _minScale * 1.2) {
                                    _scale = _minScale;
                                    _offset = Offset.zero;
                                  } else {
                                    _scale = (_minScale * 2.0).clamp(_minScale, _minScale * 5.0);
                                  }
                                  _clampOffset();
                                });
                                _triggerGridVisibility();
                                _scheduleGridHide();
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // The transformed photo
                                  CustomPaint(
                                    painter: _WhatsAppImagePainter(
                                      image: _uiImage!,
                                      scale: _scale,
                                      offset: _offset,
                                      center: _cropCenter,
                                      quarterTurns: _quarterTurns,
                                      isFlipped: _isFlipped,
                                    ),
                                  ),

                                  // WhatsApp circular mask & dynamic 3x3 grid
                                  CustomPaint(
                                    painter: _WhatsAppCropOverlayPainter(
                                      cropRect: cropRect,
                                      showGrid: _showGrid,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Action Bar
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Cancel',
            onPressed: _isCropping ? null : () => Navigator.of(context).pop(null),
          ),
          const SizedBox(width: 8),
          Text(
            'Move and scale',
            style: GoogleFonts.robotoFlex(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.white70),
            tooltip: 'Reset',
            onPressed: _isCropping ? null : _reset,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF111B21),
        border: Border(
          top: BorderSide(color: Color(0xFF1F2C34), width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Cancel Text Button
          TextButton(
            onPressed: _isCropping ? null : () => Navigator.of(context).pop(null),
            child: Text(
              'Cancel',
              style: GoogleFonts.robotoFlex(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Action Buttons: Rotate & Flip
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.flip_rounded, color: Colors.white70, size: 22),
                tooltip: 'Flip horizontally',
                onPressed: _isCropping ? null : _flipHorizontal,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.rotate_90_degrees_cw_rounded, color: Colors.white, size: 23),
                tooltip: 'Rotate 90°',
                onPressed: _isCropping ? null : _rotateQuarterTurn,
              ),
            ],
          ),

          // WhatsApp Signature Done Button (Teal/Emerald)
          FilledButton.icon(
            onPressed: _isCropping ? null : _cropAndFinish,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00A884),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
            icon: _isCropping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              'Done',
              style: GoogleFonts.robotoFlex(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the photo onto the canvas applying user translation, rotation, flip, and zoom.
class _WhatsAppImagePainter extends CustomPainter {
  const _WhatsAppImagePainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.center,
    required this.quarterTurns,
    required this.isFlipped,
  });

  final ui.Image image;
  final double scale;
  final Offset offset;
  final Offset center;
  final int quarterTurns;
  final bool isFlipped;

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    canvas.save();
    canvas.translate(center.dx + offset.dx, center.dy + offset.dy);
    canvas.rotate(quarterTurns * math.pi / 2);
    if (isFlipped) {
      canvas.scale(-1, 1);
    }
    canvas.scale(scale, scale);
    canvas.drawImage(
      image,
      Offset(-imgW / 2, -imgH / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WhatsAppImagePainter old) {
    return old.scale != scale ||
        old.offset != offset ||
        old.center != center ||
        old.quarterTurns != quarterTurns ||
        old.isFlipped != isFlipped ||
        old.image != image;
  }
}

/// Paints the WhatsApp circular cutout scrim, crisp white circle border,
/// and rule-of-thirds grid lines that appear when interacting.
class _WhatsAppCropOverlayPainter extends CustomPainter {
  const _WhatsAppCropOverlayPainter({
    required this.cropRect,
    required this.showGrid,
  });

  final Rect cropRect;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Darkened outer mask with circular cutout (scrim)
    final outerPath = Path()..addRect(Offset.zero & size);
    final circlePath = Path()..addOval(cropRect);
    final scrimPath = Path.combine(PathOperation.difference, outerPath, circlePath);

    final scrimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;
    canvas.drawPath(scrimPath, scrimPaint);

    // 2. Crisp circular border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawOval(cropRect, borderPaint);

    // 3. WhatsApp Rule-of-Thirds Grid (3x3) inside circle
    if (showGrid) {
      canvas.save();
      // Clip to circle so grid lines stay strictly inside the circular crop aperture
      canvas.clipPath(circlePath);

      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      final stepX = cropRect.width / 3;
      final stepY = cropRect.height / 3;

      // Vertical lines
      canvas.drawLine(
        Offset(cropRect.left + stepX, cropRect.top),
        Offset(cropRect.left + stepX, cropRect.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(cropRect.left + stepX * 2, cropRect.top),
        Offset(cropRect.left + stepX * 2, cropRect.bottom),
        gridPaint,
      );

      // Horizontal lines
      canvas.drawLine(
        Offset(cropRect.left, cropRect.top + stepY),
        Offset(cropRect.right, cropRect.top + stepY),
        gridPaint,
      );
      canvas.drawLine(
        Offset(cropRect.left, cropRect.top + stepY * 2),
        Offset(cropRect.right, cropRect.top + stepY * 2),
        gridPaint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WhatsAppCropOverlayPainter old) {
    return old.cropRect != cropRect || old.showGrid != showGrid;
  }
}
