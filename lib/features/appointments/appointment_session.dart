import 'dart:async';
import 'dart:convert';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_dental_chart.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// One draft per visit for the whole app session: every window of the visit edits
/// it, and `appointmentSessions` keeps it to one session per stored visit.
final class AppointmentSession implements HostedRecordSession {
  AppointmentSession._({
    required this.item,
    required this.chart,
    required Map<String, dynamic> baseline,
    void Function()? onDispose,
  })  : _baseline = _detached(baseline),
        _onDispose = onDispose;

  /// The session for [appointment]. The draft comes from the store, not the
  /// caller's copy, which may predate a sync; the copy is used only if unstored.
  factory AppointmentSession(
    Appointment appointment, {
    void Function()? onDispose,
  }) {
    final stored = appointments.get(appointment.id);
    final asOpened = _detached(stored?.toJson() ?? appointment.toJson());
    final draft = Appointment.fromJson(_detached(asOpened));
    late final AppointmentSession session;
    final chart = appointmentDentalChart(
      draft,
      onSave: () => session.save(),
    );
    session = AppointmentSession._(
      item: draft,
      chart: chart,
      baseline: asOpened,
      onDispose: onDispose,
    );
    chart.setBaseline(
      teeth: draft.teeth,
      extraNotes: draft.teethExtraNotes,
    );
    return session;
  }

  /// The visit's draft: the one thing every window of this visit edits.
  final Appointment item;

  /// The visit's chart, owned here so its own Save writes this draft, not a second
  /// copy of the visit, and a visit save re-baselines it too.
  final DentalChartSession chart;

  /// Called when this session is dropped for good — the registry forgets it.
  final void Function()? _onDispose;

  /// Built once: the windows edit [item], so a rebuilt one would be a second editor.
  @override
  late final List<PanelWindow> windows = appointmentSessionWindows(this);

  /// The visit as last written — `asOpened` in the delta write. Detached JSON,
  /// because `toJson` hands out live maps that a baseline would follow.
  Map<String, dynamic> _baseline;

  /// Follow-up changes staged by the operative form; the visit's Save applies them.
  late final FollowUpDraft followUpDraft =
      FollowUpDraft(onChanged: refreshDirty);

  @override
  final ObservableState<bool> inProgress = ObservableState(false);

  @override
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);

  final Completer<void> _result = Completer<void>();

  String? _savedId;
  bool _disposed = false;

  /// The visit's id — the one record this session is about.
  @override
  String get itemId => item.id;

  /// The visit's stable scope, for windows and for work adopted from them.
  String get scope => 'appointment:${item.id}';

  @override
  String get displayTitle => appointmentOwnerLine(item);

  /// The record's kind, for the layout preferences: `appointment/attached`.
  @override
  String get singularName => 'appointment';

  /// The glyph that marks a visit wherever it is drawn.
  @override
  String get unicodeSymbol => '📅';

  @override
  Color? get accent => PanelAccents.appointment;

  /// The key the visit's Save wears: it names the record it writes.
  @override
  String get saveLabel => 'saveVisit';

  @override
  String get bandLabel =>
      txt('visitOf').replaceAll('{date}', DF.allNumbers(item.date));

  @override
  Widget? get bandContent => Column(
        key: ValueKey('visit-form-${item.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppointmentBandDetails(
            item,
            key: ValueKey('visit-fields-${item.id}'),
            onEdited: refreshDirty,
          ),
          AppointmentBandDock(session: this),
        ],
      );

  @override
  bool get isDone => item.isDone;

  @override
  void markDone(bool done) {
    item.isDone = done;
    refreshDirty();
  }

  @override
  bool get canArchive => login.perm(Perm.appointments).full;

  @override
  Future<void> setArchived(bool archived) async {
    if (!canArchive) throw StateError('Visit archive permission is required');
    if (archived) {
      appointments.archive(item.id);
    } else {
      appointments.unarchive(item.id);
    }
    item.archived = archived;
    // Only the archived flag was written, so acknowledge that field alone and
    // leave the draft's unsaved text dirty.
    markFieldsSaved(const ['archived']);
  }

  /// Visits are stored by the create dialog, so this is true only once the record
  /// has been removed from the store.
  @override
  bool get isNew => appointments.get(item.id) == null;

  @override
  bool get isArchived =>
      item.archived == true || appointments.get(item.id)?.archived == true;

  /// The visit has a Save: it is the visit's own write, never the patient's.
  @override
  bool get showBottomControls => true;

  /// Whether the visit draft, its teeth, or its staged patient follow-up changed.
  @override
  bool get hasPendingEdits =>
      followUpDraft.isDirty || _encode(item.toJson()) != _encode(_baseline);

  @override
  Future<void> get result => _result.future;

  /// The id this session last wrote, or null while it has written nothing.
  @override
  String? get savedId => _savedId;

  @override
  void refreshDirty() {
    final dirty = hasPendingEdits;
    if (hasUnsavedChanges() != dirty) hasUnsavedChanges(dirty);
  }

  /// Writes the delta of this draft against the visit as stored now: the store is
  /// re-read first, so a sync or another window's write is not undone.
  @override
  Future<void> save() async {
    if (inProgress()) return;
    inProgress(true);
    try {
      final pendingFollowUp = followUpDraft;
      if (pendingFollowUp.isDirty) {
        final patientID = pendingFollowUp.patientID;
        if (!login.perm(Perm.appointments).some) {
          throw StateError(txt('followUpSavePermissionRequired'));
        }
        if (patientID == null ||
            patientID.isEmpty ||
            patients.get(patientID) == null) {
          throw StateError(txt('followUpSavePatientMissing'));
        }
        setFollowUp(
          patientID,
          pendingFollowUp.day,
          note: pendingFollowUp.note,
        );
        pendingFollowUp.clear();
      }
      final stored = appointments.get(item.id);
      final json = stored == null
          ? _detached(item.toJson())
          : mergeAppointmentJson(
              item,
              asOpened: _baseline,
              into: stored.toJson(),
            );
      appointments.set(appointments.modeling(json));
      _savedId = item.id;
      markSaved();
    } finally {
      inProgress(false);
    }
  }

  /// Re-baselines the whole draft: a write that went through [save].
  @override
  void markSaved() {
    _baseline = _detached(item.toJson());
    chart.markSaved();
    refreshDirty();
  }

  @override
  void markFieldsSaved(Iterable<String> fields) {
    final current = item.toJson();
    for (final field in fields) {
      if (current.containsKey(field)) {
        _baseline[field] = current[field];
      } else {
        _baseline.remove(field);
      }
    }
    _baseline = _detached(_baseline);
    refreshDirty();
  }

  /// Applies [mutate] to the draft and stores only the fields it changed, for a
  /// control that reads the store rather than the draft (a checkbox, a calendar
  /// drag). The rest of the draft stays dirty, so typed text is still the user's.
  void writeThrough(void Function(Appointment appointment) mutate) {
    final before = _detached(item.toJson());
    mutate(item);
    final current = item.toJson();
    final changed = <String>[
      for (final key in {...before.keys, ...current.keys})
        if (_encode(before[key]) != _encode(current[key])) key,
    ];
    if (changed.isEmpty) return;
    final stored = appointments.get(item.id);
    // Nothing stored to write into: the draft stays dirty rather than pretending
    // to be written.
    if (stored == null) return;
    appointments.set(appointments.modeling(
      mergeAppointmentJson(item, asOpened: before, into: stored.toJson()),
    ));
    markFieldsSaved(changed);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose?.call();
    if (!_result.isCompleted) _result.complete();
  }

  bool get isDisposed => _disposed;
}

/// Copies [draft]'s fields that differ from [asOpened] into [into], the visit as
/// stored now, leaving every other stored field alone. A field reset to its model
/// default is absent from `toJson`, so the key must be removed rather than written.
Map<String, dynamic> mergeAppointmentJson(
  Appointment draft, {
  required Map<String, dynamic> asOpened,
  required Map<String, dynamic> into,
}) {
  final merged = _detached(into);
  final current = draft.toJson();
  for (final key in {...asOpened.keys, ...current.keys}) {
    if (_encode(current[key]) == _encode(asOpened[key])) continue;
    if (current.containsKey(key)) {
      merged[key] = current[key];
    } else {
      merged.remove(key);
    }
  }
  return _detached(merged);
}

/// Deep copy of [json]: `toJson` hands out live maps, which must not be shared.
Map<String, dynamic> _detached(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// Key-order-insensitive JSON encoding, so a draft compares cleanly to a stored copy.
String _encode(Object? json) => jsonEncode(_canonical(json));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = [for (final key in value.keys) key.toString()]..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonical(item)];
  }
  return value;
}
