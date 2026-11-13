import 'dart:math' as math;

import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/ui/design/mica_backdrop.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// How tall a card floating over the chart may stand at rest: enough for the
/// operative form, little enough to keep most of the teeth in view.
const double kDentalChartCardMaxHeight = 300.0;

/// A card floating over the chart, and how much of that surface it covers: 0
/// at rest, 1 while a field on it is being edited. The card reads it to fold
/// away the tail that points at the teeth while it has the surface.
class DentalChartCardScope extends InheritedWidget {
  const DentalChartCardScope({
    super.key,
    required this.expansion,
    required super.child,
  });

  final Animation<double> expansion;

  static DentalChartCardScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DentalChartCardScope>();

  @override
  bool updateShouldNotify(DentalChartCardScope oldWidget) =>
      expansion != oldWidget.expansion;
}

/// A narrow chart with a card floating at its foot.
///
/// The card is a bubble at rest: the teeth are drawn at full size and scroll
/// behind it. Typing is what the bubble cannot hold — on a phone the keyboard
/// leaves it a third of the room it had — so while a field on it is being
/// edited the card unfolds over the chart, which dims and recedes behind it. A
/// band of the teeth stays uncovered, and tapping it only ends the edit: the
/// tap must not reach a tooth, or the wheel it opens would steal the
/// keyboard's dismissal.
class DentalChartOverlay extends StatefulWidget {
  const DentalChartOverlay({
    super.key,
    required this.chart,
    required this.card,
  });

  /// The teeth, drawn as wide as the screen and scrolled behind the card.
  final Widget chart;

  /// The card floating at the surface's foot.
  final Widget card;

  @override
  State<DentalChartOverlay> createState() => _DentalChartOverlayState();
}

class _DentalChartOverlayState extends State<DentalChartOverlay>
    with SingleTickerProviderStateMixin {
  /// Close to the keyboard's own entrance, so the two finish together.
  static const Duration _expandDuration = Duration(milliseconds: 260);
  static const Duration _collapseDuration = Duration(milliseconds: 200);

  /// The share of the surface the resting card covers, before its own ceiling.
  static const double _restShare = 0.6;

  /// A band of the dimmed teeth kept above the unfolded card: the card has the
  /// surface, but the teeth stay reachable enough to be the way out of it.
  static const double _peekMax = 52;
  static const double _peekShare = 0.14;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _expandDuration,
    reverseDuration: _collapseDuration,
  );

  /// Eases in one direction only: unfolding that slows as it lands reads as
  /// the card growing, not as a block sliding up.
  late final Animation<double> _coverage = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );

  late final Animation<double> _chartOpacity =
      Tween<double>(begin: 1, end: 0.82).animate(_coverage);
  late final Animation<double> _chartScale =
      Tween<double>(begin: 1, end: 0.97).animate(_coverage);

  final FocusNode _cardFocus = FocusNode(
    debugLabel: 'dentalChartCard',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// Whether a field on the card is being edited, which is what asks for the
  /// whole surface.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    // Focus moves between the card's fields without leaving the card, so the
    // manager is the level that can tell one field from the next.
    FocusManager.instance.addListener(_followFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A device that asked for no animation gets the unfolded card at once.
    final still = MediaQuery.disableAnimationsOf(context);
    _controller.duration = still ? Duration.zero : _expandDuration;
    _controller.reverseDuration = still ? Duration.zero : _collapseDuration;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_followFocus);
    _controller.dispose();
    _cardFocus.dispose();
    super.dispose();
  }

  /// Only typing unfolds the card: a button or a checkbox on it must not take
  /// the surface away from the feet.
  static bool _isTextField(FocusNode? node) =>
      node?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  void _followFocus() {
    if (!mounted) return;
    final editing =
        _cardFocus.hasFocus && _isTextField(FocusManager.instance.primaryFocus);
    if (editing == _editing) return;
    setState(() => _editing = editing);
    if (editing) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  /// Ends the edit without touching anything under the finger. The next tap
  /// lands on the chart, which is what makes "tap away" harmless.
  void _stopEditing() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final surface = constraints.maxHeight;
        final rest = math.min(surface * _restShare, kDentalChartCardMaxHeight);
        // A surface with no height to give (a chart laid out unbounded) has
        // nowhere to unfold to; the card keeps its resting ceiling.
        final unfolded = surface.isFinite
            ? surface - math.min(_peekMax, surface * _peekShare)
            : rest;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The teeth stay where they were, dimmed and a touch smaller, so
            // the card reads as being in front of them rather than replacing
            // them.
            Positioned.fill(
              child: ExcludeSemantics(
                excluding: _editing,
                child: FadeTransition(
                  opacity: _chartOpacity,
                  child: ScaleTransition(
                    scale: _chartScale,
                    child: SingleChildScrollView(
                      // The resting card covers the teeth's foot; scrolling
                      // clears it rather than hiding the last molars for good.
                      padding: EdgeInsets.only(bottom: rest),
                      child: widget.chart,
                    ),
                  ),
                ),
              ),
            ),
            // The pane the card unfolds onto: the chart behind softens into
            // frosted glass instead of a flat grey veil, and its rounded
            // corner keeps the teeth at the surface's corners, so the card
            // reads as a sheet laid on a surface rather than a block painted
            // over them.
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _coverage,
                  child: AcrylicSurface(
                    radius: 12,
                    blur: 16,
                    color: FluentMaterials.of(context)
                        .acrylic
                        .withValues(alpha: 0.38),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (_editing)
              Positioned.fill(
                child: GestureDetector(
                  key: WK.dentalChartOverlayBarrier,
                  behavior: HitTestBehavior.opaque,
                  onTap: _stopEditing,
                ),
              ),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _coverage,
                // The card is built once: only the room it is given changes.
                child: DentalChartCardScope(
                  expansion: _coverage,
                  child: Focus(
                    focusNode: _cardFocus,
                    skipTraversal: true,
                    canRequestFocus: false,
                    includeSemantics: false,
                    child: KeyedSubtree(
                      key: WK.dentalChartOverlayCard,
                      child: widget.card,
                    ),
                  ),
                ),
                builder: (context, child) => ConstrainedBox(
                  // A ceiling, not a height: a short card stays short, and a
                  // form longer than the surface unfolds to all of it, short of
                  // the band of teeth left to tap.
                  constraints: BoxConstraints(
                    maxHeight: rest + (unfolded - rest) * _coverage.value,
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
