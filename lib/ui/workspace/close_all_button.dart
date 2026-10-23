import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The way out of a clean workspace: one command button that puts every panel
/// and every floating window away at once.
///
/// It comes out only while something is open **and nothing holds work that has
/// not been stored**. A panel or window with unsaved work has its own Close,
/// which asks before throwing the work away; one button that silently closed
/// all of them would be the easiest way to lose a day's notes, so it stays
/// hidden until there is nothing to lose.
///
/// The button floats in the corner where the content meets the panel's own
/// start edge — beside the panel, never over it. With no panel open it takes
/// the same corner of the screen.
///
/// It wears the shape of a Fluent command rather than that of a round floating
/// action: the corner radius and hairline Fluent gives its controls, the one
/// soft shadow it gives a flyout, and the label spelled out beside the glyph, as
/// Fluent asks of any action whose glyph does not say it on its own.
///
/// The pointer is answered in three ways at once — the fill steps lighter, the
/// shadow reaches further out, and the whole control grows a little — so the one
/// press that empties the workspace can be felt coming from across the screen.
///
/// Its body is the same dark grey with white text that every Close in the app
/// wears — the window's and the dialog's — in either theme, so the last way out
/// of the workspace is recognisably the same kind of control as all the others.
class CloseAllButton extends StatefulWidget {
  const CloseAllButton({
    super.key,
    required this.screenWidth,
    required this.panelWidth,
  });

  /// The width of the screen it floats in.
  final double screenWidth;

  /// The width of the panel on screen, or 0 when none is open.
  final double panelWidth;

  @override
  State<CloseAllButton> createState() => _CloseAllButtonState();
}

class _CloseAllButtonState extends State<CloseAllButton>
    with SingleTickerProviderStateMixin {
  /// A draft is edited in place, and only its owner can say whether it differs
  /// from what is stored: the same sample a standalone window takes for its own
  /// unsaved dot, and often enough that the button is there the moment the last
  /// save lands.
  static const Duration _sampleEvery = Duration(milliseconds: 400);

  /// The gap between the button and the panel — or the screen — it sits beside.
  static const double _margin = 16;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    reverseDuration: const Duration(milliseconds: 167),
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  /// Rises into place rather than appearing where it will sit: the corner it
  /// belongs to is the one it comes up from. Fluent's entrances travel a short
  /// way and decelerate into place; nothing bounces.
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  ));

  Timer? _sampler;
  StreamSubscription<List<Panel>>? _panelsSub;
  StreamSubscription<List<FloatingWindow>>? _windowsSub;

  /// Whether the button is out of its corner.
  bool _shown = false;

  /// Whether the pointer is on it, for the lift it answers with.
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _panelsSub = PanelsManager.active.stream.listen((_) => _sample());
    _windowsSub = WindowsManager.stream.listen((_) => _sample());
    _sampler = Timer.periodic(_sampleEvery, (_) => _sample());
    _sample();
  }

  @override
  void didUpdateWidget(covariant CloseAllButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A panel opening or closing moves the corner the button belongs in, and a
    // narrow screen takes the room it needs away.
    _sample();
  }

  @override
  void dispose() {
    _sampler?.cancel();
    unawaited(_panelsSub?.cancel());
    unawaited(_windowsSub?.cancel());
    _entrance.dispose();
    super.dispose();
  }

  /// A panel fills the screen on a phone, and a narrow screen dims the app
  /// behind a barrier while one is open: there is no corner beside the panel to
  /// float in until the screen is wide enough to show both.
  bool get _hasRoom =>
      widget.panelWidth == 0 || widget.screenWidth >= kWindowsBreakpoint;

  /// There is something to close, and nothing on screen is holding work that
  /// closing it would throw away.
  ///
  /// A panel's floating windows save with the panel, so the panel's own answer
  /// covers them.
  bool get _allClean {
    final panels = PanelsManager.active();
    final floating = WindowsManager.open();
    if (panels.isEmpty && floating.isEmpty) return false;
    if (panels.any((panel) => panel.hasPendingEdits)) return false;
    return !floating.any((window) => window.hasChanges?.call() ?? false);
  }

  void _sample() {
    final shown = _hasRoom && _allClean;
    if (shown == _shown || !mounted) return;
    if (shown) {
      _entrance.forward();
    } else {
      _entrance.reverse();
    }
    setState(() {
      _shown = shown;
      // It leaves under a pointer that was on it: the hover it took with it
      // must not be waiting when it comes back.
      if (!shown) _hovered = false;
    });
  }

  /// Puts everything away at once. Everything is clean by the time this can be
  /// pressed, so nothing here needs a confirmation.
  void _closeAll() {
    // Read the workspace again: a press that landed as a draft was being typed
    // into must not close the window holding it.
    if (!_allClean) return;
    WindowsManager.closeAll();
    PanelsManager.closeAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    // The panel's start edge is the content's end edge: the button sits in the
    // content, beside the panel, at the bottom of both. It slides when that edge
    // moves, in step with the panel's own entrance.
    final edge = _margin + widget.panelWidth;
    final label = txt("closeAllWindows");
    // The elevation a flyout gets: one soft shadow, under a surface that keeps
    // its own hairline — rather than a stack of glows holding up a circle. On
    // the pointer it reaches a little further out, the way a lifted control
    // does, so the button is felt before it is read.
    final floatingShadow = BoxShadow(
      color: theme.shadowColor.withValues(alpha: _hovered ? 0.26 : 0.2),
      offset: _hovered ? const Offset(2, 3) : const Offset(1, 1),
      blurRadius: _hovered ? 18 : 10,
    );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      bottom: _margin + MediaQuery.paddingOf(context).bottom,
      right: ltr ? edge : null,
      left: ltr ? null : edge,
      child: IgnorePointer(
        ignoring: !_shown,
        child: ExcludeSemantics(
          excluding: !_shown,
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: AnimatedScale(
                  // Under the pointer the whole control steps up — body, glyph
                  // and label together, as one thing — instead of only its fill
                  // and shadow changing.
                  scale: _hovered ? 1.03 : 1,
                  duration: theme.fastAnimationDuration,
                  curve: theme.animationCurve,
                  child: AnimatedContainer(
                    duration: theme.fasterAnimationDuration,
                    curve: theme.animationCurve,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [floatingShadow],
                    ),
                    child: Button(
                      key: WK.closeAllWindows,
                      onPressed: _closeAll,
                      style: greyButtonStyle.copyWith(
                        // A step above a standard control's padding: this is pressed
                        // once at the end of a session, so it is given the room to
                        // be hit without aiming.
                        padding: const WidgetStatePropertyAll(
                          EdgeInsetsDirectional.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        iconSize: const WidgetStatePropertyAll(18),
                        textStyle: const WidgetStatePropertyAll(
                          TextStyle(fontSize: 15),
                        ),
                        backgroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          // The grey the Close buttons wear, a step lighter while
                          // the pointer is on it: a floating command still answers
                          // the pointer, and at rest it is the same control.
                          if (states.isPressed) return Colors.grey[140];
                          if (states.isHovered) return Colors.grey[150];
                          return Colors.grey;
                        }),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          const Icon(FluentIcons.remove_content),
                          Txt(label),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
