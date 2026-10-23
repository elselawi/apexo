import 'dart:async';
import 'dart:math' as math;

import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panel_width.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_defaults.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_workspace.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panel_window_card.dart';
import 'package:apexo/ui/workspace/standalone_window_card.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:fluent_ui/fluent_ui.dart';

part 'window_entry.dart';
part 'window_entrance.dart';
part 'window_building.dart';

/// How long a window takes to grow out of the dock, and to fold back into it.
const Duration _openDuration = Duration(milliseconds: 200);
const Duration _closeDuration = Duration(milliseconds: 150);

/// Every window the app floats above itself: a panel's own windows, and the
/// windows that stand on their own — a record opened from a table, a scan, a
/// photo.
///
/// Each sits wherever it was put, in a stack you can drag windows around in, and
/// each is as tall as its content. On a phone, where nothing fits beside a panel,
/// the newest one comes over it as a sheet that slides down from the top edge —
/// the same edge the dock's buttons sit on.
class WindowsLayer extends StatelessWidget {
  const WindowsLayer({
    super.key,
    required this.visible,
    required this.screenWidth,
    this.defaults,
    this.refreshStreams = const <Stream<Object?>>[],
  });

  /// False outside the staff app (login, the patient side), where nothing
  /// floats.
  final bool visible;

  final double screenWidth;

  /// Where the windows each kind of panel was left with are remembered. The host
  /// passes the settings store; a test passes its own. Null uses [windowDefaults],
  /// which remembers nothing until a host binds it.
  final WindowDefaults? defaults;

  /// What else a window's labels read, so a record edited elsewhere relabels the
  /// window that shows it. The host passes its stores; the layer itself knows no
  /// store, no feature and no record — which is what keeps it below both.
  final List<Stream<Object?>> refreshStreams;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return MStreamBuilder<Object?>(
      streams: [
        PanelsManager.active.stream,
        PanelsManager.minimize.stream,
        WindowsManager.stream,
        ...refreshStreams,
      ],
      builder: (context, _) {
        final panels = PanelsManager.active();
        final panel = panels.isEmpty ? null : panels.last;
        return _WindowsArea(
          key: panel == null ? null : ObjectKey(panel),
          panel: panel,
          defaults: defaults ?? windowDefaults,
          screenWidth: screenWidth,
          collapsed:
              PanelsManager.minimize() && screenWidth < kWindowsBreakpoint,
        );
      },
    );
  }
}

/// One window on screen, described by what it is rather than by a widget — so a
/// rebuild (a language change, a theme change) rebuilds the window too.
class _WindowsArea extends StatefulWidget {
  const _WindowsArea({
    super.key,
    required this.panel,
    required this.screenWidth,
    required this.collapsed,
    required this.defaults,
  });

  final Panel? panel;
  final double screenWidth;
  final WindowDefaults defaults;

  /// A phone panel that has been collapsed: its windows go with it.
  final bool collapsed;

  @override
  State<_WindowsArea> createState() => _WindowsAreaState();
}

class _WindowsAreaState extends State<_WindowsArea> {
  WindowsLayout _layout = const WindowsLayout(compact: false, capacity: 0);

  /// What is on screen, and what is folding away from it.
  List<_WindowEntry> _live = const [];
  final Map<String, _WindowEntry> _closing = <String, _WindowEntry>{};

  /// The entry the phone sheet is showing, which is the only one a phone has an
  /// exit animation for.
  String? _shown;

  /// The window the app last asked for while a phone is drawing sheets: a phone
  /// shows one window at a time, and the one just asked for is the one to show.
  ///
  /// It survives the list being rebuilt, because that list puts a panel's own
  /// windows *after* the standing ones — the order the wide screen stacks them
  /// in, where the panel's sit above — so "the newest entry" would keep showing
  /// the panel's window and leave a window asked for over it behind.
  String? _sheetFocus;

  /// Where each window sits, by key, and the order they stack in — bottom first.
  ///
  /// A placement outlives the window being put away: a window you minimize comes
  /// back where you left it. The value is the window's *intent*; what is drawn is
  /// that intent clamped to the screen, so shrinking the screen can never strand
  /// a window off it, and growing it back returns the window to its own corner.
  final Map<String, ValueNotifier<WindowPlacement>> _places = {};
  final List<String> _stack = <String>[];

  /// How much room each window was given by the last arrangement, by key: a
  /// window is drawn no taller than its cell, so it never covers the one below.
  final Map<String, double> _cells = {};

  StreamSubscription<int>? _workspaceSub;

  PanelWorkspace? get _workspace => widget.panel?.workspace;

  List<PanelWindow> get _floating =>
      widget.panel?.floatingWindows ?? const <PanelWindow>[];

  /// The width the panel takes on this screen — none when no panel is open, so
  /// the whole screen is free for the windows that are.
  double get _panelWidth => widget.panel == null
      ? 0
      : computePanelWidth(screenWidth: widget.screenWidth);

  /// The height the windows have to work with: the screen, less whatever the
  /// system keeps at its edges — what the grid decides how many rows to use by.
  double get _room {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return size.height - padding.top - padding.bottom;
  }

  WindowsLayout _computeLayout() => computeWindowsLayout(
        floating: _floating,
        screenWidth: widget.screenWidth,
        panelWidth: _panelWidth,
        screenHeight: _room,
      );

  /// False until the first arrangement has been made. Its place is
  /// [didChangeDependencies], not [initState]: how many rows of windows a screen
  /// holds is read from the screen, and inherited widgets cannot be asked that
  /// early.
  bool _arranged = false;

  /// Rebuilds this state. The drawing half lives in an extension, which may not
  /// call the protected [setState] itself.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _bindWorkspace();
    _listenToWorkspace();
    // A window opened from elsewhere in the app reaches this layer through
    // [WindowsManager]'s own stream; the panel's through its workspace's.
    _live = _entries();
    // The stack starts in the order the windows are listed, so a window the
    // opener asked for can be lifted before the first frame is drawn — a panel
    // that just came to the front is a new state, and its focus request would
    // otherwise never be read.
    _stack.addAll([for (final entry in _live) entry.key]);
    _bringFocusedForward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layout = _computeLayout();
    if (_arranged) return;
    _arranged = true;
    _arrange();
    // The panel may have opened in the same frame this layer was built for: a
    // window that was standing over the app steps aside on a phone.
    _stepAsideForPanel();
  }

  /// Teaches the panel where to send what the user opens and puts away: the
  /// host owns the memory, the panel only reports the change.
  void _bindWorkspace() {
    final panel = widget.panel;
    if (panel == null) return;
    panel.workspace.onUserChange =
        (open) => widget.defaults.remember(panel.singularName, open);
  }

  void _listenToWorkspace() {
    unawaited(_workspaceSub?.cancel());
    _workspaceSub = _workspace?.revision.stream.listen((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant _WindowsArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A panel has just opened (or closed) in front of whatever was on screen.
    if (oldWidget.panel == null && widget.panel != null) {
      _stepAsideForPanel();
    }
    if (oldWidget.panel != widget.panel) {
      _bindWorkspace();
      _listenToWorkspace();
    }
    _followScreen();
    // Already rebuilding: recompute what is on screen without asking for
    // another frame.
    final live = _entries();
    _settle(live);
    _live = live;
    _bringFocusedForward();
  }

  /// On a phone a panel takes the whole screen. A window that was hanging over
  /// the app — the list whose button opened this panel — steps aside, rather
  /// than sitting on top of the panel with its barrier over it.  ///
  /// A window with unsaved work is left alone: it would be worse to throw the
  /// work away than to have it stay on top until it is saved or closed.
  void _stepAsideForPanel() {
    if (widget.screenWidth >= kWindowsBreakpoint || widget.panel == null) {
      return;
    }
    final stale = WindowsManager.open()
        .where((floating) =>
            floating.root && (floating.hasChanges?.call() ?? false) == false)
        .toList();
    if (stale.isEmpty) return;
    // Nothing may be closed while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final floating in stale) {
        WindowsManager.close(floating);
      }
    });
  }

  /// Brings the window the app last asked for in front — reopening a window
  /// that is already up must not leave it buried under the ones opened since.
  void _bringFocusedForward() {
    final focus = WindowsManager.takeFocus() ?? _workspace?.takeFocus();
    if (focus == null) return;
    if (widget.screenWidth < kWindowsBreakpoint) {
      // A phone draws one window at a time, so "in front" means "on screen":
      // the window the app just asked for is the sheet, even though the panel's
      // own windows come after it in the list they are drawn from.
      _sheetFocus = focus;
      return;
    }
    if (!_stack.contains(focus) || _stack.last == focus) return;
    _stack
      ..remove(focus)
      ..add(focus);
  }

  @override
  void dispose() {
    unawaited(_workspaceSub?.cancel());
    for (final place in _places.values) {
      place.dispose();
    }
    super.dispose();
  }

  /// The windows this screen could open by itself, in the panel's priority
  /// order: a window that needs the record stored first is not one of them.
  List<String> get _candidates => [
        for (final window in _floating)
          if (!(window.onlyIfSaved && (widget.panel?.isNew ?? false)))
            window.id,
      ];

  /// The window the opener asked for, if it is one that floats.
  String? get _focus {
    final id = widget.panel?.initialWindow;
    if (id == null) return null;
    return _floating.any((window) => window.id == id) ? id : null;
  }

  /// Opens a screenful of windows — the ones the user left on the last panel of
  /// this kind, or the panel's own first picks — unless the panel was asked to
  /// come alone, in which case its dock is where they stay until the user asks
  /// for one.
  void _arrange() {
    final panel = widget.panel;
    if (panel == null) return;
    if (!panel.opensWithWindows) {
      // Nothing is opened, but the row's capacity is still learned: the windows
      // the user asks for from the dock afterwards have to make room by it.
      panel.workspace.measure(_layout);
      return;
    }
    panel.workspace.arrange(
      layout: _layout,
      candidates: _candidates,
      preferred: widget.defaults.of(panel.singularName),
      focus: _focus,
    );
  }

  /// Follows the screen: a resize that changes how many windows fit — or
  /// crosses the phone breakpoint — rearranges what is on screen, exactly as
  /// opening the panel would have on that screen.
  void _followScreen() {
    final next = _computeLayout();
    final changed =
        next.capacity != _layout.capacity || next.compact != _layout.compact;
    _layout = next;
    if (changed) _arrange();
  }

  /// Everything that should be on screen right now: the standalone windows,
  /// then the panel's own, so the panel's sit above them in the stack.
  List<_WindowEntry> _entries() {
    final entries = <_WindowEntry>[
      for (final floating in WindowsManager.open())
        _WindowEntry.standalone(floating),
    ];
    if (!widget.collapsed) {
      for (final window in _floating) {
        if (_workspace?.isOpen(window.id) ?? false) {
          entries.add(_WindowEntry.hosted(window, window.id));
        }
      }
    }
    return entries;
  }

  /// Recomputes what is on screen, keeping the windows that left for the length
  /// of their closing animation.
  void _sync() {
    if (!mounted) return;
    setState(() {
      final live = _entries();
      _settle(live);
      _live = live;
      _bringFocusedForward();
    });
  }

  /// Moves the windows that are no longer listed into [_closing], where they
  /// stay until their closing animation reports it is done — and takes back any
  /// window that came back while it was still folding away.
  void _settle(List<_WindowEntry> live) {
    final keys = {for (final entry in live) entry.key};
    // A window that is on screen again is not leaving, however recently it
    // started to: forgetting this is what would leave it drawn at zero opacity
    // but still taking clicks.
    _closing.removeWhere((key, entry) {
      if (!keys.contains(key)) return false;
      // It came back before it finished leaving, so it is a new window and not
      // the one that was folding away: the place it is drawn at is the place it
      // is opened from now, not where the window before it was left.
      if (!entry.isHosted) _places.remove(key)?.dispose();
      return true;
    });
    final oneAtATime = widget.screenWidth < kWindowsBreakpoint;
    for (final entry in _live) {
      if (keys.contains(entry.key)) continue;
      // One at a time means the windows queued behind the one on screen were
      // never shown, so they have no exit to animate: only the window that is
      // up folds away.
      if (oneAtATime && entry.key != _shown) continue;
      _closing[entry.key] = entry;
    }
  }

  /// A window that has finished folding away is forgotten — and, if it closed
  /// for good, so is where it stood: a window opened again comes from where it
  /// is opened, not from where the one before it was left.
  ///
  /// A panel's own window keeps its place, because minimizing it is not closing
  /// it: it comes back where you put it.
  void _forget(String key) {
    final entry = _closing[key];
    if (entry == null) return;
    setState(() {
      _closing.remove(key);
      if (!entry.isHosted) _places.remove(key)?.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_live.isEmpty && _closing.isEmpty) {
      _shown = null;
      return const SizedBox.shrink();
    }
    if (widget.screenWidth < kWindowsBreakpoint) {
      // One window at a time: the one the app last asked for, else the newest,
      // or the one still folding away.
      final shown = _entryFor(_sheetFocus) ??
          (_live.isNotEmpty ? _live.last : _closing.values.lastOrNull);
      _shown = shown?.key;
      return shown == null ? const SizedBox.shrink() : _buildSheet(shown);
    }
    _sheetFocus = null;
    _shown = null;
    return _buildStack();
  }

  /// The entry [key] names, on screen or still folding away.
  _WindowEntry? _entryFor(String? key) {
    if (key == null) return null;
    for (final entry in _live) {
      if (entry.key == key) return entry;
    }
    return _closing[key];
  }

  /// The room windows have, asked where they are drawn: beside the panel when
  /// one is open, the whole screen when none is.
  _AreaMetrics get _metrics {
    final viewPadding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final panelWidth = _panelWidth;
    // The panel sits on the trailing edge of the screen, so the windows keep to
    // the other side of it — whichever side the reading direction makes that.
    final panelOnTheLeft = panelWidth > 0 && _rtl;
    final panelOnTheRight = panelWidth > 0 && !_rtl;
    final bounds = WindowBounds(
      left: panelOnTheLeft ? panelWidth + kWindowGap : kWindowEdgeInset,
      right: panelOnTheRight
          ? size.width - panelWidth - kWindowGap
          : size.width - kWindowEdgeInset,
      top: viewPadding.top + kWindowEdgeInset,
      bottom: size.height - viewPadding.bottom,
    );
    return _AreaMetrics(
      panelWidth: panelWidth,
      bounds: bounds,
      room: size.height - viewPadding.top - viewPadding.bottom,
    );
  }
}
