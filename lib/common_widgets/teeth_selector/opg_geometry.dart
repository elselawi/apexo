part of 'opg_dental_chart.dart';

class _ArchSeat {
  const _ArchSeat({
    required this.iso,
    required this.center,
    required this.rotation,
    required this.span,
    required this.drawSpan,
    required this.length,
  });

  final String iso;
  final Offset center;
  final double rotation;

  /// Arc length the tooth owns on the curve.
  final double span;

  /// Width the tooth is drawn at, which is its own share of the curve.
  final double drawSpan;

  /// Root-to-crown drawing height.
  final double length;
}

/// Seats for [isos] along a jaw's arch, sized by each tooth's share of the
/// curve length; offsets are relative to the jaw's centre.
List<_ArchSeat> _seatsAlongArch({
  required List<String> isos,
  required bool isUpper,
  required double rx,
  required double ry,
  double toothFill = 1.0,
}) {
  final weights = [
    for (final iso in isos) _toothWidthWeight(iso).toDouble(),
  ];
  final total = weights.fold<double>(0, (sum, weight) => sum + weight);

  // Average tooth size, used to keep the crown curve inside the outer arch.
  final approxArc = _archArc(rx: rx, ry: ry);
  final avgDrawSpan = (approxArc / isos.length) * toothFill;
  final avgHalfLen = avgDrawSpan * 0.78;

  // Tilted posterior teeth reach outward, so the horizontal inset is smaller.
  final crownRx = math.max(12.0, rx - avgHalfLen * 0.62);
  final crownRy = math.max(12.0, ry - avgHalfLen * 0.85);

  Offset crownPoint(double progress) =>
      _archPointAt(progress, rx: crownRx, ry: crownRy);

  // Arc-length table so shares are measured along the curve, not by angle.
  const steps = 240;
  final lengths = List<double>.filled(steps + 1, 0);
  var previous = crownPoint(0);
  for (var step = 1; step <= steps; step++) {
    final point = crownPoint(step / steps);
    lengths[step] = lengths[step - 1] + (point - previous).distance;
    previous = point;
  }
  final arc = lengths[steps];

  double progressForShare(double share) {
    final target = share.clamp(0.0, 1.0) * arc;
    var low = 0;
    var high = steps;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lengths[middle] < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = low.clamp(1, steps);
    final segment = lengths[index] - lengths[index - 1];
    final within = segment == 0 ? 0.0 : (target - lengths[index - 1]) / segment;
    return (index - 1 + within) / steps;
  }

  // Lock the canine to the corner midpoint, laterals to the anterior segment.
  final cornerBounds = _archCornerShareBounds(rx: crownRx, ry: crownRy);
  final anteriorStartIdx = isos.indexWhere((iso) => iso.endsWith('2'));
  final canineIdx = isos.indexWhere((iso) => iso.endsWith('3'));

  double weightUpTo(int endExclusive) {
    var s = 0.0;
    for (var i = 0; i < endExclusive; i++) {
      s += weights[i];
    }
    return s / total;
  }

  final rightCanineMidRaw = canineIdx >= 0
      ? weightUpTo(canineIdx) + (weights[canineIdx] / total) * 0.5
      : 0.0;
  final rightAnteriorStartRaw =
      anteriorStartIdx > 0 ? weightUpTo(anteriorStartIdx) : 0.0;
  final targetCanineMid = cornerBounds.rightCornerMid;
  final targetAnteriorStart = cornerBounds.rightCornerEnd;

  const midlineHalfGap = 0.009;
  const anteriorEnd = 0.5 - midlineHalfGap;

  double remapShare(double rawShare, int pos) {
    if (anteriorStartIdx <= 0 || canineIdx < 0) return rawShare;

    final mirrored = rawShare > 0.5;
    final s = mirrored ? (1.0 - rawShare) : rawShare;
    double mapped;
    if (s <= rightCanineMidRaw) {
      mapped = rightCanineMidRaw <= 0
          ? s
          : (s / rightCanineMidRaw) * targetCanineMid;
    } else if (s <= rightAnteriorStartRaw) {
      final t = (s - rightCanineMidRaw) /
          math.max(1e-6, rightAnteriorStartRaw - rightCanineMidRaw);
      mapped = targetCanineMid + t * (targetAnteriorStart - targetCanineMid);
    } else {
      final t = (s - rightAnteriorStartRaw) /
          math.max(1e-6, 0.5 - rightAnteriorStartRaw);
      mapped = targetAnteriorStart + t * (anteriorEnd - targetAnteriorStart);
      if (pos == 2) {
        // Extra interproximal gap between the lateral and central incisors.
        mapped -= 0.0045;
      }
    }
    return mirrored ? (1.0 - mapped) : mapped;
  }

  final half = (isos.length - 1) / 2;
  final avgAnteriorShare = (weights[isos.length ~/ 2] +
          weights[(isos.length ~/ 2 - 1).clamp(0, isos.length - 1)]) /
      (2 * total);

  double widthFactorForPos(int pos) => switch (pos) {
        1 => 1.15,
        2 => 1.14,
        3 => 1.10,
        _ => 1.0,
      };

  double lengthAspectForPos(int pos) => switch (pos) {
        1 => 1.72,
        2 => 1.68,
        3 => 1.62,
        4 => 1.50,
        _ => 1.44,
      };

  final avgAnteriorLength = arc *
      avgAnteriorShare *
      toothFill *
      widthFactorForPos(1) *
      lengthAspectForPos(1);

  final seats = <_ArchSeat>[];
  var walked = 0.0;
  for (var index = 0; index < isos.length; index++) {
    final iso = isos[index];
    final pos = int.parse(iso[1]);
    final share = weights[index] / total;
    final midShare = remapShare(walked + share / 2, pos);
    final progress = progressForShare(midShare);
    final crown = crownPoint(progress);
    final rotation = _fanTilt(
      iso,
      index,
      half,
      isUpper: isUpper,
    );
    final span = arc * share;
    final drawSpan = span * toothFill * widthFactorForPos(pos);
    final length = drawSpan * lengthAspectForPos(pos);
    final isIncisor = (index - half).abs() <= 1.6;
    final centerOffsetLen =
        isIncisor ? (length * 0.45 + avgAnteriorLength * 0.55) : length;
    // The tooth grows outward from its crown, which is the point on the curve.
    final axis = _toothAxis(rotation, isUpper: isUpper);
    seats.add(_ArchSeat(
      iso: iso,
      center: (isUpper ? crown : Offset(crown.dx, -crown.dy)) +
          axis * (centerOffsetLen / 2),
      rotation: rotation,
      span: span,
      drawSpan: drawSpan,
      length: length,
    ));
    walked += share;
  }
  return seats;
}

/// Fraction of a notation's font size a compact tooth can carry, so the labels
/// do not overlap on small screens.
double _notationScale(double band, double toothSpan) => math.min(
      (band / 24.0).clamp(0.46, 0.72),
      toothSpan <= 0 ? 0.65 : (toothSpan / 29.0).clamp(0.44, 0.72),
    );

/// Arc length of an [rx]×[ry] arch, i.e. the total tooth width it holds.
double _archArc({required double rx, required double ry}) {
  const steps = 80;
  var length = 0.0;
  var previous = _archPointAt(0, rx: rx, ry: ry);
  for (var step = 1; step <= steps; step++) {
    final point = _archPointAt(step / steps, rx: rx, ry: ry);
    length += (point - previous).distance;
    previous = point;
  }
  return length;
}

/// How far a tooth leans off upright, in radians; the sign flips on the
/// patient's right side and again on the lower jaw.
double _fanTilt(
  String iso,
  int index,
  double half, {
  required bool isUpper,
}) {
  if (half <= 0) return 0;
  final pos = int.parse(iso[1]);
  final isPrimary = int.parse(iso[0]) >= 5;

  final double lean = isPrimary
      ? switch (pos) {
          1 => 0.04, // ~2.3°
          2 => 0.24, // ~13.8°
          3 => 0.64, // ~36.7° (canine at the arch corner)
          4 => 0.86, // ~49.3°
          _ => 0.96, // ~55.0°
        }
      : switch (pos) {
          1 => 0.035, // ~2.0°  central incisor (upright)
          2 => 0.23, // ~13.2° lateral incisor (gentle flair away from central)
          3 => 0.66, // ~37.8° canine (cornerstone at the angle of the arch)
          4 => 0.84, // ~48.1° first premolar
          5 => 0.90, // ~51.6° second premolar
          6 => 0.94, // ~53.9° first molar
          7 => 0.97, // ~55.6° second molar
          _ => 1.00, // ~57.3° wisdom tooth / third molar
        };

  final side = index < half ? -1.0 : 1.0;
  return lean * side * (isUpper ? 1 : -1);
}

/// The direction a tooth's root points in when it is turned by [rotation].
Offset _toothAxis(double rotation, {required bool isUpper}) => isUpper
    ? Offset(math.sin(rotation), -math.cos(rotation))
    : Offset(-math.sin(rotation), math.cos(rotation));

/// Anterior incisor segment width as a share of `rx`.
const double _archFrontHalfShare = 0.295;

/// Radius of the canine corner bend as a fraction of the smaller half-axis.
const double _archCornerShare = 0.22;

/// Posterior buccal divergence from vertical, in radians (~27.5°).
const double _archPosteriorSplay = 0.48;

/// Arc-length fractions on `_archPointAt` where the right canine corner's
/// midpoint and inner end sit.
({double rightCornerMid, double rightCornerEnd}) _archCornerShareBounds({
  required double rx,
  required double ry,
}) {
  final geom = _archCurveMetrics(rx: rx, ry: ry);
  if (geom.total <= 0) {
    return (rightCornerMid: 0.30, rightCornerEnd: 0.35);
  }
  return (
    rightCornerMid: (geom.sideLen + geom.bendLen * 0.5) / geom.total,
    rightCornerEnd: (geom.sideLen + geom.bendLen * 0.92) / geom.total,
  );
}

({
  double frontHalf,
  double corner,
  double sweep,
  double cosS,
  double sinS,
  double rightCx,
  double rightCy,
  Offset rightCornerStart,
  Offset rightEnd,
  double sideLen,
  double bendLen,
  double frontLen,
  double total,
}) _archCurveMetrics({required double rx, required double ry}) {
  final frontHalf = rx * _archFrontHalfShare;
  final maxCorner = math.min(rx - frontHalf, ry) * 0.55;
  final double corner = (math.min(rx, ry) * _archCornerShare)
      .clamp(2.0, math.max(2.0, maxCorner));

  const sweep = (math.pi / 2) - _archPosteriorSplay;
  final cosS = math.cos(_archPosteriorSplay);
  final sinS = math.sin(_archPosteriorSplay);

  final rightCx = -frontHalf;
  final rightCy = -(ry - corner);

  final rightCornerStart = Offset(
    rightCx - corner * cosS,
    rightCy - corner * sinS,
  );
  final rightEnd = Offset(-rx, 0);

  final sideLen = (rightCornerStart - rightEnd).distance;
  final bendLen = sweep * corner;
  final frontLen = 2 * frontHalf;
  final total = 2 * sideLen + 2 * bendLen + frontLen;

  return (
    frontHalf: frontHalf,
    corner: corner,
    sweep: sweep,
    cosS: cosS,
    sinS: sinS,
    rightCx: rightCx,
    rightCy: rightCy,
    rightCornerStart: rightCornerStart,
    rightEnd: rightEnd,
    sideLen: sideLen,
    bendLen: bendLen,
    frontLen: frontLen,
    total: total,
  );
}

/// A point on one jaw's arch; [progress] runs 0→1 from the patient's right third
/// molar to the left, in upper-jaw coordinates (`y = -ry` at the midline).
Offset _archPointAt(
  double progress, {
  required double rx,
  required double ry,
}) {
  final m = _archCurveMetrics(rx: rx, ry: ry);
  if (m.total <= 0) return Offset.zero;

  var left = progress.clamp(0.0, 1.0) * m.total;

  // 1. Right posterior run: bowed from (-rx, 0) to the corner start.
  if (left <= m.sideLen) {
    final t = m.sideLen == 0 ? 0.0 : (left / m.sideLen).clamp(0.0, 1.0);
    // Outward belly so the posterior run bows instead of running straight.
    final linear = Offset.lerp(m.rightEnd, m.rightCornerStart, t)!;
    final belly = math.sin(t * math.pi) * (rx - m.frontHalf) * 0.08;
    return Offset(linear.dx - belly, linear.dy);
  }
  left -= m.sideLen;

  // 2. Right canine corner (13 / 43)
  if (left <= m.bendLen) {
    final theta = (math.pi + _archPosteriorSplay) + (left / m.corner);
    return Offset(
      m.rightCx + m.corner * math.cos(theta),
      m.rightCy + m.corner * math.sin(theta),
    );
  }
  left -= m.bendLen;

  // 3. Anterior incisor segment (12, 11, 21, 22)
  if (left <= m.frontLen) {
    final u = m.frontLen == 0 ? 0.5 : (left / m.frontLen).clamp(0.0, 1.0);
    // 1.5px dome so the four incisors read as a curve, not a flat line.
    final dome = math.sin(u * math.pi) * 1.5;
    return Offset(-m.frontHalf + left, -ry - dome);
  }
  left -= m.frontLen;

  // 4. Left canine corner (23 / 33)
  if (left <= m.bendLen) {
    final theta = (3 * math.pi / 2) + (left / m.corner);
    return Offset(
      m.frontHalf + m.corner * math.cos(theta),
      m.rightCy + m.corner * math.sin(theta),
    );
  }
  left -= m.bendLen;

  // 5. Patient's left posterior buccal segment (24..28)
  final leftCornerEnd = Offset(
    m.frontHalf + m.corner * m.cosS,
    m.rightCy - m.corner * m.sinS,
  );
  final leftEnd = Offset(rx, 0);
  final t = m.sideLen == 0 ? 1.0 : (left / m.sideLen).clamp(0.0, 1.0);
  final linear = Offset.lerp(leftCornerEnd, leftEnd, t)!;
  final belly = math.sin(t * math.pi) * (rx - m.frontHalf) * 0.08;
  return Offset(linear.dx + belly, linear.dy);
}

/// Rotated bounding box of a jaw's teeth plus the `band` padding around them.
({double left, double right, double top, double bottom}) _seatsExtent(
  List<_ArchSeat> seats,
  double band,
) {
  var left = double.infinity;
  var right = -double.infinity;
  var top = double.infinity;
  var bottom = -double.infinity;
  final pad = band * 0.55;
  for (final seat in seats) {
    final cos = math.cos(seat.rotation).abs();
    final sin = math.sin(seat.rotation).abs();
    final halfHeight =
        (seat.length / 2 + pad) * cos + (seat.drawSpan / 2) * sin;
    final halfWidth = (seat.length / 2 + pad) * sin + (seat.drawSpan / 2) * cos;
    left = math.min(left, seat.center.dx - halfWidth);
    right = math.max(right, seat.center.dx + halfWidth);
    top = math.min(top, seat.center.dy - halfHeight);
    bottom = math.max(bottom, seat.center.dy + halfHeight);
  }
  return (left: left, right: right, top: top, bottom: bottom);
}

class _CompactPairLayout {
  const _CompactPairLayout({
    required this.toothBand,
    required this.upperCenter,
    required this.lowerCenter,
    required this.upperSeats,
    required this.lowerSeats,
  });

  /// Space each tooth keeps past root tip (apex icons) and crown (notation).
  final double toothBand;
  final Offset upperCenter;
  final Offset lowerCenter;
  final List<_ArchSeat> upperSeats;
  final List<_ArchSeat> lowerSeats;
}

/// Fits one facing pair of jaws into [band]: a taller chart buys bigger teeth
/// rather than more empty space in the middle.
_CompactPairLayout _layoutCompactPair({
  required double width,
  required Rect band,
  required List<String> upperIsos,
  required List<String> lowerIsos,
  required double toothBand,
  required double jawGap,
  double toothFill = 1.0,
}) {
  var rx = math.max(24.0, width / 2 - toothBand * 2);
  var ry = math.max(20.0, band.height / 5);
  late List<_ArchSeat> upperSeats;
  late List<_ArchSeat> lowerSeats;

  for (var pass = 0; pass < 8; pass++) {
    upperSeats = _seatsAlongArch(
      isos: upperIsos,
      isUpper: true,
      rx: rx,
      ry: ry,
      toothFill: toothFill,
    );
    lowerSeats = _seatsAlongArch(
      isos: lowerIsos,
      isUpper: false,
      rx: rx,
      ry: ry,
      toothFill: toothFill,
    );

    // Damped step: ry grows slower than the measured shortfall.
    final upperExtent = _seatsExtent(upperSeats, toothBand);
    final lowerExtent = _seatsExtent(lowerSeats, toothBand);
    final needed = (upperExtent.bottom - upperExtent.top) +
        (lowerExtent.bottom - lowerExtent.top) +
        jawGap;
    ry = math.max(20.0, ry + (band.height - needed) / 2.2);

    // Damped stretch so the outermost posterior teeth reach the canvas edges.
    final widest = <double>[
      upperExtent.right.abs(),
      upperExtent.left.abs(),
      lowerExtent.right.abs(),
      lowerExtent.left.abs(),
    ].reduce(math.max);
    rx = math.max(24.0, rx + 0.92 * (width / 2 - 1 - widest));
  }

  final upperExtent = _seatsExtent(upperSeats, toothBand);
  final lowerExtent = _seatsExtent(lowerSeats, toothBand);
  return _CompactPairLayout(
    toothBand: toothBand,
    upperCenter: Offset(width / 2, band.top - upperExtent.top),
    lowerCenter: Offset(width / 2, band.bottom - lowerExtent.bottom),
    upperSeats: upperSeats,
    lowerSeats: lowerSeats,
  );
}

class _ToothHistoryEntry {
  const _ToothHistoryEntry({
    required this.isCurrentDraft,
    required this.label,
    this.condition,
    this.extraNote,
    this.appointmentId,
    this.isBaseline = false,
  });

  final bool isCurrentDraft;
  final String label;
  final String? condition;
  final String? extraNote;
  final String? appointmentId;
  final bool isBaseline;
}

class _ToothOperationLayer {
  const _ToothOperationLayer({
    required this.operation,
    required this.color,
    required this.isCurrentDraft,
  });

  final String operation;
  final Color color;
  final bool isCurrentDraft;

  @override
  bool operator ==(Object other) =>
      other is _ToothOperationLayer &&
      other.operation == operation &&
      other.color == color &&
      other.isCurrentDraft == isCurrentDraft;

  @override
  int get hashCode => Object.hash(operation, color, isCurrentDraft);
}
