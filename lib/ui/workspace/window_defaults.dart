import 'dart:convert';

import 'package:apexo/ui/workspace/window_group.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// Which of a panel's windows were left open, remembered per device and keyed by
/// kind + slot rather than record id, so the next record opens the same way.
class WindowDefaults {
  const WindowDefaults({required this.read, required this.write});

  /// The stored JSON, or an empty string when nothing has been stored.
  final String Function() read;

  /// Stores [value] — the whole JSON, the only shape this class writes.
  final void Function(String value) write;

  /// Windows left open on a [kind] panel in [slot], in screen order. Null means
  /// never configured; an empty list means the user closed them all, and is kept.
  List<String>? of(String kind, [String slot = kHostSlot]) {
    final stored = _read();
    final scoped = stored['$kind/$slot'];
    if (scoped != null) return List<String>.of(scoped);
    // Written before slots existed: a memory of the kind is the host slot's.
    final legacy = stored[kind];
    if (slot != kHostSlot || legacy == null) return null;
    return List<String>.of(legacy);
  }

  void remember(String kind, List<String> open, {String slot = kHostSlot}) {
    final all = _read();
    final key = '$kind/$slot';
    final previous = all[key] ?? (slot == kHostSlot ? all[kind] : null);
    if (previous != null && listEquals(previous, open)) return;
    // The un-slotted key is migrated; keeping it would let a stale default return.
    if (slot == kHostSlot) all.remove(kind);
    all[key] = List<String>.of(open);
    write(jsonEncode(all));
  }

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

/// Fallback store for a layer built without one (tests, previews): remembers
/// nothing until a host binds a real store.
WindowDefaults windowDefaults = const WindowDefaults(
  read: _nothingStored,
  write: _ignoreWrite,
);

String _nothingStored() => '';
void _ignoreWrite(String value) {}
