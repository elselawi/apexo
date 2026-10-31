import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/ui/workspace/workspace_close_dialog.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A top-edge workspace command, beside the panel rather than over it.
/// Unsaved owners are counted, including retained visits; closing asks whether
/// to save or discard their work. A clean workspace still closes in one press.
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
  /// Drafts are edited in place, so sample their owners for the unsaved count.
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

  /// Fluent entrances travel a short way from their edge and decelerate.
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.25),
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
  int _dirtyCount = 0;
  bool _saving = false;
  bool _dialogOpen = false;

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

  void _sample() {
    final request = WorkspaceCloseRequest();
    final shown =
        _hasRoom && (request.panels.isNotEmpty || request.windows.isNotEmpty);
    final dirtyCount = request.dirtyCount;
    final saving = request.saving;
    if (!mounted ||
        (shown == _shown && dirtyCount == _dirtyCount && saving == _saving)) {
      return;
    }
    if (shown != _shown) {
      if (shown) {
        _entrance.forward();
      } else {
        _entrance.reverse();
      }
    }
    setState(() {
      _shown = shown;
      _dirtyCount = dirtyCount;
      _saving = saving;
      if (!shown) _hovered = false;
    });
  }

  Future<void> _closeAll() async {
    if (_dialogOpen) return;
    // Re-read on activation: a keystroke can land between samples.
    final request = WorkspaceCloseRequest();
    if (request.saving) return;
    if (request.dirtyCount == 0) {
      request.close();
      return;
    }
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        dismissWithEsc: false,
        builder: (_) => WorkspaceCloseDialog(request: request),
      );
    } finally {
      if (mounted) {
        setState(() => _dialogOpen = false);
        _sample();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    // Keep the command outside the panel, mirrored with the workspace in RTL.
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
      top: kWindowEdgeInset + MediaQuery.paddingOf(context).top,
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
                    constraints: BoxConstraints(
                      maxWidth:
                          (widget.screenWidth - widget.panelWidth - _margin * 2)
                              .clamp(0, double.infinity),
                    ),
                    child: Button(
                      key: WK.closeAllWindows,
                      onPressed: _saving || _dialogOpen ? null : _closeAll,
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
                          Flexible(
                            child: Txt(label,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (_dirtyCount > 0)
                            Tooltip(
                              message: txt('workspaceUnsavedCount')
                                  .replaceAll('{count}', '$_dirtyCount'),
                              child: Semantics(
                                label: txt('workspaceUnsavedCount')
                                    .replaceAll('{count}', '$_dirtyCount'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.accentColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: ExcludeSemantics(
                                    child: Text(
                                      '$_dirtyCount',
                                      style: TextStyle(
                                        color: theme.resources
                                            .textOnAccentFillColorPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
