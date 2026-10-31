import 'dart:async';

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panel_workspace.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show nonVirtual, protected;

/// A panel, as the host sees it: everything [PanelScreen] needs from whatever is
/// on screen, independent of how the records behind it are stored.
///
/// A panel is the **owner** of the record its windows edit — [WindowRecordSession]
/// is that fact, named so a window can ask for it without knowing what kind of
/// panel is answering — and it can also carry visits beside itself (see
/// [attach]).
abstract base class Panel implements WindowRecordSession {
  Panel({
    required this.windows,
    required this.icon,
    required this.singularName,
    required this.unicodeSymbol,
    this.newTitle,
    this.recordTitle,
    this.liveTitle,
    this.initialWindow,
    this.opensWithWindows = true,
    this.accent,
    this.showBottomControls = true,
    this.saveLabel = 'save',
    this.recordsWindowId,
    this.workspaceWindows = const <String>[],
    this.attachmentLayout = false,
    this.additionalControls,
    this.archiveButtonReplacement,
  });

  /// The windows this panel offers, in priority order. The first **row** window
  /// is drawn in the panel itself; the rest of the row floats beside it. Windows
  /// with [PanelWindow.attachedTo] set are attachments and are not in the row.
  final List<PanelWindow> windows;

  /// The windows the row draws: everything that is not an attachment.
  ///
  /// Computed on every read rather than frozen at construction: the list of
  /// windows is built from what the user may see, and a permission that changes
  /// while the panel is open must not leave a window behind that the panel may
  /// no longer show.
  List<PanelWindow> get rowWindows => <PanelWindow>[
        for (final window in windows)
          if (!window.isAttachment) window
      ];

  /// The editor the panel keeps inline — what its first tab used to be. Null
  /// for a panel with no windows at all.
  PanelWindow? get primaryWindow =>
      rowWindows.isEmpty ? null : rowWindows.first;

  /// The editors the panel floats: the row's windows after the inline one, in
  /// priority order. A screen with room for two of these opens the first two.
  List<PanelWindow> get floatingWindows =>
      rowWindows.length <= 1 ? const <PanelWindow>[] : rowWindows.sublist(1);

  /// The windows hanging off the panel itself — a patient's photos and page,
  /// drawn as an attachment tray under the body rather than as row windows.
  List<PanelWindow> get panelAttachments => <PanelWindow>[
        for (final window in windows)
          if (window.attachedTo == PanelWindow.panelAttachment) window,
      ];

  /// The windows hanging off [windowId], drawn as a tray on that window's own
  /// frame.
  List<PanelWindow> attachmentsOf(String windowId) => <PanelWindow>[
        for (final window in windows)
          if (window.attachedTo == windowId) window,
      ];

  /// The window the opener wants on screen, by [PanelWindow.id] — the one that
  /// answers the question the user asked when they opened the panel. Null when
  /// the panel decides by itself.
  final String? initialWindow;

  /// Whether opening the panel also puts the windows this screen has room for on
  /// screen. False for an opener that came for the record itself — a dashboard
  /// row that means "this new patient", not "their chart" — which leaves every
  /// window one click away in the dock, and none of them in the way.
  final bool opensWithWindows;

  /// The colour this kind of record is known by — see `PanelAccents`. Null keeps
  /// the theme's accent.
  final Color? accent;

  /// Which of [windows] are on screen. Lives on the panel, so a window's state
  /// survives the panel's rebuilds and goes away with the panel itself.
  ///
  /// The host sets [PanelWorkspace.onUserChange] when it attaches the panel, so
  /// what the user opens and puts away is remembered for the next panel of the
  /// same kind — without the panel knowing where that memory lives.
  late final PanelWorkspace workspace = PanelWorkspace();

  final IconData icon;
  final String singularName;
  final String unicodeSymbol;

  /// What the header shows while the record does not exist yet ("New patient"):
  /// nothing on a record that is not there can name it, so the opener does.
  /// Null falls through to [itemId].
  ///
  /// This is a localization *key*, not a sentence: the widget translates it
  /// when drawing, so a language switch relabels a live panel. A real name
  /// passes through `txt` unchanged, so a caller may hand one in.
  final String? newTitle;

  /// Reads the record's own title. The opener supplies it, because only it can
  /// name its schema's rows — [readTitle] asks before the panel is shown and
  /// again after every save.
  final Future<String?> Function()? recordTitle;

  @override
  final bool showBottomControls;

  /// The localization key for this panel's own Save — "savePatient" — so the
  /// bottom bar says which of the two records on screen it writes (plan §4.4).
  final String saveLabel;

  /// The window of this panel that lists the records it **carries** — a
  /// patient's Visits window. Tapping the band's unsaved count opens it, so a
  /// retained draft always has somewhere to be seen. Null for a panel that
  /// carries nothing.
  final String? recordsWindowId;

  /// The row windows this panel offers as **workspace buttons**, inside its own
  /// body — a patient's chart and Visits list.
  ///
  /// A panel that lists them here does not also list them in a dock: one window
  /// has one control, so nothing on screen offers the same thing twice.
  final List<String> workspaceWindows;

  /// Whether this panel presents its secondary windows as **attachments** rather
  /// than as a dock under the header.
  ///
  /// A patient's photos and page hang off the panel (an attachment tray under
  /// the record), and its chart and Visits list are the labelled workspace
  /// buttons inside it: that is the whole surface, and a dock would only repeat
  /// it. Other panels keep their dock untouched.
  final bool attachmentLayout;

  final Widget? additionalControls;
  final Widget? archiveButtonReplacement;

  @override
  final inProgress = ObservableState(false);
  @override
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);
  final int creationDate = DateTime.now().millisecondsSinceEpoch;

  String get identifier => identifierFor(singularName, itemId, isNew: isNew);

  /// The identifier a panel of this kind shows for [itemId] — the record's own
  /// id, or the kind's "new" name while the record is not stored yet.
  ///
  /// The same rule [identifier] follows, so an opener can ask "is this record's
  /// panel already open?" before it builds one, and its answer cannot disagree
  /// with what [PanelsManager.open] would do with the panel it builds.
  static String identifierFor(
    String singularName,
    String itemId, {
    required bool isNew,
  }) =>
      isNew ? 'new+$singularName' : itemId;

  /// The record's own draft, as JSON — what the work of a window is written
  /// over.
  ///
  /// Empty for a panel that owns no record: it has no draft of its own to
  /// write anything over.
  Map<String, dynamic> get draftJson => const <String, dynamic>{};

  /// Takes in the work a window of this record was holding: the record's own
  /// fields, written over the draft this panel already holds.
  ///
  /// A panel that opens over a window adopts the work rather than leaving two
  /// drafts of one record on screen: the panel carries it, starts dirty on it,
  /// and its own Save is the one write.
  ///
  /// A panel that owns no record — or one that tracks several — has nothing to
  /// take in, and does nothing.
  void adoptDraft(Map<String, dynamic> json) {}

  /// Completes when the panel is finished: saved, or closed without saving.
  /// Every removal from the stack settles it too, so awaiting it never hangs.
  @override
  Future<void> get result => _result.future;

  final Completer<void> _result = Completer<void>();

  /// Settles [result]: the panel is done — saved, or closed without saving.
  /// Idempotent: [save] and `PanelsManager` both call it, and whichever is
  /// first is the answer.
  void settle() {
    if (!_result.isCompleted) _result.complete();
  }

  final List<String> _savedIds = <String>[];

  /// The ids of the records this panel's own saves wrote, in the order written
  List<String> get savedIds => List.unmodifiable(_savedIds);

  /// The one id an opener hands back: the first record this panel saved, or
  /// `null` when it saved none — the same `null` a panel that was closed
  /// produces, so a caller reads "nothing was saved" in exactly one way.
  String? get savedId => _savedIds.isEmpty ? null : _savedIds.first;

  /// Records one record this panel's save wrote, from the kind's own [persist]
  /// and from nothing else: a [DelegatedPanel]'s `onSave` answers with the ids
  /// it wrote and the panel records them here, so no caller has to remember.
  @protected
  void recordSaved(String id) {
    if (!_savedIds.contains(id)) _savedIds.add(id);
  }

  /// The id of the record this panel is showing — never null, even while the
  /// record is still unsaved.
  @override
  String get itemId;

  /// The record's title as last read, or `null` while nothing has named it.
  String? _recordTitle;

  bool _titleRead = false;

  /// A plain-text label for the panel switcher: the record's own title, else the
  /// opener's placeholder while the record is new, else [itemId].
  ///
  /// The row id shows only when nothing named the record at all — each schema
  /// names its rows through its own extension, so the opener supplies
  /// [recordTitle] to read it.
  ///
  /// Whatever this returns — a key ([newTitle]) or a real name ([recordTitle])
  /// — is translated where it is drawn, never here: only a build knows the
  /// current language.
  @override
  String get displayTitle =>
      liveTitle?.call() ?? _recordTitle ?? (isNew ? newTitle : null) ?? itemId;

  /// The record's title, read live rather than remembered — for a record whose
  /// name can change while its panel is open, such as a supplier that is
  /// renamed from inside the panel.
  ///
  /// A panel that reads its title once keeps showing the old name after the
  /// rename that happened inside it.
  final String Function()? liveTitle;

  /// Reads [recordTitle] into the header.
  ///
  /// The opener runs it before showing the panel, so the first frame is right;
  /// the host runs it as a safety net, and [save] runs it again with `refresh`
  /// so a name typed into a new record shows once the record exists.
  Future<void> readTitle({bool refresh = false}) async {
    if (_titleRead && !refresh) return;
    _titleRead = true;
    final read = await recordTitle?.call();
    _recordTitle = (read == null || read.trim().isEmpty) ? null : read;
  }

  /// Whether the record does not exist in storage yet.
  @override
  bool get isNew;

  @override
  bool get isArchived;

  /// Whether the panel currently holds work that is not persisted yet — the
  /// host's question, answered by each panel for itself.
  @override
  bool get hasPendingEdits;

  /// Publishes [anyUnsavedChanges] into [hasUnsavedChanges], which is what the
  /// header's dot and a close prompt watch: closing this panel closes the visit
  /// it carries, so the visit's work counts too (plan §2.4).
  ///
  /// A panel whose answer is pushed (`pendingEditsSignal`) hears about an edit
  /// without being asked; a panel whose draft is edited in place — a row panel's
  /// fields, an owned visit session's windows — has to be asked, so the owner of
  /// each owned session is asked here too.
  ///
  /// The Save button does **not** read this: it reads [hasPendingEdits], because
  /// this panel's Save writes this panel's record and nothing else (plan §4.5).
  @override
  void refreshDirty() {
    for (final session in _owned) {
      session.refreshDirty();
    }
    final dirty = anyUnsavedChanges;
    if (hasUnsavedChanges() != dirty) {
      hasUnsavedChanges(dirty);
    }
  }

  /// The sessions this panel carries, whether or not they are selected: a
  /// retained draft outlives being swapped out of the row.
  final List<HostedRecordSession> _owned = <HostedRecordSession>[];

  /// The one session whose windows are in the row.
  HostedRecordSession? _attached;

  /// The window of [_attached] the opener asked for, by [PanelWindow.id].
  String? _attachedFocus;

  /// Emits whenever what this panel carries changes — a visit attached,
  /// detached or dropped.
  ///
  /// Attaching mutates a panel that is already on screen, and nothing else
  /// observes that: the layer rebuilds on the panel *object* changing, which it
  /// does not when a visit joins it. Without this signal `attach()` compiles,
  /// runs, and shows nothing (plan §6.2-2).
  final ObservableState<int> attachments = ObservableState(0);

  /// Every session this panel is responsible for, selected or not.
  List<HostedRecordSession> get owned => List.unmodifiable(_owned);

  /// The session whose windows are in the row, if any.
  HostedRecordSession? get attached => _attached;

  /// The window of the attached session the opener asked for, if any.
  String? get attachedFocus => _attachedFocus;

  /// The panel's own window the user asked for **now** — a chart's "all
  /// appointments", the band's unsaved count, a list the user tapped.
  ///
  /// The layer reads it once, as the row's focus, and clears it: the request is
  /// an instruction to show one window now, not a permanent arrangement. The
  /// arrangement itself is the remembered open set (see `WindowDefaults`).
  String? requestedWindow;

  /// Asks for one of the panel's own windows: on screen, in front of the record.
  ///
  /// What a control outside the window means — a chart's "all appointments", the
  /// band's unsaved count, a list the user tapped. The layer reads it once, as
  /// the row's focus, and clears it: the request is an instruction to show one
  /// window now, not a permanent arrangement. Choosing it does, however, end the
  /// request the record's opener made — a visit's chart is no longer the window
  /// to show just because the visit was opened for it.
  void showWindow(String id) {
    requestedWindow = id;
    _attachedFocus = null;
    workspace.show(id);
  }

  /// Whether anything this panel is responsible for holds unsaved work: its own
  /// record, or any visit it carries — including one whose windows are not on
  /// screen (plan §2.4).
  bool get anyUnsavedChanges =>
      hasPendingEdits || _owned.any((session) => session.hasPendingEdits);

  /// Makes [session] the record whose windows are in the row, keeping its draft
  /// — and every other draft this panel already owns.
  ///
  /// Never prompts: a draft is not discarded by looking at another one (plan
  /// §2.5). [focus] names the window the opener came for; the layer opens it if
  /// the row has room.
  void attach(HostedRecordSession session, {String? focus}) {
    if (!_owned.any((owned) => identical(owned, session))) {
      _owned.add(session);
    }
    _attached = session;
    _attachedFocus = focus;
    // The opener's own request, made here as well as in the layer's plan: a
    // window asked for by name is on screen as soon as the visit is attached,
    // whether or not this panel's row has been planned yet.
    if (focus != null) workspace.show(focus, slot: kAttachedSlot);
    attachments(attachments() + 1);
  }

  /// Takes the attached record out of the row, **keeping** ownership: its draft
  /// is the user's until the panel is done with it.
  void detach() {
    if (_attached == null) return;
    _attached = null;
    _attachedFocus = null;
    workspace.clearSlot(kAttachedSlot);
    attachments(attachments() + 1);
  }

  /// Drops [session] for good: its draft is not written and it leaves the
  /// registry. This is what "discard" means, and the only thing that loses work.
  void disposeSession(HostedRecordSession session) {
    _owned.removeWhere((owned) => identical(owned, session));
    if (identical(_attached, session)) {
      _attached = null;
      _attachedFocus = null;
      workspace.clearSlot(kAttachedSlot);
    }
    session.dispose();
    attachments(attachments() + 1);
  }

  /// Drops every session this panel carries — the panel itself is going away,
  /// so nothing would be left to show or save them.
  ///
  /// Not a save: a caller that wants the work written saves first.
  void releaseSessions() {
    final sessions = _owned.toList();
    _owned.clear();
    _attached = null;
    _attachedFocus = null;
    workspace.clearSlot(kAttachedSlot);
    for (final session in sessions) {
      session.dispose();
    }
    if (sessions.isNotEmpty) attachments(attachments() + 1);
  }

  /// A signal the host can watch instead of sampling [hasPendingEdits], for a
  /// kind whose answer changes without the host asking. Null when the kind has
  /// nothing to push: a [DelegatedPanel]'s answer is its caller's callback,
  /// which the host can only ask.
  ObservableState<int>? get pendingEditsSignal => null;

  /// The header title widget of this panel: [displayTitle], greyed out once the
  /// record is archived.
  ///
  /// Shared as-is; no panel has needed a different header.
  ///
  /// [displayTitle] is translated here, at draw time: `Txt` renders its input
  /// verbatim, so a key would show as the raw key on screen. `txt` returns a
  /// non-key unchanged, so a real name is handed through as-is.
  Widget buildTitle(BuildContext context) => Txt(
        txt(displayTitle),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: isArchived ? Colors.grey : null),
      );

  /// Persists the editor's current state, re-reads the title, then settles
  /// [result]. The kinds implement [persist]; overriding this would skip the
  /// settlement.
  @nonVirtual
  @override
  Future<void> save() async {
    if (inProgress()) return;
    inProgress(true);
    try {
      await persist();
      settle();
      await readTitle(refresh: true);
    } finally {
      inProgress(false);
    }
  }

  /// The panel's own write, run by [save] and by nothing else.
  @protected
  Future<void> persist();

  /// Archives or restores the record.
  Future<void> setArchived(bool archived);
}
