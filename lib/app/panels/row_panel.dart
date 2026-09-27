import 'dart:convert';

import 'package:apexo/app/panels/panel.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';

/// A panel that edits **one** stored record through the app's [Store].
///
/// This is the storage half of the panel refactor. [Panel] is everything
/// `PanelScreen` needs and deliberately knows nothing about how records are
/// stored; this is what the app's Hive [Store] gives it. One class per
/// storage backend is the whole point of that split — so this is the same idea
/// as the migration branch's `RowPanel` over `localpocket`, against the store
/// the app actually uses.
///
/// The constructor keeps the shape the feature panels were already written
/// against (`item`, `store`, `title`, `canNotBeNew`, `checkUnsavedChanges`,
/// `onSave`), so a feature names this class instead of the old `Panel<T>` and
/// changes nothing else.
final class RowPanel<T extends Model> extends Panel {
  RowPanel({
    required this.item,
    required this.store,
    required this.title,
    required super.tabs,
    required super.icon,
    required super.singularName,
    required super.unicodeSymbol,
    bool? existing,
    this.canNotBeNew = false,
    this.checkUnsavedChanges,
    this.onSave,
    super.inherentlyScrollable,
    super.showTitles,
    super.showBottomControls,
    super.additionalControls,
    super.archiveButtonReplacement,
    super.selectedTabIndex,
  })  : _existing = existing ?? (store.get(item.id) != null),
        _savedJson = jsonEncode(item.toJson()),
        super(
          // The old constructor took one `title` that already knew whether the
          // record existed; the host wants the two questions apart. Splitting it
          // here keeps that in one place instead of in every feature, and the
          // header still ends up right: the opener calls `readTitle()` before
          // showing the panel, which fills in a stored record's own name, and
          // `newTitle` covers the record that has no name yet.
          newTitle: title,
          recordTitle: () async => item.title,
        );

  /// The record this panel edits — a copy, so the store only sees it on save.
  final T item;

  /// The store the record lives in.
  final Store<T> store;

  /// The label the header shows while the record does not exist yet.
  final String title;

  /// A panel that can never be new (one aggregating records, keyed by a
  /// synthetic id): the header shows the id, never a "new …" label.
  final bool canNotBeNew;

  /// Answers [hasPendingEdits] when the caller manages more than one record and
  /// therefore keeps the snapshot itself.
  final bool Function()? checkUnsavedChanges;

  /// Replaces the default `store.set(item)` when the save is the caller's.
  final void Function()? onSave;

  /// Whether the record was stored when the panel opened.
  ///
  /// Not the same question as "does it have an id": a new record carries an id
  /// before it is ever written.
  bool _existing;

  /// The record's JSON as of the last save, for the unsaved-changes check.
  String _savedJson;

  @override
  String get itemId => item.id;

  @override
  bool get isNew => !canNotBeNew && !_existing;

  @override
  bool get isArchived => item.archived == true;

  /// A caller that manages several records answers for itself; otherwise the
  /// record's own JSON against the snapshot taken when the panel opened.
  @override
  bool get hasPendingEdits =>
      checkUnsavedChanges?.call() ?? (jsonEncode(item.toJson()) != _savedJson);

  @override
  Future<void> persist() async {
    if (onSave != null) {
      onSave!();
    } else {
      store.set(item);
    }
    // The record is stored now, so it is clean and it exists: without this the
    // panel would keep saying "Cancel" over work it has just saved, and the
    // next close would ask about changes that are already in the store.
    markSaved();
    recordSaved(item.id);
  }

  /// Re-baselines the unsaved-changes check after a write that did not go
  /// through [persist].
  ///
  /// The gallery saves an appointment the moment a photo is uploaded or
  /// deleted, so the record is stored and the panel is already clean; without
  /// this it would keep offering to save what it has just saved.
  void markSaved() {
    _savedJson = jsonEncode(item.toJson());
    _existing = true;
  }

  @override
  Future<void> setArchived(bool archived) async {
    if (archived) {
      store.archive(item.id);
    } else {
      store.unarchive(item.id);
    }
  }
}
