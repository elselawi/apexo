import 'dart:convert';
import 'package:flutter/material.dart';

/// Whether [drawing] holds anything worth drawing — the stored form of a photo
/// with no strokes on it is an empty list.
bool hasStrokes(String? drawing) =>
    drawing != null && drawing.isNotEmpty && drawing != '[]';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    this.initialDrawing,
    required this.onSave,
    this.isDrawingMode = false,
    this.showDrawings = true,
    this.selectedColor = Colors.red,
    this.isEraserMode = false,
  });
  final String? initialDrawing;
  final void Function(String) onSave;
  final bool isDrawingMode;
  final bool showDrawings;
  final Color selectedColor;
  final bool isEraserMode;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class Stroke {
  Stroke({
    required this.points,
    required this.color,
    this.isEraser = false,
    this.strokeWidth = 3.0,
  });

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      points: (json['points'] as List<dynamic>)
          .map((p) => _point(p as Map<String, dynamic>))
          .toList(),
      color: json['color'] != null ? Color(json['color'] as int) : Colors.red,
      isEraser: json['isEraser'] as bool? ?? false,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 3.0,
    );
  }

  /// One stored point, in the `{'dx': num, 'dy': num}` shape [toJson] writes.
  static Offset _point(Map<String, dynamic> p) =>
      Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble());
  final List<Offset> points;
  final Color color;
  final bool isEraser;
  final double strokeWidth;

  Map<String, dynamic> toJson() => {
        'points': points
            .map((p) => {
                  'dx': (p.dx * 1000).round() / 1000,
                  'dy': (p.dy * 1000).round() / 1000
                })
            .toList(),
        'color': color.toARGB32(),
        'isEraser': isEraser,
        'strokeWidth': strokeWidth,
      };
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<Stroke> _strokes = [];
  Stroke? _currentStroke;
  Offset? _mousePosition;
  int _activePointerCount = 0;
  final double _eraserSize = 40.0;
  final double _penSize = 3.0;

  @override
  void initState() {
    super.initState();
    _loadDrawing();
  }

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDrawing != widget.initialDrawing && _strokes.isEmpty) {
      _loadDrawing();
    }
  }

  void _loadDrawing() {
    if (widget.initialDrawing != null && widget.initialDrawing!.isNotEmpty) {
      try {
        final List<dynamic> decoded =
            jsonDecode(widget.initialDrawing!) as List<dynamic>;
        _strokes = decoded.map((item) {
          if (item is List) {
            // Backwards compatibility for old format: List<List<Offset>>
            final points = item.map((p) {
              final map = p as Map<String, dynamic>;
              return Offset(map['dx'] as double, map['dy'] as double);
            }).toList();
            return Stroke(points: points, color: Colors.red);
          } else {
            // New format: Map<String, dynamic>
            return Stroke.fromJson(item as Map<String, dynamic>);
          }
        }).toList();
      } catch (e) {
        // Handle parsing error
        _strokes = [];
        debugPrint('Error parsing drawing: $e');
      }
    }
  }

  void _saveDrawing() {
    final serialized = _strokes.map((stroke) => stroke.toJson()).toList();
    widget.onSave(jsonEncode(serialized));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showDrawings) return const SizedBox.shrink();

    final Widget canvas = LayoutBuilder(builder: (context, constraints) {
      return CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _DrawingPainter(_strokes, _currentStroke,
            widget.isEraserMode ? _mousePosition : null, _eraserSize),
      );
    });

    if (widget.isDrawingMode) {
      return LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          cursor:
              widget.isEraserMode ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (event) {
            if (widget.isEraserMode) {
              setState(() {
                _mousePosition = event.localPosition;
              });
            }
          },
          onExit: (event) {
            setState(() {
              _mousePosition = null;
            });
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              setState(() {
                _activePointerCount++;
                if (_activePointerCount == 1) {
                  _mousePosition = event.localPosition;
                  _currentStroke = Stroke(
                    points: [
                      Offset(event.localPosition.dx / size.width,
                          event.localPosition.dy / size.height)
                    ],
                    color: widget.selectedColor,
                    isEraser: widget.isEraserMode,
                    strokeWidth: widget.isEraserMode ? _eraserSize : _penSize,
                  );
                } else {
                  _currentStroke = null;
                }
              });
            },
            onPointerMove: (event) {
              setState(() {
                if (_activePointerCount > 1) {
                  _currentStroke = null;
                  return;
                }
                _mousePosition = event.localPosition;

                if (_currentStroke != null &&
                    _currentStroke!.points.isNotEmpty) {
                  final lastPoint = _currentStroke!.points.last;
                  final pixelDistance = (Offset(lastPoint.dx * size.width,
                              lastPoint.dy * size.height) -
                          event.localPosition)
                      .distance;

                  if (pixelDistance > 3.0) {
                    _currentStroke!.points.add(Offset(
                        event.localPosition.dx / size.width,
                        event.localPosition.dy / size.height));
                  }
                }
              });
            },
            onPointerUp: (event) {
              setState(() {
                _activePointerCount--;
                if (_currentStroke != null && _activePointerCount == 0) {
                  _strokes.add(_currentStroke!);
                  _saveDrawing();
                }
                _currentStroke = null;
              });
            },
            onPointerCancel: (event) {
              setState(() {
                _activePointerCount--;
                _currentStroke = null;
              });
            },
            child: canvas,
          ),
        );
      });
    }

    return IgnorePointer(child: canvas);
  }
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter(
      this.strokes, this.currentStroke, this.mousePosition, this.eraserSize);
  final List<Stroke> strokes;
  final Stroke? currentStroke;
  final Offset? mousePosition;
  final double eraserSize;

  @override
  void paint(Canvas canvas, Size size) {
    // We use saveLayer and restore to allow BlendMode.clear to act properly
    // as an eraser over the other strokes
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final stroke in strokes) {
      _paintStroke(canvas, size, stroke);
    }

    if (currentStroke != null) {
      _paintStroke(canvas, size, currentStroke!);
    }

    canvas.restore();

    if (mousePosition != null) {
      final paint = Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(mousePosition!, eraserSize / 2, paint);

      final innerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(mousePosition!, (eraserSize / 2) - 1, innerPaint);
    }
  }

  void _paintStroke(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.isEraser ? Colors.transparent : stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    final path = Path()
      ..moveTo(stroke.points.first.dx * size.width,
          stroke.points.first.dy * size.height);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(
          stroke.points[i].dx * size.width, stroke.points[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return true;
  }
}
