import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:fluent_ui/fluent_ui.dart' show Color, Widget;

/// What a window needs from the owner of the record it edits: the window reads
/// the record and asks the owner to save — one owner, one Save.
abstract interface class WindowRecordSession {
  /// The id of the record being edited — never null, even while it is unsaved.
  String get itemId;

  /// A plain-text label for the record, for a window's owner line and a band.
  String get displayTitle;

  /// Whether the record does not exist in storage yet.
  bool get isNew;

  bool get isArchived;

  /// Whether the owner offers a Save; windows of one that saves nothing get none.
  bool get showBottomControls;

  /// The record's unsaved state as a signal the host can watch.
  ObservableState<bool> get hasUnsavedChanges;

  /// Whether a write is running, so the host can show it and refuse a second.
  ObservableState<bool> get inProgress;

  /// Whether there is anything to write, asked live — the draft is edited in
  /// place, so only the owner can compare it with what was stored.
  bool get hasPendingEdits;

  /// Copies [hasPendingEdits] into [hasUnsavedChanges]. A window edits the draft
  /// in place and calls nothing, so the host must ask and the owner publishes.
  void refreshDirty();

  /// Writes what this owner holds and settles [result]. The one write.
  Future<void> save();

  /// Completes when the owner is finished: saved, or closed without saving.
  Future<void> get result;
}

/// An owner that writes outside its own Save can acknowledge only the fields it
/// wrote; clearing the whole draft would discard edits made beside them.
abstract interface class DraftAcknowledgements {
  /// The id this owner's saves wrote, or null when it wrote nothing.
  String? get savedId;

  /// Re-baselines the whole draft: a write that went through this owner's Save.
  void markSaved();

  /// Re-baselines **only** [fields]: a write that landed outside the Save.
  void markFieldsSaved(Iterable<String> fields);
}

/// A record a panel carries beside itself: one draft, one Save, and the windows
/// the record itself builds.
abstract interface class HostedRecordSession
    implements WindowRecordSession, DraftAcknowledgements {
  /// The windows this record offers. Re-read on every layout: a permission can
  /// change while the panel is open.
  List<PanelWindow> get windows;

  /// The record's kind, which is the key layout preferences are remembered by —
  /// never the record's id, or every visit would open differently.
  String get singularName;

  /// The glyph that marks the kind wherever it is drawn — 📅 for a visit.
  String get unicodeSymbol;

  Color? get accent;

  /// The localization key for this record's Save, such as "saveVisit" — a key,
  /// not a sentence.
  String get saveLabel;

  /// The band's identity line about this record — a visit's day, say.
  String get bandLabel;

  /// The record's compact editor drawn inside the band, so a form that fits needs
  /// no window of its own. Null when it has none.
  Widget? get bandContent;

  /// Whether the record is finished (a visit's `completed`), read live from the
  /// draft.
  bool get isDone;

  /// Sets the finished flag through the draft, so a band toggle and a form toggle
  /// are one edit.
  void markDone(bool done);

  /// Whether the current account may archive or restore this record.
  bool get canArchive;

  /// Archives or restores the record. Not a draft edit: it writes the stored
  /// record, and Save never flips it.
  Future<void> setArchived(bool archived);

  /// Finishes this record for good: the draft goes unwritten and the registry
  /// entry with it. A panel that means to keep the draft detaches instead.
  void dispose();
}
