import 'package:apexo/app/panels/panel.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A panel that shows editors whose persistence belongs to the caller.
///
/// Compared with [RowPanel]:
///   - A [RowPanel] *owns* its record: it holds one `RowDraft`, writes it with
///     `patch`/`put`, and derives `save`, `setArchived`, `isArchived` and
///     `hasPendingEdits` from that draft.
///   - This panel owns no record — the expenses
///     panel keeps one draft per order and saves them all at once, the labwork
///     panel edits whichever appointment the user picks — so the caller supplies
///     what the panel cannot know
///     such as [checkUnsavedChanges], [onSave], [checkArchived], [onSetArchived]
///
final class DelegatedPanel extends Panel {
  DelegatedPanel({
    required this.itemId,
    required super.tabs,
    required super.icon,
    required super.singularName,
    required super.unicodeSymbol,
    required this.checkUnsavedChanges,
    required this.onSave,
    bool isNew = false,
    bool Function()? checkArchived,
    this.onSetArchived,
    super.newTitle,
    super.recordTitle,
    super.inherentlyScrollable,
    super.showTitles,
    super.showBottomControls,
    super.additionalControls,
    super.archiveButtonReplacement,
    super.selectedTabIndex,
  })  : _isNew = isNew,
        _checkArchived = checkArchived;

  /// The id the caller gave this panel: a stored record's id, or the synthetic
  /// id of a panel that aggregates records.
  @override
  final String itemId;

  /// Whether the caller's drafts hold work that is not saved yet.
  ///
  /// This panel owns no record and keeps no snapshot of one, so the caller —
  /// which is what actually holds the drafts — is the only one who can answer.
  final bool Function() checkUnsavedChanges;

  /// The caller's save: it writes, and answers with the ids of the records it
  /// wrote. Required, because this panel owns no record to write.
  ///
  /// Answering with the ids is what keeps the panel's `savedId` honest: a
  /// caller that had to remember to report one would hand its opener the same
  /// `null` a cancel produces, and nothing would catch the mistake.
  final Future<List<String>> Function() onSave;

  /// Whether the records this panel shows are not stored yet. A panel that does
  /// not know is showing stored records.
  final bool _isNew;

  /// Answers [isArchived] when the caller has an archive flag to report; a
  /// panel that aggregates several records has none, and answers `false`.
  final bool Function()? _checkArchived;

  /// Applies an archive change. `null` when the caller has no archive
  /// operation — see [archiveButtonReplacement].
  final Future<void> Function(bool archived)? onSetArchived;

  @override
  bool get isNew => _isNew;

  @override
  bool get isArchived => _checkArchived?.call() ?? false;

  /// There is no record and no snapshot here — the caller holds the drafts — so
  /// pending work is whatever [checkUnsavedChanges] reports.
  @override
  bool get hasPendingEdits => checkUnsavedChanges();

  /// The archive slot, which exists only when the caller can archive.
  ///
  /// The host's default archive button calls [setArchived] and labels itself
  /// from [isArchived]; without an [onSetArchived] it would offer a delete that
  /// does nothing. A caller that cannot archive therefore gets no button — pass
  /// [archiveButtonReplacement] to put something else in the slot.
  @override
  Widget? get archiveButtonReplacement =>
      super.archiveButtonReplacement ??
      (onSetArchived == null ? const SizedBox.shrink() : null);

  /// The caller's save, so that any path reaching a save saves rather than
  /// silently returning; the ids it answers with are what this panel reports.
  @override
  Future<void> persist() async {
    for (final id in await onSave()) {
      recordSaved(id);
    }
  }

  @override
  Future<void> setArchived(bool archived) async {
    await onSetArchived?.call(archived);
  }
}
