import 'dart:async';
import 'dart:convert';
import 'package:apexo/utils/safe_dir.dart';
import 'package:apexo/utils/safe_hive_init.dart';
import 'package:hive_flutter/adapters.dart';
import '../reactive/observable_base.dart';

/// Persists its data to a hive box
/// however only data that are defined in toJson and fromJson will be persisted
abstract class ObservablePersistingObject
    extends ObservableBase<ObservablePersistingObject> {
  ObservablePersistingObject(this.identifier, {this.storagePath}) {
    box = () async {
      await safeHiveInit();
      return Hive.openBox<String>(
        identifier,
        path: storagePath ?? await filesDir(),
      );
    }();
    ready = _initialLoad();
  }

  String identifier;
  final String? storagePath;
  late Future<Box<String>> box;
  late final Future<void> ready;

  Future<void> _initialLoad() async {
    final value = (await box).get(identifier);
    if (value == null) {
      return;
    }
    await fromJson(jsonDecode(value) as Map<String, dynamic>);
    super.notifyObservers(
        this); // calling it from super so we don't have to reload from box,
    // yet we're notifying the view
  }

  @override
  void notifyObservers(event) {
    super.notifyObservers(event);
    final snapshot = jsonEncode(toJson());
    unawaited(box.then((loadedBox) => loadedBox.put(identifier, snapshot))
        .catchError((Object e, StackTrace s) {
      onError(e, s);
    }));
  }

  // a short hand for calling notifyObservers
  void notifyAndPersist() => notifyObservers(this);

  FutureOr<void> fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

