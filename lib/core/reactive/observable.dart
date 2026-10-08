import '../model.dart';
import 'observable_base.dart';
export 'observable_base.dart';

/// creates an observable dictionary
/// values of this dictionary should extend Model
/// this is typically used by stores (dictionaries of models)
class ObservableDict<G extends Model> extends ObservableBase<List<DictEvent>> {
  final Map<String, Map<String, dynamic>> _jsonCopies = {};
  final Map<String, G> _dictionary = {};

  G? get(String id) {
    return _dictionary[id];
  }

  void set(G item) {
    final bool isNew = !_dictionary.containsKey(item.id);
    _dictionary[item.id] = item;

    if (item.targetsToPushTo.isNotEmpty) {
      // the following gymnastics would only
      // be done when the item is meant to be pushed
      // otherwise it's just a waste of time and resources
      final newJson = _copyJsonMap(item.jsonCopyForPush);
      final oldJson = (item.copy(true)..fromJson(_jsonCopies[item.id] ?? {}))
          .jsonCopyForPush;

      final List<String> diff;
      if (!isNew && item.pushIfChanged.isNotEmpty) {
        diff = diffJson(oldJson, newJson).toList();
      } else {
        diff = [];
      }

      final List<dynamic> newVals = diff.map((key) => newJson[key]).toList();
      final List<dynamic> oldVals = diff.map((key) => oldJson[key]).toList();

      notifyObservers([
        if (isNew)
          DictEvent.add(item.id, document: item)
        else
          DictEvent.modify(
            item.id,
            modifiedKeys: diff,
            document: item,
            newVals: newVals,
            oldVals: oldVals,
          ),
      ]);
    } else {
      notifyObservers([
        if (isNew)
          DictEvent.add(item.id, document: item)
        else
          DictEvent.modify(
            item.id,
            modifiedKeys: [],
            document: item,
            newVals: [],
            oldVals: [],
          ),
      ]);
    }
    _copyDictionary([item.id]);
  }

  void setAll(List<G> items) {
    for (var item in items) {
      _dictionary[item.id] = item;
      _copyDictionary([item.id]);
    }
    notifyObservers(
        items.map((item) => DictEvent.add(item.id, document: null)).toList());
  }

  /// Like setAll but more optimized
  /// accepts map as arguments
  /// & accepts the pre-decoded JSON maps so that _jsonCopies
  /// can be populated directly, avoiding a redundant re-serialization of every
  /// Use this when loading from persistence.
  void setAllWithJson(
      Map<String, G> items, Map<String, Map<String, dynamic>> jsonMaps) {
    assert(
      items.length == jsonMaps.length,
      'items and jsonMaps must contain the same number of entries',
    );

    _dictionary.addAll(items);
    _jsonCopies.addAll(jsonMaps.map(
        (id, json) => MapEntry(id, _copyJsonMap(json))));

    notifyObservers(items.entries
        .map((item) => DictEvent.add(item.key, document: item.value))
        .toList());
  }

  void remove(String id) {
    if (_dictionary.containsKey(id)) {
      _jsonCopies.remove(id);
      _dictionary.remove(id);
      notifyObservers([DictEvent.remove(id)]);
    }
  }

  void clear() {
    _dictionary.clear();
    _jsonCopies.clear();
    notifyObservers([DictEvent.remove('__removed_all__')]);
  }

  void notifyView() {
    notifyObservers([
      DictEvent.modify(
        '__ignore_view__',
        modifiedKeys: const [],
        document: null,
        newVals: [],
        oldVals: [],
      )
    ]);
  }

  List<G> get values => _dictionary.values.toList();

  List<String> get keys => _dictionary.keys.toList();

  Map<String, G> get docs => Map<String, G>.unmodifiable(_dictionary);

  /// Creates a deep copy of the entire dictionary
  void _copyDictionary(List<String> ids) {
    for (final id in ids) {
      _jsonCopies[id] = _copyJsonMap(_dictionary[id]!.jsonCopyForPush);
    }
  }

  Map<String, dynamic> _copyJsonMap(Map<String, dynamic> json) {
    return json.map((key, value) => MapEntry(key, _copyJsonValue(value)));
  }

  Object? _copyJsonValue(Object? value) {
    if (value is List) {
      return value.map(_copyJsonValue).toList();
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key, _copyJsonValue(value)));
    }
    return value;
  }
}

enum DictEventType {
  add,
  modify,
  remove,
}

class DictEvent {
  DictEvent.add(this.id, {required this.document})
      : type = DictEventType.add,
        modifiedKeys = const [],
        newVals = const [],
        oldVals = const [];
  DictEvent.modify(
    this.id, {
    required this.modifiedKeys,
    required this.document,
    required this.newVals,
    required this.oldVals,
  }) : type = DictEventType.modify;
  DictEvent.remove(this.id)
      : type = DictEventType.remove,
        modifiedKeys = const [],
        document = null,
        newVals = const [],
        oldVals = const [];
  final DictEventType type;
  final String id;
  final List<String> modifiedKeys;
  final Model? document;
  final List<dynamic> newVals;
  final List<dynamic> oldVals;
}

/// Checks if two objects (including Lists and Maps) are deeply equal.
/// Required because Dart's `==` on Collections only checks reference.
bool _areEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_areEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_areEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Performs a 1-level diff and returns a Set of keys that were
/// added, removed, or modified.
Set<String> diffJson(
  Map<String, dynamic> oldJson,
  Map<String, dynamic> newJson,
) {
  final changedKeys = <String>{};

  // Check for additions and modifications
  newJson.forEach((key, newValue) {
    if (!oldJson.containsKey(key) || !_areEqual(oldJson[key], newValue)) {
      changedKeys.add(key);
    }
  });

  // Check for removals
  oldJson.forEach((key, _) {
    if (!newJson.containsKey(key)) {
      changedKeys.add(key);
    }
  });

  return changedKeys;
}
