part of 'opg_dental_chart.dart';

class _AnatomicalToothPainter extends CustomPainter {
  const _AnatomicalToothPainter({
    required this.iso,
    required this.isUpper,
    required this.isPrimary,
    required this.darkMode,
    required this.stateColor,
    required this.hasCurrent,
    required this.hasOld,
    required this.isHovered,
    required this.operationLayers,
  });

  final String iso;
  final bool isUpper;
  final bool isPrimary;
  final bool darkMode;
  final Color? stateColor;
  final bool hasCurrent;
  final bool hasOld;
  final bool isHovered;
  final List<_ToothOperationLayer> operationLayers;

  bool _hasOp(String name) => operationLayers.any((l) => l.operation == name);

  _ToothOperationLayer? _layerForOp(String name) {
    for (final l in operationLayers.reversed) {
      if (l.operation == name) return l;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final q = int.parse(iso[0]);
    final pos = int.parse(iso[1]);
    final isPatientRight = q == 1 || q == 4 || q == 5 || q == 8;
    final isAnterior = pos <= 3;

    canvas.save();

    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.translate(cx, cy);
    final sx = (size.width * 0.46) * (isPatientRight ? -1.0 : 1.0);
    final sy = (size.height * 0.46) * (isUpper ? 1.0 : -1.0);

    if (_hasOp('malposition')) {
      canvas.rotate(isPatientRight ? 0.11 : -0.11);
    } else if (_hasOp('impacted')) {
      canvas.translate(0, isUpper ? -4.0 : 4.0);
      canvas.rotate(isPatientRight ? -0.22 : 0.22);
    }

    Offset pt(double nx, double ny) {
      return Offset(nx * sx, (ny * 2.0 - 1.0) * sy);
    }

    final geometry = _buildToothGeometry(
      pos: pos,
      isUpper: isUpper,
      isPrimary: isPrimary,
      pt: pt,
    );

    final isMissing = _hasOp('missing') || _hasOp('extraction');
    final implantLayer = _layerForOp('implant');
    final isImplant = implantLayer != null;
    final isPontic = _hasOp('pontic');
    final rrootLayer = _layerForOp('rroot');
    final isRetainedRoot = rrootLayer != null;

    // Base tooth colors: only tint the tooth body when there is a current
    // draft note (`hasCurrent`). When the tooth only has history from another
    // appointment (`hasOld`), keep the tooth in neutral radiographic tones!
    final Color rootFillStart;
    final Color rootFillEnd;
    final Color enamelStart;
    final Color enamelEnd;
    final Color strokeColor;

    if (hasCurrent && stateColor != null) {
      rootFillStart = Color.lerp(
        darkMode ? const Color(0xFF647996) : const Color(0xFFD6DEE8),
        stateColor!,
        darkMode ? 0.38 : 0.28,
      )!
          .withValues(alpha: darkMode ? 0.68 : 0.85);
      rootFillEnd = Color.lerp(
        darkMode ? const Color(0xFF94A9C9) : const Color(0xFFE4EBF3),
        stateColor!,
        darkMode ? 0.45 : 0.34,
      )!
          .withValues(alpha: darkMode ? 0.86 : 0.92);
      enamelStart = Color.lerp(
        darkMode ? const Color(0xFFE6EEF8) : const Color(0xFFFFFFFF),
        stateColor!,
        darkMode ? 0.32 : 0.22,
      )!;
      enamelEnd = Color.lerp(
        darkMode ? const Color(0xFFB4C6DF) : const Color(0xFFEEF3F9),
        stateColor!,
        darkMode ? 0.42 : 0.32,
      )!;
      strokeColor = darkMode
          ? Colors.white.withValues(alpha: 0.92)
          : stateColor!.toAccentColor().darkest;
    } else if (darkMode) {
      rootFillStart = const Color(0xFF647996).withValues(alpha: 0.55);
      rootFillEnd = const Color(0xFF94A9C9).withValues(alpha: 0.82);
      enamelStart = const Color(0xFFE6EEF8);
      enamelEnd = const Color(0xFFB4C6DF);
      strokeColor = isHovered
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF8CA4C4).withValues(alpha: 0.85);
    } else {
      rootFillStart = const Color(0xFFD6DEE8);
      rootFillEnd = const Color(0xFFE4EBF3);
      enamelStart = const Color(0xFFFFFFFF);
      enamelEnd = const Color(0xFFEEF3F9);
      strokeColor = isHovered
          ? const Color(0xFF1E293B)
          : const Color(0xFF64748B).withValues(alpha: 0.85);
    }

    final opacity = isMissing ? 0.24 : 1.0;

    final rootShaderRect = Rect.fromPoints(pt(-1, 0), pt(1, 0.65));
    final rootPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: isUpper ? Alignment.topCenter : Alignment.bottomCenter,
        end: isUpper ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [
          rootFillStart.withValues(alpha: rootFillStart.a * opacity),
          rootFillEnd.withValues(alpha: rootFillEnd.a * opacity),
        ],
      ).createShader(rootShaderRect);

    final crownShaderRect = Rect.fromPoints(pt(-1, 0.55), pt(1, 1.0));
    final crownPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: isUpper ? Alignment.bottomCenter : Alignment.topCenter,
        end: isUpper ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [
          enamelStart.withValues(alpha: enamelStart.a * opacity),
          enamelEnd.withValues(alpha: enamelEnd.a * opacity),
        ],
      ).createShader(crownShaderRect);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHovered ? 1.6 : 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = strokeColor.withValues(alpha: strokeColor.a * opacity);

    // 1. Roots (either implant fixture or natural roots unless pontic)
    if (isImplant) {
      _paintImplantRoots(
        canvas,
        pt,
        implantLayer.color,
      );
    } else if (!isPontic) {
      for (final backRoot in geometry.backRoots) {
        canvas.drawPath(backRoot, rootPaint);
        canvas.drawPath(
          backRoot,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = outlinePaint.color,
        );
      }
      for (final root in geometry.roots) {
        canvas.drawPath(root, rootPaint);
        canvas.drawPath(root, outlinePaint);
      }
    }

    // 2. Natural radiolucent pulp chamber & canals (when not pontic/implant)
    if (!isImplant && !isPontic) {
      final naturalPulpPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = darkMode
            ? const Color(0xFF0B111A).withValues(alpha: 0.55 * opacity)
            : const Color(0xFF94A3B8).withValues(alpha: 0.28 * opacity);
      for (final canal in geometry.pulpAndCanals) {
        canvas.drawPath(canal, naturalPulpPaint);
      }
    }

    // 3. Endodontic layers (RCT / Re-RCT / Pulpotomy) drawn inside the root/pulp
    // space BEFORE the crown body is painted on top.
    for (final layer in operationLayers) {
      if (layer.operation == 'rCT' || layer.operation == 're-RCT') {
        _paintRctObturation(
          canvas,
          pt,
          geometry,
          layer,
          isReRct: layer.operation == 're-RCT',
        );
      } else if (layer.operation == 'pulpotomy') {
        _paintPulpotomy(canvas, pt, geometry, layer.color);
      }
    }

    // 4. Crown body + internal anatomical ridges/grooves
    if (!isRetainedRoot) {
      canvas.drawPath(geometry.crown, crownPaint);
      canvas.drawPath(geometry.crown, outlinePaint);

      final detailPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.95
        ..strokeCap = StrokeCap.round
        ..color = strokeColor.withValues(alpha: 0.42 * opacity);
      for (final detail in geometry.details) {
        canvas.drawPath(detail, detailPaint);
      }
    } else {
      _paintRetainedRootStump(
        canvas,
        pt,
        rrootLayer.color,
      );
    }

    // 5. Coronal & surgical treatment layers drawn in chronological order
    for (final layer in operationLayers) {
      _paintCoronalOrPerioLayer(
        canvas: canvas,
        pt: pt,
        geometry: geometry,
        layer: layer,
        isAnterior: isAnterior,
      );
    }

    canvas.restore();
  }

  void _paintCoronalOrPerioLayer({
    required Canvas canvas,
    required Offset Function(double nx, double ny) pt,
    required _ToothGeometry geometry,
    required _ToothOperationLayer layer,
    required bool isAnterior,
  }) {
    final op = layer.operation;
    final color = layer.color;

    switch (op) {
      case 'filling':
        _paintFilling(canvas, pt, geometry, color, isAnterior: isAnterior);
      case 'overlay':
        _paintOverlayRestoration(canvas, pt, geometry, color);
      case 'veneer':
        _paintVeneer(canvas, pt, geometry, color);
      case 'crown':
      case 'abutment':
        _paintEnlargedCrown(
          canvas,
          pt,
          geometry,
          color,
          dashed: false,
          isAbutment: op == 'abutment',
        );
      case 'temporary':
        _paintEnlargedCrown(
          canvas,
          pt,
          geometry,
          color,
          dashed: true,
        );
      case 'bridge':
      case 'pontic':
        _paintBridgeOrPontic(
          canvas,
          pt,
          geometry,
          color,
          isPontic: op == 'pontic',
        );
      case 'ortho':
        _paintOrthoBracket(canvas, pt, geometry, color);
      case 'surgery':
        _paintSurgicalStitches(canvas, pt, color);
      case 'caries':
        _paintCariesLesion(canvas, pt, geometry, color, isAnterior: isAnterior);
      case 'fractured':
        _paintFractureCrack(canvas, pt, geometry, color);
      case 'recession':
        _paintGingivalRecession(canvas, pt, color);
      case 'mobility':
        _paintMobilityArrows(canvas, pt, color);
      case 'clean':
        _paintCervicalCleanArc(canvas, pt, color);
      case 'whitening':
        _paintWhiteningSparkle(canvas, pt, geometry, color);
      case 'rprimary':
        _paintRetainedPrimaryBadge(canvas, pt, color);
      case 'missing':
      case 'extraction':
        _paintExtractionCross(canvas, pt, color);
      default:
        break;
    }
  }

  /// Titanium implant fixture with realistic tapered body, apical roundness,
  /// abutment collar, and fine screw threads.
  void _paintImplantRoots(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final fixture = Path()
      ..moveTo(pt(-0.34, 0.56).dx, pt(-0.34, 0.56).dy)
      ..lineTo(pt(-0.22, 0.14).dx, pt(-0.22, 0.14).dy)
      ..quadraticBezierTo(
        pt(0, 0.08).dx,
        pt(0, 0.08).dy,
        pt(0.22, 0.14).dx,
        pt(0.22, 0.14).dy,
      )
      ..lineTo(pt(0.34, 0.56).dx, pt(0.34, 0.56).dy)
      ..close();

    final rect = fixture.getBounds();
    canvas.drawPath(
      fixture,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.85),
            color.withValues(alpha: 0.85),
          ],
        ).createShader(rect),
    );

    final threadStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(fixture, threadStroke);

    for (var i = 0; i < 4; i++) {
      final ny = 0.20 + i * 0.09;
      final hw = 0.24 + i * 0.025;
      canvas.drawLine(pt(-hw, ny), pt(hw, ny), threadStroke);
    }
  }

  /// RCT / Re-RCT: When registered in the current draft, uses the vibrant
  /// gutta-percha/treatment color; when from another appointment, uses neutral
  /// radiographic silver-grey.
  void _paintRctObturation(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    _ToothOperationLayer layer, {
    required bool isReRct,
  }) {
    final fillColor = layer.isCurrentDraft
        ? (isReRct ? const Color(0xFFFFB300) : const Color(0xFFFFD54F))
        : layer.color;
    final strokeColor = layer.isCurrentDraft
        ? (isReRct ? layer.color : Colors.white.withValues(alpha: 0.92))
        : (darkMode
            ? Colors.white.withValues(alpha: 0.65)
            : const Color(0xFF475569));

    for (final canal in geometry.pulpAndCanals) {
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor.withValues(
            alpha: layer.isCurrentDraft ? 0.95 : 0.75,
          ),
      );
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isReRct ? 1.4 : 1.0
          ..strokeJoin = StrokeJoin.round
          ..color = strokeColor,
      );
    }
  }

  /// Pulpotomy: Distinct from RCT — only the coronal pulp chamber at the neck/
  /// top of the root-crown junction is filled, while the root canals toward the
  /// apex remain untouched!
  void _paintPulpotomy(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    final c1 = pt(-1.0, 0.44);
    final c2 = pt(1.0, 0.72);
    final coronalClip = Rect.fromPoints(c1, c2).inflate(2);

    canvas.save();
    canvas.clipRect(coronalClip);
    for (final canal in geometry.pulpAndCanals) {
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.92),
      );
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..color = Colors.white.withValues(alpha: 0.90),
      );
    }
    canvas.restore();

    final cap = Path()
      ..moveTo(pt(-0.28, 0.54).dx, pt(-0.28, 0.54).dy)
      ..quadraticBezierTo(
        pt(0, 0.67).dx,
        pt(0, 0.67).dy,
        pt(0.28, 0.54).dx,
        pt(0.28, 0.54).dy,
      )
      ..quadraticBezierTo(
        pt(0, 0.49).dx,
        pt(0, 0.49).dy,
        pt(-0.28, 0.54).dx,
        pt(-0.28, 0.54).dy,
      )
      ..close();
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.90),
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.95
        ..color = Colors.white.withValues(alpha: 0.88),
    );
  }

  /// Filling: Clipped directly to `geometry.crown` so it hugs the natural tooth
  /// enamel contour!
  void _paintFilling(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool isAnterior,
  }) {
    canvas.save();
    canvas.clipPath(geometry.crown);

    final Path patch;
    if (isAnterior) {
      patch = Path()
        ..moveTo(pt(-0.95, 0.64).dx, pt(-0.95, 0.64).dy)
        ..quadraticBezierTo(
          pt(-0.08, 0.68).dx,
          pt(-0.08, 0.68).dy,
          pt(-0.14, 0.88).dx,
          pt(-0.14, 0.88).dy,
        )
        ..quadraticBezierTo(
          pt(-0.22, 0.96).dx,
          pt(-0.22, 0.96).dy,
          pt(-0.95, 0.95).dx,
          pt(-0.95, 0.95).dy,
        )
        ..close();
    } else {
      patch = Path()
        ..moveTo(pt(-0.48, 1.02).dx, pt(-0.48, 1.02).dy)
        ..quadraticBezierTo(
          pt(-0.44, 0.73).dx,
          pt(-0.44, 0.73).dy,
          pt(0.0, 0.75).dx,
          pt(0.0, 0.75).dy,
        )
        ..quadraticBezierTo(
          pt(0.44, 0.73).dx,
          pt(0.44, 0.73).dy,
          pt(0.48, 1.02).dx,
          pt(0.48, 1.02).dy,
        )
        ..close();
    }

    canvas.drawPath(
      patch,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      patch,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.88),
    );
    canvas.restore();
  }

  /// Overlay: Extends across the entire crown from mesial to distal, clipped
  /// cleanly to `geometry.crown`.
  void _paintOverlayRestoration(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(geometry.crown);

    final overlayBand = Path()
      ..moveTo(pt(-1.15, 0.66).dx, pt(-1.15, 0.66).dy)
      ..lineTo(pt(-1.15, 1.08).dx, pt(-1.15, 1.08).dy)
      ..lineTo(pt(1.15, 1.08).dx, pt(1.15, 1.08).dy)
      ..lineTo(pt(1.15, 0.66).dx, pt(1.15, 0.66).dy)
      ..quadraticBezierTo(
        pt(0.48, 0.74).dx,
        pt(0.48, 0.74).dy,
        pt(0.0, 0.67).dx,
        pt(0.0, 0.67).dy,
      )
      ..quadraticBezierTo(
        pt(-0.48, 0.74).dx,
        pt(-0.48, 0.74).dy,
        pt(-1.15, 0.66).dx,
        pt(-1.15, 0.66).dy,
      )
      ..close();

    canvas.drawPath(
      overlayBand,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.82),
    );
    canvas.drawPath(
      overlayBand,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.90),
    );
    canvas.restore();

    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = color,
    );
  }

  /// Veneer: Half a crown covering only one side (mesial half of `geometry.crown`).
  void _paintVeneer(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    final bounds = geometry.crown.getBounds();
    final midX = pt(0.02, 0.78).dx;
    final mesialX = pt(-1.2, 0.78).dx;
    final clipLeft = math.min(midX, mesialX);
    final clipRight = math.max(midX, mesialX);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
      clipLeft,
      bounds.top - 6,
      clipRight,
      bounds.bottom + 6,
    ));

    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.65),
    );
    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..color = color,
    );
    canvas.restore();

    canvas.save();
    canvas.clipPath(geometry.crown);
    canvas.drawLine(
      pt(0.02, 0.50),
      pt(0.02, 1.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.90),
    );
    canvas.restore();
  }

  /// Crown & Temporary Crown: Enlarged anatomical crown contour (`1.13x`),
  /// dashed when `temporary`.
  void _paintEnlargedCrown(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool dashed,
    bool isAbutment = false,
  }) {
    final bounds = geometry.crown.getBounds();
    final outerCrown = _scalePathAround(
      geometry.crown,
      bounds.center,
      1.13,
      1.11,
    );

    canvas.drawPath(
      outerCrown,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: isUpper ? Alignment.bottomCenter : Alignment.topCenter,
          end: isUpper ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: dashed ? 0.28 : 0.52),
            color.withValues(alpha: dashed ? 0.14 : 0.32),
          ],
        ).createShader(bounds),
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.65 : 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    if (dashed) {
      _drawDashedPath(
        canvas,
        outerCrown,
        borderPaint,
        dashLength: 2.6,
        gapLength: 2.2,
      );
    } else {
      canvas.drawPath(outerCrown, borderPaint);
      canvas.drawPath(
        geometry.crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85
          ..color = Colors.white.withValues(alpha: 0.65),
      );
    }

    if (isAbutment) {
      canvas.drawLine(
        pt(0, 0.48),
        pt(0, 0.78),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.88),
      );
    }
  }

  void _paintBridgeOrPontic(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool isPontic,
  }) {
    _paintEnlargedCrown(canvas, pt, geometry, color, dashed: false);
    final connectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(pt(-1.04, 0.76), pt(-0.74, 0.76), connectorPaint);
    canvas.drawLine(pt(0.74, 0.76), pt(1.04, 0.76), connectorPaint);
  }

  void _paintOrthoBracket(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    final c = pt(0, 0.76);
    final wireLeft = pt(-0.98, 0.76);
    final wireRight = pt(0.98, 0.76);

    canvas.drawLine(
      wireLeft,
      wireRight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
    );

    final padRect = Rect.fromCenter(center: c, width: 7.2, height: 6.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(1.3)),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(1.3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.95
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    final slotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..color = Colors.white;
    canvas.drawLine(
      Offset(c.dx, c.dy - 2.6),
      Offset(c.dx, c.dy + 2.6),
      slotPaint,
    );
    canvas.drawLine(
      Offset(c.dx - 3.2, c.dy),
      Offset(c.dx + 3.2, c.dy),
      slotPaint,
    );
  }

  void _paintSurgicalStitches(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final flap = Path()
      ..moveTo(pt(-0.56, 0.34).dx, pt(-0.56, 0.34).dy)
      ..quadraticBezierTo(
        pt(0.0, 0.24).dx,
        pt(0.0, 0.24).dy,
        pt(0.56, 0.34).dx,
        pt(0.56, 0.34).dy,
      );
    canvas.drawPath(
      flap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    final stitchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.90);

    for (final nx in [-0.32, 0.0, 0.32]) {
      final baseNy = nx == 0.0 ? 0.29 : 0.315;
      canvas.drawLine(
        pt(nx - 0.04, baseNy - 0.065),
        pt(nx + 0.04, baseNy + 0.065),
        stitchPaint,
      );
      canvas.drawLine(
        pt(nx - 0.055, baseNy + 0.015),
        pt(nx + 0.055, baseNy - 0.015),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.05
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  void _paintCariesLesion(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool isAnterior,
  }) {
    canvas.save();
    canvas.clipPath(geometry.crown);
    final center = isAnterior ? pt(0.34, 0.75) : pt(0.16, 0.83);
    canvas.drawCircle(
      center,
      3.8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.88),
    );
    canvas.drawCircle(
      center,
      1.8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withValues(alpha: 0.50),
    );
    canvas.restore();
  }

  void _paintFractureCrack(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(geometry.crown);
    final crack = Path()
      ..moveTo(pt(-0.46, 0.95).dx, pt(-0.46, 0.95).dy)
      ..lineTo(pt(-0.08, 0.80).dx, pt(-0.08, 0.80).dy)
      ..lineTo(pt(0.14, 0.83).dx, pt(0.14, 0.83).dy)
      ..lineTo(pt(0.48, 0.65).dx, pt(0.48, 0.65).dy);
    canvas.drawPath(
      crack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
  }

  void _paintGingivalRecession(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final rec = Path()
      ..moveTo(pt(-0.58, 0.54).dx, pt(-0.58, 0.54).dy)
      ..quadraticBezierTo(
        pt(0.0, 0.36).dx,
        pt(0.0, 0.36).dy,
        pt(0.58, 0.54).dx,
        pt(0.58, 0.54).dy,
      );
    canvas.drawPath(
      rec,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintMobilityArrows(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    final pL = pt(-0.62, 0.80);
    final pR = pt(0.62, 0.80);
    canvas.drawLine(pL, pR, paint);
    canvas.drawLine(pL, Offset(pL.dx + 3.0, pL.dy - 2.2), paint);
    canvas.drawLine(pL, Offset(pL.dx + 3.0, pL.dy + 2.2), paint);
    canvas.drawLine(pR, Offset(pR.dx - 3.0, pR.dy - 2.2), paint);
    canvas.drawLine(pR, Offset(pR.dx - 3.0, pR.dy + 2.2), paint);
  }

  void _paintCervicalCleanArc(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final arc = Path()
      ..moveTo(pt(-0.54, 0.58).dx, pt(-0.54, 0.58).dy)
      ..quadraticBezierTo(
        pt(0, 0.52).dx,
        pt(0, 0.52).dy,
        pt(0.54, 0.58).dx,
        pt(0.54, 0.58).dy,
      );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintWhiteningSparkle(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(geometry.crown);
    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.restore();

    final c = pt(0.0, 0.78);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(Offset(c.dx - 4.0, c.dy), Offset(c.dx + 4.0, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - 4.0), Offset(c.dx, c.dy + 4.0), p);
  }

  void _paintRetainedRootStump(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final jagged = Path()
      ..moveTo(pt(-0.50, 0.56).dx, pt(-0.50, 0.56).dy)
      ..lineTo(pt(-0.18, 0.61).dx, pt(-0.18, 0.61).dy)
      ..lineTo(pt(0.12, 0.54).dx, pt(0.12, 0.54).dy)
      ..lineTo(pt(0.50, 0.58).dx, pt(0.50, 0.58).dy);
    canvas.drawPath(
      jagged,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintRetainedPrimaryBadge(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final cap = Path()
      ..moveTo(pt(-0.46, 0.62).dx, pt(-0.46, 0.62).dy)
      ..quadraticBezierTo(
        pt(0, 0.75).dx,
        pt(0, 0.75).dy,
        pt(0.46, 0.62).dx,
        pt(0.46, 0.62).dy,
      );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintExtractionCross(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.80);
    canvas.drawLine(pt(-0.54, 0.22), pt(0.54, 0.85), crossPaint);
    canvas.drawLine(pt(-0.54, 0.85), pt(0.54, 0.22), crossPaint);
  }

  Path _scalePathAround(Path path, Offset pivot, double sx, double sy) {
    final matrix = Matrix4.identity()
      ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
    return path.transform(matrix.storage);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnatomicalToothPainter oldDelegate) {
    if (oldDelegate.iso != iso ||
        oldDelegate.isUpper != isUpper ||
        oldDelegate.isPrimary != isPrimary ||
        oldDelegate.darkMode != darkMode ||
        oldDelegate.stateColor != stateColor ||
        oldDelegate.hasCurrent != hasCurrent ||
        oldDelegate.hasOld != hasOld ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.operationLayers.length != operationLayers.length) {
      return true;
    }
    for (var i = 0; i < operationLayers.length; i++) {
      if (oldDelegate.operationLayers[i] != operationLayers[i]) return true;
    }
    return false;
  }
}
