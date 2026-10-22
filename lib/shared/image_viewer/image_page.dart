import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' hide Colors, IconButton;

import 'drawing_canvas.dart';

/// One page of the viewer: a photo you can pinch, pan and double-tap back to
/// fit, with the pen's strokes drawn over it.
///
/// It reports the scale it is at, because a zoomed photo must not be swiped
/// away from — the drag belongs to the photo, not to the pages beside it.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.image,
    required this.onScaleChanged,
    this.drawing,
    this.onSaveDrawing,
    this.isDrawingMode = false,
    this.showDrawings = true,
    required this.selectedColor,
    this.isEraserMode = false,
  });

  /// The photo itself, already resolved: loading it is the loader's business.
  final ImageProvider image;

  /// The drawing already stored on this photo, in `DrawingCanvas`'s own format.
  final String? drawing;

  /// Saves a new drawing. Null means this photo is not drawn on at all, and no
  /// pen layer is put over it.
  final void Function(String)? onSaveDrawing;

  final bool isDrawingMode;
  final bool showDrawings;
  final Color selectedColor;
  final bool isEraserMode;

  /// How far the photo is zoomed, after every gesture and every double tap.
  final ValueChanged<double> onScaleChanged;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;

  /// The zoom a double tap takes the photo to, and the zoom it is already past
  /// when a double tap means "back to fit".
  static const double _doubleTapScale = 2.0;

  final TransformationController _zoom = TransformationController();
  late final AnimationController _animation = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );
  Animation<Matrix4>? _zooming;
  TapDownDetails _doubleTapAt = TapDownDetails();

  /// The photo's own shape, once it is known.
  ///
  /// The pen's strokes are stored against the photo, not against the box the
  /// photo is shown in: a photo that is letterboxed would otherwise have its
  /// annotations drawn over the bars beside it. Knowing the photo's shape lets
  /// the photo be drawn at exactly that shape, so the strokes land on it.
  double? _aspectRatio;

  /// The photo whose shape has been asked for, so it is not asked twice.
  ImageProvider? _measured;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The photo's shape is read from the screen it is shown on, so it can only
    // be asked for once the inherited widgets are there.
    _resolveAspectRatio();
  }

  @override
  void didUpdateWidget(covariant ImageViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _aspectRatio = null;
      _measured = null;
      _resolveAspectRatio();
    }
    // The pen takes the drag away from the photo, so a photo that was zoomed
    // in is put back to fit when the pen is put away — otherwise it stays
    // stuck zoomed, with no way to pan it.
    if (oldWidget.isDrawingMode && !widget.isDrawingMode) {
      _animation.stop();
      _zooming = null;
      _zoom.value = Matrix4.identity();
      // The viewer owns the zoom lock, and it is being built right now: the
      // news waits for the frame to finish.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onScaleChanged(1.0);
      });
    }
  }

  /// Asks the photo how big it is.
  void _resolveAspectRatio() {
    if (_measured == widget.image) return;
    _measured = widget.image;
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    stream.addListener(ImageStreamListener((info, _) {
      final width = info.image.width;
      final height = info.image.height;
      if (width <= 0 || height <= 0) return;
      final ratio = width / height;
      if (ratio.isNaN || ratio.isInfinite) return;
      if (!mounted) return;
      setState(() => _aspectRatio = ratio);
    }));
  }

  @override
  void dispose() {
    _animation.dispose();
    _zoom.dispose();
    _zooming
      ?..removeListener(_followAnimation)
      ..removeStatusListener(_reportAnimationEnd);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _photo();

    final saveDrawing = widget.onSaveDrawing;
    if (saveDrawing != null) {
      content = Stack(
        fit: StackFit.loose,
        children: [
          content,
          Positioned.fill(
            child: DrawingCanvas(
              initialDrawing: widget.drawing,
              onSave: saveDrawing,
              isDrawingMode: widget.isDrawingMode,
              showDrawings: widget.showDrawings,
              selectedColor: widget.selectedColor,
              isEraserMode: widget.isEraserMode,
            ),
          ),
        ],
      );
    }

    final zoomed = SizedBox.expand(
      child: InteractiveViewer(
        transformationController: _zoom,
        minScale: _minScale,
        maxScale: _maxScale,
        // While the pen is out, the drag draws instead of moving the photo.
        panEnabled: !widget.isDrawingMode,
        scaleEnabled: !widget.isDrawingMode,
        onInteractionEnd: (_) =>
            widget.onScaleChanged(_zoom.value.getMaxScaleOnAxis()),
        child: Center(child: content),
      ),
    );

    if (widget.isDrawingMode) return zoomed;
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapAt = details,
      onDoubleTap: _toggleZoom,
      child: zoomed,
    );
  }

  /// The photo, while it loads and if it never arrives.
  ///
  /// A photo fades in once it is ready rather than popping in, and a broken one
  /// says so in its own page: one unreadable file must not take the whole
  /// viewer down with it.
  Widget _photo() {
    final image = Image(
      image: widget.image,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        return IndexedStack(
          index: 1,
          alignment: Alignment.center,
          children: [
            child,
            CircularProgressIndicator(
              value:
                  total == null ? null : progress.cumulativeBytesLoaded / total,
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, color: Colors.red, size: 120),
          Txt(
            txt('couldNotOpenImage'),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
    final ratio = _aspectRatio;
    if (ratio == null) return image;
    // The photo at its own shape, so that it fills the box the pen's strokes
    // are drawn in: a letterboxed photo would have its annotations drawn over
    // the bars beside it.
    return AspectRatio(aspectRatio: ratio, child: image);
  }

  void _toggleZoom() {
    final scale = _zoom.value.getMaxScaleOnAxis();
    final beginIn = scale < _doubleTapScale;

    final Matrix4 begin;
    final Matrix4 end;
    if (beginIn) {
      final at = _doubleTapAt.localPosition;
      begin = _zoom.value;
      end = Matrix4.identity()
        ..translateByDouble(-at.dx, -at.dy, 0.0, 1.0)
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1.0, 1.0);
    } else {
      begin = Matrix4.identity();
      end = _zoom.value;
    }

    _zooming
      ?..removeListener(_followAnimation)
      ..removeStatusListener(_reportAnimationEnd);
    _zooming = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeInOut),
    )
      ..addListener(_followAnimation)
      ..addStatusListener(_reportAnimationEnd);

    if (beginIn) {
      _animation.forward(from: 0.0);
    } else {
      _animation.reverse(from: 1.0);
    }
  }

  void _followAnimation() {
    _zoom.value = _zooming?.value ?? Matrix4.identity();
  }

  void _reportAnimationEnd(AnimationStatus status) {
    if (status case AnimationStatus.completed || AnimationStatus.dismissed) {
      widget.onScaleChanged(_zoom.value.getMaxScaleOnAxis());
    }
  }
}
