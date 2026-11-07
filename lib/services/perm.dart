import 'dart:convert';

/// Permissions are a JSON-encoded int array in `profiles`, indexed by slot:
/// 0 = none, 1 = personal/limited, 2 = full; missing slots count as 0.
class Perm {
  static const int patients = 0;
  static const int appointments = 1;
  static const int postOp = 2;
  static const int stats = 3;
  static const int expenses = 4;
  static const int setting = 5;
  static const int photos = 6;
  static const int notes = 7;
  static const int revenue = 8;

  /// Total number of permission slots. Update this when adding/removing slots.
  static const int count = 9;

  /// All-zero permissions array of length [count].
  static List<int> get zeroes => List.filled(count, 0);

  /// Full-access permissions array (2 for most slots, 1 for the rest).
  static List<int> get full => List.generate(count, (i) => i < 5 ? 2 : 1);

  /// Decodes stored permissions and pads missing slots to [count] with 0.
  static List<int> parse(Object? source) {
    if (source == null) return zeroes;
    if (source is List<int>) return pad(source);
    // A decoded JSON array is `List<dynamic>`, not `List<int>`, so accept any
    // list of numbers (or numeric strings); zeroes only for real garbage.
    if (source is List) {
      final parsed = <int>[];
      for (final value in source) {
        if (value is int) {
          parsed.add(value);
        } else if (value is num) {
          parsed.add(value.toInt());
        } else {
          final asInt = int.tryParse(value?.toString() ?? '');
          if (asInt == null) return zeroes;
          parsed.add(asInt);
        }
      }
      return pad(parsed);
    }
    if (source is String && source.isNotEmpty) {
      try {
        return pad(List<int>.from(jsonDecode(source) as List<dynamic>));
      } catch (_) {
        return zeroes;
      }
    }
    return zeroes;
  }

  /// Pads [perms] with zeros if shorter than [count]. Backward-compatible.
  static List<int> pad(List<int> perms) {
    if (perms.length >= count) return List<int>.from(perms);
    return [...perms, ...List.filled(count - perms.length, 0)];
  }
}

class PermLevel {
  const PermLevel(this._value);
  final int _value;

  /// The level is exactly 0 (no access).
  bool get none => _value == 0;

  /// The level is at least 1 (has some access).
  bool get some => _value > 0;
  bool get read => _value > 0;

  /// The level is at least 2 (full access).
  bool get full => _value >= 2;

  /// The level is exactly [n].
  bool exact(int n) => _value == n;

  /// The level is at least [n].
  bool min(int n) => _value >= n;

  /// The level is not equal to [n].
  bool not(int n) => _value != n;
}

extension PermListAccess on List<int> {
  PermLevel perm(int slot) => PermLevel(this[slot]);
}
