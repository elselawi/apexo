part of 'open_dicom_viewer_window.dart';

enum _MeasureMode { none, ruler, roi }

class _MeasureState {
  const _MeasureState({
    this.mode = _MeasureMode.none,
    this.start,
    this.end,
    this.stats,
    this.rulerMm,
  });
  final _MeasureMode mode;
  final Offset? start;
  final Offset? end;
  final RoiStatistics? stats;
  final double? rulerMm;

  _MeasureState copyWith({
    _MeasureMode? mode,
    Offset? start,
    Offset? end,
    RoiStatistics? stats,
    double? rulerMm,
    bool clearStart = false,
    bool clearEnd = false,
    bool clearStats = false,
    bool clearRuler = false,
  }) =>
      _MeasureState(
        mode: mode ?? this.mode,
        start: clearStart ? null : (start ?? this.start),
        end: clearEnd ? null : (end ?? this.end),
        stats: clearStats ? null : (stats ?? this.stats),
        rulerMm: clearRuler ? null : (rulerMm ?? this.rulerMm),
      );
}

// ─── Dialog ───────────────────────────────────────────────────────

/// The scan itself: the image, its tools and its measurements, with no chrome
/// of its own — the window it is put in provides that.

class _MeasureOverlay extends StatelessWidget {
  const _MeasureOverlay({required this.measure, required this.imageSize});
  final _MeasureState measure;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
      final imgAspect = imageSize.width / imageSize.height;
      final widgetAspect = widgetSize.width / widgetSize.height;
      double displayW, displayH, offsetX, offsetY;
      if (imgAspect > widgetAspect) {
        displayW = widgetSize.width;
        displayH = widgetSize.width / imgAspect;
        offsetX = 0;
        offsetY = (widgetSize.height - displayH) / 2;
      } else {
        displayH = widgetSize.height;
        displayW = widgetSize.height * imgAspect;
        offsetX = (widgetSize.width - displayW) / 2;
        offsetY = 0;
      }
      return IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _MeasurePainter(
            measure: measure,
            displayW: displayW,
            displayH: displayH,
            offsetX: offsetX,
            offsetY: offsetY,
            imageW: imageSize.width,
            imageH: imageSize.height,
          ),
        ),
      );
    });
  }
}

class _MeasurePainter extends CustomPainter {
  _MeasurePainter({
    required this.measure,
    required this.displayW,
    required this.displayH,
    required this.offsetX,
    required this.offsetY,
    required this.imageW,
    required this.imageH,
  });
  final _MeasureState measure;
  final double displayW, displayH, offsetX, offsetY;
  final double imageW, imageH;
  static const _accent = Color(0xFF4CC2FF);

  Offset _toCanvas(Offset pixel) => Offset(
        pixel.dx / imageW * displayW + offsetX,
        pixel.dy / imageH * displayH + offsetY,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _accent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final start = measure.start;
    if (start == null) return;
    final s = _toCanvas(start);

    if (measure.mode == _MeasureMode.ruler) {
      _crosshair(canvas, s, paint);
      if (measure.end != null) {
        final e = _toCanvas(measure.end!);
        _crosshair(canvas, e, paint);
        canvas.drawLine(s, e, paint..strokeWidth = 1.5);
        if (measure.rulerMm != null) {
          _label(canvas, e, '${measure.rulerMm!.toStringAsFixed(1)} mm');
        }
      }
    }

    if (measure.mode == _MeasureMode.roi && measure.end != null) {
      final e = _toCanvas(measure.end!);
      final rect = Rect.fromPoints(s, e);
      canvas.drawRect(
          rect,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawRect(
          rect,
          paint
            ..color = _accent.withValues(alpha: 0.12)
            ..style = PaintingStyle.fill);
    }
  }

  void _crosshair(Canvas canvas, Offset c, Paint paint) {
    const r = 5.0;
    canvas.drawCircle(c, r, paint);
    canvas.drawLine(Offset(c.dx - r - 2, c.dy), Offset(c.dx + r + 2, c.dy),
        paint..strokeWidth = 1);
    canvas.drawLine(
        Offset(c.dx, c.dy - r - 2), Offset(c.dx, c.dy + r + 2), paint);
  }

  void _label(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 3, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 4.0, padY = 2.0;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pos.dx - padX, pos.dy - tp.height - padY,
                tp.width + padX * 2, tp.height + padY * 2),
            const Radius.circular(3)),
        Paint()..color = _accent.withValues(alpha: 0.8));
    tp.paint(canvas, Offset(pos.dx, pos.dy - tp.height - padY + 1));
  }

  @override
  bool shouldRepaint(covariant _MeasurePainter o) => measure != o.measure;
}
