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

/// The screen's safe area as if no keyboard were up. [MediaQueryData.padding]
/// gives the keys the bottom it covers, and a keyboard must not read as a
/// screen with more room: that re-plans the row and takes windows away.
EdgeInsets _safeArea(MediaQueryData media) {
  final padding = media.padding;
  final safe = media.viewPadding;
  final insets = media.viewInsets;
  // What the keyboard took, and no more than the safe area itself.
  double edge(double padding, double safe, double inset) =>
      padding + math.min(math.max(safe - padding, 0), inset);
  return EdgeInsets.fromLTRB(
    edge(padding.left, safe.left, insets.left),
    edge(padding.top, safe.top, insets.top),
    edge(padding.right, safe.right, insets.right),
    edge(padding.bottom, safe.bottom, insets.bottom),
  );
}

class WindowsLayer extends StatelessWidget {
  const WindowsLayer({
    super.key,
    required this.visible,
    required this.screenWidth,
    this.defaults,
    this.refreshStreams = const <Stream<Object?>>[],
  });

  /// False outside the staff app (login, patient side), where nothing floats.
  final bool visible;

  final double screenWidth;

  /// Remembered window layouts from the host; null uses [windowDefaults].
  final WindowDefaults? defaults;

  /// Extra stores window labels read, so edits elsewhere relabel open windows.
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
  WindowsPlan _plan = WindowsPlan.none;

  /// What is on screen, and what is folding away from it.
  List<_WindowEntry> _live = const [];
  final Map<String, _WindowEntry> _closing = <String, _WindowEntry>{};

  /// Replacing content in an existing frame must not replay its entrance.
  final Set<String> _replacements = <String>{};

  /// The entry the phone sheet shows; the only one a phone animates out.
  String? _shown;

  /// The window the app last asked for, kept in front: a focus that arrives
  /// before the row is planned must not be buried by the next frame.
  String? _focusKey;

  /// The sheet a phone is showing, kept across rebuilds because the list puts a
  /// panel's own windows after the standing ones.
  String? _sheetFocus;

  /// Where each window sits, by key, and the stack order, bottom first.
  /// Values are intent, clamped to the screen when drawn so nothing is stranded.
  final Map<String, ValueNotifier<WindowPlacement>> _places = {};
  final List<String> _stack = <String>[];

  /// Room each window was given by the last arrangement: it is drawn no taller.
  final Map<String, double> _cells = {};

  /// Height each tap-opened window asked for once laid out, by key, so it can
  /// be lifted whole above the bottom edge ([placementAt]).
  final Map<String, double> _heights = {};

  /// Windows already measured, so their height is not read again every frame.
  final Set<String> _fitted = {};

  StreamSubscription<int>? _workspaceSub;
  StreamSubscription<int>? _attachmentsSub;

  PanelWorkspace? get _workspace => widget.panel?.workspace;

  /// The groups the row draws, attached record first. A visit's group exists
  /// only while attached, and its memory is keyed by kind and slot, never by id.
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
          remembered: widget.defaults.of(attached.singularName, kAttachedSlot),
        ),
      WindowGroup(
        slot: kHostSlot,
        id: '${panel.singularName}:${panel.itemId}',
        session: panel,
        // The panel's floating windows plus its attachments: an open one is
        // drawn but never takes a row slot.
        windows: _hostWindows(panel, attached),
        label: () => panel.displayTitle,
        kind: panel.singularName,
        accent: panel.accent,
        remembered: widget.defaults.of(panel.singularName, kHostSlot),
      ),
    ];
  }

  /// The panel's own windows minus those the attached record replaces: while a
  /// visit's chart is on screen the patient's own entry must not win instead.
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

  /// What each group asks the row for. [hostOpens] drops only the host's
  /// remembered windows; a window needing a saved record opens only if named.
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
    final padding = _safeArea(MediaQuery.of(context));
    return math.max(
      0,
      size.height - padding.top - padding.bottom - _commandHeight,
    );
  }

  /// The row key of the window the opener asked for: an explicit request wins,
  /// then the attached record's request, then the panel's own initial window.
  String? get _focus {
    final panel = widget.panel;
    if (panel == null) return null;
    final attached = panel.attached;
    // Only windows this panel really offers: a replaced one is not among them.
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
    // The request is honoured (or could not be): a second plan must not keep
    // forcing the window it named over the user's arrangement.
    widget.panel?.requestedWindow = null;
    return plan;
  }

  /// False until the first arrangement, which must wait for
  /// [didChangeDependencies]: the row count is read from inherited widgets.
  bool _arranged = false;

  /// setState for the drawing extension, which cannot call it itself.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _bindWorkspace();
    _listenToWorkspace();
    // Windows opened elsewhere reach this layer through [WindowsManager]'s
    // stream; the panel's own through its workspace's.
    _live = _entries();
    // Start the stack in listing order so a window the opener asked for can be
    // lifted before the first frame is drawn.
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
    // One plan only: computing it here too would spend the one-shot focus
    // request on a plan nothing draws.
    _arrange();
    _stepAsideForPanel();
  }

  /// Reports the workspace's open/close changes to the host's layout memory,
  /// keyed by record kind and slot — never by the record's id.
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

  /// The kind of the record in [slot]; empty when the slot holds none.
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
    // Attaching a visit mutates the panel in place, so nothing rebuilds the
    // layer for it; listen for the change.
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
      // Another record's panel: its own remembered windows decide the row.
      _arrange();
    } else {
      _followScreen();
    }
    // Already rebuilding: recompute what is on screen without another frame.
    final live = _entries();
    _settle(live);
    _live = live;
    _bringFocusedForward();
  }

  /// On a phone a standing window steps aside for the panel, unless it holds
  /// unsaved work — losing that is worse than leaving it on top.
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

  /// Moves the window the app last asked for to the front, so reopening it does
  /// not leave it buried.
  void _bringFocusedForward() {
    final focus = WindowsManager.takeFocus() ?? _workspace?.takeFocus();
    if (focus == null) return;
    if (widget.screenWidth < kWindowsBreakpoint) {
      // A phone draws one window at a time, so "in front" means "the sheet".
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

  /// Puts the phone's sheet away before Back touches the panel under it: a
  /// hosted window returns to its dock, a standalone closes after its prompt.
  bool _dismissSheet() {
    final entry = _entryFor(_shown);
    if (entry == null) return false;
    unawaited(_dismiss(entry));
    return true;
  }

  /// Opens a screenful: the remembered windows per kind, or the group's first
  /// picks — unless the panel was asked to come alone.
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

  /// Re-plans only when the screen changes: re-planning on any other rebuild
  /// would reset the row to remembered defaults and close the window asked for.
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

  /// Everything on screen: standalone windows first, then the panel's own, so
  /// the panel's sit above them in the stack.
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

  void _sync() {
    if (!mounted) return;
    setState(() {
      final live = _entries();
      _settle(live);
      _live = live;
      _bringFocusedForward();
    });
  }

  /// Moves windows that left into [_closing] until their exit animation ends,
  /// and takes back ones that returned.
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
    // A window on screen again is not leaving: forgetting this leaves it drawn
    // at zero opacity but still taking clicks.
    _closing.removeWhere((key, entry) {
      if (!keys.contains(key)) return false;
      // It returned mid-exit, so it is a new window: a standalone forgets the
      // place it was left in.
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
      // One at a time: the queued windows were never shown, so only the one on
      // screen has an exit to animate.
      if (oneAtATime && entry.key != _shown) continue;
      _closing[entry.key] = entry;
    }
  }

  /// Forgets a window that finished folding away. A standalone loses its place;
  /// a hosted one keeps it, because minimizing is not closing.
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

  _AreaMetrics get _metrics {
    final viewPadding = _safeArea(MediaQuery.of(context));
    final size = MediaQuery.sizeOf(context);
    final panelWidth = _panelWidth;
    // The panel sits on the trailing edge, so windows keep to whichever other
    // side the reading direction makes.
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
