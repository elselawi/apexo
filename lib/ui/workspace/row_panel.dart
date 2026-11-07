import 'dart:convert';

import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';

/// A panel that edits one stored record through the app's [Store].
final class RowPanel<T extends Model> extends Panel
    implements DraftAcknowledgements {
  RowPanel({
    required this.item,
    required this.store,
    required this.title,
    required super.windows,
    required super.icon,
    required super.singularName,
    required super.unicodeSymbol,
    bool? existing,
    this.canNotBeNew = false,
    this.checkUnsavedChanges,
    this.onSave,
    this.validate,
    String? savedBaseline,
    super.showBottomControls,
    super.saveLabel,
    super.carriedDraftWindowId,
    super.workspaceWindows,
    super.attachmentLayout,
    super.additionalControls,
    super.archiveButtonReplacement,
    super.carriedBandFooter,
    super.initialWindow,
    super.opensWithWindows,
    super.accent,
  })  : _existing = existing ?? (store.get(item.id) != null),
        _savedJson = savedBaseline ?? jsonEncode(item.toJson()),
        super(
          // One `title` comes in; the host wants "named yet?" and "its name"
          // apart, so it becomes `newTitle` and `recordTitle`.
          newTitle: title,
          recordTitle: () async => item.title,
        );

  /// The record this panel edits — a copy, so the store only sees it on save.
  final T item;

  /// The store the record lives in.
  final Store<T> store;

  /// The label the header shows while the record does not exist yet.
  final String title;

  /// A panel that can never be new, such as one aggregating records under a
  /// synthetic id.
  final bool canNotBeNew;

  /// Answers [hasPendingEdits] for a caller that tracks more than one record.
  final bool Function()? checkUnsavedChanges;

  /// Replaces the default `store.set(item)` when the save is the caller's.
  final void Function()? onSave;

  final String? Function()? validate;

  /// Whether the record was stored when the panel opened — not the same question
  /// as having an id, which a new record has before it is written.
  bool _existing;

  /// The record's JSON as of the last save. A panel adopting a window's work
  /// passes the stored JSON as `savedBaseline`, so it opens dirty.
  String _savedJson;

  @override
  String get itemId => item.id;

  /// The record's own draft, as JSON — what a window's work is written over.
  @override
  Map<String, dynamic> get draftJson => item.toJson();

  /// Writes the incoming fields onto the draft the panel already holds: its
  /// windows edit that same draft, so replacing it would leave them stale.
  @override
  void adoptDraft(Map<String, dynamic> json) {
    item.fromJson(json);
  }

  @override
  bool get isNew => !canNotBeNew && !_existing;

  @override
  bool get isArchived => item.archived == true;

  @override
  bool get hasPendingEdits =>
      checkUnsavedChanges?.call() ?? (jsonEncode(item.toJson()) != _savedJson);

  @override
  Future<void> persist() async {
    final validationError = validate?.call();
    if (validationError != null) throw FormatException(validationError);
    if (onSave != null) {
      onSave!();
    } else {
      store.set(store.modeling(
          jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>));
    }
    // The record is stored now: without re-baselining, the panel would keep
    // offering to save work already written and ask again on close.
    markSaved();
    recordSaved(item.id);
  }

  /// Re-baselines the unsaved check after a write that bypassed [persist] (a
  /// photo upload saves at once) and marks the record stored.
  @override
  void markSaved() {
    _savedJson = jsonEncode(item.toJson());
    _existing = true;
  }

  /// Acknowledges fields saved immediately without clearing other draft edits.
  @override
  void markFieldsSaved(Iterable<String> fields) {
    final saved = jsonDecode(_savedJson) as Map<String, dynamic>;
    final current = item.toJson();
    for (final field in fields) {
      if (current.containsKey(field)) {
        saved[field] = current[field];
      } else {
        saved.remove(field);
      }
    }
    _savedJson = jsonEncode({
      for (final field in {...current.keys, ...saved.keys})
        if (saved.containsKey(field)) field: saved[field],
    });
  }

  @override
  Future<void> setArchived(bool archived) async {
    final validationError = validate?.call();
    if (validationError != null) throw FormatException(validationError);
    final updated = store
        .modeling(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>)
      ..archived = archived;
    store.set(updated);
    item.archived = archived;
    markSaved();
  }
}
