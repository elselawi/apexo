import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

/// Which of a panel's floating windows the user left open last time, remembered
/// **per device** and keyed by the kind of record the panel shows
/// (`Panel.singularName`) — so a patient's panel opens the way the last
/// patient's was left, without a setting anywhere to find.
///
/// Only the *default* is remembered: the screen still decides what fits, and a
/// window the panel no longer offers is simply dropped when the default is
/// restored.
///
/// Storage is handed in rather than imported: the host passes the settings
/// store, a test passes a string. Reading a preference is not a reason for the
/// window system to know what a settings store, a feature or an app binding is.
class WindowDefaults {
  const WindowDefaults({required this.read, required this.write});

  /// The stored JSON, or an empty string when nothing has been stored.
  final String Function() read;

  /// Stores [value] — the whole JSON, the only shape this class writes.
  final void Function(String value) write;

  /// The windows left open on a `kind` panel, in the order they were on screen.
  ///
  /// Null when the user has never left this kind of panel — the panel then opens
  /// its own first picks — and an empty list when they left none of its windows
  /// open, which is a choice and is kept: such a panel comes alone, with every
  /// window one click away in its dock.
  List<String>? of(String kind) {
    final stored = _read()[kind];
    return stored == null ? null : List<String>.of(stored);
  }

  /// Remembers [open] as the windows a `kind` panel should open with next time.
  void remember(String kind, List<String> open) {
    final all = _read();
    final previous = all[kind];
    if (previous != null && listEquals(previous, open)) return;
    all[kind] = List<String>.of(open);
    write(jsonEncode(all));
  }

  /// The stored defaults, parsed. Anything unreadable is treated as "nothing
  /// remembered": a corrupt preference must never stop a panel from opening.
  Map<String, List<String>> _read() {
    final stored = read();
    if (stored.isEmpty) return <String, List<String>>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return <String, List<String>>{};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: <String>[
              for (final id in entry.value as List)
                if (id is String) id,
            ],
      };
    } on FormatException {
      return <String, List<String>>{};
    }
  }
}

/// The store the running host bound, for a layer that was built without one
/// (tests, previews). Defaults to remembering nothing: a host that never binds a
/// store must not open a panel with windows read from somewhere else.
WindowDefaults windowDefaults = const WindowDefaults(
  read: _nothingStored,
  write: _ignoreWrite,
);

String _nothingStored() => '';
void _ignoreWrite(String value) {}
