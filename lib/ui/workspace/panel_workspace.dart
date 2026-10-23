import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:flutter/foundation.dart';

/// Which of a panel's floating windows are on screen, for as long as that panel
/// is.
///
/// Windows are tracked by [PanelWindow.id], never by position: a panel builds
/// its windows from a list that permissions can shorten, and an index would
/// point at a different editor the moment one is hidden.
///
/// The shell opens a screenful when the panel appears and again when the screen
/// changes ([arrange]); [toggle] is the user's own choice, and it only ever adds
/// or takes away the window it names.
final class PanelWorkspace {
  PanelWorkspace({this.onUserChange});

  final Set<String> _open = <String>{};

  /// Told after the *user's* own change to what is on screen — a window opened,
  /// put away or switched — so the host can remember it for next time. Never
  /// called for [arrange], which is the screen deciding, not the user.
  ///
  /// The host sets this when it attaches the panel, so the panel model itself
  /// needs no knowledge of where the preference lives.
  void Function(List<String> open)? onUserChange;

  /// Emits on every change, so the panel's toggle bar and the windows themselves
  /// redraw together.
  final ObservableState<int> revision = ObservableState(0);

  /// The shell's last word on whether the screen holds one window at a time.
  bool _compact = false;

  /// The window the layer was last asked to raise, once — see [takeFocus].
  String? _focus;

  /// The window to bring in front of the others, once — null when there is no
  /// such request waiting.
  String? takeFocus() {
    final focus = _focus;
    _focus = null;
    return focus;
  }

  /// How many windows the screen shows at once — one row, side by side. The
  /// shell answers it from the screen ([WindowsLayout.capacity]), and it is what
  /// keeps the row from overflowing: asking for one window more makes room for it
  /// instead of showing a window nobody can see.
  int _capacity = 0;

  /// Ids of the windows on screen.
  List<String> get open => _open.toList();

  bool isOpen(String id) => _open.contains(id);

  /// Puts a screenful of windows on screen: the ones the user left open last
  /// time ([preferred]), or the panel's own first picks when nothing has been
  /// left — in the panel's order, never more than the screen holds. A screen
  /// that holds a single window gets only [focus], the window the opener asked
  /// for.
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
    _replace(next);
  }

  /// Learns what the screen can hold, without touching what is on screen. A panel
  /// that opens with no windows of its own still needs this: the windows the user
  /// opens afterwards from its dock have to make room by it.
  void measure(WindowsLayout layout) {
    _compact = layout.compact;
    _capacity = layout.capacity;
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
  void show(String id) {
    _focus = id;
    if (_compact) {
      _replace({id});
    } else if (_open.contains(id)) {
      _notify();
    } else {
      _makeRoom();
      _open.add(id);
      _notify();
    }
  }

  /// Shows or hides window [id].
  ///
  /// The screen shows as many windows as its row holds, so opening one more than
  /// that gives up the one that has been up longest — never the one just asked
  /// for. A phone shows one at a time, so there opening a window replaces the one
  /// on screen.
  void toggle(String id) {
    if (_open.contains(id)) {
      _open.remove(id);
    } else {
      if (_compact) {
        _open.clear();
      } else {
        _makeRoom();
      }
      _open.add(id);
      // The user asked for this window by name: it is the one to bring forward —
      // and on a phone it is the sheet to put on screen, over whatever the app
      // last opened.
      _focus = id;
    }
    _notify(byUser: true);
  }

  /// Gives up the window that has been on screen longest, when the row is full.
  void _makeRoom() {
    while (_capacity > 0 && _open.length >= _capacity) {
      _open.remove(_open.first);
    }
  }

  /// Takes window [id] off the screen, leaving the rest as they are.
  void minimize(String id) {
    if (_open.remove(id)) _notify(byUser: true);
  }

  void _replace(Set<String> next, {bool byUser = false}) {
    if (setEquals(_open, next)) return;
    _open
      ..clear()
      ..addAll(next);
    _notify(byUser: byUser);
  }

  /// Announces a change to everything that draws from this workspace, and — when
  /// the user is the one who made it — to the panel, which remembers it for the
  /// next panel of its kind.
  void _notify({bool byUser = false}) {
    if (byUser) onUserChange?.call(open);
    revision(revision() + 1);
  }
}
