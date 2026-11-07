import 'dart:async';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A session with no feature behind it, so a failing window test implicates
/// the hosting machinery, not a record model.
final class FakeSession implements HostedRecordSession {
  FakeSession({
    required this.itemId,
    required this.windows,
    this.singularName = 'appointment',
    this.displayTitleText = 'Ali Karim · 24/10 · pending',
    this.accent = PanelAccentsStub.appointment,
    this.unicodeSymbol = '📅',
    this.hasWork = false,
  });

  @override
  final String itemId;

  @override
  final List<PanelWindow> windows;

  @override
  final String singularName;

  @override
  final String unicodeSymbol;

  @override
  final Color? accent;

  final String displayTitleText;

  /// Whether the draft reads as edited — the flag a test flips by hand.
  bool hasWork;

  @override
  String get displayTitle => displayTitleText;

  @override
  String get saveLabel => 'saveVisit';

  @override
  String get bandLabel => bandLabelText;

  /// The band's identity line, for a test that looks for it.
  String bandLabelText = 'Visit · 24/10';

  /// What the band draws under the identity line; null draws nothing.
  Widget? band;

  @override
  Widget? get bandContent => band;

  /// The visit's finished state, as the band reads it.
  bool done = false;

  @override
  bool get isDone => done;

  @override
  void markDone(bool value) {
    done = value;
    refreshDirty();
  }

  bool archived = false;
  @override
  bool canArchive = true;
  Future<void> Function(bool value)? archive;

  @override
  Future<void> setArchived(bool value) async {
    await archive?.call(value);
    archived = value;
    refreshDirty();
  }

  @override
  bool get isNew => false;

  @override
  bool get isArchived => false;

  bool isDisposed = false;

  /// Ids each [save] wrote, in order: proves which record a window's Save hit.
  final List<String> saves = <String>[];

  /// Every field set acknowledged outside the Save, in order.
  final List<Iterable<String>> acknowledged = <Iterable<String>>[];

  @override
  bool get showBottomControls => true;

  @override
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);

  @override
  final ObservableState<bool> inProgress = ObservableState(false);

  @override
  bool get hasPendingEdits => hasWork;

  final Completer<void> _result = Completer<void>();

  String? _savedId;

  @override
  String? get savedId => _savedId;

  @override
  void refreshDirty() {
    if (hasUnsavedChanges() != hasWork) hasUnsavedChanges(hasWork);
  }

  @override
  Future<void> save() async {
    saves.add(itemId);
    hasWork = false;
    _savedId = itemId;
    refreshDirty();
  }

  @override
  Future<void> get result => _result.future;

  @override
  void markSaved() {
    hasWork = false;
    refreshDirty();
  }

  @override
  void markFieldsSaved(Iterable<String> fields) {
    acknowledged.add(fields);
    refreshDirty();
  }

  @override
  void dispose() {
    isDisposed = true;
    if (!_result.isCompleted) _result.complete();
  }

  /// A window of this record, as the feature would build one.
  static PanelWindow window(
    String id, {
    String title = 'operativeDetails',
    double width = 350,
    double minHeight = 300,
    bool matchesPanelWidth = true,
    bool editsRecord = true,
    String? saveLabel,
    Widget? body,
    String? attachedTo,
    bool byDefault = true,
    Widget? Function()? chipPreview,
  }) =>
      PanelWindow(
        id: id,
        title: title,
        attachedTo: attachedTo,
        byDefault: byDefault,
        icon: WindowsIcons.calendar,
        body: body ?? SizedBox(height: 40, child: Text('body-$id')),
        matchesPanelWidth: matchesPanelWidth,
        preferredWidth: width,
        minHeight: minHeight,
        editsRecord: editsRecord,
        saveLabel: saveLabel,
        chipPreview: chipPreview,
      );
}

/// Accents for window tests, hardcoded so no feature palette is imported.
abstract final class PanelAccentsStub {
  static const Color appointment = Color(0xFF7C4DFF);
  static const Color patient = Color(0xFF1E88E5);
}
