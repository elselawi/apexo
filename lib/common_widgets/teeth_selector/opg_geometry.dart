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

  /// Root-to-crown drawing height. Anterior teeth (incisors and canines) are
  /// elongated vertically to utilize the vertical room at the top and bottom
  /// of the arch.
  final double length;
}

/// Places [isos] along one jaw's arch, sizing them by their share of the curve
/// so a molar still reads wider than an incisor on a phone. The seats come back
/// relative to the jaw's centre.
///
/// The teeth stand on the anatomical ovoid/pyramidal arch line their *crowns*
/// trace:
/// - Central and lateral incisors (`pos 1, 2`) sit along the anterior segment
///   with a slight midline diastema/gap between the two centrals and extra
///   breathing room + gentle rotation on the laterals.
/// - Canines (`pos 3`) sit squarely at the corner bend of the arch.
/// - Premolars and molars (`pos 4..8`) diverge progressively outward toward the
///   wisdom teeth, forming a pyramid on the upper jaw (and an inverted pyramid
///   on the lower jaw) that reaches the left and right edges of the chart.
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

  // Average tooth span estimate so the crown curve sits inside the outer arch
  // boundary by the radial distance from crown to root tip.
  final approxArc = _archArc(rx: rx, ry: ry);
  final avgDrawSpan = (approxArc / isos.length) * toothFill;
  final avgHalfLen = avgDrawSpan * 0.78;

  // Keep a small radial inset at the top/bottom (where incisors stand upright)
  // and a slightly smaller horizontal inset at the posterior ends (where tilted
  // wisdom teeth reach outward).
  final crownRx = math.max(12.0, rx - avgHalfLen * 0.62);
  final crownRy = math.max(12.0, ry - avgHalfLen * 0.85);

  Offset crownPoint(double progress) =>
      _archPointAt(progress, rx: crownRx, ry: crownRy);

  // Arc-length parameterization table so every tooth receives its exact
  // mesiodistal share of the arch curve.
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

  // Anchor the canine (`pos 3`) at the exact midpoint of the arch corner, and
  // keep the four incisors (`pos 1, 2` on both sides) inside the anterior
  // segment with breathing room between the two centrals and between each
  // lateral and its neighbouring central.
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

  // Leave a distinct midline gap between the left and right central incisors
  // (`0.491` vs `0.509`), and shift the lateral incisors slightly outward
  // toward the canine corner so they have breathing room away from the
  // centrals.
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
        // Nudge the lateral incisor slightly away from the central incisor for
        // extra interproximal breathing room.
        mapped -= 0.0045;
      }
    }
    return mirrored ? (1.0 - mapped) : mapped;
  }

  final half = (isos.length - 1) / 2;
  final avgAnteriorShare = (weights[isos.length ~/ 2] +
          weights[(isos.length ~/ 2 - 1).clamp(0, isos.length - 1)]) /
      (2 * total);

  // Anterior teeth (`pos 1, 2, 3`) get a larger width & vertical length boost
  // so they stand out prominently and utilize the vertical room at the top and
  // bottom of each arch.
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

/// How much of the notation's own size a compact tooth can carry: scaled down
/// so Palmer / ISO / Universal labels never overlap on small phone screens.
double _notationScale(double band, double toothSpan) => math.min(
      (band / 24.0).clamp(0.46, 0.72),
      toothSpan <= 0 ? 0.65 : (toothSpan / 29.0).clamp(0.44, 0.72),
    );

/// The length of the curve an [rx]×[ry] arch runs, which is also the total
/// width of the teeth that stand on it.
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

/// How far a tooth leans off upright, in radians, and which way.
///
/// Uses explicit anatomical tooth angles by position (`1..8` / `1..5`) so that:
/// - Central incisors (`pos 1`) stand nearly vertical (`~2°`).
/// - Lateral incisors (`pos 2`) have only a gentle tilt (`~9°`), staying part
///   of the anterior front row rather than turning the corner.
/// - Canines (`pos 3`) sit right at the ~38° corner angle of the arch.
/// - First and second premolars (`pos 4, 5`) and molars (`pos 6, 7, 8`) open
///   progressively along the ovoid/pyramidal buccal slope (`~50°–60°`).
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

/// Share of `rx` occupied by the anterior incisor segment (`12–11–21–22`).
/// Sized so the two central incisors have a clear midline space between them
/// and the lateral incisors have breathing room away from the centrals while
/// the canines remain on the arch corners.
const double _archFrontHalfShare = 0.295;

/// Radius of the canine corner bend as a fraction of the smaller half-axis.
const double _archCornerShare = 0.22;

/// Outward divergence angle (radians, `~27.5°` off vertical) of the posterior
/// buccal segments from the canine corner out to the wisdom teeth: each
/// successive tooth (`4 -> 5 -> 6 -> 7 -> 8`) sits progressively further apart
/// horizontally than the pair before it, forming a pyramid on the upper jaw and
/// an inverted pyramid on the lower jaw.
const double _archPosteriorSplay = 0.48;

/// Returns the arc-length fractions along `_archPointAt` where the right-side
/// canine corner midpoint and inner end sit, so `_seatsAlongArch` can lock the
/// canine (`pos 3`) onto the corner and keep the lateral incisor (`pos 2`) on
/// the anterior segment.
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

/// A point along one jaw's anatomical ovoid/pyramidal arch curve.
///
/// [progress] runs `0 → 1` from the patient's right third molar (`18`/`48`) to
/// their left (`28`/`38`), laid out in upper-jaw coordinates (`y = -ry` at the
/// anterior midline, `y = 0` at the posterior ends):
/// 1. Patient's right posterior buccal segment (`18 → 14`), sloping inward from
///    `-rx` toward the canine corner so `18–28` are widest apart, `17–27`
///    slightly narrower, `16–26` narrower still, `15–25` narrower, and `14–24`
///    narrower approaching the canine.
/// 2. Right canine corner arc (`13`/`43`), where the buccal slope bends into
///    the anterior segment.
/// 3. Gently curved anterior incisor segment (`12, 11, 21, 22`).
/// 4. Left canine corner arc (`23`/`33`).
/// 5. Patient's left posterior buccal segment (`24 → 28`), flaring outward to
///    `+rx`.
Offset _archPointAt(
  double progress, {
  required double rx,
  required double ry,
}) {
  final m = _archCurveMetrics(rx: rx, ry: ry);
  if (m.total <= 0) return Offset.zero;

  var left = progress.clamp(0.0, 1.0) * m.total;

  // 1. Patient's right posterior buccal segment (18..14 -> 13): gently bowed
  // ovoid curve from (-rx, 0) up and inward to rightCornerStart.
  if (left <= m.sideLen) {
    final t = m.sideLen == 0 ? 0.0 : (left / m.sideLen).clamp(0.0, 1.0);
    // Slight outward ovoid belly so the molars/premolars trace a natural dental
    // arch while monotonically widening from 14 out to 18.
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
    // Subtle anterior arch curvature (1.5px crown dome at central incisors) so
    // the four incisors stay level while reading as a natural anterior curve.
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

/// The box the teeth of a jaw occupy, relative to that jaw's centre: matches
/// the exact rotated bounding box of each `_compactTooth` (`seat.length +
/// band * 1.1` tall by `seat.drawSpan` wide) so the arch fills the full
/// horizontal width right to `0..width` without overflowing.
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

/// Where one facing pair of compact arches sits, and the seats its teeth
/// stand on.
class _CompactPairLayout {
  const _CompactPairLayout({
    required this.toothBand,
    required this.upperCenter,
    required this.lowerCenter,
    required this.upperSeats,
    required this.lowerSeats,
  });

  /// Room each tooth keeps beyond its root tip (the apex icons) and beyond its
  /// crown (its notation).
  final double toothBand;
  final Offset upperCenter;
  final Offset lowerCenter;
  final List<_ArchSeat> upperSeats;
  final List<_ArchSeat> lowerSeats;
}

/// Lays one facing pair of jaws into [band], sizing the curve to the room it is
/// given: the teeth are only ever as big as the curve they stand on, so a
/// taller chart buys bigger teeth rather than more empty space in the middle of
/// the mouth. How they fan is [_seatsAlongArch]'s business; the fit here only
/// decides how large the mouth ends up.
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

    // The pair is as tall as its two jaws plus the daylight between them, and
    // the curve grows a little slower than that, so the step is damped.
    final upperExtent = _seatsExtent(upperSeats, toothBand);
    final lowerExtent = _seatsExtent(lowerSeats, toothBand);
    final needed = (upperExtent.bottom - upperExtent.top) +
        (lowerExtent.bottom - lowerExtent.top) +
        jawGap;
    ry = math.max(20.0, ry + (band.height - needed) / 2.2);

    // Stretch rx so the outermost posterior teeth reach the left and right
    // edges of the canvas.
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
