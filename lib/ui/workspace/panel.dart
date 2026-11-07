import 'dart:async';

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panel_workspace.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show nonVirtual, protected;

/// A panel as the host sees it. It owns the record its windows edit
/// ([WindowRecordSession]) and can carry a visit alongside it (see [attach]).
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
    this.carriedDraftWindowId,
    this.workspaceWindows = const <String>[],
    this.attachmentLayout = false,
    this.additionalControls,
    this.archiveButtonReplacement,
    this.carriedBandFooter,
  });

  /// In priority order: the first row window is drawn inline, the rest float beside it.
  final List<PanelWindow> windows;

  /// Computed on every read: a permission change while open must not leave its window behind.
  List<PanelWindow> get rowWindows => <PanelWindow>[
        for (final window in windows)
          if (!window.isAttachment) window
      ];

  PanelWindow? get primaryWindow =>
      rowWindows.isEmpty ? null : rowWindows.first;

  List<PanelWindow> get floatingWindows =>
      rowWindows.length <= 1 ? const <PanelWindow>[] : rowWindows.sublist(1);

  List<PanelWindow> get panelAttachments => <PanelWindow>[
        for (final window in windows)
          if (window.attachedTo == PanelWindow.panelAttachment) window,
      ];

  List<PanelWindow> attachmentsOf(String windowId) => <PanelWindow>[
        for (final window in windows)
          if (window.attachedTo == windowId) window,
      ];

  /// The window the opener wants shown; null lets the layer decide.
  final String? initialWindow;

  /// Whether opening also puts windows on screen; false leaves all of them in the dock.
  final bool opensWithWindows;

  final Color? accent;

  /// Which of [windows] are on screen. Lives on the panel, so it survives its
  /// rebuilds; the host binds [PanelWorkspace.onUserChange] to remember it per kind and slot.
  late final PanelWorkspace workspace = PanelWorkspace();

  final IconData icon;
  final String singularName;
  final String unicodeSymbol;

  /// Header title while the record is new; falls back to [itemId]. This is a
  /// localization key, or a real name — translated where it is drawn, not here.
  final String? newTitle;

  /// Reads the record's title; the opener supplies it since only it knows the schema's rows.
  final Future<String?> Function()? recordTitle;

  @override
  final bool showBottomControls;

  /// Localization key for this panel's own Save (e.g. "savePatient"), translated by the bottom bar.
  final String saveLabel;

  /// The window whose switch shows the unsaved dot when a carried record has a
  /// draft, even with that window closed. Null when the panel carries nothing.
  final String? carriedDraftWindowId;

  /// Row windows offered as buttons inside the panel body instead of in its dock.
  final List<String> workspaceWindows;

  /// Secondary windows drawn as attachments rather than in a dock under the header.
  final bool attachmentLayout;

  final Widget? additionalControls;
  final Widget? archiveButtonReplacement;

  /// Drawn under a carried record's band: the carried record can edit this field
  /// too, so it must stay reachable while the band covers the record's own form.
  final Widget? carriedBandFooter;

  @override
  final inProgress = ObservableState(false);
  @override
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);
  final int creationDate = DateTime.now().millisecondsSinceEpoch;

  String get identifier => identifierFor(singularName, itemId, isNew: isNew);

  /// The id a panel of this kind uses for [itemId]; must match [identifier], so a
  /// caller can ask whether this record's panel is open before building one.
  static String identifierFor(
    String singularName,
    String itemId, {
    required bool isNew,
  }) =>
      isNew ? 'new+$singularName' : itemId;

  Map<String, dynamic> get draftJson => const <String, dynamic>{};

  /// Takes in work a window of this record still held, so the panel becomes the
  /// record's one draft: it starts dirty and its own Save is the only write.
  void adoptDraft(Map<String, dynamic> json) {}

  /// Completes when the panel is done, saved or not; removal from the stack settles it too.
  @override
  Future<void> get result => _result.future;

  final Completer<void> _result = Completer<void>();

  /// Settles [result]; idempotent, since [save] and `PanelsManager` both call it.
  void settle() {
    if (!_result.isCompleted) _result.complete();
  }

  final List<String> _savedIds = <String>[];

  /// The ids of the records this panel's own saves wrote, in the order written
  List<String> get savedIds => List.unmodifiable(_savedIds);

  /// The first record this panel's save wrote; null when nothing was saved, closed or otherwise.
  String? get savedId => _savedIds.isEmpty ? null : _savedIds.first;

  /// Records an id this panel's save wrote; called from [persist], not by callers.
  @protected
  void recordSaved(String id) {
    if (!_savedIds.contains(id)) _savedIds.add(id);
  }

  @override
  String get itemId;

  /// The record's title as last read, or `null` while nothing has named it.
  String? _recordTitle;

  bool _titleRead = false;

  /// Label for the panel switcher: live title, else the read title, else [newTitle]
  /// while new, else [itemId]. Never translated here — a key goes out unchanged.
  @override
  String get displayTitle =>
      liveTitle?.call() ?? _recordTitle ?? (isNew ? newTitle : null) ?? itemId;

  /// Reads the title on each call, so a rename made inside the panel is not stale.
  final String Function()? liveTitle;

  /// Reads [recordTitle] into the header; `refresh` forces a re-read, which [save]
  /// does after persisting so a new record's name appears.
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

  @override
  bool get hasPendingEdits;

  /// Refreshes [hasUnsavedChanges] for the header dot and the close prompt, after
  /// asking each owned session. Save reads [hasPendingEdits] instead — this record only.
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

  /// Every session the panel carries, attached or not: a retained draft outlives the row.
  final List<HostedRecordSession> _owned = <HostedRecordSession>[];

  /// The one session whose windows are in the row.
  HostedRecordSession? _attached;

  /// The window of [_attached] the opener asked for, by [PanelWindow.id].
  String? _attachedFocus;

  /// Emits when what the panel carries changes. Attaching mutates a panel already on
  /// screen, and nothing rebuilds on that, so this stream is the only trigger.
  final ObservableState<int> attachments = ObservableState(0);

  /// Every session this panel is responsible for, selected or not.
  List<HostedRecordSession> get owned => List.unmodifiable(_owned);

  /// The session whose windows are in the row, if any.
  HostedRecordSession? get attached => _attached;

  /// The window of the attached session the opener asked for, if any.
  String? get attachedFocus => _attachedFocus;

  /// The panel's own window asked for now; the layer reads it once and clears it. The
  /// remembered arrangement lives in `WindowDefaults`, not here.
  String? requestedWindow;

  /// Asks for one of the panel's own windows now, ending the opener's request: a
  /// visit's chart is no longer the window to show just because it was opened for it.
  void showWindow(String id) {
    requestedWindow = id;
    _attachedFocus = null;
    workspace.show(id);
  }

  /// This panel's record or any visit it carries, on screen or not, has unsaved work.
  bool get anyUnsavedChanges =>
      hasPendingEdits || _owned.any((session) => session.hasPendingEdits);

  /// Makes [session] the record in the row, keeping its draft and every other draft
  /// this panel owns; never prompts. [focus] is the window the opener came for.
  void attach(HostedRecordSession session, {String? focus}) {
    if (!_owned.any((owned) => identical(owned, session))) {
      _owned.add(session);
    }
    _attached = session;
    _attachedFocus = focus;
    // the named window must show before the row is planned, so it cannot wait for the layer.
    if (focus != null) workspace.show(focus, slot: kAttachedSlot);
    attachments(attachments() + 1);
  }

  /// Takes the attached record out of the row but keeps it: its draft stays the user's.
  void detach() {
    if (_attached == null) return;
    _attached = null;
    _attachedFocus = null;
    workspace.clearSlot(kAttachedSlot);
    attachments(attachments() + 1);
  }

  /// Discards [session] for good: its draft is never written, and it leaves the registry.
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

  /// Drops every carried session without saving; a caller that wants the work written saves first.
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

  /// Pushes unsaved changes for a kind whose answer changes without being asked; null
  /// when the host can only poll [hasPendingEdits] (a [DelegatedPanel]'s callback).
  ObservableState<int>? get pendingEditsSignal => null;

  /// Header title: [displayTitle], greyed when archived. Translated here because `Txt`
  /// draws its input verbatim, while `txt` passes a real name through unchanged.
  Widget buildTitle(BuildContext context) => Txt(
        txt(displayTitle),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: isArchived ? Colors.grey : null),
      );

  /// Persists, settles [result], then re-reads the title. Kinds implement [persist];
  /// overriding this would skip the settlement.
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
