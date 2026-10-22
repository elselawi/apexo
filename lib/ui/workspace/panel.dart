import 'dart:async';

import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panel_workspace.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show nonVirtual, protected;

/// A panel, as the host sees it: everything [PanelScreen] needs from whatever is
/// on screen, independent of how the records behind it are stored.
abstract base class Panel {
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
    this.additionalControls,
    this.archiveButtonReplacement,
  });

  /// The windows this panel offers, in priority order: the first one is drawn
  /// in the panel itself, and the rest are what it floats beside itself.
  final List<PanelWindow> windows;

  /// The editor the panel keeps inline — what its first tab used to be. Null
  /// for a panel with no windows at all.
  PanelWindow? get primaryWindow => windows.isEmpty ? null : windows.first;

  /// The editors the panel floats: everything but the primary one, in priority
  /// order. A screen with room for two of these opens the first two.
  ///
  /// Computed on every read rather than frozen at construction: the list of
  /// windows is built from what the user may see, and a permission that
  /// changes while the panel is open must not leave a window behind that the
  /// panel may no longer show.
  List<PanelWindow> get floatingWindows =>
      windows.length <= 1 ? const <PanelWindow>[] : windows.sublist(1);

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

  final bool showBottomControls;
  final Widget? additionalControls;
  final Widget? archiveButtonReplacement;

  final inProgress = ObservableState(false);
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
  String get displayTitle =>
      liveTitle?.call() ??
      _recordTitle ??
      (isNew ? newTitle : null) ??
      itemId;

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
  bool get isNew;

  bool get isArchived;

  /// Whether the panel currently holds work that is not persisted yet — the
  /// host's question, answered by each panel for itself.
  bool get hasPendingEdits;

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
