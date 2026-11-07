import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:flutter/foundation.dart';

/// Which of a panel's [PanelWindow] windows are open, tracked by id (permissions can
/// shorten the list) and per slot (two records both offer a `gallery`).
final class PanelWorkspace {
  PanelWorkspace({this.onUserChange});

  /// The windows on screen, by slot. A slot with nothing open is absent.
  final Map<String, Set<String>> _open = <String, Set<String>>{};

  /// Called only for the user's own changes (not [applyPlan]/[arrange]), so the
  /// host can remember them.
  void Function(String slot, List<String> open)? onUserChange;

  /// Emits on every change, so the toggle bar and windows redraw together.
  final ObservableState<int> revision = ObservableState(0);

  /// The shell's last word on whether the screen holds one window at a time.
  bool _compact = false;

  /// How many windows the row holds (for panels still measured by count).
  int _capacity = 0;

  /// What the row last showed when the shell planned it.
  WindowsPlan? _plan;

  /// The window the layer was last asked to raise, once — see [takeFocus].
  String? _focus;

  /// The window to bring in front of the others, once — null when none is waiting.
  String? takeFocus() {
    final focus = _focus;
    _focus = null;
    return focus;
  }

  /// The slots a row draws, from the panel's edge outwards.
  static const List<String> rowSlots = <String>[kAttachedSlot, kHostSlot];

  /// Ids of the windows on screen, in row order.
  List<String> get open => <String>[
        for (final slot in rowSlots) ...?_open[slot],
      ];

  /// Ids of the windows [slot] has on screen, in the order they were put up.
  List<String> openIn(String slot) => _open[slot]?.toList() ?? const <String>[];

  bool isOpen(String id, {String slot = kHostSlot}) =>
      _open[slot]?.contains(id) ?? false;

  /// Whether the row key [key] (`slot/windowId`) is on screen.
  bool isKeyOpen(String key) =>
      isOpen(windowIdOfRowKey(key), slot: slotOfRowKey(key));

  /// Puts a screenful on screen for a single-record panel: the remembered windows,
  /// or its first picks when none were ever chosen. A null [preferred] means never
  /// chosen; an empty list means the user chose none.
  void arrange({
    required WindowsLayout layout,
    required List<String> candidates,
    List<String>? preferred,
    String? focus,
  }) {
    measure(layout);
    final kept = preferred?.toSet();
    final next = <String>{};
    if (!layout.compact) {
      for (final candidate in candidates) {
        if (next.length >= layout.capacity) break;
        if (kept != null && !kept.contains(candidate)) continue;
        next.add(candidate);
      }
    }
    // Nothing to give up when the screen holds no window; an open one needs no room.
    if (focus != null && layout.capacity > 0 && !next.contains(focus)) {
      while (next.length >= layout.capacity) {
        // `next` is insertion-ordered, so its last entry is the least important.
        next.remove(next.last);
      }
      next.add(focus);
    }
    _replace(kHostSlot, next);
  }

  /// Learns the screen's capacity without changing what is on screen.
  void measure(WindowsLayout layout) {
    _compact = layout.compact;
    _capacity = layout.capacity;
  }

  /// Shows exactly what [plan] selected. The plan is kept because a later dock
  /// opening must know whether the row has room, which is a question of widths.
  void applyPlan(WindowsPlan plan) {
    _plan = plan;
    _compact = plan.compact;
    _capacity = plan.selected.length;
    final next = <String, Set<String>>{};
    for (final key in plan.selected) {
      (next[slotOfRowKey(key)] ??= <String>{}).add(windowIdOfRowKey(key));
    }
    _replaceAll(next);
  }

  /// Brings [id] on screen without disturbing the others; an already-open window
  /// is brought forward. This is the opener's request, not the user's, so it is not
  /// remembered — only [toggle] and [minimize] are.
  void show(String id, {String slot = kHostSlot}) {
    _focus = rowKey(slot, id);
    if (_compact) {
      _replaceAll(<String, Set<String>>{
        slot: <String>{id},
      });
    } else if (isOpen(id, slot: slot)) {
      _notify();
    } else {
      _makeRoomFor(rowKey(slot, id));
      (_open[slot] ??= <String>{}).add(id);
      _notify();
    }
  }

  /// Shows or hides [id]. Opening beyond the row's capacity gives up the
  /// longest-open window; a phone shows one sheet, so it replaces the one on screen.
  void toggle(String id, {String slot = kHostSlot}) {
    final before = _snapshot();
    if (isOpen(id, slot: slot)) {
      _open[slot]!.remove(id);
      if (_open[slot]!.isEmpty) _open.remove(slot);
    } else {
      if (_compact) {
        _open.clear();
      } else {
        _makeRoomFor(rowKey(slot, id));
      }
      (_open[slot] ??= <String>{}).add(id);
      // The user asked for this window by name, so it comes forward (on a phone, it
      // is the sheet on screen).
      _focus = rowKey(slot, id);
    }
    _notify(byUser: true, slot: slot, before: before);
  }

  /// Gives up the window that has been on screen longest, when the row is full.
  void _makeRoom() {
    while (_capacity > 0 && open.length >= _capacity) {
      // The window up longest is the one the panel offered first — the least missed.
      String? slot;
      for (final candidate in rowSlots) {
        if ((_open[candidate] ?? const <String>{}).isNotEmpty) slot = candidate;
      }
      if (slot == null) return;
      _removeKey(rowKey(slot, _open[slot]!.first));
    }
  }

  /// Gives up windows from the far end of the row first until [incoming] fits. Room
  /// is arithmetic on widths, not a count (a chart is 960 wide, a pre-op form 560).
  void _makeRoomFor(String incoming) {
    final plan = _plan;
    final width = plan?.widthOf(incoming) ?? 0;
    if (plan == null || width <= 0) {
      // Nothing planned: fall back to what a count can say.
      _makeRoom();
      return;
    }
    final evictionOrder = <String>[
      for (final slot in rowSlots.reversed)
        for (final id in (_open[slot] ?? const <String>{}).toList().reversed)
          rowKey(slot, id),
    ];
    for (final key in evictionOrder) {
      final used = _usedWidth(plan, excluding: incoming);
      final next = used + (used == 0 ? 0 : kWindowGap) + width;
      if (next <= plan.available + 0.5) break;
      _removeKey(key);
    }
  }

  /// The width the row takes, by the plan's own measurements, without [excluding].
  double _usedWidth(WindowsPlan plan, {String? excluding}) {
    var used = 0.0;
    var counted = 0;
    for (final slot in rowSlots) {
      for (final id in _open[slot] ?? const <String>{}) {
        final key = rowKey(slot, id);
        if (key == excluding) continue;
        final width = plan.widthOf(key);
        if (width <= 0) continue;
        used += (counted == 0 ? 0 : kWindowGap) + width;
        counted++;
      }
    }
    return used;
  }

  void _removeKey(String key) {
    final slot = slotOfRowKey(key);
    final id = windowIdOfRowKey(key);
    _open[slot]?.remove(id);
    if (_open[slot]?.isEmpty ?? false) _open.remove(slot);
  }

  /// Removes [id] without recording it — the window was replaced, not closed.
  void hide(String id, {String slot = kHostSlot}) {
    if (_open[slot]?.remove(id) ?? false) {
      if (_open[slot]!.isEmpty) _open.remove(slot);
      _notify();
    }
  }

  /// Takes window [id] off the screen, leaving the rest as they are.
  void minimize(String id, {String slot = kHostSlot}) {
    if (_open[slot]?.remove(id) ?? false) {
      if (_open[slot]!.isEmpty) _open.remove(slot);
      _notify(byUser: true, slot: slot);
    }
  }

  /// Removes everything in [slot] without recording it — the panel let the record go.
  void clearSlot(String slot) {
    if (_open.remove(slot) != null) _notify();
  }

  void _replace(String slot, Set<String> next) {
    final current = _open[slot] ?? const <String>{};
    if (setEquals(current, next)) return;
    if (next.isEmpty) {
      _open.remove(slot);
    } else {
      _open[slot] = <String>{...next};
    }
    _notify();
  }

  void _replaceAll(Map<String, Set<String>> next) {
    final same = next.keys.every((slot) => setEquals(
            _open[slot] ?? const <String>{}, next[slot] ?? const {})) &&
        _open.keys.every(next.containsKey);
    if (same) return;
    _open.clear();
    for (final entry in next.entries) {
      if (entry.value.isEmpty) continue;
      _open[entry.key] = <String>{...entry.value};
    }
    _notify();
  }

  /// Announces a change to everything that draws from this workspace, and to the
  /// panel when the user made it. Every touched slot is reported: making room can
  /// close another slot's window, and a stale memory would bring it back.
  void _notify({
    bool byUser = false,
    String? slot,
    Map<String, List<String>>? before,
  }) {
    if (byUser && slot != null) {
      final changed = before == null
          ? <String>[slot]
          : <String>[
              for (final each in rowSlots)
                if (!listEquals(
                  before[each] ?? const <String>[],
                  openIn(each),
                ))
                  each,
            ];
      for (final each in changed) {
        onUserChange?.call(each, openIn(each));
      }
    }
    revision(revision() + 1);
  }

  /// What each slot holds now, so a user change reports every slot it touched.
  Map<String, List<String>> _snapshot() => <String, List<String>>{
        for (final slot in rowSlots) slot: openIn(slot),
      };
}
