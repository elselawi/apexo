import 'dart:async';

import 'package:apexo/app/panels/panel_tab.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show nonVirtual, protected;

/// A panel, as the host sees it: everything [PanelScreen] needs from whatever is
/// on screen, independent of how the records behind it are stored.
abstract base class Panel {
  Panel({
    required this.tabs,
    required this.icon,
    required this.singularName,
    required this.unicodeSymbol,
    this.newTitle,
    this.recordTitle,
    this.inherentlyScrollable = false,
    this.showTitles = false,
    this.showBottomControls = true,
    this.additionalControls,
    this.archiveButtonReplacement,
    int? selectedTabIndex,
  }) {
    selectedTab(selectedTabIndex);
  }

  final List<PanelTab> tabs;
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

  final bool inherentlyScrollable;
  final bool showTitles;
  final bool showBottomControls;
  final Widget? additionalControls;
  final Widget? archiveButtonReplacement;

  final inProgress = ObservableState(false);
  final selectedTab = ObservableState<int>(0);
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);
  final int creationDate = DateTime.now().millisecondsSinceEpoch;

  String get identifier => isNew ? 'new+$singularName' : itemId;

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
      _recordTitle ?? (isNew ? newTitle : null) ?? itemId;

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
    await persist();
    settle();
    await readTitle(refresh: true);
  }

  /// The panel's own write, run by [save] and by nothing else.
  @protected
  Future<void> persist();

  /// Archives or restores the record.
  Future<void> setArchived(bool archived);
}
