import 'dart:convert';

/// ## Permissions — single source of truth
///
/// Permissions are stored on the server as a **JSON-encoded string** in the
/// `profiles` PocketBase collection, e.g. `"[2, 1, 0, 0, 0, 0, 0, 0, 0]"`.
/// Each index in the array corresponds to one access slot (patients,
/// appointments, post-op notes, etc.) and holds a permission level (0 = none,
/// 1 = personal/limited, 2 = full).
///
/// ### How they flow
///
/// ```
/// Server (JSON string)  →  Perm.parse()       →  List<int>
///                                  ↓
/// AccountModel.fromJson()  →  permissions field  →  login.permissions
///                                  ↓
/// PermLevel wrapper  →  login.perm(Perm.photos).some  →  show/hide features
/// ```
///
/// - **Read:** `Perm.parse(serverString)` decodes, pads, returns a `List<int>`.
/// - **Write:** `jsonEncode(permissions)` sends the list back to PocketBase.
/// - **Check:** `login.perm(Perm.photos).some` / `.none` / `.full` / `.exact(n)`.
/// - **Admin/demo:** always get `Perm.full` (all slots unlocked).
///
/// ### Preferred access API — `login.perm(slot)`
///
/// Instead of raw array indexing, use the fluent [PermLevel] wrapper:
///
/// ```dart
/// login.perm(Perm.photos).none       // == 0
/// login.perm(Perm.photos).some       // > 0
/// login.perm(Perm.photos).full       // >= 2
/// login.perm(Perm.expenses).exact(1) // == 1
/// login.perm(Perm.patients).min(2)   // >= 2
/// login.perm(Perm.appointments).not(2) // != 2
/// ```
///
/// The wrapper is a const-constructible thin value type — the Dart compiler
/// inlines it, so there is **zero runtime overhead** vs raw array access.
///
/// ### How to add a new permission slot
///
/// 1. Add a constant above, **before** [count]:
///    ```dart
///    static const int newFeature = count;  // current count value
///    ```
/// 2. Bump [count] by 1.
/// 3. Add an entry to `_permissionDefs` in `open_account_panel.dart`:
///    ```dart
///    _PermDef(Perm.newFeature, "newFeature", _threeLevel),
///    ```
/// 4. Add localization keys for `"newFeature"` and its level labels.
/// 5. Use it for access control anywhere:
///    ```dart
///    if (login.perm(Perm.newFeature).some) { … }
///    ```
///
/// **Backward compatibility is automatic:** [parse] and [pad] fill missing
/// slots with `0`, so old server data (shorter arrays) works with new code,
/// and new data works with old code that ignores the extra slot.
///
/// See also: `_permissionDefs` in `open_account_panel.dart` for the UI
/// registry of all permission selectors.
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

  /// Parses a JSON-encoded permissions string from the server, padding to
  /// [count] if shorter. Handles null, empty, and malformed input gracefully.
  ///
  /// Example: `"[2, 1, 0]"` → `[2, 1, 0, 0, 0, 0, 0, 0, 0]`
  static List<int> parse(dynamic source) {
    if (source == null) return zeroes;
    if (source is List<int>) return pad(source);
    if (source is String && source.isNotEmpty) {
      try {
        return pad(List<int>.from(jsonDecode(source)));
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

/// Fluent wrapper around a single permission level value.
///
/// Returned by [PermListAccess.perm] so you can write expressive checks:
/// ```dart
/// login.perm(Perm.photos).none       // == 0
/// login.perm(Perm.photos).some       // > 0
/// login.perm(Perm.photos).full       // >= 2
/// login.perm(Perm.expenses).exact(1) // == 1
/// login.perm(Perm.patients).min(2)   // >= 2
/// login.perm(Perm.appointments).not(2) // != 2
/// ```
///
/// Const-constructible and inlined by the Dart compiler — zero overhead.
class PermLevel {
  final int _value;
  const PermLevel(this._value);

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

/// Extension on `List<int>` so any permissions array can use [perm].
///
/// Primary usage is through [login.perm]:
/// ```dart
/// if (login.perm(Perm.photos).some) { … }
/// ```
extension PermListAccess on List<int> {
  PermLevel perm(int slot) => PermLevel(this[slot]);
}
