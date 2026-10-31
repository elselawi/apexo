import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:fluent_ui/fluent_ui.dart' show Color, Widget;

/// What a **window** needs from whatever owns the record it edits.
///
/// A window is an editor, not an owner: it holds no record and writes nothing
/// itself. It reads the record it edits and asks the owner to save — one owner,
/// one Save, one write (plan §2.1).
///
/// [Panel] satisfies this today, member for member: every panel is the owner of
/// the record its windows edit. A panel that owns no record — `DelegatedPanel`
/// — is the caller's editor, and the caller is the owner; it never hosts
/// windows of a second record, so it needs nothing here.
abstract interface class WindowRecordSession {
  /// The id of the record being edited — never null, even while it is unsaved.
  String get itemId;

  /// A plain-text label for the record, for a window's owner line and a band.
  String get displayTitle;

  /// Whether the record does not exist in storage yet.
  bool get isNew;

  bool get isArchived;

  /// Whether this owner offers a Save at all — the existing "this panel saves"
  /// flag. A window of an owner that saves nothing gets no Save button.
  bool get showBottomControls;

  /// Whether the record holds work that is not persisted yet, as a signal the
  /// host can watch.
  ObservableState<bool> get hasUnsavedChanges;

  /// Whether a write is running, so the host can show it and refuse a second.
  ObservableState<bool> get inProgress;

  /// Whether there is anything to write — asked live, because a window edits the
  /// draft in place and only the owner can compare it with what was stored.
  bool get hasPendingEdits;

  /// Copies the live answer of [hasPendingEdits] into [hasUnsavedChanges].
  ///
  /// A window edits the draft in place and calls nothing: the one who can see
  /// that a keystroke happened is the widget that took it, and it belongs to the
  /// feature, not to the host. So the host asks — on its own tick, and at every
  /// point that already knows an edit landed — and the owner publishes the
  /// answer where the chrome listens.
  ///
  /// A panel's own answer is already [hasPendingEdits]; this is what lets an
  /// owned session answer the same question for the same chrome.
  void refreshDirty();

  /// Writes what this owner holds and settles [result]. The one write.
  Future<void> save();

  /// Completes when the owner is finished: saved, or closed without saving.
  Future<void> get result;
}

/// A record owner that also writes **outside** its own Save — a gallery, a QR
/// page, a chart — and must acknowledge those fields without clearing the rest
/// of the draft.
///
/// Acknowledging more than was written is the defect this exists to stop: a
/// photo upload that says "the record is clean" also throws away the note typed
/// beside it (plan §7.4).
///
/// `RowPanel` satisfies this today; `DelegatedPanel` does not write anything of
/// its own and does not need to.
abstract interface class DraftAcknowledgements {
  /// The id this owner's saves wrote, or null when it wrote nothing.
  String? get savedId;

  /// Re-baselines the whole draft: a write that went through this owner's Save.
  void markSaved();

  /// Re-baselines **only** [fields]: a write that landed outside the Save.
  void markFieldsSaved(Iterable<String> fields);
}

/// A record a panel carries **beside** itself: one draft, one Save, and the
/// windows that edit it.
///
/// The panel is the room, the record is the table, and its windows are the
/// instruments on it (plan §3). So the windows belong to the record — a visit
/// builds its own, because only the feature knows what a visit's pre-op form
/// is — and the panel only decides where they go.
///
/// This is deliberately narrower than [WindowRecordSession]: a `DelegatedPanel`
/// owns no record and carries nothing, so it is never one of these.
abstract interface class HostedRecordSession
    implements WindowRecordSession, DraftAcknowledgements {
  /// The windows this record offers, in the order it offers them.
  ///
  /// Named rather than counted, and read on every layout: a permission can
  /// change while the panel is open, and the row must not keep a window the
  /// record may no longer show.
  List<PanelWindow> get windows;

  /// The record's kind — its `singularName`, the key the layout preferences are
  /// remembered by. **Never** the record's id: a remembered layout is per kind,
  /// or every visit would open differently (plan §6.2-4).
  String get singularName;

  /// The glyph that marks the kind wherever it is drawn — 📅 for a visit.
  String get unicodeSymbol;

  /// The colour the kind is known by, so a visit's windows and its patient's are
  /// told apart at a glance.
  Color? get accent;

  /// The localization key for this record's Save — "saveVisit" — so the band and
  /// the record's windows say **which** record they write (plan §4.4).
  String get saveLabel;

  /// What the band's identity line says about this record.
  ///
  /// The record's own claim on the eye — a visit's day, say — without repeating
  /// the record the panel already names in its header.
  String get bandLabel;

  /// The record's compact editor, drawn **inside** the band the panel gives it.
  ///
  /// A visit's whole appointment form — when, how long, whose, what was planned
  /// — fits in the band, so it needs no window of its own, no row slot, and no
  /// click. Null for a record with nothing to put there.
  Widget? get bandContent;

  /// Whether the record is finished: a visit's `completed`. The band shows it
  /// live, from the draft (plan §8.1).
  bool get isDone;

  /// Marks the record finished, or not — through the record's own draft, so a
  /// band toggle and a form toggle are the same edit.
  void markDone(bool done);

  /// Whether the current account may archive or restore this record.
  bool get canArchive;

  /// Archives or restores the record.
  ///
  /// Not a draft edit: the flag changes the stored record, and opening or saving
  /// the record never flips it (plan §4.7).
  Future<void> setArchived(bool archived);

  /// Finishes this record for good: the panel that carried it is done with it.
  ///
  /// Disposing is **not** saving: the draft goes unwritten, and the record's
  /// registry entry with it. A panel that means to keep the draft detaches
  /// instead, and the draft stays in `owned`.
  void dispose();
}
