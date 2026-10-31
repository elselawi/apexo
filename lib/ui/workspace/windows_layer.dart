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
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/ui/workspace/standalone_window_card.dart';
import 'package:apexo/ui/workspace/window_attachments.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/scheduler.dart';

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
  /// What the row last showed: which windows, at what widths, in what order.
  ///
  /// A count would not do. The chart asks for 960, a pre-op form for 560 and a
  /// tool for the panel's width, so "two windows fit" describes one selection and
  /// says nothing about the next (plan §1).
  WindowsPlan _plan = WindowsPlan.none;

  /// What is on screen, and what is folding away from it.
  List<_WindowEntry> _live = const [];
  final Map<String, _WindowEntry> _closing = <String, _WindowEntry>{};

  /// Replacing content in an existing frame must not replay its entrance.
  final Set<String> _replacements = <String>{};

  /// The entry the phone sheet is showing, which is the only one a phone has an
  /// exit animation for.
  String? _shown;

  /// The window the app last asked for, kept in front of the row for as long as
  /// it is on screen: a focus that arrives before the rest of the row has been
  /// planned must not be buried by the next frame.
  String? _focusKey;

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

  /// The height each window that was opened at a tap asked for, by key, once it
  /// has been laid out — the height it is then lifted by, so the whole of it fits
  /// above the bottom edge of the screen ([placementAt]).
  ///
  /// Only the windows a tap placed need this: a window in the row is given its
  /// cell's room by the arrangement and never starts scrolled.
  final Map<String, double> _heights = {};

  /// The windows whose own height has been read, so they are placed by it rather
  /// than measured again on every frame.
  final Set<String> _fitted = {};

  StreamSubscription<int>? _workspaceSub;
  StreamSubscription<int>? _attachmentsSub;

  PanelWorkspace? get _workspace => widget.panel?.workspace;

  /// The records this panel draws in its row, from the panel's edge outwards: the
  /// visit it carries beside itself, then its own record (plan §4.1).
  ///
  /// The visit's group exists only while a visit is attached, and its memory is
  /// keyed by the visit **kind** and the slot — never by the visit's id, or every
  /// visit would open differently (plan §6.2-4).
  List<WindowGroup> get _groups {
    final panel = widget.panel;
    if (panel == null) return const <WindowGroup>[];
    final attached = panel.attached;
    return <WindowGroup>[
      if (attached != null)
        WindowGroup(
          slot: kAttachedSlot,
          id: '${attached.singularName}:${attached.itemId}',
          session: attached,
          windows: attached.windows,
          label: () => attached.displayTitle,
          kind: attached.singularName,
          accent: attached.accent,
          glyph: attached.unicodeSymbol,
          remembered: widget.defaults.of(attached.singularName, kAttachedSlot),
        ),
      WindowGroup(
        slot: kHostSlot,
        id: '${panel.singularName}:${panel.itemId}',
        session: panel,
        // The row's floating windows, plus the attachments that hang off the
        // panel itself: an attachment still has to be drawn when it is open, it
        // just never takes a row slot (see `computeWindowsPlan`).
        windows: _hostWindows(panel, attached),
        label: () => panel.displayTitle,
        kind: panel.singularName,
        accent: panel.accent,
        glyph: panel.unicodeSymbol,
        remembered: widget.defaults.of(panel.singularName, kHostSlot),
      ),
    ];
  }

  /// The panel's own windows, less the ones the record it carries replaces.
  ///
  /// A visit's chart *is* the chart while that visit is on screen: the patient's
  /// own entry for the same editor is not offered (the dock hides it, and
  /// [PanelScreen]'s workspace button drives the visit's), so the row must not
  /// open it either. Leaving it in the candidates let it win whenever the visit's
  /// chart did not fit — on a short screen the wrong record's chart appeared, and
  /// the visit's post-op record with it had no window to sit in (plan §4.3).
  List<PanelWindow> _hostWindows(
    Panel panel,
    HostedRecordSession? attached,
  ) {
    final replaced = <String>{
      if (attached != null)
        for (final window in attached.windows)
          if (window.replacementGroup case final group?) group,
    };
    return <PanelWindow>[
      for (final window in panel.floatingWindows)
        if (window.replacementGroup == null ||
            !replaced.contains(window.replacementGroup))
          window,
      ...panel.panelAttachments,
    ];
  }

  /// What each group asks the row for, in the row's order.
  ///
  /// [hostOpens] is the panel's `opensWithWindows`: a record asked for on its own
  /// — a dashboard row that means "this patient", not "their chart" — brings its
  /// own windows neither up nor away. That flag is about the panel's record: a
  /// visit attached to it still opens the window its opener asked for (plan §4.7).
  ///
  /// A window that needs the record stored first is not one the screen opens by
  /// itself — but the opener may still have asked for it by name, and an opener
  /// that names a window knows what it is asking for.
  List<WindowGroupDemand> _demands({required bool hostOpens}) =>
      <WindowGroupDemand>[
        for (final group in _groups)
          WindowGroupDemand(
            slot: group.slot,
            windows: <PanelWindow>[
              for (final window in group.windows)
                if (!(window.onlyIfSaved && group.session.isNew) ||
                    rowKey(group.slot, window.id) == _focus)
                  window,
            ],
            remembered: switch (group.slot) {
              kHostSlot when !hostOpens => const <String>[],
              _ => group.remembered,
            },
          ),
      ];

  /// The width the panel takes on this screen — none when no panel is open, so
  /// the whole screen is free for the windows that are.
  double get _panelWidth => widget.panel == null
      ? 0
      : computePanelWidth(screenWidth: widget.screenWidth);

  double get _commandHeight =>
      widget.panel == null || widget.screenWidth >= kWindowsBreakpoint
          ? kWorkspaceCommandHeight
          : 0;

  /// The grid uses the same command and safe-area insets as the drawn windows.
  double get _room {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return math.max(
      0,
      size.height - padding.top - padding.bottom - _commandHeight,
    );
  }

  /// The window the opener asked for, as a row key.
  ///
  /// A window the user has just asked the panel to show wins over everything
  /// else: pressing "all appointments" on a chart means the list, even if that
  /// costs the chart its place (it keeps its draft, and the band keeps its chip).
  /// After that the attached record's request wins: a caller that opened a visit's
  /// treatment plan came for that visit, not for whatever its patient's panel
  /// would have shown by itself.
  String? get _focus {
    final panel = widget.panel;
    if (panel == null) return null;
    final attached = panel.attached;
    // The windows this panel may actually put in the row: one an attached record
    // replaces is not one of them, however it is asked for.
    final hostWindows = _hostWindows(panel, attached);
    bool offersHost(String id) => hostWindows.any((window) => window.id == id);
    final requested = panel.requestedWindow;
    if (requested != null && offersHost(requested)) {
      return rowKey(kHostSlot, requested);
    }
    final attachedFocus = panel.attachedFocus;
    if (attached != null &&
        attachedFocus != null &&
        attached.windows.any((window) => window.id == attachedFocus)) {
      return rowKey(kAttachedSlot, attachedFocus);
    }
    final host = panel.initialWindow;
    if (host != null && offersHost(host) && panel.opensWithWindows) {
      return rowKey(kHostSlot, host);
    }
    return null;
  }

  WindowsPlan _computePlan({bool? hostOpens}) {
    final plan = computeWindowsPlan(
      screenWidth: widget.screenWidth,
      screenHeight: _room,
      panelWidth: _panelWidth,
      groups: _demands(
        hostOpens: hostOpens ?? (widget.panel?.opensWithWindows ?? true),
      ),
      focus: _focus,
    );
    // The request has been honoured (or honestly could not be): a second plan
    // must not keep forcing the window it named over the user's arrangement.
    widget.panel?.requestedWindow = null;
    return plan;
  }

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
    if (_arranged) {
      _followScreen();
      return;
    }
    _arranged = true;
    // One plan, and only one: [_arrange] computes it. Computing it here as well
    // would spend the window the app asked for — a one-shot request — on a plan
    // nothing draws, and the second plan would put that window away again before
    // the first frame that could have shown it.
    _arrange();
    // The panel may have opened in the same frame this layer was built for: a
    // window that was standing over the app steps aside on a phone.
    _stepAsideForPanel();
  }

  /// Teaches the panel where to send what the user opens and puts away: the
  /// host owns the memory, the panel only reports the change.
  ///
  /// The memory is keyed by the record's **kind** and the **slot** — `patient/host`,
  /// `appointment/attached` — so every visit of every patient opens the way the
  /// last one was left. Keying it by the record's id would make the layout
  /// per-visit (plan §6.2-4).
  void _bindWorkspace() {
    final panel = widget.panel;
    if (panel == null) return;
    panel.workspace.onUserChange = (slot, open) {
      final kind = _kindForSlot(slot);
      // No record of that kind is on screen — nothing to remember it for.
      if (kind.isEmpty) return;
      widget.defaults.remember(kind, open, slot: slot);
    };
  }

  /// The kind the record in [slot] is, for the layout memory. Empty when the
  /// slot holds no record: a memory of "the appointment slot of no appointment"
  /// is not a preference anyone can use.
  String _kindForSlot(String slot) {
    final panel = widget.panel;
    if (panel == null) return '';
    if (slot == kAttachedSlot) {
      return panel.attached?.singularName ?? '';
    }
    return panel.singularName;
  }

  void _listenToWorkspace() {
    unawaited(_workspaceSub?.cancel());
    _workspaceSub = _workspace?.revision.stream.listen((_) => _sync());
    // Attaching a visit mutates a panel that is already on screen: nothing
    // rebuilds the layer for it, so it listens for the change itself (plan
    // §6.2-2).
    unawaited(_attachmentsSub?.cancel());
    _attachmentsSub = widget.panel?.attachments.stream.listen((_) {
      if (!mounted) return;
      _arrange();
      _sync();
    });
  }

  @override
  void didUpdateWidget(covariant _WindowsArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A panel has just opened (or closed) in front of whatever was on screen.
    if (oldWidget.panel == null && widget.panel != null) {
      _stepAsideForPanel();
    }
    final panelChanged = oldWidget.panel != widget.panel;
    if (panelChanged) {
      _bindWorkspace();
      _listenToWorkspace();
      // Another record's panel: its own remembered windows decide the row, even
      // on the same screen.
      _arrange();
    } else {
      _followScreen();
    }
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
    _focusKey = focus;
    if (!_stack.contains(focus) || _stack.last == focus) return;
    _stack
      ..remove(focus)
      ..add(focus);
  }

  @override
  void dispose() {
    unawaited(_workspaceSub?.cancel());
    unawaited(_attachmentsSub?.cancel());
    if (identical(_dismissSheet, WindowsManager.dismissSheet)) {
      WindowsManager.dismissSheet = null;
    }
    for (final place in _places.values) {
      place.dispose();
    }
    super.dispose();
  }

  /// Puts the sheet a phone is showing away — the first step Back walks out by
  /// (plan §4.2). A hosted window goes back to its dock; a window standing on
  /// its own closes, asking first if it holds work.
  bool _dismissSheet() {
    final entry = _entryFor(_shown);
    if (entry == null) return false;
    unawaited(_dismiss(entry));
    return true;
  }

  /// Opens a screenful of windows: the ones the user left on the last panel of
  /// each kind, or the group's own first picks — unless the panel was asked to
  /// come alone, in which case its own windows stay in its dock until the user
  /// asks for one.
  ///
  /// The plan is the answer, and the workspace holds it: which windows, how wide,
  /// in what order (plan §6.2-5).
  void _arrange() {
    final panel = widget.panel;
    if (panel == null) return;
    _plan = _computePlan(hostOpens: panel.opensWithWindows);
    _arrangedFor = (
      width: widget.screenWidth,
      room: _room,
      panelWidth: _panelWidth,
    );
    panel.workspace.applyPlan(_plan);
  }

  /// Follows the screen: a resize that changes what fits — or crosses the phone
  /// breakpoint — rearranges what is on screen, exactly as opening the panel
  /// would have on that screen.
  ///
  /// Only the screen does this. A rebuild for something else — the store
  /// emitting after a visit's checkbox is ticked, a language change, a save —
  /// leaves what the user is looking at exactly where it is: re-planning would
  /// put the row back to the remembered defaults, closing the window the app had
  /// just asked for.
  void _followScreen() {
    if (!_screenChanged) return;
    _arrange();
  }

  /// The screen the last arrangement was made for. Null before the first one.
  ({double width, double room, double panelWidth})? _arrangedFor;

  bool get _screenChanged {
    final seen = _arrangedFor;
    return seen == null ||
        seen.width != widget.screenWidth ||
        seen.room != _room ||
        seen.panelWidth != _panelWidth;
  }

  /// Everything that should be on screen right now: the standalone windows,
  /// then the panel's own and the record it carries, so the panel's sit above
  /// them in the stack.
  List<_WindowEntry> _entries() {
    final entries = <_WindowEntry>[
      for (final floating in WindowsManager.open())
        _WindowEntry.standalone(floating),
    ];
    if (!widget.collapsed) {
      for (final group in _groups) {
        for (final window in group.windows) {
          if (_workspace?.isOpen(window.id, slot: group.slot) ?? false) {
            entries.add(_WindowEntry.hosted(window, group));
          }
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
    _replacements.retainAll(keys);
    for (final incoming in live) {
      final group = incoming.model.replacementGroup;
      if (group == null) continue;
      for (final previous in [..._live, ..._closing.values]) {
        if (keys.contains(previous.key) ||
            previous.model.replacementGroup != group) {
          continue;
        }
        _replacements.add(incoming.key);
        final place = _places[previous.key];
        if (place != null) {
          _places.putIfAbsent(incoming.key, () => ValueNotifier(place.value));
        }
        _closing.remove(previous.key);
      }
    }
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
      final group = entry.model.replacementGroup;
      if (group != null && live.any((e) => e.model.replacementGroup == group)) {
        continue;
      }
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
      // Back puts the sheet away before it touches the panel it lies over.
      WindowsManager.dismissSheet = _dismissSheet;
      return shown == null ? const SizedBox.shrink() : _buildSheet(shown);
    }
    if (identical(_dismissSheet, WindowsManager.dismissSheet)) {
      WindowsManager.dismissSheet = null;
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
      top: viewPadding.top + kWindowEdgeInset + _commandHeight,
      bottom: size.height - viewPadding.bottom,
    );
    return _AreaMetrics(
      panelWidth: panelWidth,
      bounds: bounds,
      room: _room,
    );
  }
}
