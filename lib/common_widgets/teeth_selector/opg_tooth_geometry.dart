part of 'opg_dental_chart.dart';

class _ToothGeometry {
  const _ToothGeometry({
    required this.roots,
    this.backRoots = const [],
    required this.crown,
    this.pulpAndCanals = const [],
    this.details = const [],
  });

  final List<Path> roots;
  final List<Path> backRoots;
  final Path crown;
  final List<Path> pulpAndCanals;
  final List<Path> details;
}

/// Builds anatomically distinct tooth outlines in normalized coordinates:
/// - `nx` in [-1..1]: `-nx` is MESIAL, `+nx` is DISTAL.
/// - `ny` in [0..1]: `0` is root apex, `~0.58` is CEJ (cervical line), `1.0` is
///   incisal edge / cusp tip.
_ToothGeometry _buildToothGeometry({
  required int pos,
  required bool isUpper,
  required bool isPrimary,
  required Offset Function(double nx, double ny) pt,
}) {
  if (isPrimary) {
    return switch (pos) {
      1 => _incisorGeometry(
          pt: pt,
          crownHalfWidth: isUpper ? 0.68 : 0.54,
          cejHalfWidth: isUpper ? 0.46 : 0.36,
          rootLengthNy: 0.14,
          distalIncisalRoundness: 0.05,
          distalRootBend: 0.04,
          hasLabialGrooves: isUpper,
        ),
      2 => _incisorGeometry(
          pt: pt,
          crownHalfWidth: isUpper ? 0.56 : 0.58,
          cejHalfWidth: isUpper ? 0.38 : 0.40,
          rootLengthNy: 0.16,
          distalIncisalRoundness: 0.11,
          distalRootBend: 0.12,
          hasLabialGrooves: false,
        ),
      3 => _canineGeometry(
          pt: pt,
          crownHalfWidth: 0.68,
          cejHalfWidth: 0.46,
          rootApexNy: 0.10,
          cuspSharpness: 0.14,
        ),
      4 => isUpper
          ? _upperMolarGeometry(
              pt: pt,
              variant: 1,
              crownScale: 0.86,
              rootApexNy: 0.14,
            )
          : _lowerMolarGeometry(
              pt: pt,
              variant: 2,
              crownScale: 0.86,
              rootApexNy: 0.14,
            ),
      _ => isUpper
          ? _upperMolarGeometry(
              pt: pt,
              variant: 1,
              crownScale: 0.94,
              rootApexNy: 0.12,
            )
          : _lowerMolarGeometry(
              pt: pt,
              variant: 1,
              crownScale: 0.94,
              rootApexNy: 0.12,
            ),
    };
  }

  return switch (pos) {
    1 => isUpper
        ? _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.76,
            cejHalfWidth: 0.50,
            rootLengthNy: 0.10,
            distalIncisalRoundness: 0.05,
            distalRootBend: 0.03,
            hasLabialGrooves: true,
          )
        : _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.52,
            cejHalfWidth: 0.34,
            rootLengthNy: 0.12,
            distalIncisalRoundness: 0.02,
            distalRootBend: 0.01,
            hasLabialGrooves: false,
          ),
    2 => isUpper
        ? _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.60,
            cejHalfWidth: 0.40,
            rootLengthNy: 0.13,
            distalIncisalRoundness: 0.14,
            distalRootBend: 0.16,
            hasLabialGrooves: false,
            crownTopNy: 0.94,
          )
        : _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.60,
            cejHalfWidth: 0.38,
            rootLengthNy: 0.10,
            distalIncisalRoundness: 0.09,
            distalRootBend: 0.10,
            hasLabialGrooves: false,
          ),
    3 => _canineGeometry(
        pt: pt,
        crownHalfWidth: isUpper ? 0.72 : 0.66,
        cejHalfWidth: isUpper ? 0.48 : 0.44,
        rootApexNy: 0.04,
        cuspSharpness: isUpper ? 0.17 : 0.13,
      ),
    4 => _premolarGeometry(
        pt: pt,
        isFirst: true,
        isUpper: isUpper,
      ),
    5 => _premolarGeometry(
        pt: pt,
        isFirst: false,
        isUpper: isUpper,
      ),
    6 => isUpper
        ? _upperMolarGeometry(pt: pt, variant: 1)
        : _lowerMolarGeometry(pt: pt, variant: 1),
    7 => isUpper
        ? _upperMolarGeometry(pt: pt, variant: 2)
        : _lowerMolarGeometry(pt: pt, variant: 2),
    _ => isUpper
        ? _upperMolarGeometry(pt: pt, variant: 3)
        : _lowerMolarGeometry(pt: pt, variant: 3),
  };
}

_ToothGeometry _incisorGeometry({
  required Offset Function(double nx, double ny) pt,
  required double crownHalfWidth,
  required double cejHalfWidth,
  required double rootLengthNy,
  required double distalIncisalRoundness,
  required double distalRootBend,
  required bool hasLabialGrooves,
  double crownTopNy = 0.97,
}) {
  const cejNy = 0.56;

  final root = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..cubicTo(
      pt(-cejHalfWidth * 0.85, 0.36).dx,
      pt(-cejHalfWidth * 0.85, 0.36).dy,
      pt(-0.14 + distalRootBend * 0.5, rootLengthNy + 0.08).dx,
      pt(-0.14 + distalRootBend * 0.5, rootLengthNy + 0.08).dy,
      pt(distalRootBend, rootLengthNy).dx,
      pt(distalRootBend, rootLengthNy).dy,
    )
    ..cubicTo(
      pt(0.14 + distalRootBend, rootLengthNy + 0.08).dx,
      pt(0.14 + distalRootBend, rootLengthNy + 0.08).dy,
      pt(cejHalfWidth * 0.85, 0.36).dx,
      pt(cejHalfWidth * 0.85, 0.36).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..close();

  final mesialIncisalNy = crownTopNy;
  final distalIncisalNy = crownTopNy - distalIncisalRoundness;

  final crown = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.04).dx,
      pt(0, cejNy - 0.04).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalfWidth * 0.98, cejNy + 0.14).dx,
      pt(crownHalfWidth * 0.98, cejNy + 0.14).dy,
      pt(crownHalfWidth, distalIncisalNy - 0.06).dx,
      pt(crownHalfWidth, distalIncisalNy - 0.06).dy,
      pt(crownHalfWidth * 0.86, distalIncisalNy).dx,
      pt(crownHalfWidth * 0.86, distalIncisalNy).dy,
    )
    ..quadraticBezierTo(
      pt(0, crownTopNy + 0.01).dx,
      pt(0, crownTopNy + 0.01).dy,
      pt(-crownHalfWidth * 0.92, mesialIncisalNy).dx,
      pt(-crownHalfWidth * 0.92, mesialIncisalNy).dy,
    )
    ..cubicTo(
      pt(-crownHalfWidth, mesialIncisalNy - 0.05).dx,
      pt(-crownHalfWidth, mesialIncisalNy - 0.05).dy,
      pt(-crownHalfWidth * 0.96, cejNy + 0.14).dx,
      pt(-crownHalfWidth * 0.96, cejNy + 0.14).dy,
      pt(-cejHalfWidth, cejNy).dx,
      pt(-cejHalfWidth, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(distalRootBend * 0.85, rootLengthNy + 0.05).dx,
        pt(distalRootBend * 0.85, rootLengthNy + 0.05).dy)
    ..lineTo(pt(-cejHalfWidth * 0.28, cejNy + 0.14).dx,
        pt(-cejHalfWidth * 0.28, cejNy + 0.14).dy)
    ..lineTo(pt(cejHalfWidth * 0.28, cejNy + 0.14).dx,
        pt(cejHalfWidth * 0.28, cejNy + 0.14).dy)
    ..close();

  final details = <Path>[];
  if (hasLabialGrooves) {
    final g1 = Path()
      ..moveTo(pt(-0.22, cejNy + 0.12).dx, pt(-0.22, cejNy + 0.12).dy)
      ..lineTo(
          pt(-0.26, crownTopNy - 0.05).dx, pt(-0.26, crownTopNy - 0.05).dy);
    final g2 = Path()
      ..moveTo(pt(0.22, cejNy + 0.12).dx, pt(0.22, cejNy + 0.12).dy)
      ..lineTo(pt(0.26, crownTopNy - 0.05).dx, pt(0.26, crownTopNy - 0.05).dy);
    details.addAll([g1, g2]);
  } else {
    final g = Path()
      ..moveTo(pt(0.0, cejNy + 0.10).dx, pt(0.0, cejNy + 0.10).dy)
      ..lineTo(pt(distalIncisalRoundness * 0.4, crownTopNy - 0.07).dx,
          pt(distalIncisalRoundness * 0.4, crownTopNy - 0.07).dy);
    details.add(g);
  }

  return _ToothGeometry(
    roots: [root],
    crown: crown,
    pulpAndCanals: [pulp],
    details: details,
  );
}

_ToothGeometry _canineGeometry({
  required Offset Function(double nx, double ny) pt,
  required double crownHalfWidth,
  required double cejHalfWidth,
  required double rootApexNy,
  required double cuspSharpness,
}) {
  const cejNy = 0.56;

  final root = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..cubicTo(
      pt(-cejHalfWidth * 0.88, 0.32).dx,
      pt(-cejHalfWidth * 0.88, 0.32).dy,
      pt(-0.14, rootApexNy + 0.08).dx,
      pt(-0.14, rootApexNy + 0.08).dy,
      pt(0.06, rootApexNy).dx,
      pt(0.06, rootApexNy).dy,
    )
    ..cubicTo(
      pt(0.20, rootApexNy + 0.08).dx,
      pt(0.20, rootApexNy + 0.08).dy,
      pt(cejHalfWidth * 0.88, 0.32).dx,
      pt(cejHalfWidth * 0.88, 0.32).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..close();

  final crown = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.05).dx,
      pt(0, cejNy - 0.05).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalfWidth * 0.95, cejNy + 0.10).dx,
      pt(crownHalfWidth * 0.95, cejNy + 0.10).dy,
      pt(crownHalfWidth * 1.02, 0.76).dx,
      pt(crownHalfWidth * 1.02, 0.76).dy,
      pt(crownHalfWidth * 0.88, 0.81).dx,
      pt(crownHalfWidth * 0.88, 0.81).dy,
    )
    ..lineTo(
        pt(-0.04, 0.82 + cuspSharpness).dx, pt(-0.04, 0.82 + cuspSharpness).dy)
    ..lineTo(pt(-crownHalfWidth * 0.88, 0.84).dx,
        pt(-crownHalfWidth * 0.88, 0.84).dy)
    ..cubicTo(
      pt(-crownHalfWidth, 0.78).dx,
      pt(-crownHalfWidth, 0.78).dy,
      pt(-crownHalfWidth * 0.92, cejNy + 0.10).dx,
      pt(-crownHalfWidth * 0.92, cejNy + 0.10).dy,
      pt(-cejHalfWidth, cejNy).dx,
      pt(-cejHalfWidth, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(0.05, rootApexNy + 0.06).dx, pt(0.05, rootApexNy + 0.06).dy)
    ..lineTo(pt(-0.16, cejNy + 0.08).dx, pt(-0.16, cejNy + 0.08).dy)
    ..lineTo(pt(-0.03, cejNy + 0.22).dx, pt(-0.03, cejNy + 0.22).dy)
    ..lineTo(pt(0.16, cejNy + 0.08).dx, pt(0.16, cejNy + 0.08).dy)
    ..close();

  final labialRidge = Path()
    ..moveTo(pt(0.0, cejNy + 0.06).dx, pt(0.0, cejNy + 0.06).dy)
    ..lineTo(
        pt(-0.04, 0.80 + cuspSharpness).dx, pt(-0.04, 0.80 + cuspSharpness).dy);

  return _ToothGeometry(
    roots: [root],
    crown: crown,
    pulpAndCanals: [pulp],
    details: [labialRidge],
  );
}

_ToothGeometry _premolarGeometry({
  required Offset Function(double nx, double ny) pt,
  required bool isFirst,
  required bool isUpper,
}) {
  const cejNy = 0.56;
  final cejHalf = isFirst ? 0.46 : 0.48;
  final crownHalf = isFirst ? 0.72 : 0.75;

  final roots = <Path>[];
  final backRoots = <Path>[];
  final pulps = <Path>[];

  if (isUpper && isFirst) {
    final palatalRoot = Path()
      ..moveTo(pt(-cejHalf * 0.75, cejNy).dx, pt(-cejHalf * 0.75, cejNy).dy)
      ..quadraticBezierTo(
        pt(0.28, 0.28).dx,
        pt(0.28, 0.28).dy,
        pt(0.22, 0.14).dx,
        pt(0.22, 0.14).dy,
      )
      ..quadraticBezierTo(
        pt(0.38, 0.30).dx,
        pt(0.38, 0.30).dy,
        pt(cejHalf * 0.85, cejNy).dx,
        pt(cejHalf * 0.85, cejNy).dy,
      )
      ..close();
    backRoots.add(palatalRoot);

    final buccalRoot = Path()
      ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
      ..cubicTo(
        pt(-cejHalf * 0.85, 0.34).dx,
        pt(-cejHalf * 0.34, 0.34).dy,
        pt(-0.22, 0.18).dx,
        pt(-0.22, 0.18).dy,
        pt(-0.14, 0.11).dx,
        pt(-0.14, 0.11).dy,
      )
      ..cubicTo(
        pt(0.02, 0.18).dx,
        pt(0.02, 0.18).dy,
        pt(cejHalf * 0.75, 0.36).dx,
        pt(cejHalf * 0.75, 0.36).dy,
        pt(cejHalf, cejNy).dx,
        pt(cejHalf, cejNy).dy,
      )
      ..close();
    roots.add(buccalRoot);
  } else {
    final apexNy = isFirst ? 0.11 : 0.13;
    final bend = isFirst ? 0.04 : 0.09;
    final singleRoot = Path()
      ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
      ..cubicTo(
        pt(-cejHalf * 0.85, 0.34).dx,
        pt(-cejHalf * 0.85, 0.34).dy,
        pt(-0.14 + bend * 0.5, apexNy + 0.08).dx,
        pt(-0.14 + bend * 0.5, apexNy + 0.08).dy,
        pt(bend, apexNy).dx,
        pt(bend, apexNy).dy,
      )
      ..cubicTo(
        pt(0.16 + bend, apexNy + 0.08).dx,
        pt(0.16 + bend, apexNy + 0.08).dy,
        pt(cejHalf * 0.85, 0.34).dx,
        pt(cejHalf * 0.85, 0.34).dy,
        pt(cejHalf, cejNy).dx,
        pt(cejHalf, cejNy).dy,
      )
      ..close();
    roots.add(singleRoot);
  }

  pulps.add(
    Path()
      ..moveTo(pt(0.0, 0.18).dx, pt(0.0, 0.18).dy)
      ..lineTo(pt(-0.16, cejNy + 0.12).dx, pt(-0.16, cejNy + 0.12).dy)
      ..lineTo(pt(0.16, cejNy + 0.12).dx, pt(cejHalf * 0.3, cejNy + 0.12).dy)
      ..close(),
  );

  final cuspTipNy = isFirst ? 0.96 : 0.93;
  final crown = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.04).dx,
      pt(0, cejNy - 0.04).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalf, cejNy + 0.12).dx,
      pt(crownHalf, cejNy + 0.12).dy,
      pt(crownHalf, 0.78).dx,
      pt(crownHalf, 0.78).dy,
      pt(crownHalf * 0.82, 0.84).dx,
      pt(crownHalf * 0.82, 0.84).dy,
    )
    ..lineTo(pt(isFirst ? -0.04 : 0.0, cuspTipNy).dx,
        pt(isFirst ? -0.04 : 0.0, cuspTipNy).dy)
    ..lineTo(pt(-crownHalf * 0.84, 0.84).dx, pt(-crownHalf * 0.84, 0.84).dy)
    ..cubicTo(
      pt(-crownHalf, 0.78).dx,
      pt(-crownHalf, 0.78).dy,
      pt(-crownHalf, cejNy + 0.12).dx,
      pt(-crownHalf, cejNy + 0.12).dy,
      pt(-cejHalf, cejNy).dx,
      pt(-cejHalf, cejNy).dy,
    )
    ..close();

  final lingualCuspArc = Path()
    ..moveTo(pt(-crownHalf * 0.55, 0.83).dx, pt(-crownHalf * 0.55, 0.83).dy)
    ..quadraticBezierTo(
      pt(isFirst ? 0.18 : 0.12, 0.91).dx,
      pt(isFirst ? 0.18 : 0.12, 0.91).dy,
      pt(crownHalf * 0.65, 0.82).dx,
      pt(crownHalf * 0.65, 0.82).dy,
    );
  final buccalRidge = Path()
    ..moveTo(pt(0, cejNy + 0.08).dx, pt(0, cejNy + 0.08).dy)
    ..lineTo(pt(isFirst ? -0.04 : 0.0, cuspTipNy - 0.04).dx,
        pt(isFirst ? -0.04 : 0.0, cuspTipNy - 0.04).dy);

  return _ToothGeometry(
    roots: roots,
    backRoots: backRoots,
    crown: crown,
    pulpAndCanals: pulps,
    details: [lingualCuspArc, buccalRidge],
  );
}

_ToothGeometry _upperMolarGeometry({
  required Offset Function(double nx, double ny) pt,
  required int variant,
  double crownScale = 1.0,
  double? rootApexNy,
}) {
  const cejNy = 0.55;
  final scale = crownScale *
      switch (variant) {
        1 => 1.0,
        2 => 0.92,
        _ => 0.82,
      };
  final cejHalf = 0.64 * scale;
  final crownHalf = 0.86 * scale;
  final apexNy = rootApexNy ??
      switch (variant) {
        1 => 0.10,
        2 => 0.13,
        _ => 0.19,
      };
  final rootSpread = switch (variant) {
    1 => 0.56,
    2 => 0.42,
    _ => 0.24,
  };
  final distalBend = switch (variant) {
    1 => 0.04,
    2 => 0.12,
    _ => 0.20,
  };

  final palatalRoot = Path()
    ..moveTo(pt(-0.24 * scale, cejNy).dx, pt(-0.24 * scale, cejNy).dy)
    ..cubicTo(
      pt(-0.16, 0.30).dx,
      pt(-0.16, 0.30).dy,
      pt(-0.08 + distalBend * 0.4, apexNy + 0.02).dx,
      pt(-0.08 + distalBend * 0.4, apexNy + 0.02).dy,
      pt(0.02 + distalBend * 0.4, apexNy - 0.02).dx,
      pt(0.02 + distalBend * 0.4, apexNy - 0.02).dy,
    )
    ..cubicTo(
      pt(0.14 + distalBend * 0.4, apexNy + 0.02).dx,
      pt(0.14 + distalBend * 0.4, apexNy + 0.02).dy,
      pt(0.20, 0.30).dx,
      pt(0.20, 0.30).dy,
      pt(0.24 * scale, cejNy).dx,
      pt(0.24 * scale, cejNy).dy,
    )
    ..close();

  final furcationNy = variant == 3 ? 0.34 : 0.42;
  final buccalRoots = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..cubicTo(
      pt(-cejHalf * 1.02, 0.36).dx,
      pt(-cejHalf * 1.02, 0.36).dy,
      pt(-rootSpread, apexNy + 0.08).dx,
      pt(-rootSpread, apexNy + 0.08).dy,
      pt(-rootSpread * 0.82 + distalBend, apexNy + 0.02).dx,
      pt(-rootSpread * 0.82 + distalBend, apexNy + 0.02).dy,
    )
    ..quadraticBezierTo(
      pt(-0.14, 0.28).dx,
      pt(-0.14, 0.28).dy,
      pt(0.0, furcationNy).dx,
      pt(0.0, furcationNy).dy,
    )
    ..quadraticBezierTo(
      pt(0.16, 0.28).dx,
      pt(0.16, 0.28).dy,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.05).dx,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.05).dy,
    )
    ..cubicTo(
      pt(rootSpread + distalBend, apexNy + 0.12).dx,
      pt(rootSpread + distalBend, apexNy + 0.12).dy,
      pt(cejHalf * 1.02, 0.36).dx,
      pt(cejHalf * 1.02, 0.36).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..close();

  final crown = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.03).dx,
      pt(0, cejNy - 0.03).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalf, cejNy + 0.10).dx,
      pt(crownHalf, cejNy + 0.10).dy,
      pt(crownHalf, 0.80).dx,
      pt(crownHalf, 0.80).dy,
      pt(crownHalf * 0.82, 0.87).dx,
      pt(crownHalf * 0.82, 0.87).dy,
    )
    ..quadraticBezierTo(
      pt(crownHalf * 0.46, 0.96).dx,
      pt(crownHalf * 0.46, 0.96).dy,
      pt(0.04, 0.87).dx,
      pt(0.04, 0.87).dy,
    )
    ..quadraticBezierTo(
      pt(-crownHalf * 0.46, 0.98).dx,
      pt(-crownHalf * 0.46, 0.98).dy,
      pt(-crownHalf * 0.85, 0.88).dx,
      pt(-crownHalf * 0.85, 0.88).dy,
    )
    ..cubicTo(
      pt(-crownHalf, 0.80).dx,
      pt(-crownHalf, 0.80).dy,
      pt(-crownHalf, cejNy + 0.10).dx,
      pt(-crownHalf, cejNy + 0.10).dy,
      pt(-cejHalf, cejNy).dx,
      pt(-cejHalf, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(-rootSpread * 0.68 + distalBend, apexNy + 0.08).dx,
        pt(-rootSpread * 0.68 + distalBend, apexNy + 0.08).dy)
    ..lineTo(
        pt(-0.32 * scale, cejNy + 0.15).dx, pt(-0.32 * scale, cejNy + 0.15).dy)
    ..lineTo(
        pt(0.32 * scale, cejNy + 0.15).dx, pt(0.32 * scale, cejNy + 0.15).dy)
    ..lineTo(pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dx,
        pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dy)
    ..lineTo(pt(0.08, cejNy + 0.02).dx, pt(0.08, cejNy + 0.02).dy)
    ..lineTo(pt(-0.08, cejNy + 0.02).dx, pt(-0.08, cejNy + 0.02).dy)
    ..close();

  final buccalGroove = Path()
    ..moveTo(pt(0.04, 0.87).dx, pt(0.04, 0.87).dy)
    ..lineTo(pt(0.02, cejNy + 0.14).dx, pt(0.02, cejNy + 0.14).dy);

  return _ToothGeometry(
    roots: [buccalRoots],
    backRoots: [palatalRoot],
    crown: crown,
    pulpAndCanals: [pulp],
    details: [buccalGroove],
  );
}

_ToothGeometry _lowerMolarGeometry({
  required Offset Function(double nx, double ny) pt,
  required int variant,
  double crownScale = 1.0,
  double? rootApexNy,
}) {
  const cejNy = 0.55;
  final scale = crownScale *
      switch (variant) {
        1 => 1.0,
        2 => 0.92,
        _ => 0.82,
      };
  final cejHalf = 0.66 * scale;
  final crownHalf = 0.88 * scale;
  final apexNy = rootApexNy ??
      switch (variant) {
        1 => 0.10,
        2 => 0.13,
        _ => 0.19,
      };
  final rootSpread = switch (variant) {
    1 => 0.54,
    2 => 0.40,
    _ => 0.24,
  };
  final distalBend = switch (variant) {
    1 => 0.05,
    2 => 0.12,
    _ => 0.20,
  };
  final furcationNy = variant == 3 ? 0.35 : 0.43;

  final roots = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..cubicTo(
      pt(-cejHalf * 1.02, 0.36).dx,
      pt(-cejHalf * 1.02, 0.36).dy,
      pt(-rootSpread, apexNy + 0.08).dx,
      pt(-rootSpread, apexNy + 0.08).dy,
      pt(-rootSpread * 0.78 + distalBend, apexNy).dx,
      pt(-rootSpread * 0.78 + distalBend, apexNy).dy,
    )
    ..quadraticBezierTo(
      pt(-0.12, 0.26).dx,
      pt(-0.12, 0.26).dy,
      pt(0.0, furcationNy).dx,
      pt(0.0, furcationNy).dy,
    )
    ..quadraticBezierTo(
      pt(0.14, 0.26).dx,
      pt(0.14, 0.26).dy,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.03).dx,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.03).dy,
    )
    ..cubicTo(
      pt(rootSpread + distalBend, apexNy + 0.10).dx,
      pt(rootSpread + distalBend, apexNy + 0.10).dy,
      pt(cejHalf * 1.02, 0.36).dx,
      pt(cejHalf * 1.02, 0.36).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..close();

  final crown = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.03).dx,
      pt(0, cejNy - 0.03).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalf, cejNy + 0.10).dx,
      pt(crownHalf, cejNy + 0.10).dy,
      pt(crownHalf, 0.79).dx,
      pt(crownHalf, 0.79).dy,
      pt(crownHalf * 0.85, 0.86).dx,
      pt(crownHalf * 0.85, 0.86).dy,
    );

  final details = <Path>[];

  if (variant == 1) {
    crown
      ..quadraticBezierTo(
        pt(crownHalf * 0.68, 0.93).dx,
        pt(crownHalf * 0.68, 0.93).dy,
        pt(crownHalf * 0.44, 0.86).dx,
        pt(crownHalf * 0.44, 0.86).dy,
      )
      ..quadraticBezierTo(
        pt(0.08, 0.97).dx,
        pt(0.08, 0.97).dy,
        pt(-crownHalf * 0.26, 0.87).dx,
        pt(-crownHalf * 0.26, 0.87).dy,
      )
      ..quadraticBezierTo(
        pt(-crownHalf * 0.58, 0.98).dx,
        pt(-crownHalf * 0.58, 0.98).dy,
        pt(-crownHalf * 0.86, 0.88).dx,
        pt(-crownHalf * 0.86, 0.88).dy,
      );

    details.add(
      Path()
        ..moveTo(pt(-crownHalf * 0.26, 0.87).dx, pt(-crownHalf * 0.26, 0.87).dy)
        ..lineTo(pt(-crownHalf * 0.24, cejNy + 0.12).dx,
            pt(-crownHalf * 0.24, cejNy + 0.12).dy),
    );
    details.add(
      Path()
        ..moveTo(pt(crownHalf * 0.44, 0.86).dx, pt(crownHalf * 0.44, 0.86).dy)
        ..lineTo(pt(crownHalf * 0.38, cejNy + 0.18).dx,
            pt(crownHalf * 0.38, cejNy + 0.18).dy),
    );
  } else {
    crown
      ..quadraticBezierTo(
        pt(crownHalf * 0.45, 0.95).dx,
        pt(crownHalf * 0.45, 0.95).dy,
        pt(0.0, 0.86).dx,
        pt(0.0, 0.86).dy,
      )
      ..quadraticBezierTo(
        pt(-crownHalf * 0.45, 0.97).dx,
        pt(-crownHalf * 0.45, 0.97).dy,
        pt(-crownHalf * 0.85, 0.87).dx,
        pt(-crownHalf * 0.85, 0.87).dy,
      );

    details.add(
      Path()
        ..moveTo(pt(0.0, 0.86).dx, pt(0.0, 0.86).dy)
        ..lineTo(pt(0.0, cejNy + 0.14).dx, pt(0.0, cejNy + 0.14).dy),
    );
  }

  crown
    ..cubicTo(
      pt(-crownHalf, 0.80).dx,
      pt(-crownHalf, 0.80).dy,
      pt(-crownHalf, cejNy + 0.10).dx,
      pt(-crownHalf, cejNy + 0.10).dy,
      pt(-cejHalf, cejNy).dx,
      pt(-cejHalf, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(-rootSpread * 0.65 + distalBend, apexNy + 0.08).dx,
        pt(-rootSpread * 0.65 + distalBend, apexNy + 0.08).dy)
    ..lineTo(
        pt(-0.34 * scale, cejNy + 0.15).dx, pt(-0.34 * scale, cejNy + 0.15).dy)
    ..lineTo(
        pt(0.34 * scale, cejNy + 0.15).dx, pt(0.34 * scale, cejNy + 0.15).dy)
    ..lineTo(pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dx,
        pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dy)
    ..lineTo(pt(0.10, cejNy + 0.02).dx, pt(0.10, cejNy + 0.02).dy)
    ..lineTo(pt(-0.10, cejNy + 0.02).dx, pt(-0.10, cejNy + 0.02).dy)
    ..close();

  return _ToothGeometry(
    roots: [roots],
    crown: crown,
    pulpAndCanals: [pulp],
    details: details,
  );
}
