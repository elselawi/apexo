import 'package:apexo/ui/workspace/panel.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A panel that shows editors whose persistence belongs to the caller: it holds
/// no record, so the caller supplies save, unsaved-work and archive checks.
final class DelegatedPanel extends Panel {
  DelegatedPanel({
    required this.itemId,
    required super.windows,
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
    super.liveTitle,
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
  })  : _isNew = isNew,
        _checkArchived = checkArchived;

  @override
  final String itemId;

  /// Whether the caller's drafts hold unsaved work; only it holds those drafts.
  final bool Function() checkUnsavedChanges;

  /// The caller's save; it must return the ids it wrote, which [persist] reports.
  /// Without them the opener sees the null a cancel produces.
  final Future<List<String>> Function() onSave;

  bool _isNew;

  final bool Function()? _checkArchived;

  /// Applies an archive change; null when the caller has no archive operation.
  final Future<void> Function(bool archived)? onSetArchived;

  @override
  bool get isNew => _isNew;

  @override
  bool get isArchived => _checkArchived?.call() ?? false;

  @override
  bool get hasPendingEdits => checkUnsavedChanges();

  /// No button when the caller cannot archive: the default archive button would
  /// call [onSetArchived] and offer a delete that does nothing.
  @override
  Widget? get archiveButtonReplacement =>
      super.archiveButtonReplacement ??
      (onSetArchived == null ? const SizedBox.shrink() : null);

  @override
  Future<void> persist() async {
    final ids = await onSave();
    for (final id in ids) {
      recordSaved(id);
    }
    if (ids.isNotEmpty) _isNew = false;
  }

  @override
  Future<void> setArchived(bool archived) async {
    await onSetArchived?.call(archived);
  }
}
