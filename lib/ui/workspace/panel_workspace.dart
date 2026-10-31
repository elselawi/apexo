import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:flutter/foundation.dart';

/// Which of a panel's windows are on screen, for as long as that panel is.
///
/// Windows are tracked by [PanelWindow.id], never by position: a panel builds
/// its windows from a list that permissions can shorten, and an index would
/// point at a different editor the moment one is hidden. They are tracked **per
/// slot** as well — the panel's own record and the record it carries beside
/// itself both offer a `gallery`, and the row draws both — so "is this window
/// open?" is always asked of a slot (plan §6.2-4).
///
/// The shell opens a screenful when the panel appears and again when the screen
/// changes ([applyPlan], or [arrange] for a panel that draws one record);
/// [toggle] is the user's own choice, and it only ever adds or takes away the
/// window it names.
final class PanelWorkspace {
  PanelWorkspace({this.onUserChange});

  /// The windows on screen, by slot. A slot with nothing open is absent.
  final Map<String, Set<String>> _open = <String, Set<String>>{};

  /// Told after the *user's* own change to what is on screen — a window opened,
  /// put away or switched — with the slot it happened in, so the host can
  /// remember it for next time. Never called for [applyPlan] or [arrange], which
  /// is the screen deciding, not the user.
  ///
  /// The host sets this when it attaches the panel, so the panel model itself
  /// needs no knowledge of where the preference lives.
  void Function(String slot, List<String> open)? onUserChange;

  /// Emits on every change, so the panel's toggle bar and the windows themselves
  /// redraw together.
  final ObservableState<int> revision = ObservableState(0);

  /// The shell's last word on whether the screen holds one window at a time.
  bool _compact = false;

  /// How many windows the row holds, for a panel that still describes its screen
  /// by a count ([measure]) rather than by a [WindowsPlan].
  int _capacity = 0;

  /// What the row last showed, when the shell planned it — what opening a window
  /// from the dock afterwards has to fit into.
  WindowsPlan? _plan;

  /// The window the layer was last asked to raise, once — see [takeFocus].
  String? _focus;

  /// The window to bring in front of the others, once — null when there is no
  /// such request waiting.
  String? takeFocus() {
    final focus = _focus;
    _focus = null;
    return focus;
  }

  /// The slots a row draws, from the panel's edge outwards: the record it carries
  /// beside itself first, its own windows after it (plan §4.1).
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

  /// Puts a screenful of windows on screen for a panel that draws **one** record:
  /// the ones the user left open last time ([preferred]), or the panel's own
  /// first picks when nothing has been left — in the panel's order, never more
  /// than the screen holds. A screen that holds a single window gets only
  /// [focus], the window the opener asked for.
  ///
  /// [preferred] is null when the user has never touched this kind of panel, and
  /// an empty list when they left none of its windows open — which is a choice,
  /// and one to keep.
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
    // A screen that can hold no window at all has nothing to give up for the
    // one that was asked for — and a window that is already on screen needs no
    // room made for it, which would otherwise put a neighbour away for nothing.
    if (focus != null && layout.capacity > 0 && !next.contains(focus)) {
      while (next.length >= layout.capacity) {
        // `next` is insertion-ordered, so its last entry is the least important
        // window the panel offered — the one to give up first.
        next.remove(next.last);
      }
      next.add(focus);
    }
    _replace(kHostSlot, next);
  }

  /// Learns what the screen can hold, without touching what is on screen. A panel
  /// that opens with no windows of its own still needs this: the windows the user
  /// opens afterwards from its dock have to make room by it.
  void measure(WindowsLayout layout) {
    _compact = layout.compact;
    _capacity = layout.capacity;
  }

  /// Puts on screen exactly what [plan] selected — the shell's answer for a row
  /// that holds more than one record.
  ///
  /// The plan is kept: a window opened from a dock afterwards has to know whether
  /// the row still has room for it, and that is a question about widths, which a
  /// count cannot answer.
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

  /// Brings window [id] on screen without disturbing the others: the opener's
  /// own request, which must not wait for a click on the panel's toggle bar.
  ///
  /// Asking for a window that is already up brings it forward rather than doing
  /// nothing: the layer lifts it above the windows opened after it. The row
  /// itself stays as it is — which window gives way when the next one opens does
  /// not change because the user looked at one again.
  ///
  /// This is the **opener's** request, not the user's: asking a supplier row for
  /// "the unpaid orders" must not rewrite the windows the user left open on
  /// every orders panel. Only [toggle] and [minimize] are the user's own
  /// change, and only they are remembered.
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

  /// Shows or hides window [id].
  ///
  /// The screen shows as many windows as its row holds, so opening one more than
  /// that gives up the one that has been up longest — never the one just asked
  /// for. A phone shows one at a time, so there opening a window replaces the one
  /// on screen — of either record: a phone has one sheet.
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
      // The user asked for this window by name: it is the one to bring forward —
      // and on a phone it is the sheet to put on screen, over whatever the app
      // last opened.
      _focus = rowKey(slot, id);
    }
    _notify(byUser: true, slot: slot, before: before);
  }

  /// Gives up the window that has been on screen longest, when the row is full.
  void _makeRoom() {
    while (_capacity > 0 && open.length >= _capacity) {
      // The window that has been up longest is the one the panel offered first —
      // a window nobody can see is not a window, and it is the least missed.
      String? slot;
      for (final candidate in rowSlots) {
        if ((_open[candidate] ?? const <String>{}).isNotEmpty) slot = candidate;
      }
      if (slot == null) return;
      _removeKey(rowKey(slot, _open[slot]!.first));
    }
  }

  /// Gives up windows — from the far end of the row first, which is the panel's
  /// own record — until the row has room for [incoming].
  ///
  /// The chart is 960 wide and a pre-op form 560, so "is there room?" is
  /// arithmetic on widths, not a count: a row that holds two 350-pixel tools may
  /// hold no chart at all.
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

  /// Takes window [id] off the screen without recording it as a user
  /// preference — for a window replaced by another scope's editor.
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

  /// Takes everything in [slot] off the screen — a record the panel no longer
  /// carries. Not the user's choice, so not remembered.
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

  /// Announces a change to everything that draws from this workspace, and — when
  /// the user is the one who made it — to the panel, which remembers the windows
  /// for the next panel of the same kind.
  ///
  /// Every slot whose windows the change touched is reported, not just [slot]:
  /// opening a window can put another one away to make room, and a window of the
  /// record the panel carries is often the one that goes. A memory that still
  /// listed it would bring it back at the next plan, undoing the choice the user
  /// just made.
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

  /// What each slot holds on screen right now — what a user change is measured
  /// against, so every slot it touched is reported.
  Map<String, List<String>> _snapshot() => <String, List<String>>{
        for (final slot in rowSlots) slot: openIn(slot),
      };
}
