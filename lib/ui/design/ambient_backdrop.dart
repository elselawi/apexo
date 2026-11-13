import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

/// The material a window is made of where it cannot sample the desktop.
///
/// Windows hands the wallpaper to DWM and gets Mica back: blurred, tinted and
/// composed behind the window. A phone, a browser and a Mac have nothing to
/// sample, so this paints the stand-in — the same neutral base and the same
/// tint, with a few very large, very soft colour clouds drifting underneath
/// them. The motion is slow enough that it is felt rather than watched; it is
/// what keeps the material from reading as a flat grey page.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> {
  /// One full drift of every cloud.
  static const _period = Duration(seconds: 72);

  /// No cloud moves more than a pixel or two between steps, so a step every
  /// sixth of a second is indistinguishable from a smooth one. A timer rather
  /// than a ticker on purpose: it lets the engine sleep in between instead of
  /// asking for sixty frames a second to move a haze a pixel.
  static const _step = Duration(milliseconds: 150);

  /// Where the material rests when motion is turned off: the clouds spread out,
  /// not caught halfway through a move.
  static const _restingPhase = 0.27;

  final ValueNotifier<double> _phase = ValueNotifier(_restingPhase);
  Timer? _drift;

  /// Where in the cycle the drift is, from 0 to 1. It starts on the resting
  /// frame, so the first step moves the clouds on instead of snapping them
  /// somewhere else.
  double _cycle = _restingPhase;

  void _advance() {
    _cycle = (_cycle + _step.inMilliseconds / _period.inMilliseconds) % 1;
    _phase.value = _cycle;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion leaves the material still, on a composition that does not
    // look like the clouds stopped halfway.
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _drift?.cancel();
      _drift = null;
      _cycle = _restingPhase;
      _phase.value = _restingPhase;
    } else {
      _drift ??= Timer.periodic(_step, (_) => _advance());
    }
  }

  @override
  void dispose() {
    _drift?.cancel();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Its own layer: the drift repaints this and nothing else.
        RepaintBoundary(
          child: CustomPaint(
            painter: AmbientMaterial(
              materials: FluentMaterials.of(context),
              phase: _phase,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Paints [AmbientBackdrop]: the Mica base, the colour clouds over it, and the
/// tint that keeps text legible through both.
class AmbientMaterial extends CustomPainter {
  AmbientMaterial({
    required this.materials,
    required ValueListenable<double> phase,
  })  : _phase = phase,
        super(repaint: phase);

  final FluentMaterials materials;

  final ValueListenable<double> _phase;

  /// How far through the cycle the clouds are, from 0 to 1.
  @visibleForTesting
  double get phase => _phase.value;

  static const _turn = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = materials.micaBase;
    canvas.drawRect(rect, Paint()..color = base);

    final phase = _phase.value;
    for (final cloud in _clouds) {
      _paintCloud(canvas, size, cloud, phase);
    }

    final tint = materials.micaTint;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [tint, Color.lerp(tint, base, 0.3)!],
        ),
    );
  }

  void _paintCloud(Canvas canvas, Size size, _Cloud cloud, double phase) {
    final washes = materials.ambientWashes;
    final wash = washes[cloud.wash % washes.length];
    final turn = _turn * (phase * cloud.tempo + cloud.drift);

    final centre = Offset(
      (cloud.centre.dx + cloud.orbit.dx * math.sin(turn)) * size.width,
      (cloud.centre.dy + cloud.orbit.dy * math.cos(turn)) * size.height,
    );
    // The breath trails the wander by a quarter of a lap, so a cloud is already
    // on its way out while it swells.
    final radius =
        cloud.radius * size.shortestSide * (1 + 0.16 * math.sin(turn + 1.6));
    final alpha = materials.ambientStrength * cloud.strength;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          radius,
          [
            wash.withValues(alpha: alpha),
            wash.withValues(alpha: alpha * 0.88),
            wash.withValues(alpha: alpha * 0.56),
            wash.withValues(alpha: alpha * 0.19),
            wash.withValues(alpha: 0),
          ],
          const [0, 0.25, 0.5, 0.75, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant AmbientMaterial oldDelegate) =>
      oldDelegate.materials.brightness != materials.brightness ||
      oldDelegate.materials.ambientStrength != materials.ambientStrength;
}

/// One cloud: a soft disc of colour that wanders slowly around a corner of the
/// window, breathing as it goes.
class _Cloud {
  const _Cloud({
    required this.centre,
    required this.radius,
    required this.orbit,
    required this.drift,
    required this.tempo,
    required this.wash,
    required this.strength,
  });

  /// Where it sits, as a fraction of the window. The corners are pushed out of
  /// the window so only the soft shoulder of each cloud is on screen.
  final Offset centre;

  /// Its radius, as a fraction of the window's shorter side.
  final double radius;

  /// How far its centre wanders, as a fraction of the window.
  final Offset orbit;

  /// Where it starts in the cycle, so the clouds never move in lockstep.
  final double drift;

  /// How many laps it makes over the cycle.
  final double tempo;

  /// Which wash from [FluentMaterials.ambientWashes] it carries.
  final int wash;

  final double strength;
}

/// One cloud per corner, so no part of the window is ever flat. The colours are
/// cool at the top and warm at the bottom, the way a tinted wallpaper reads.
const _clouds = <_Cloud>[
  _Cloud(
    centre: Offset(-0.05, -0.04),
    radius: 0.95,
    orbit: Offset(0.05, 0.04),
    drift: 0,
    tempo: 0.8,
    wash: 0,
    strength: 0.26,
  ),
  _Cloud(
    centre: Offset(1.02, 0.10),
    radius: 0.82,
    orbit: Offset(0.04, 0.06),
    drift: 0.35,
    tempo: 0.6,
    wash: 1,
    strength: 0.22,
  ),
  _Cloud(
    centre: Offset(0.22, 1.04),
    radius: 0.86,
    orbit: Offset(0.06, 0.03),
    drift: 0.62,
    tempo: 0.9,
    wash: 2,
    strength: 0.22,
  ),
  _Cloud(
    centre: Offset(0.90, 0.94),
    radius: 0.74,
    orbit: Offset(0.05, 0.05),
    drift: 0.85,
    tempo: 0.7,
    wash: 3,
    strength: 0.20,
  ),
];
