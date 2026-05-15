import 'dart:async';
import 'dart:convert';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';
import 'model.dart';

/// This file introduces 4 types of observable objects
/// all of which will notify their observers and automatically updates ObservableWidgets
/// when their properties change
/// - ObservableBase: would rarely be useful
/// - ObservableState: would be useful for storing standalone observable state (not part of a class)
/// - ObservablePersistingObject: same as above but with persistence
/// - ObservableDict: Typically used by stores

typedef Observer<S> = void Function(S event);

/// Base observable class
/// the observable functionality of the application is all based on this class
class ObservableBase<S> {
  ObservableBase() {
    stream.listen((events) {
      for (var observer in observers) {
        try {
          observer(events);
        } catch (e, s) {
          logger("Error while notifying an observer: $e", s);
        }
      }
    });
  }

  final StreamController<S> _controller = StreamController<S>.broadcast();
  final List<Observer<S>> observers = [];
  Stream<S> get stream => _controller.stream;
  double _silent = 0;

  void notifyObservers(S event) {
    if (_silent != 0) return;
    _controller.add(event);
  }

  int observe(Observer<S> callback) {
    int existing = observers.indexWhere((o) => o == callback);
    if (existing > -1) {
      return existing;
    }
    observers.add(callback);
    return observers.length - 1;
  }

  void unObserve(Observer<S> callback) {
    observers.removeWhere((existing) => existing == callback);
  }

  void dispose() {
    _silent = double.maxFinite;
    observers.clear();
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void silently(void Function() fn) {
    _silent++;
    try {
      fn();
    } catch (e, s) {
      login.askForLoginAgain(e);
      logger("Error during silent modification: $e", s);
    }
    _silent--;
  }
}

/// Creates a standalone observable value
/// this can be accessed by calling it "()"
/// and can be set by passing a value when calling it "(value)"
class ObservableState<T> extends ObservableBase<T> {
  T _value;

  ObservableState(this._value);

  T call([T? newValue]) {
    if (newValue != null) {
      _value = newValue;
      notifyObservers(_value);
    }
    return _value;
  }
}

/// Persists its data to a hive box
/// however only data that are defined in toJson and fromJson will be persisted
abstract class ObservablePersistingObject
    extends ObservableBase<ObservablePersistingObject> {
  ObservablePersistingObject(this.identifier) {
    box = () async {
      await safeHiveInit();
      return Hive.openBox<String>(identifier, path: await filesDir());
    }();
    _initialLoad();
  }

  String identifier;
  late Future<Box<String>> box;

  _initialLoad() async {
    var value = (await box).get(identifier);
    if (value == null) {
      return;
    }
    fromJson(jsonDecode(value));
    super.notifyObservers(
        this); // calling it from super so we don't have to reload from box,
    // yet we're notifying the view
  }

  @override
  void notifyObservers(event) {
    super.notifyObservers(event);
    box.then((loadedBox) {
      loadedBox.put(identifier, jsonEncode(toJson()));
    });
  }

  // a short hand for calling notifyObservers
  notifyAndPersist() => notifyObservers(this);

  fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

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
    bool isNew = !_dictionary.containsKey(item.id);
    _dictionary[item.id] = item;

    if (item.targetsToPushTo.isNotEmpty) {
      // the following gymnastics would only
      // be done when the item is meant to be pushed
      // otherwise it's just a waste of time and resources
      final newJson = item.jsonCopyForPush;
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
    assert(items.length == jsonMaps.length);

    _dictionary.addAll(items);
    _jsonCopies.addAll(jsonMaps);

    notifyObservers(items.entries
        .map((item) => DictEvent.add(item.key, document: item.value))
        .toList());
  }

  void remove(String id) {
    if (_dictionary.containsKey(id)) {
      _dictionary.remove(id);
      notifyObservers([DictEvent.remove(id)]);
      _copyDictionary([id]);
    }
  }

  void clear() {
    _dictionary.clear();
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
      _jsonCopies[id] = _dictionary[id]!.jsonCopyForPush;
    }
  }
}

enum DictEventType {
  add,
  modify,
  remove,
}

class DictEvent {
  final DictEventType type;
  final String id;
  final List<String> modifiedKeys;
  final Model? document;
  final List<dynamic> newVals;
  final List<dynamic> oldVals;

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
}

/// Checks if two objects (including Lists and Maps) are deeply equal.
/// Required because Dart's `==` on Collections only checks reference.
bool _areEqual(dynamic a, dynamic b) {
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
